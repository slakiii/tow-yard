-- Thin shell: love callbacks, input wiring, camera, fixed-timestep loop.
-- All game rules live in lib/ and are covered by `love tests`.

local rig = require("lib.rig")
local session = require("lib.session")
local levels = require("lib.levels")
local input = require("lib.input")
local draw = require("lib.draw")
local audit = require("lib.audit")
local progress = require("lib.progress")
local run = require("lib.run")
local menu = require("lib.menu")
local levelfmt = require("lib.levelfmt")
local codec = require("lib.codec")
local share = require("lib.share")
local doc = require("lib.edit.doc")
local props = require("lib.props")
local undo = require("lib.edit.undo")
local autosave = require("lib.edit.autosave")
local palette = require("lib.edit.palette")
local levelcheck = require("lib.levelcheck")
local sfx = require("lib.sfx")
local audio_device = require("lib.audio_device")

local DT = 1 / 120          -- physics step: fixed, or the unstable reverse
local MAX_STEPS = 12        -- never spiral past this in one frame

-- The progress store takes a disk rather than love.filesystem, so its rules stay
-- testable; this table is the only place the two meet.
local disk = {
    read = function(name) return love.filesystem.read(name) end,
    write = function(name, data) return love.filesystem.write(name, data) end,
    remove = function(name) return love.filesystem.remove(name) end,
    mkdir = function(name) return love.filesystem.createDirectory(name) end,
}

local smoke = { enabled = false, frames = 0, frozen = false }

-- A mode is a screen with its own update/draw/keys. The game began as a single
-- implicit state; the level select and the editor make the switch explicit, so a
-- key press cannot leak into the screen that is not showing.
local MODE = { play = "play", menu = "menu", editor = "editor" }

-- Flip this to false for a build that ships without the editor: `E` in the level
-- select, `--edit` and the editor mode all go away. Note that users cannot change
-- the shipped tracks either way -- the editor writes only into the save
-- directory, and saving an id that belongs to a shipped level becomes
-- "<id>-copy" -- but a build with no editor is the simpler promise to make.
local EDITOR_ENABLED = true

local SNAP = 0.5
-- How far a click may wander, in screen pixels, before it counts as a drag:
-- selecting a prop must never nudge it (or snap it onto the grid).
local DRAG_SLOP = 3

local game = {
    mode = MODE.menu,
    -- Off by default: the arc is an assist, and it hands the manoeuvre away --
    -- it is the one thing on screen that says where the caravan will go, so a
    -- first park should be the player's own line. G / Y turns it on.
    guide = false,
    debug = false,
    paused = false,
    acc = 0,
    steps = 0,
    new_best = false,
    record = nil,             -- the best that stood when this run ended
    delta = nil,              -- counted time minus that record, signed
    ghost = nil,
    ghost_mode = "rig",       -- rig | trail | off: the silhouette is the honest one
    custom = {},              -- imported levels, beside the campaign
    toast = nil,
    editor = nil,
    playtest = false,         -- play came from the editor: Esc goes back there
    input = input.new_state(),
}

local function camera(lvl)
    local W, H = love.graphics.getDimensions()
    local b = lvl.bounds
    local pad = 56
    local w, h = b.x1 - b.x0, b.y1 - b.y0
    local scale = math.min((W - pad * 2) / w, (H - pad * 2) / h)
    local ox = pad + (W - pad * 2 - w * scale) / 2 - b.x0 * scale
    local oy = pad + (H - pad * 2 - h * scale) / 2 + b.y1 * scale
    return scale, ox, oy
end

-- A ghost that is stored but refused is invisible otherwise, so "why is there no
-- ghost on my level?" has no answer anywhere. Not in the smoke: its store is a
-- fixture that claims ghosts it never wrote. Defined before the loader that
-- uses it -- a Lua local is not visible above its declaration.
local function ghost_note(level, why)
    if smoke.enabled then return end
    print("ghost for " .. tostring(level and level.id) .. " not shown: " .. tostring(why))
end

local function load_level_object(lvl)
    game.last_played = lvl and lvl.id or game.last_played
    game.level = lvl
    game.s = session.new(game.level)
    game.run = run.new(game.level)
    game.acc = 0
    game.steps = 0
    game.new_best = false
    game.record = nil
    game.delta = nil
    game.input.steer, game.input.throttle, game.input.brake, game.input.handbrake = 0, 0, 0, false
    game.scale, game.ox, game.oy = camera(game.level)

    -- The stored best run, verified before it is allowed on screen: a ghost that
    -- was recorded on other geometry is not a ghost, it is a different level's
    -- run wearing this level's name.
    game.ghost = nil
    if game.progress and game.codec then
        local text = progress.ghost_text(game.progress, game.level)
        local g, why = text and run.decode(text, game.codec)
        if g then
            local ok, detail = run.verify(game.level, g)
            if ok then
                -- runs stored before recording began with the first action carry an
                -- idle prefix; without this the ghost hesitates at the start line
                run.trim(g)
                game.ghost = {
                    run = g, trail = run.trace(game.level, g),
                    s = session.new(game.level), step = 0,
                }
            else
                ghost_note(game.level, detail)
            end
        elseif text then
            ghost_note(game.level, "unreadable - " .. tostring(why))
        elseif progress.mark(game.progress, game.level).ghost then
            ghost_note(game.level, "the file is missing")
        end
    end
end

local function load_level(n)
    load_level_object(levels.get(n))
end

-- Restart what you are actually playing. The catalogue index only describes
-- campaign levels, so reloading by index dropped the player into whatever
-- campaign level was last played -- pressing R on a custom track (or on an
-- editor playtest) silently swapped the level under them.
local function reload_level()
    if game.level then load_level_object(game.level) end
end

local function say(text, seconds)
    game.toast = { text = text, expires = love.timer.getTime() + (seconds or 4) }
end

