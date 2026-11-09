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
local levelcheck = require("lib.levelcheck")

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

-- Everything the editor can place. "select" is a tool, not a kind: the palette
-- is one list so the player's eye does not have to sort it into two.
local PALETTE = { "select", "bay", "spawn", "hedge", "building", "tent", "rv", "car", "pool", "table",
                  "cone", "firepit", "chair", "umbrella", "gravel", "grass", "deck" }
local SNAP = 0.5

local game = {
    mode = MODE.menu,
    index = 1,
    guide = true,
    debug = false,
    paused = false,
    acc = 0,
    steps = 0,
    new_best = false,
    gain = nil,
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

local function load_level_object(lvl)
    game.last_played = lvl and lvl.id or game.last_played
    game.index = levels.find(lvl.id) or game.index
    game.level = lvl
    game.s = session.new(game.level)
    game.run = run.new(game.level)
    game.acc = 0
    game.steps = 0
    game.new_best = false
    game.gain = nil
    game.input.steer, game.input.throttle, game.input.brake, game.input.handbrake = 0, 0, 0, false
    game.scale, game.ox, game.oy = camera(game.level)

    -- The stored best run, verified before it is allowed on screen: a ghost that
    -- was recorded on other geometry is not a ghost, it is a different level's
    -- run wearing this level's name.
    game.ghost = nil
    if game.progress and game.codec then
        local text = progress.ghost_text(game.progress, game.level)
        local g = text and run.decode(text, game.codec)
        if g and run.verify(game.level, g) then
            -- runs stored before recording began with the first action carry an
            -- idle prefix; without this the ghost hesitates at the start line
            run.trim(g)
            game.ghost = {
                run = g, trail = run.trace(game.level, g),
                s = session.new(game.level), step = 0,
            }
        end
    end
end

local function load_level(n)
    load_level_object(levels.get(n))
end

local function say(text, seconds)
    game.toast = { text = text, expires = love.timer.getTime() + (seconds or 4) }
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
        if got.run and run.verify(got.level, got.run) then
            progress.put_ghost(game.progress, got.level, run.encode(got.run, game.codec))
        end
        game.custom = levelfmt.scan_custom(disk)
        if game.menu then menu.rebuild(game.menu, levels.ALL, game.custom) end
        -- open it: an imported level you cannot play is a download, not a level
        load_level_object(got.level)
        game.mode = MODE.play
        say("imported " .. tostring(got.level.name))
    elseif got.run then
        local ok, why = run.verify(game.level, got.run)
        if ok then
            progress.put_ghost(game.progress, game.level, run.encode(got.run, game.codec))
            load_level(game.index)
            say("rival ghost loaded")
        else
            say("that run does not fit this level: " .. tostring(why), 6)
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

local function editor_autosave_now()
    local e = game.editor
    if not e or not e.dirty then return end
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
    e.dirty = true
    editor_errors()
    editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
end

local function open_editor(lvl)
    if not EDITOR_ENABLED then return end
    local W, H = love.graphics.getDimensions()
    local b = lvl.bounds
    game.editor = {
        doc = doc.new(lvl),
        undo = undo.new(),
        cam = {
            x = (b.x0 + b.x1) / 2,
            y = (b.y0 + b.y1) / 2,
            scale = math.min((W - 300) / (b.x1 - b.x0), (H - 120) / (b.y1 - b.y0)),
        },
        origin_id = lvl.id,      -- what this document was opened as; see editor_export_lua
        tool = "select",
        snap = SNAP,
        palette = PALETTE,
        errors = {},
        dirty = false,
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
                game.editor.dirty = true
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
    e.dirty = false
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

    if key == "escape" then
        -- never leave silently with unsaved work: a copy is kept either way, but
        -- "did my edit go anywhere?" is a question the editor should answer
        editor_autosave_now()
        if e.dirty then
            e.prompt = true
        else
            open_menu()
        end
    elseif key == "f2" then
        e.typing = { buffer = e.doc.level.name or "", original = e.doc.level.name or "" }
    elseif key == "leftbracket" or key == "rightbracket" then
        local n = #e.palette
        local i = 1
        for j, name in ipairs(e.palette) do if name == e.tool then i = j end end
        i = ((i - 1 + (key == "rightbracket" and 1 or -1)) % n) + 1
        e.tool = e.palette[i]
    elseif ctrl and key == "z" then
        local text = undo.back(e.undo)
        if text then
            doc.restore(e.doc, text)
            editor_errors()
            e.dirty = true
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
        if tool then
            e.tool = tool
            if tool ~= "select" then say(tool .. ": click the yard to place it", 3) end
        end
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
                -- which corner was grabbed decides which one is pinned
                e.resizing = { sx = h.sx, sy = h.sy }
                return
            end
        end

        local sel = doc.pick(e.doc, wx, wy, 0.4 / e.cam.scale)
        local entry = sel and (sel.list == "bay" or sel.list == "spawn")
            and e.doc.level[sel.list] or (sel and (e.doc.level[sel.list] or {})[sel.index])
        if entry then e.drag = { wx = wx, wy = wy, ox = entry.x, oy = entry.y } end
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

    if e.resizing then
        -- The corner opposite the grab stays put: the drag sizes the prop away
        -- from the edge you already lined up, which is how a gap gets filled.
        local wx, wy = editor_to_world(x, y)
        doc.resize_to_cursor(e.doc, e.resizing, wx, wy, e.snap)
        e.dirty = true
        editor_errors()
        editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
        return
    end

    if e.pan then
        e.cam.x = e.pan.cx - (x - e.pan.x) / e.cam.scale
        e.cam.y = e.pan.cy + (y - e.pan.y) / e.cam.scale
        return
    end
    if e.drag then
        local wx, wy = editor_to_world(x, y)
        local sel = e.doc.selection
        local entry = sel and ((sel.list == "bay" or sel.list == "spawn")
            and e.doc.level[sel.list] or (e.doc.level[sel.list] or {})[sel.index])
        if not entry then return end
        local nx = snap(e.drag.ox + (wx - e.drag.wx), e.snap)
        local ny = snap(e.drag.oy + (wy - e.drag.wy), e.snap)
        if nx ~= entry.x or ny ~= entry.y then
            if not e.drag.pushed then
                undo.push(e.undo, doc.snapshot(e.doc))
                e.drag.pushed = true
            end
            entry.x, entry.y = nx, ny
            e.dirty = true
            editor_errors()
            editor_autosave(e.origin_id or e.doc.level.id, doc.snapshot(e.doc))
        end
    end
end

local function editor_mousereleased(x, y, button)
    local e = game.editor
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
    local fakest = {
        read = function() return nil end,
        write = function() return true end,
        remove = function() return true end,
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
    local want_edit = false
    for _, a in ipairs(args or {}) do
        if a == "--edit" then want_edit = true end
    end

    love.graphics.setBackgroundColor(0.05, 0.05, 0.06)
    draw.init()
    input.init(game.input)
    game.codec = codec.love_data()
    game.progress = smoke.enabled and smoke_progress() or progress.open(disk)
    if not smoke.enabled then
        local imported, warnings = levelfmt.scan_custom(disk)
        game.custom = imported
        for _, w in ipairs(warnings) do print("custom: " .. w) end
    end
    load_level(game.index)
    -- the smoke harness drives play frames itself; a normal launch starts on the
    -- title screen
    game.mode = smoke.enabled and MODE.play or MODE.menu
    if game.mode == MODE.menu then open_menu() end
    if want_edit and not smoke.enabled then open_editor(levels.get(1)) end

    -- LÖVE's default error handler is an interactive loop: a draw-time error
    -- under --smoke sits there until something kills it, so the run reports as a
    -- timeout (124) rather than as a failure with a traceback. It has happened.
    if smoke.enabled then
        love.errorhandler = function(msg)
            print("SMOKE ERROR: " .. tostring(msg))
            print(debug.traceback("", 2))
            io.stdout:flush()
            os.exit(1)
        end
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
        load_level(game.index)
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
        local before = progress.mark(game.progress, game.level).best
        local _, improved = progress.record(game.progress, game.level, game.s)
        game.new_best = improved and true or false
        game.gain = (before and game.s.final.time) and (before - game.s.final.time) or nil
        if game.gain and game.gain <= 0 then game.gain = nil end
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
    if acts.up then menu.move(game.menu, -1) end
    if acts.down then menu.move(game.menu, 1) end
    if acts.left or acts.right then menu.cycle_tab(game.menu, 1) end
    if acts.confirm then open_selected() end
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
        love.graphics.captureScreenshot("smoke-scene.png")
        print("SAVE DIR " .. love.filesystem.getSaveDirectory())
    elseif smoke.frames == 2 then
        -- full lock: the frame that has to show steered wheels and rays
        game.input.steer = 0.8
        game.s.rig.steer = rig.CAR.max_steer * 0.8
        game.s.rig.ph = game.s.rig.th - math.rad(12)
    elseif smoke.frames == 3 then
        love.graphics.captureScreenshot("smoke-steer.png")
        game.input.steer = 0
    elseif smoke.frames == 4 then
        game.s.parked = true
        game.s.t = 12.5
        game.s.final = { time = 12.5, bumps = 0, angle_err = 1.2 }
    elseif smoke.frames == 5 then
        love.graphics.captureScreenshot("smoke-parked.png")
        game.debug = true
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
        -- forward it spanned the whole yard). Compare with smoke-scene.png.
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

        -- A corner drag must pin the opposite corner -- through the editor's own
        -- mouse path, not just the document function. Autosave is throttled out
        -- for this frame so the smoke leaves no recovery file behind.
        local hs = doc.resize_handles(e.doc)
        assert(#hs == 4, "fixture: the selected wall must offer corners")
        local grabbed, opposite = hs[4], hs[1]
        local ax, ay = opposite.x, opposite.y
        local W, H = love.graphics.getDimensions()
        local sx = W / 2 + (grabbed.x - e.cam.x) * e.cam.scale
        local sy = H / 2 - (grabbed.y - e.cam.y) * e.cam.scale
        e.autosave_state = { at = math.huge, text = "" }
        e.resizing = { sx = grabbed.sx, sy = grabbed.sy }
        editor_mousemoved(sx + 40, sy + 25, 0, 0)
        e.resizing = nil
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
        local sel = e.doc.selection
        local wall = (e.doc.level[sel.list] or {})[sel.index]
        print(string.format("EDITOR DRAG pinned (%.3f, %.3f), wall now %.2f x %.2f",
            still.x, still.y, props.footprint(wall).w, props.footprint(wall).h))

        -- put the pointer over the yard so the frame shows the placement preview
        love.mouse.setPosition(math.floor(W * 0.62), math.floor(H * 0.52))
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
        -- the question Esc asks when there is unsaved work
        game.editor.dirty = true
        game.editor.prompt = true
    elseif smoke.frames == 26 then
        love.graphics.captureScreenshot("smoke-editor-prompt.png")
    elseif smoke.frames >= 27 then
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
    elseif key == "tab" or key == "left" or key == "right" then
        menu.cycle_tab(game.menu, 1)
    elseif key == "n" then
        new_level()
    elseif key == "e" then
        local lvl = menu.current(game.menu)
        if lvl then open_editor(lvl) end
    elseif key == "x" then
        menu_delete()
    elseif key == "up" or key == "w" then
        menu.move(game.menu, -1)
    elseif key == "down" or key == "s" then
        menu.move(game.menu, 1)
    elseif key == "return" or key == "kpenter" or key == "space" then
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
        load_level(game.index)
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
        load_level(game.index % #levels.ALL + 1)
    elseif key == "tab" then
        load_level(game.index % #levels.ALL + 1)
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
    if game.mode == MODE.editor then return end
    if game.mode == MODE.play then
        update_play(dt)
    elseif game.mode == MODE.menu then
        update_menu(dt)
    end
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