-- "Next level" is a campaign idea. On a custom level there is no next, and
-- guessing from a stale index is how R used to land on the wrong track; saying
-- so is the honest answer. Defined after `say`, which it needs to be in scope.
local function next_campaign_level()
    local i = levels.find(game.level and game.level.id)
    if not i then
        say("this level is not in the campaign", 3)
        return
    end
    load_level(i % #levels.ALL + 1)
end

-- A share string from anywhere: the clipboard, a dropped file, eventually a
-- server. One path, so the three transports cannot behave differently.
local function import_text(text)
    local got, err = share.unpack(text, game.codec)
    if not got then
        say("import failed: " .. tostring(err), 6)
        return
    end

    if got.level then
        local name = levelfmt.save_custom(disk, got.level)
        if not name then
            say("could not store that level", 6)
            return
        end
        -- `got.run and run.verify(...)` would truncate the second return value,
        -- and adopt needs the run's own time; keep the two apart.
        local ok, final
        if got.run then ok, final = run.verify(got.level, got.run) end
        if ok then
            -- The entry is what makes ghost_text() look for the blob: without it
            -- the bundled ghost is stored and never shown.
            progress.adopt(game.progress, got.level, final)
            progress.put_ghost(game.progress, got.level, run.encode(got.run, game.codec))
            progress.save(game.progress)
        end
        game.custom = levelfmt.scan_custom(disk)
        if game.menu then menu.rebuild(game.menu, levels.ALL, game.custom) end
        -- open it: an imported level you cannot play is a download, not a level
        load_level_object(got.level)
        game.mode = MODE.play
        say((ok and ("imported " .. tostring(got.level.name) .. " - its ghost is the time to beat")
            or ("imported " .. tostring(got.level.name))), 6)
    elseif got.run then
        local ok, final = run.verify(game.level, got.run)
        if ok then
            progress.adopt(game.progress, game.level, final)
            progress.put_ghost(game.progress, game.level, run.encode(got.run, game.codec))
            progress.save(game.progress)
            reload_level()
            say("rival ghost loaded")
        else
            say("that run does not fit this level: " .. tostring(final), 6)
        end
    end
end

-- The code carries the level too when the level is not shipped, or the
-- recipient would get a run for a level they do not have.
local function export_share()
    local custom = levels.find(game.level.id) == nil
    local r = game.s and game.s.parked and game.run or nil
    local text = share.bundle(custom and game.level or nil, r, game.codec, "user")
    if not text then
        say("nothing to share yet", 4)
        return
    end
    local code = share.code(text, game.codec)
    love.system.setClipboardText(code)
    say(string.format("share code copied (%d chars)", #code))
end

-- The ghost advances with the player's own step count, never with wall-clock
-- time: pausing must not let it drive off.
local function advance_ghost()
    if not game.ghost then return end
    run.advance(game.ghost, game.steps)
end

-- The model is rebuilt on entry so the marks are what the store says now: a park
-- made a second ago must not still read as unplayed.
local function open_menu()
    game.custom = levelfmt.scan_custom(disk)
    game.menu = menu.new(levels.ALL, game.custom, game.progress)
    -- come back to the level you just drove: it is the one you are most likely to
    -- want, and hunting for it after every attempt is friction for nothing
    if game.last_played then menu.focus(game.menu, game.last_played) end
    game.mode = MODE.menu
end

local function open_selected()
    local lvl = menu.confirm(game.menu)
    if not lvl then return end
    load_level_object(lvl)
    game.mode = MODE.play
end

-- ------------------------------------------------------------------ editor

local function editor_to_world(mx, my)
    local W, H = love.graphics.getDimensions()
    local cam = game.editor.cam
    return cam.x + (mx - W / 2) / cam.scale, cam.y - (my - H / 2) / cam.scale
end

local function snap(v, step)
    if not step or step <= 0 then return v end
    return math.floor(v / step + 0.5) * step
end

-- Autosave policy lives in lib/edit/autosave.lua (tested); this is the wiring.
local function editor_autosave(level_id, text, force)
    local e = game.editor
    if not e or not text then return end
    local ok = autosave.save(disk, level_id, text, e.autosave_state or {}, love.timer.getTime(), force)
    e.autosave_state = e.autosave_state or {}
    if ok == false and force and text ~= e.autosave_state.text then
        say("could not autosave", 4)
    end
end

-- "Modified" is a fact about the document, not a flag a gesture sets: the text
-- differs from the text this document was opened (or last saved) as. A click
-- that only selects, a rotate with nothing selected, an undo back to where you
-- started -- none of those are unsaved work, and none of them should ask you to
-- save on the way out.
local function editor_dirty()
    local e = game.editor
    return e ~= nil and e.baseline ~= doc.snapshot(e.doc)
end

local function editor_autosave_now()
    local e = game.editor
    if not e or not editor_dirty() then return end
    -- Never under --smoke: a failing run quits from a document its frames had
    -- been editing, and the recovery file it wrote was then restored into the
    -- NEXT run -- so one real failure poisoned every run after it.
    if smoke.enabled then return end
    editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc), true)
end

local function editor_errors()
    local e = game.editor
    e.errors = levelcheck.errors(doc.level(e.doc))
end

-- Every mutation goes through here: snapshot first, then change, then re-check.
-- One path means nothing can be edited without being undoable or unchecked.
local function editor_edit(fn)
    local e = game.editor
    undo.push(e.undo, doc.snapshot(e.doc))
    fn()
    editor_errors()
    editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
end

local function open_editor(lvl)
    if not EDITOR_ENABLED then return end
    local W, H = love.graphics.getDimensions()
    local b = lvl.bounds
    local document = doc.new(lvl)
    game.editor = {
        doc = document,
        -- what "unmodified" means for this screen: the text it opened as. Taken
        -- before an autosave can be restored over it, so a restored copy is
        -- unsaved work and says so.
        baseline = doc.snapshot(document),
        undo = undo.new(),
        cam = {
            x = (b.x0 + b.x1) / 2,
            y = (b.y0 + b.y1) / 2,
            scale = math.min((W - 300) / (b.x1 - b.x0), (H - 120) / (b.y1 - b.y0)),
        },
        origin_id = lvl.id,      -- what this document was opened as; see editor_export_lua
        tool = "select",
        snap = SNAP,
        -- the rail's contents and order come from the vocabulary, not from a
        -- list kept here: props.PALETTE groups the kinds the game has
        palette = palette.groups(),
        tool_order = palette.order(),
        errors = {},
    }
    editor_errors()

    -- unsaved work from a previous session, offered back. Restoring is a rescue
    -- here, not a surprise: the file only exists because this id was being edited
    -- and never saved.
    local text = autosave.load(disk, lvl.id)
    if text then
        local saved = levelfmt.decode(text)
        if saved and not doc.same_level(saved, lvl) then
            if doc.restore(game.editor.doc, text) then
                editor_errors()
                game.editor.autosave_state = { text = text }
                local info = love.filesystem.getInfo(autosave.path(lvl.id))
                say("restored unsaved edits from "
                    .. (info and os.date("%H:%M", info.modtime) or "earlier")
                    .. " - S saves, L exports", 10)
            end
        end
    end

    game.mode = MODE.editor
end

local function new_level()
    local taken = {}
    for _, l in ipairs(levels.ALL) do taken[#taken + 1] = l.id end
    for _, l in ipairs(game.custom) do taken[#taken + 1] = l.id end
    -- the authored level, not the document: open_editor takes a level and wraps it
    open_editor(doc.blank(doc.free_id(taken, "untitled"), "Untitled").level)
end

-- The way a BUILT-IN level gets authored. The editor writes data, and levels.lua
-- is where the campaign's data lives, so the honest bridge is a table literal:
-- copy it, paste it over the entry of the same id, run the tests and the audit.
local function editor_export_lua()
    local e = game.editor
    local lvl = doc.level(e.doc)
    -- the id it was opened as: editing a shipped level and pressing S renames the
    -- copy, but exporting must still produce the block that replaces the original
    lvl.id = e.origin_id or lvl.id

    local text = levelfmt.to_lua(lvl)
    love.system.setClipboardText(text)
    love.filesystem.createDirectory("drafts")
    local path = "drafts/" .. lvl.id .. ".lua"
    love.filesystem.write(path, text)
    autosave.clear(disk, e.origin_id or lvl.id)
    e.autosave_state = {}
    say("levels.lua entry for " .. lvl.id .. " copied, and written to "
        .. love.filesystem.getSaveDirectory() .. "/" .. path, 9)
end

-- A custom level may not take a shipped level's id: progress, ghosts and the
-- content hash are all keyed by it, and two levels answering to "straight-back"
-- is a bug that surfaces as somebody else's best time.
local function editor_save()
    local e = game.editor
    local lvl = doc.level(e.doc)
    if levels.find(lvl.id) then
        local base, n = lvl.id .. "-copy", 1
        while levels.find(base) or (function()
            for _, c in ipairs(game.custom) do if c.id == base then return true end end
        end)() do
            n = n + 1
            base = lvl.id .. "-copy" .. n
        end
        e.doc.level.id = base
        lvl = doc.level(e.doc)
        say("renamed to " .. base .. " (that id belongs to a shipped level)", 6)
    end

    local name, err = levelfmt.save_custom(disk, lvl)
    if not name then
        say("could not save: " .. tostring(err), 6)
        return
    end
    game.custom = levelfmt.scan_custom(disk)
    e.baseline = doc.snapshot(e.doc)      -- saved: this is the text now on disk
    autosave.clear(disk, e.origin_id or lvl.id)
    e.autosave_state = {}
    say("saved " .. name)
end

local function editor_verify()
    local e = game.editor
    local lvl = doc.level(e.doc)

    -- The audit blocks for ~2 s. Present the notice BEFORE calling it, or the
    -- player stares at a frozen frame and thinks the editor died.
    love.graphics.setFont(love.graphics.newFont(19))
    love.graphics.setColor(0.9, 0.92, 0.95)
    love.graphics.print("verifying - the audit tries every staging pose...", 260, 18)
    love.graphics.present()

    local res = audit.solve(lvl, { grid = audit.QUICK_GRID })
    if res.solved then
        say(string.format("a line exists: %.1f s by machine (a floor, not a par)", res.best.time), 8)
    else
        say("no line found - this level may still be playable, but it needs a playtest", 8)
    end
end

-- What the selection points at, or nil. Three gestures need this and none of
-- them may invent their own idea of what "selected" means.
local function editor_selected_entry(d)
    local sel = d.doc.selection
    if not sel then return nil end
    if sel.list == "bay" or sel.list == "spawn" then return d.doc.level[sel.list] end
    return (d.doc.level[sel.list] or {})[sel.index]
end

-- Arm a tool. Placing is a promise to add something, so it drops any selection:
-- "the thing I just placed stays selected" is only true if the thing you were
-- editing before did not. Esc from here lands on the last placement -- or on
-- nothing, if you placed nothing.
local function editor_arm(name)
    local e = game.editor
    e.tool = name
    if name ~= "select" then
        doc.deselect(e.doc)
        say(name .. ": click the yard to place it", 3)
    end
end

local function editor_keypressed(key)
    local e = game.editor
    local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")

    -- the prompt owns the keyboard until it is answered
    if e.prompt then
        if key == "s" then
            e.prompt = nil
            editor_save()
            open_menu()
        elseif key == "escape" then
            e.prompt = nil
            editor_autosave_now()
            open_menu()
        elseif key == "return" or key == "kpenter" then
            e.prompt = nil
        end
        return
    end

    if e.typing then
        if key == "return" or key == "kpenter" then
            local name = (e.typing.buffer:gsub("^%s+", ""):gsub("%s+$", "")):sub(1, 60)
            if name == "" then name = e.typing.original end
            if name ~= e.typing.original then
                editor_edit(function() e.doc.level.name = name end)
            end
            e.typing = nil
        elseif key == "escape" then
            e.typing = nil
        elseif key == "backspace" then
            e.typing.buffer = e.typing.buffer:sub(1, -2)
        end
        return
    end

    -- Esc walks back out one step at a time, and each step is what the player
    -- can see: an armed tool becomes `select` (the last placement is still
    -- selected, ready to drag, turn or resize); a selection drops; only with
    -- nothing armed and nothing selected does Esc mean "leave the editor".
    if key == "escape" and e.tool ~= "select" then
        e.tool = "select"
        if e.doc.selection then
            say("select: drag, Q/E or a handle adjusts the selection", 4)
        else
            say("select: click a prop to adjust it", 4)
        end
        return
    end

    if key == "escape" and e.doc.selection then
        doc.deselect(e.doc)
        say("selection cleared", 3)
        return
    end

    if key == "escape" then
        -- never leave silently with unsaved work: a copy is kept either way, but
        -- "did my edit go anywhere?" is a question the editor should answer. A
        -- level you only looked at has nothing to ask about.
        editor_autosave_now()
        if editor_dirty() then
            e.prompt = true
        else
            open_menu()
        end
    elseif key == "f2" then
        e.typing = { buffer = e.doc.level.name or "", original = e.doc.level.name or "" }
    elseif key == "leftbracket" or key == "rightbracket" then
        local n = #e.tool_order
        local i = 1
        for j, name in ipairs(e.tool_order) do if name == e.tool then i = j end end
        i = ((i - 1 + (key == "rightbracket" and 1 or -1)) % n) + 1
        editor_arm(e.tool_order[i])
    elseif ctrl and key == "z" then
        local text = undo.back(e.undo)
        if text then
            doc.restore(e.doc, text)
            editor_errors()
            say("undo")
        else
            say("nothing to undo")
        end
    elseif key == "g" then
        e.snap = (e.snap and e.snap > 0) and 0 or SNAP
    elseif key == "q" or key == "e" then
        editor_edit(function() doc.rotate(e.doc, key == "q" and -15 or 15) end)
    elseif key == "=" or key == "kp+" then
        editor_edit(function() doc.resize(e.doc, 0.5, 0.5) end)
    elseif key == "minus" or key == "kp-" then
        editor_edit(function() doc.resize(e.doc, -0.5, -0.5) end)
    elseif key == "delete" or key == "backspace" then
        editor_edit(function() doc.remove(e.doc) end)
    elseif key == "v" then
        editor_verify()
    elseif key == "p" then
        game.playtest = true
        load_level_object(doc.level(e.doc))
        game.mode = MODE.play
    elseif key == "s" then
        editor_save()
    elseif key == "l" then
        editor_export_lua()
    elseif key == "o" then
        local text = share.bundle(doc.level(e.doc), nil, game.codec, "user")
        if text then
            love.system.setClipboardText(share.code(text, game.codec))
            say("level code copied")
        end
    end
end

local function editor_mousepressed(x, y, button)
    local e = game.editor

    -- the rail takes the click: picking a tool and then clicking the yard is how
    -- every editor works, and it is the answer to "how do I add something"
    if e.prompt then return end

    if x <= draw.RAIL and button == 1 then
        local tool = draw.editor_tool_at(x, y, e.palette)
        if tool then editor_arm(tool) end
        return
    end

    local wx, wy = editor_to_world(x, y)

    if button == 2 or button == 3 then
        e.pan = { x = x, y = y, cx = e.cam.x, cy = e.cam.y }
        return
    end
    if button ~= 1 then return end

    if e.tool == "select" then
        -- a handle sits ON the prop's edge, so grabbing one must not be read as
        -- "start dragging the whole prop"
        local grab = 9 / e.cam.scale
        for _, h in ipairs(doc.resize_handles(e.doc)) do
            if math.abs(h.x - wx) <= grab and math.abs(h.y - wy) <= grab then
                undo.push(e.undo, doc.snapshot(e.doc))
                -- which corner was grabbed decides which one is pinned; the
                -- press point is kept so a click without movement does nothing
                e.resizing = { sx = h.sx, sy = h.sy, px = x, py = y }
                return
            end
        end

        -- Only the selection is grabbable. Dragging whatever sits under the
        -- cursor sounds convenient until a level is dressed: then the whole yard
        -- is one surface, the map cannot be panned anywhere, and a slip moves
        -- the ground itself. The selection's own outline says what a drag will
        -- move; anything else starts a pan, and a press that never travels is
        -- still a click (it picks on release).
        local hit = doc.hit(e.doc, wx, wy, 0.4 / e.cam.scale)
        local sel = e.doc.selection
        local entry = editor_selected_entry(e)
        if hit and sel and hit.list == sel.list and (hit.index or 0) == (sel.index or 0) and entry then
            e.drag = { px = x, py = y, wx = wx, wy = wy, ox = entry.x, oy = entry.y }
        else
            e.pan = { x = x, y = y, cx = e.cam.x, cy = e.cam.y, click = { wx = wx, wy = wy } }
        end
    elseif e.tool == "bay" or e.tool == "spawn" then
        -- place, then keep it selected: the next thing you want is usually a drag
        local field = (e.tool == "bay") and "bay" or "spawn"
        editor_edit(function()
            if field == "bay" then
                doc.set_bay(e.doc, { x = snap(wx, e.snap), y = snap(wy, e.snap) })
            else
                doc.set_spawn(e.doc, { x = snap(wx, e.snap), y = snap(wy, e.snap) })
            end
            doc.select(e.doc, field)
        end)
    else
        editor_edit(function() doc.add(e.doc, e.tool, snap(wx, e.snap), snap(wy, e.snap)) end)
    end
end

local function editor_mousemoved(x, y, dx, dy)
    local e = game.editor
    if e.prompt then return end

    -- A click is not a drag. Below a few pixels the hand has not asked for
    -- anything, and acting on it is destructive: it snapped an off-grid prop onto
    -- the 0.5 m grid on the way to merely selecting it, which also marked the
    -- level modified and made Esc ask about unsaved work.
    local function not_dragged(start)
        return math.abs(x - (start.px or x)) < DRAG_SLOP
            and math.abs(y - (start.py or y)) < DRAG_SLOP
    end

    if e.resizing then
        if not_dragged(e.resizing) then return end
        -- The corner opposite the grab stays put: the drag sizes the prop away
        -- from the edge you already lined up, which is how a gap gets filled.
        local entry = editor_selected_entry(e)
        if not entry then return end
        local w0, h0, x0, y0 = entry.w, entry.h, entry.x, entry.y
        local wx, wy = editor_to_world(x, y)
        doc.resize_to_cursor(e.doc, e.resizing, wx, wy, e.snap)
        if entry.w == w0 and entry.h == h0 and entry.x == x0 and entry.y == y0 then return end
        editor_errors()
        editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
        return
    end

    if e.pan then
        -- A wobble is not a pan: below the slop the press is still a click, and a
        -- hand that moved 1 px should not have shifted the map under it.
        if e.pan.click and not e.pan.moved then
            if math.abs(x - e.pan.x) < DRAG_SLOP and math.abs(y - e.pan.y) < DRAG_SLOP then
                return
            end
            e.pan.moved = true
        end
        e.cam.x = e.pan.cx - (x - e.pan.x) / e.cam.scale
        e.cam.y = e.pan.cy + (y - e.pan.y) / e.cam.scale
        return
    end
    if e.drag then
        if not_dragged(e.drag) then return end
        local wx, wy = editor_to_world(x, y)
        local entry = editor_selected_entry(e)
        if not entry then return end
        local nx = snap(e.drag.ox + (wx - e.drag.wx), e.snap)
        local ny = snap(e.drag.oy + (wy - e.drag.wy), e.snap)
        if nx ~= entry.x or ny ~= entry.y then
            if not e.drag.pushed then
                undo.push(e.undo, doc.snapshot(e.doc))
                e.drag.pushed = true
            end
            entry.x, entry.y = nx, ny
            editor_errors()
            editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
        end
    end
end

local function editor_mousereleased(x, y, button)
    local e = game.editor
    -- A press that never travelled is a click, and a click is what selects (or
    -- clears): selection cannot happen on the way down any more, because the way
    -- down may be the start of a pan.
    if e.pan and e.pan.click and not e.pan.moved then
        local wx, wy = editor_to_world(x, y)
        doc.pick(e.doc, wx, wy, 0.4 / e.cam.scale)
    end
    e.pan = nil
    e.drag = nil
    e.resizing = nil
end

local function editor_wheelmoved(dx, dy)
    local e = game.editor
    local mx, my = love.mouse.getPosition()
    local wx, wy = editor_to_world(mx, my)
    local W, H = love.graphics.getDimensions()
    local s = math.max(6, math.min(40, e.cam.scale * (1 + dy * 0.12)))
    e.cam.scale = s
    e.cam.x = wx - (mx - W / 2) / s
    e.cam.y = wy + (my - H / 2) / s
end

local function draw_editor()
    local W, H = love.graphics.getDimensions()
    local e = game.editor
    love.graphics.push()
    love.graphics.translate(W / 2 - e.cam.x * e.cam.scale, H / 2 + e.cam.y * e.cam.scale)
    love.graphics.scale(e.cam.scale, -e.cam.scale)
    draw.editor_world(e.doc, e)
    love.graphics.pop()
    draw.editor_ui(e.doc, e, game)
    draw.editor_prompt(e, game)
end

-- `love . --audit N` / `--audit all`: is the level parkable at all? A level no
-- line parks is a shipped bug, and this is the only cheap evidence for it.
-- Exit 0 when every level asked about has a line.
-- A real ghost for the smoke frame: level 1 driven to a park, recorded, encoded
-- and decoded, exactly as a stored ghost arrives.
local function smoke_ghost(lvl)
    local s, r = session.new(lvl), run.new(lvl)
    local stop_x = lvl.bay.x - (rig.CARAVAN.coupling - rig.CARAVAN.length / 2)
    local t = 0
    while t < 60 and not s.parked do
        local inp = (s.rig.x > stop_x)
            and { steer = 0, throttle = 0, brake = 1, handbrake = false }
            or { steer = 0, throttle = 0, brake = 0, handbrake = true }
        run.record(r, inp)
        session.update(s, inp, DT)
        t = t + DT
    end
    run.finish(r, s)
    local g = run.decode(run.encode(r, game.codec), game.codec)
    return { run = g, trail = run.trace(lvl, g), s = session.new(lvl), step = 0 }
end

local function run_audit(arg, quick)
    local targets = {}
    if arg == nil or arg == "all" then
        for i = 1, #levels.ALL do targets[#targets + 1] = i end
    else
        -- a position in the catalogue (the row you see in the level select) or an
        -- id. Anything else is refused: `--audit angled-bay` used to fall back to
        -- level 1 and audit the wrong level while saying it had audited one.
        local n = tonumber(arg)
        if n then
            if n < 1 or n > #levels.ALL or n ~= math.floor(n) then
                print(string.format("no level %s: the catalogue has 1..%d", arg, #levels.ALL))
                love.event.quit(2)
                return
            end
            targets[1] = n
        else
            local at
            for i, l in ipairs(levels.ALL) do
                if l.id == arg then at = i end
            end
            if not at then
                local ids = {}
                for _, l in ipairs(levels.ALL) do ids[#ids + 1] = l.id end
                print("no level with id " .. tostring(arg))
                print("known ids: " .. table.concat(ids, ", "))
                love.event.quit(2)
                return
            end
            targets[1] = at
        end
    end
    local failed = 0
    for _, i in ipairs(targets) do
        local res = audit.solve(levels.get(i), { grid = quick and audit.QUICK_GRID or nil })
        for _, line in ipairs(audit.format(res, i)) do print(line) end
        if not res.solved then failed = failed + 1 end
    end
    print(string.format("%d level(s) audited, %d without a line", #targets, failed))
    love.event.quit(failed > 0 and 1 or 0)
end

-- The smoke run must not read the player's progress: a screenshot carrying last
-- week's best times is not a screenshot, and it would differ on every machine.
-- These numbers are scripted, and one level's content hash is deliberately stale
-- so the "level changed" card is in the frame.
local function smoke_progress()
    -- A memory disk, not a no-op: a store that cannot read back what it wrote
    -- makes every ghost in the smoke silently vanish, including the one an import
    -- carries.
    local files = {}
    local fakest = {
        read = function(n) return files[n] end,
        write = function(n, d) files[n] = d; return true end,
        remove = function(n) files[n] = nil; return true end,
        mkdir = function() return true end,
    }
    local p = progress.open(fakest)
    local function line(lvl, stars, best, ghost, hash)
        return string.format("level %s %d %.2f %d %s\n", lvl.id, stars, best, ghost,
            hash or levelfmt.content_hash(lvl))
    end
    progress.load(p, progress.HEADER .. progress.VERSION .. "\n"
        .. line(levels.get(1), 3, 13.21, 1)
        .. line(levels.get(2), 2, 31.40, 1)
        .. line(levels.get(4), 1, 38.00, 0)
        .. line(levels.get(5), 2, 33.10, 1, string.rep("ab", 32)))
    return p
end

-- Leave room for the title bar, the panel and the window border: a window that
-- is exactly the desktop size cannot be moved, and on Wayland one that is LARGER
-- than the desktop spawns with its edges cut off (SDL#11747, kwin_wayland).
local WINDOW_MARGIN_X, WINDOW_MARGIN_Y = 80, 120

-- Ask for the window size once more, now that there is a window to ask.
--
-- On KWin/Wayland a resizable window whose minimum size is set can be created AT
-- that minimum instead of at the requested size: LÖVE applies the size before the
-- minimum-size limits (love2d/love#2287), and the compositor sizes the first
-- mapped surface from those limits. This game opened at 900x560 -- exactly its
-- minwidth/minheight -- on a 1920x1200 desktop at 100% scaling.
--
-- One boot-time call is not enough there: at love.load the surface may not be
-- mapped (and the desktop size not yet known), so the request can be dropped. The
-- check therefore runs again for the first few frames -- after the window exists --
-- and stops for good as soon as the size is the one we want, so a compositor that
-- honoured the first request sees exactly one comparison and no second setMode.
local WINDOW_MARGIN_X, WINDOW_MARGIN_Y = 80, 120
local WINDOW_ATTEMPTS = 3          -- then accept it: a tiling WM may mean it
local window_attempts, window_settled, window_frames = 0, false, 0

local function want_window_size()
    local dw, dh = love.window.getDesktopDimensions()
    -- before the display is configured this is 0x0; ask for the conf size rather
    -- than clamp to a screen we cannot see yet, and let the frames below retry
    if not dw or dw <= 0 or not dh or dh <= 0 then return 1280, 720 end
    return math.min(1280, math.max(900, dw - WINDOW_MARGIN_X)),
           math.min(720, math.max(560, dh - WINDOW_MARGIN_Y))
end

local function fix_window_size(why)
    if window_settled then return end
    local w, h, flags = love.window.getMode()
    local want_w, want_h = want_window_size()
    if w == want_w and h == want_h then
        window_settled = true
        return
    end
    if window_attempts >= WINDOW_ATTEMPTS then
        window_settled = true
        if smoke.enabled then
            print(string.format("WINDOW gave up at %dx%d (want %dx%d)", w, h, want_w, want_h))
        end
        return
    end
    window_attempts = window_attempts + 1
    -- flags is getMode's settings table, so resizable/minwidth/minheight/vsync and
    -- the position ride along: this asks for a size, not for a different window
    love.window.setMode(want_w, want_h, flags)
    if smoke.enabled then
        local nw, nh = love.window.getMode()
        local dw, dh = love.window.getDesktopDimensions()
        print(string.format("WINDOW %s: %dx%d -> want %dx%d (desktop %dx%d) -> now %dx%d",
            why, w, h, want_w, want_h, dw or -1, dh or -1, nw, nh))
    end
end

function love.load(args)
    local want_audit, audit_arg, quick = false, nil, false
    for i, a in ipairs(args or {}) do
        if a == "--smoke" then smoke.enabled = true end
        if a == "--quick" then quick = true end
        if a == "--audit" then
            want_audit = true
            local next_arg = args[i + 1]
            if next_arg and next_arg:sub(1, 2) ~= "--" then audit_arg = next_arg end
        end
    end
    if want_audit then return run_audit(audit_arg, quick) end
    -- Installed before anything else can fail: a load-time error under --smoke
    -- otherwise sits in LÖVE's interactive error screen until something kills
    -- it, so the run reports as a timeout (124) instead of a failure with a
    -- traceback. That has now happened twice -- the second time was this
    -- mixer's first boot.
    if smoke.enabled then
        love.errorhandler = function(msg)
            print("SMOKE ERROR: " .. tostring(msg))
            print(debug.traceback("", 2))
            io.stdout:flush()
            os.exit(1)
        end
    end
    local want_edit = false
    for _, a in ipairs(args or {}) do
        if a == "--edit" then want_edit = true end
    end

    -- before anything creates a font or a canvas: setMode replaces the window and
    -- its GL context, so objects made earlier would belong to the old one
    fix_window_size("boot")

    love.graphics.setBackgroundColor(0.05, 0.05, 0.06)
    draw.init()
    -- Built at boot, so a cue that cannot be loaded is reported once and up
    -- front instead of the first time something is hit.
    game.sfx_log = smoke.enabled and {} or nil
    game.sfx_dev = audio_device.new(sfx.FILES, { log = game.sfx_log })
    game.sfx = sfx.new(game.sfx_dev)
    sfx.attach(game.sfx)
    input.init(game.input)
    game.codec = codec.love_data()
    game.progress = smoke.enabled and smoke_progress() or progress.open(disk)
    if not smoke.enabled then
        local imported, warnings = levelfmt.scan_custom(disk)
        game.custom = imported
        for _, w in ipairs(warnings) do print("custom: " .. w) end
    end
    load_level(1)
    -- the smoke harness drives play frames itself; a normal launch starts on the
    -- title screen
    game.mode = smoke.enabled and MODE.play or MODE.menu
    if game.mode == MODE.menu then open_menu() end
    if want_edit and not smoke.enabled then open_editor(levels.get(1)) end

    -- LÖVE's default error handler is an interactive loop: a draw-time error
    -- under --smoke sits there until something kills it, so the run reports as a
    -- timeout (124) rather than as a failure with a traceback. It has happened.
    if smoke.enabled then
        -- The suite cannot see assets/ (it mounts tests/ as the game root), so
        -- "all twelve cues are actually in the directory" is checked here, by
        -- the run that does have them. And a cue pushed through the mixer, not
        -- just a device called directly: the wiring is the part a headless test
        -- cannot reach.
        assert(#game.sfx_dev.missing == 0,
            "audio: missing " .. table.concat(game.sfx_dev.missing, ", "))
        local want = 0
        for _ in pairs(sfx.FILES) do want = want + 1 end
        assert(game.sfx_dev.loaded == want,
            string.format("audio: loaded %d of %d cues", game.sfx_dev.loaded, want))
        sfx.cues(game.sfx, { { kind = "bump", cause = "wall", speed = 5 } })
        local last = game.sfx_log[#game.sfx_log]
        assert(last == "wall_thud", "a cue never reached the device, got " .. tostring(last))
        print(string.format("SFX OK %d file(s) loaded, cue %s", game.sfx_dev.loaded, last))
    end
end

local function update_play(dt)
    -- The smoke run forces exact states for its screenshots. A physics step
    -- between the frame that sets a state and the frame that captures it makes
    -- the PNG depend on wall-clock timing -- it is how "the screenshots are
    -- unchanged" becomes false on a busy machine.
    if smoke.frozen then return end

    local acts = input.poll_actions(game.input)
    if acts.reset then
        reload_level()
        return
    end
    if acts.guide then game.guide = not game.guide end
    if acts.pause then game.paused = not game.paused end

    input.poll(game.input)

    if game.paused then
        input.rumble(game.input, 0, nil)
        return
    end

    game.acc = game.acc + math.min(dt, 0.1)
    local steps = 0
    local parked_before = game.s.parked
    -- One frame per physics step, recorded BEFORE the step: the frame is the
    -- input the sim is about to consume. A parked session stops the loop, so the
    -- run cannot grow while the result card is up.
    while game.acc >= DT and steps < MAX_STEPS and not game.s.parked do
        if run.recording(game.s, game.input) then run.record(game.run, game.input) end
        session.update(game.s, game.input, DT)
        -- the ghost counts the player's own steps, and only once the player has
        -- started: otherwise the ghost waits out your thinking time and then
        -- jumps forward when you finally move
        if game.s.started then game.steps = game.steps + 1 end
        game.acc = game.acc - DT
        steps = steps + 1
    end
    advance_ghost()
    if steps >= MAX_STEPS then game.acc = 0 end

    -- Cues are drained once per frame, after whatever steps ran: a step list
    -- that emits two bumps in one frame must still make two sounds, and one
    -- that emits none must not repeat the last.
    local cues = session.drain(game.s)
    sfx.cues(game.sfx, cues)
    -- The card's arithmetic, at the moment it happens: a price only discovered on
    -- the result panel is a rule the player learns too late. Damage speaks last,
    -- because it is the one that voids the attempt.
    for _, c in ipairs(cues) do
        if c.kind == "cone" then
            say(string.format("cone  +%.2f s", c.penalty or 0), 2)
        elseif c.kind == "bump" and (c.cause == "wall" or c.cause == "jackknife") then
            say("car damaged - this attempt cannot set a record", 3)
        end
    end

    -- The result card stops the player's clock, not the ghost's: a best run that
    -- was still on the road when you beat it finishes its line instead of
    -- freezing at the moment you won. Same fixed cadence as the sim, so it drives
    -- rather than teleports.
    if game.s.parked and game.ghost then
        local _, left = run.follow(game.ghost, game.acc, DT, MAX_STEPS)
        game.acc = left
    end

    -- The park is the event that writes progress. record() gets the session the
    -- game produced (all of its numbers are the sim's own), and the store writes
    -- once, on the transition, not every frame the card is on screen.
    if not parked_before and game.s.parked then
        run.finish(game.run, game.s)
        local f = game.s.final
        local before = progress.mark(game.progress, game.level).best
        local _, improved = progress.record(game.progress, game.level, game.s)
        game.new_best = improved and true or false
        -- the card compares the counted time against the record that stood when
        -- the run ended: read before record() replaces it, so a new best still
        -- shows what it beat and a slower run shows the gap it has to close
        game.record = before
        game.delta = before and (f.time - before) or nil
        -- the ghost is the BEST run, so a slower park must not overwrite it
        local text = improved and run.encode(game.run, game.codec) or nil
        if text then progress.put_ghost(game.progress, game.level, text) end
        progress.save(game.progress)
    end

    local impact = game.s.bump_flash > 0.30 and 1 or nil
    input.rumble(game.input, rig.art(game.s.rig), impact)
end

local function update_menu(dt)
    local acts = input.poll_menu(game.input)
    if acts.up then
        menu.move(game.menu, -1)
        sfx.one(game.sfx, "ui_tick", 0.45)
    end
    if acts.down then
        menu.move(game.menu, 1)
        sfx.one(game.sfx, "ui_tick", 0.45)
    end
    if acts.left or acts.right then
        menu.cycle_tab(game.menu, 1)
        sfx.one(game.sfx, "ui_tick", 0.45, 1.2)
    end
    if acts.confirm then
        sfx.one(game.sfx, "ui_confirm", 0.55)
        open_selected()
    end
    if acts.cancel then love.event.quit() end
end

local function draw_play()
    love.graphics.push()
    love.graphics.translate(game.ox, game.oy)
    love.graphics.scale(game.scale, -game.scale)
    draw.scene(game.level, game.s, { guide = game.guide, input = game.input })
    if game.ghost and game.ghost_mode ~= "off" then
        draw.ghost(game.ghost, game.ghost_mode)
    end
    love.graphics.pop()

    draw.hud(game.s, game)
    if game.debug then draw.debug(game.s, game) end
    if game.s.parked then draw.overlay(game.s, game) end
end

-- `love . --smoke` renders every screen once and exits: a boot check that
-- actually exercises the draw path instead of just surviving 4 seconds. Frames
-- that force a state freeze the sim, so a PNG cannot depend on frame timing.
local function smoke_step()
    smoke.frames = smoke.frames + 1
    if smoke.frames == 1 then
        -- The arc ships OFF. Assert it, then turn it on: smoke-scene.png is the
        -- shipped state (no dots), and every frame after it covers the arc's
        -- draw path. Without the assert, a default flipped back on would pass.
        assert(game.guide == false, "the guide arc must ship off by default")
        love.graphics.captureScreenshot("smoke-scene.png")
        print("SAVE DIR " .. love.filesystem.getSaveDirectory())
        game.guide = true
    elseif smoke.frames == 2 then
        -- full lock: the frame that has to show steered wheels and rays
        -- (and, since frame 1 turned the arc on, the curved reverse arc)
        -- frozen, or the steering ramp unwinds by however many steps this frame
        -- happens to run: the capture lands AFTER the next update, so the pose
        -- depended on wall-clock timing (and on how long boot took)
        smoke.frozen = true
        game.input.steer = 0.8
        game.s.rig.steer = rig.CAR.max_steer * 0.8
        game.s.rig.ph = game.s.rig.th - math.rad(12)
    elseif smoke.frames == 3 then
        love.graphics.captureScreenshot("smoke-steer.png")
        game.input.steer = 0
    elseif smoke.frames == 4 then
        game.s.parked = true
        game.s.t = 12.5
        -- the slower-than-record card: 12.50 driven + 2.00 for one cone, against a
        -- record that stood at 13.20
        game.s.final = { time = 14.50, driven = 12.50, penalties = 2.00, cone_hits = 1,
                         bumps = 1, angle_err = 1.2, damaged = false, damage = nil }
        game.s.bumps, game.s.cone_hits = 1, 1   -- the HUD must agree with the card
        game.record, game.delta, game.new_best = 13.20, 1.30, false
        -- Where the card says it went: a PARKED card over an empty bay is the
        -- smoke lying to itself, and 1.2 deg is the angle the card prints.
        session.place_caravan(game.s, game.level.bay.x, game.level.bay.y,
            game.level.bay.angle + math.rad(1.2))
    elseif smoke.frames == 5 then
        love.graphics.captureScreenshot("smoke-parked.png")
        game.debug = true
        -- The cue path end to end: a real jackknife produced by the session,
        -- out of update_play's drain, into the mixer. The PNGs prove none of
        -- that, and the state above was forced by hand, so it cannot.
        game.s.parked = false
        game.s.rig.ph = game.s.rig.th + math.rad(85)
        local before = #game.sfx_log
        smoke.frozen = false                 -- this one needs a real step
        update_play(0.1)
        smoke.frozen = true
        assert(#game.sfx_log > before, "update_play never drained a cue")
        assert(game.sfx_log[#game.sfx_log] == "jackknife",
            "the jackknife cue never reached the mixer: " .. tostring(game.sfx_log[#game.sfx_log]))
        print("SFX CUE PATH OK")
    elseif smoke.frames == 6 then
        -- level 2 in the bay, facing the wrong way: the frame that has to show
        -- the required-facing arrow and the corrective ghost
        game.debug = false
        load_level(2)
        session.place_caravan(game.s, game.level.bay.x, game.level.bay.y,
            game.level.bay.angle + math.pi)
    elseif smoke.frames == 7 then
        love.graphics.captureScreenshot("smoke-wrongway.png")
        game.paused = true
    elseif smoke.frames == 8 then
        love.graphics.captureScreenshot("smoke-paused.png")
    elseif smoke.frames == 9 then
        -- driving forward: the guide arc must be absent (it is a reverse assist;
        -- forward it spanned the whole yard). Compare with smoke-steer.png, which
        -- is the same level at rest with the arc ON -- so the toggle has to be on
        -- here too, or this frame proves nothing.
        assert(game.guide, "the forward frame must run with the arc enabled")
        game.paused = false
        load_level(1)
        smoke.frozen = true
        game.input.steer = 0.5
        game.s.rig.steer = rig.CAR.max_steer * 0.5
        game.s.rig.v = 5.0
        game.s.t = 3.0
        game.s.started = true
    elseif smoke.frames == 10 then
        love.graphics.captureScreenshot("smoke-forward.png")
    elseif smoke.frames == 11 then
        -- the title screen, drawn from the scripted store above: three marks and
        -- one "level changed" card, the same on every machine. last_played is a
        -- level that is NOT row one, so the frame proves the cursor came back to
        -- the level that was played rather than to the default.
        game.last_played = "fire-side"
        open_menu()
    elseif smoke.frames == 12 then
        love.graphics.captureScreenshot("smoke-menu.png")
    elseif smoke.frames == 13 then
        -- the ghost: built from a real drive here, not drawn from a picture of
        -- one, and advanced to a mid-run step so the trail has something to show
        game.mode = MODE.play
        load_level(1)
        game.ghost = smoke_ghost(game.level)
        game.steps = 480
        advance_ghost()
        smoke.frozen = true
    elseif smoke.frames == 14 then
        love.graphics.captureScreenshot("smoke-ghost.png")
    elseif smoke.frames == 15 then
        -- The player parks mid-run (a new best): the ghost still has its own line
        -- to drive. Step the shell at a fixed dt -- exactly what a real frame
        -- does -- and require the ghost to have moved.
        local gh = game.ghost
        game.paused = false
        game.s.parked = true
        game.s.t = 30
        game.s.final = { time = 30, bumps = 0, angle_err = 0.4 }
        game.steps = 30
        gh.step, gh.s = 0, session.new(game.level)
        run.advance(gh, 30)
        assert(not gh.s.parked, "fixture: the ghost must not have parked yet")
        smoke.frozen = false
        update_play(0.1)
        smoke.frozen = true
        assert(gh.step > 30,
            string.format("the ghost stopped when the player parked (%d/%d)", gh.step, #gh.run.frames))
    elseif smoke.frames == 16 then
        love.graphics.captureScreenshot("smoke-ghost-after-park.png")
        -- and it keeps driving until its own run ends, not just one frame
        smoke.frozen = false
        for _ = 1, 10000 do
            update_play(0.1)
            if game.ghost.s.parked then break end
        end
        smoke.frozen = true
        assert(game.ghost.s.parked, "the ghost never finished its run after the park")
        assert(game.ghost.step == #game.ghost.run.frames,
            string.format("the ghost left frames undriven: %d/%d",
                game.ghost.step, #game.ghost.run.frames))
        print("GHOST FINISHED AFTER PARK")
    elseif smoke.frames == 17 then
        -- the editor on a shipped level, with a prop selected and an error
        -- showing: the frame that has to prove the rails are readable
        open_editor(levels.get(1))
        local e = game.editor
        local W, H = love.graphics.getDimensions()

        -- Opening an untouched level is not a modification: leaving now must not
        -- ask. Skipped only when this machine really has unsaved work for the
        -- level, which the editor restores and rightly calls modified.
        local had_autosave = autosave.load(disk, "straight-back") ~= nil
        if not had_autosave then
            assert(not editor_dirty(), "opening an untouched level marked it modified")
        end
        -- Autosave is throttled out for this frame: the gestures below really do
        -- edit the document, and the smoke must not leave a recovery file behind.
        e.autosave_state = { at = math.huge, text = "" }

        -- Esc with a tool armed is "put the tool down", not "leave": it falls back
        -- to `select` so the thing you just placed can be adjusted. This calls the
        -- error handler's own key path, so it guards the real branch.
        e.tool = "umbrella"
        editor_keypressed("escape")
        assert(e.tool == "select",
            "Esc with a tool armed must fall back to select, got " .. tostring(e.tool))
        assert(game.mode == MODE.editor, "Esc with a tool armed must not leave the editor")
        print("EDITOR ESC -> SELECT")
        game.toast = nil                      -- keep the capture unchanged

        -- A click is not a drag: selecting a prop that sits off the snap grid must
        -- leave it exactly where it is. It used to snap onto the grid on the way
        -- to merely selecting, which also made Esc ask about unsaved work.
        local off_grid
        for _, c in ipairs(e.doc.level.cones) do
            if math.abs(math.floor(c.x / SNAP + 0.5) * SNAP - c.x) > 1e-9 then
                off_grid = c
                break
            end
        end
        assert(off_grid, "fixture: level 1 must have a prop off the snap grid")
        local ox, oy = off_grid.x, off_grid.y
        local px = W / 2 + (ox - e.cam.x) * e.cam.scale
        local py = H / 2 - (oy - e.cam.y) * e.cam.scale
        -- the corner test just left a wall selected, and a handle is grabbable
        -- anywhere within 9 px of it: drop it so this click is a click
        doc.deselect(e.doc)
        local dirty_before_click = editor_dirty()
        editor_mousepressed(px, py, 1)
        editor_mousemoved(px + 1, py, 0, 0)     -- a hand wobble, not a drag
        editor_mousereleased(px + 1, py, 1)
        assert(off_grid.x == ox and off_grid.y == oy,
            string.format("a click nudged the prop: %.3f,%.3f -> %.3f,%.3f",
                ox, oy, off_grid.x, off_grid.y))
        assert(editor_dirty() == dirty_before_click, "a click marked the level modified")
        print("EDITOR CLICK LEAVES THE DOC ALONE")

        -- and a real drag still moves it: the slop must not disable dragging
        editor_mousepressed(px, py, 1)
        editor_mousemoved(px + 30, py, 0, 0)
        editor_mousereleased(px + 30, py, 1)
        assert(off_grid.x ~= ox, "a 30 px drag must still move the prop: " .. off_grid.x)
        assert(editor_dirty(), "a real move is a modification, but nothing reported it")
        print("EDITOR DRAG STILL MOVES")

        -- A corner drag must pin the opposite corner -- through the editor's own
        -- mouse path, with the tool on `select` as it is when a player grabs a
        -- handle. Autosave is throttled out for this frame above.
        local free_wall
        for _, w in ipairs(e.doc.level.walls) do
            if props.resize_mode(w.kind) == "free" then free_wall = w break end
        end
        assert(free_wall, "fixture: level 1 must have a stretchable wall")
        doc.pick(e.doc, free_wall.x, free_wall.y, 0.4)
        local hs = doc.resize_handles(e.doc)
        assert(#hs == 4, "fixture: the selected wall must offer corners")
        local grabbed, opposite = hs[4], hs[1]
        local ax, ay = opposite.x, opposite.y
        local sx = W / 2 + (grabbed.x - e.cam.x) * e.cam.scale
        local sy = H / 2 - (grabbed.y - e.cam.y) * e.cam.scale
        editor_mousepressed(sx, sy, 1)          -- grabs the handle: the real path
        editor_mousemoved(sx + 40, sy + 25, 0, 0)
        editor_mousereleased(sx + 40, sy + 25, 1)
        local after = doc.resize_handles(e.doc)
        local still
        for _, h in ipairs(after) do
            if h.sx == -grabbed.sx and h.sy == -grabbed.sy then still = h end
        end
        assert(still, "fixture: the pinned corner must still exist")
        assert(math.abs(still.x - ax) < 1e-9 and math.abs(still.y - ay) < 1e-9,
            string.format("a corner drag moved the opposite corner: (%.4f, %.4f) -> (%.4f, %.4f)",
                ax, ay, still.x, still.y))
        assert(after[4].x ~= grabbed.x or after[4].y ~= grabbed.y,
            "the drag changed nothing, so the pin was never exercised")
        print(string.format("EDITOR DRAG pinned (%.3f, %.3f), wall now %.2f x %.2f",
            still.x, still.y, props.footprint(free_wall).w, props.footprint(free_wall).h))

        -- Esc walks back out one step at a time. Arming a tool drops the previous
        -- selection, so Esc can honestly land on the last placement -- or on
        -- nothing, if nothing was placed.
        editor_arm("cone")
        assert(e.doc.selection == nil, "arming a placement tool must clear the selection")
        editor_keypressed("escape")
        assert(e.tool == "select", "Esc with a tool armed must go back to select")
        assert(e.doc.selection == nil, "and leave nothing selected when nothing was placed")

        editor_arm("cone")
        local place_x, place_y = e.doc.level.spawn.x + 4, e.doc.level.spawn.y + 4
        editor_mousepressed(W / 2 + (place_x - e.cam.x) * e.cam.scale,
                            H / 2 - (place_y - e.cam.y) * e.cam.scale, 1)
        local placed = e.doc.selection
        assert(placed and placed.list == "cones", "placing must select what it placed")
        editor_keypressed("escape")
        assert(e.tool == "select", "Esc with a tool armed must go back to select")
        assert(e.doc.selection == placed, "and keep the last placement selected for editing")
        editor_keypressed("escape")
        assert(e.doc.selection == nil, "Esc with a selection must clear it")
        assert(game.mode == MODE.editor, "clearing a selection must not leave the editor")
        print("EDITOR ESC LADDER")

        -- the placed cone was a fixture: take it back out of the picture
        e.doc.selection = placed
        doc.remove(e.doc)
        editor_errors()

        -- Left-drag on the map pans it. The click test above is the other half:
        -- a press that never travels still picks. A drag must also not edit.
        local camx, camy = e.cam.x, e.cam.y
        local before_pan = doc.snapshot(e.doc)
        local gx, gy = W * 0.62, H * 0.7
        editor_mousepressed(gx, gy, 1)
        editor_mousemoved(gx + 60, gy, 0, 0)
        editor_mousereleased(gx + 60, gy, 1)
        assert(math.abs(e.cam.x - camx) > 1,
            string.format("a 60 px drag on the map must pan it, the camera stayed at %.3f", e.cam.x))
        assert(doc.snapshot(e.doc) == before_pan, "panning the map must not edit the document")
        e.cam.x, e.cam.y = camx, camy
        print("EDITOR DRAG PANS THE MAP")

        -- the frame itself: a tool armed, the new kinds placed, a wall selected
        e.tool = "hedge"
        doc.add(e.doc, "rv", e.doc.level.spawn.x, e.doc.level.spawn.y)
        -- the two new campsite kinds, placed where the yard is empty: the frame
        -- has to show their art, not just their footprint
        doc.add(e.doc, "umbrella", 52, 33)
        doc.add(e.doc, "table", 52, 7)
        -- a wall that CAN be stretched, selected last so the frame shows handles
        for _, w in ipairs(e.doc.level.walls) do
            if props.resize_mode(w.kind) == "free" then
                doc.pick(e.doc, w.x, w.y, 0.4)
                break
            end
        end
        editor_errors()

        -- put the pointer over the yard so the frame shows the placement preview.
        -- Injected, not warped: see draw.set_pointer.
        draw.set_pointer({ x = math.floor(W * 0.62), y = math.floor(H * 0.52) })
    elseif smoke.frames == 18 then
        love.graphics.captureScreenshot("smoke-editor.png")
    elseif smoke.frames == 19 then
        -- the custom tab, empty: the state a player meets before importing
        open_menu()
        menu.switch_tab(game.menu, "custom")
    elseif smoke.frames == 20 then
        love.graphics.captureScreenshot("smoke-menu-custom-empty.png")
    elseif smoke.frames == 21 then
        -- and with one imported level in it
        game.custom = { doc.level(doc.blank("my-level", "My level")) }
        menu.rebuild(game.menu, levels.ALL, game.custom)
        menu.switch_tab(game.menu, "custom")
    elseif smoke.frames == 22 then
        love.graphics.captureScreenshot("smoke-menu-custom.png")
    elseif smoke.frames == 23 then
        -- a new level: the blank site a player meets on "N", with the bay
        -- selected so the frame shows what selecting the goal looks like
        new_level()
        doc.select(game.editor.doc, "bay")
    elseif smoke.frames == 24 then
        love.graphics.captureScreenshot("smoke-editor-new.png")
    elseif smoke.frames == 25 then
        -- the question Esc asks when there is unsaved work. The flag is derived
        -- from the document now, so make a real edit rather than setting it.
        local d = game.editor.doc
        doc.add(d, "tent", d.level.spawn.x, d.level.spawn.y)
        assert(editor_dirty(), "fixture: the added tent must read as unsaved work")
        game.editor.prompt = true
    elseif smoke.frames == 26 then
        love.graphics.captureScreenshot("smoke-editor-prompt.png")
        -- the forced document is a fixture, not the player's work: mark it saved so
        -- quitting the smoke does not leave a recovery file in the save directory
        game.editor.baseline = doc.snapshot(game.editor.doc)
    elseif smoke.frames == 27 then
        -- R restarts the level you are PLAYING, not the catalogue slot it is not
        -- in: a custom track has no index in levels.ALL, and the old reload threw
        -- the player into whatever campaign level was last played.
        local custom = doc.level(doc.blank("smoke-custom", "Smoke custom"))
        load_level_object(custom)
        game.mode = MODE.play
        love.keypressed("r")          -- the real dispatch, not the handler directly
        assert(game.level and game.level.id == "smoke-custom",
            "R loaded " .. tostring(game.level and game.level.id) .. " instead of the custom level")
        love.keypressed("tab")
        assert(game.level.id == "smoke-custom",
            "Tab jumped a custom level into the campaign: " .. tostring(game.level.id))
        print("R RESTARTS THE ACTIVE LEVEL")

        -- An imported custom track arrives with a ghost. Before, the blob was
        -- written with no progress entry, so ghost_text() never looked for it and
        -- the sender's line was invisible forever.
        local imp = levelfmt.decode(levelfmt.encode(levels.get(1)))
        imp.id, imp.name = "smoke-import", "Smoke import"
        imp.series, imp.order = nil, nil
        local si, ri = session.new(imp), run.new(imp)
        local stop = imp.bay.x - (rig.CARAVAN.coupling - rig.CARAVAN.length / 2)
        local tt = 0
        while tt < 60 and not si.parked do
            local inp = (si.rig.x > stop)
                and { steer = 0, throttle = 0, brake = 1, handbrake = false }
                or { steer = 0, throttle = 0, brake = 0, handbrake = true }
            run.record(ri, inp)
            session.update(si, inp, 1 / 120)
            tt = tt + 1 / 120
        end
        run.finish(ri, si)
        assert(si.parked, "fixture: the import level parks")
        import_text(share.code(share.bundle(imp, ri, game.codec, "user"), game.codec))
        assert(game.level and game.level.id == "smoke-import", "the import did not open its level")
        assert(game.ghost ~= nil, "an imported level must show the ghost it arrived with")
        print("IMPORT SHOWS ITS GHOST")
        levelfmt.delete_custom(disk, "smoke-import")
        if love.filesystem.read(levelfmt.CUSTOM_INDEX) == "" then
            disk.remove(levelfmt.CUSTOM_INDEX)     -- leave the save directory as we found it
        end
        game.custom = levelfmt.scan_custom(disk)
    elseif smoke.frames == 28 then
        -- The card's numbers come from the park, not from the fixture: park level 1
        -- through the real loop (its store says the record is 13.21) and check the
        -- record and the delta the shell hands the card.
        load_level(1)
        game.s.started = true
        game.s.t = 15.0                      -- a 15.00 run: slower than 13.21
        session.place_caravan(game.s, game.level.bay.x, game.level.bay.y, game.level.bay.angle)
        smoke.frozen = false
        for _ = 1, 20 do
            update_play(0.1)
            if game.s.parked then break end
        end
        smoke.frozen = true
        assert(game.s.parked, "fixture: the placed caravan must park through update_play")
        assert(math.abs((game.record or 0) - 13.21) < 0.005,
            "the card did not get the record: " .. tostring(game.record))
        assert(game.delta and math.abs(game.delta - (game.s.final.time - game.record)) < 1e-9,
            "the delta must be counted time minus record: " .. tostring(game.delta))
        assert(game.new_best == false, "a slower run is not a new best")
        print(string.format("CARD record %.2f  time %.2f  delta %+.2f",
            game.record, game.s.final.time, game.delta))
    elseif smoke.frames == 29 then
        -- the result card's other two states, forced: new best (a record it beat)
        -- and a void attempt (a time that does not stand)
        game.toast = nil                       -- the import toast is a previous frame's news
        game.s.parked = true
        game.s.t = 21.0
        game.s.final = { time = 21.00, driven = 21.00, penalties = 0, cone_hits = 0,
                         bumps = 0, angle_err = 0.6, damaged = false, damage = nil }
        game.record, game.delta, game.new_best = 22.50, -1.50, true
    elseif smoke.frames == 30 then
        love.graphics.captureScreenshot("smoke-result-best.png")
        game.new_best = false
        game.s.t, game.s.bumps = 23.10, 1
        game.s.final = { time = 23.10, driven = 23.10, penalties = 0, cone_hits = 0,
                         bumps = 1, angle_err = 1.4, damaged = true, damage = "wall" }
        game.record, game.delta = 22.50, 0.60
    elseif smoke.frames == 31 then
        love.graphics.captureScreenshot("smoke-result-invalid.png")
        print("RESULT CARD STATES")
    elseif smoke.frames == 32 then
        -- The palette's words live in a tooltip now that the tiles are icons with
        -- 8 px names, and a tooltip nobody ever sees is the same as not having
        -- one. Hover a tile through the real pointer and require the hit test --
        -- the thing the tooltip is drawn from -- to name it.
        open_editor(levels.get(1))
        local e = game.editor
        e.autosave_state = { at = math.huge, text = "" }
        e.baseline = doc.snapshot(e.doc)      -- a fixture, not the player's work
        local W, H = love.graphics.getDimensions()
        local hover
        for _, t in ipairs(draw.palette_layout(e.palette, W, H).tiles) do
            if (t.item.tool or t.item.kind) == "umbrella" then hover = t end
        end
        assert(hover, "fixture: the umbrella tile must be on the rail")
        -- the pointer is injected: love.mouse.setPosition does nothing on Wayland,
        -- so warping here hovered whatever the real cursor was over
        local mx = math.floor(hover.x + hover.w / 2)
        local my = math.floor(hover.y + hover.h / 2)
        draw.set_pointer({ x = mx, y = my })
        local under = draw.editor_tool_at(mx, my, e.palette)
        assert(under == "umbrella",
            "the pointer on the umbrella tile answered " .. tostring(under))
        print("PALETTE HOVER -> UMBRELLA")
    elseif smoke.frames == 33 then
        love.graphics.captureScreenshot("smoke-editor-palette.png")
    elseif smoke.frames >= 34 then
        draw.set_pointer(nil)
        print("SMOKE OK")
        love.event.quit(0)
    end
end

local function menu_delete()
    local lvl = menu.confirm(game.menu)
    if not (lvl and menu.current_tab(game.menu) == "custom") then return end
    game.confirm_delete = { id = lvl.id, name = lvl.name }
end

local function menu_keypressed(key)
    -- a pending delete owns the keys until it is answered
    if game.confirm_delete then
        if key == "return" or key == "kpenter" then
            local id = game.confirm_delete.id
            game.confirm_delete = nil
            levelfmt.delete_custom(disk, id)
            game.custom = levelfmt.scan_custom(disk)
            menu.rebuild(game.menu, levels.ALL, game.custom)
            say("deleted " .. id)
        elseif key == "escape" then
            game.confirm_delete = nil
        end
        return
    end

    if key == "escape" then
        love.event.quit()
    elseif key == "m" then
        say(sfx.toggle(game.sfx) and "sound off   (M again to restore)" or "sound on", 2)
    elseif key == "tab" or key == "left" or key == "right" then
        sfx.one(game.sfx, "ui_tick", 0.45, 1.2)
        menu.cycle_tab(game.menu, 1)
    elseif key == "n" then
        new_level()
    elseif key == "e" then
        local lvl = menu.current(game.menu)
        if lvl then open_editor(lvl) end
    elseif key == "x" then
        menu_delete()
    elseif key == "up" or key == "w" then
        sfx.one(game.sfx, "ui_tick", 0.45)
        menu.move(game.menu, -1)
    elseif key == "down" or key == "s" then
        sfx.one(game.sfx, "ui_tick", 0.45)
        menu.move(game.menu, 1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        sfx.one(game.sfx, "ui_confirm", 0.55)
        open_selected()
    elseif key == "i" then
        import_text(love.system.getClipboardText() or "")
        menu.rebuild(game.menu, levels.ALL, game.custom)
    end
end

local function play_keypressed(key)
    if key == "escape" then
        if game.playtest then
            game.playtest = false
            game.mode = MODE.editor
        else
            open_menu()
        end
    elseif key == "r" then
        reload_level()
    elseif key == "g" then
        game.guide = not game.guide
    elseif key == "p" then
        game.paused = not game.paused
    elseif key == "y" then
        export_share()
    elseif key == "i" then
        import_text(love.system.getClipboardText() or "")
    elseif key == "h" then
        local order = { "rig", "trail", "off" }
        local at_mode = 1
        for i, m in ipairs(order) do if m == game.ghost_mode then at_mode = i end end
        game.ghost_mode = order[(at_mode % #order) + 1]
    elseif key == "m" then
        say(sfx.toggle(game.sfx) and "sound off   (M again to restore)" or "sound on", 2)
    elseif key == "f1" then
        game.debug = not game.debug
    elseif key == "f5" then
        -- re-read the store: "what did the last park actually write?"
        game.progress = progress.open(disk)
        local n = 0
        for _ in pairs(game.progress.entries) do n = n + 1 end
        local msg = string.format("progress: %d level(s) on disk", n)
        if #game.progress.warnings > 0 then msg = msg .. "  (" .. game.progress.warnings[1] .. ")" end
        print(msg)
    elseif key == "n" and game.s.parked then
        next_campaign_level()
    elseif key == "tab" then
        next_campaign_level()
    end
end

function love.resize()
    game.scale, game.ox, game.oy = camera(game.level)
end

function love.filedropped(file)
    file:open("r")
    local text = file:read()
    file:close()
    if text then import_text(text) else say("that file could not be read", 6) end
end

function love.joystickadded()
    input.refresh(game.input)
end

function love.joystickremoved()
    input.refresh(game.input)
end

-- ---------------------------------------------------------------------------
-- Mode dispatch: the only place that knows more than one screen exists. Adding
-- the editor is a branch here, not a change to the play loop.
-- ---------------------------------------------------------------------------

function love.update(dt)
    -- The window, again, once it is really on screen: see fix_window_size.
    if not window_settled and window_frames < 8 then
        window_frames = window_frames + 1
        fix_window_size("frame " .. window_frames)
    end
    if game.mode ~= MODE.editor then
        if game.mode == MODE.play then
            update_play(dt)
        else
            update_menu(dt)
        end
    end
    -- One mixer tick per frame, for every screen. The loops are silenced by
    -- volume rather than stopped, so changing mode cannot leave the engine
    -- running in the menu and cannot click when it comes back.
    sfx.update(game.sfx, game.s, game.mode == MODE.play and not game.paused, dt)
end

function love.draw()
    if game.mode == MODE.play then
        draw_play()
    elseif game.mode == MODE.menu then
        draw.menu(game.menu, game)
    elseif game.mode == MODE.editor then
        draw_editor()
    end
    if smoke.enabled then smoke_step() end
end

function love.keypressed(key)
    if game.mode == MODE.play then
        play_keypressed(key)
    elseif game.mode == MODE.menu then
        menu_keypressed(key)
    elseif game.mode == MODE.editor then
        editor_keypressed(key)
    end
end

-- Closing the window is not a save dialog: keep what was typed.
function love.quit()
    editor_autosave_now()
end

function love.textinput(text)
    if game.mode == MODE.editor and game.editor.typing then
        game.editor.typing.buffer = game.editor.typing.buffer .. text
    end
end

function love.mousepressed(x, y, button)
    if game.mode == MODE.editor then editor_mousepressed(x, y, button) end
end

function love.mousemoved(x, y, dx, dy)
    if game.mode == MODE.editor then editor_mousemoved(x, y, dx, dy) end
end

function love.mousereleased(x, y, button)
    if game.mode == MODE.editor then editor_mousereleased(x, y, button) end
end

function love.wheelmoved(dx, dy)
    if game.mode == MODE.editor then editor_wheelmoved(dx, dy) end
end
