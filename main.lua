-- Thin shell: love callbacks, input wiring, camera, fixed-timestep loop.
-- All game rules live in lib/ and are covered by `love tests`.

local rig = require("lib.rig")
local session = require("lib.session")
local levels = require("lib.levels")
local input = require("lib.input")
local draw = require("lib.draw")
local audit = require("lib.audit")
local progress = require("lib.progress")
local menu = require("lib.menu")
local levelfmt = require("lib.levelfmt")

local DT = 1 / 120          -- physics step: fixed, or the unstable reverse
local MAX_STEPS = 12        -- never spiral past this in one frame

-- The progress store takes a disk rather than love.filesystem, so its rules stay
-- testable; this table is the only place the two meet.
local disk = {
    read = function(name) return love.filesystem.read(name) end,
    write = function(name, data) return love.filesystem.write(name, data) end,
    remove = function(name) return love.filesystem.remove(name) end,
}

local smoke = { enabled = false, frames = 0, frozen = false }

-- A mode is a screen with its own update/draw/keys. The game began as a single
-- implicit state; the level select and the editor make the switch explicit, so a
-- key press cannot leak into the screen that is not showing.
local MODE = { play = "play", menu = "menu" }

local game = {
    mode = MODE.menu,
    index = 1,
    guide = true,
    debug = false,
    paused = false,
    acc = 0,
    new_best = false,
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

local function load_level(n)
    game.index = n
    game.level = levels.get(n)
    game.s = session.new(game.level)
    game.acc = 0
    game.new_best = false
    game.input.steer, game.input.throttle, game.input.brake, game.input.handbrake = 0, 0, 0, false
    game.scale, game.ox, game.oy = camera(game.level)
end

-- The model is rebuilt on entry so the marks are what the store says now: a park
-- made a second ago must not still read as unplayed.
local function open_menu()
    game.menu = menu.new(levels.ALL, {}, game.progress)
    game.mode = MODE.menu
end

local function open_selected()
    local lvl = menu.confirm(game.menu)
    local index = lvl and levels.find(lvl.id)
    if not index then return end
    load_level(index)
    game.mode = MODE.play
end

-- `love . --audit N` / `--audit all`: is the level parkable at all? A level no
-- line parks is a shipped bug, and this is the only cheap evidence for it.
-- Exit 0 when every level asked about has a line.
local function run_audit(arg, quick)
    local targets = {}
    if arg == nil or arg == "all" then
        for i = 1, #levels.ALL do targets[#targets + 1] = i end
    else
        targets[1] = tonumber(arg) or 1
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

    love.graphics.setBackgroundColor(0.05, 0.05, 0.06)
    draw.init()
    input.init(game.input)
    game.progress = smoke.enabled and smoke_progress() or progress.open(disk)
    load_level(game.index)
    -- the smoke harness drives play frames itself; a normal launch starts on the
    -- title screen
    game.mode = smoke.enabled and MODE.play or MODE.menu
    if game.mode == MODE.menu then open_menu() end
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
    while game.acc >= DT and steps < MAX_STEPS do
        session.update(game.s, game.input, DT)
        game.acc = game.acc - DT
        steps = steps + 1
    end
    if steps >= MAX_STEPS then game.acc = 0 end

    -- The park is the event that writes progress. record() gets the session the
    -- game produced (all of its numbers are the sim's own), and the store writes
    -- once, on the transition, not every frame the card is on screen.
    if not parked_before and game.s.parked then
        local _, improved = progress.record(game.progress, game.level, game.s)
        game.new_best = improved
        progress.save(game.progress)
    end

    local impact = game.s.bump_flash > 0.30 and 1 or nil
    input.rumble(game.input, rig.art(game.s.rig), impact)
end

local function update_menu(dt)
    local acts = input.poll_menu(game.input)
    if acts.up then menu.move(game.menu, -1) end
    if acts.down then menu.move(game.menu, 1) end
    if acts.confirm then open_selected() end
    if acts.cancel then love.event.quit() end
end

local function draw_play()
    love.graphics.push()
    love.graphics.translate(game.ox, game.oy)
    love.graphics.scale(game.scale, -game.scale)
    draw.scene(game.level, game.s, { guide = game.guide, input = game.input })
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
        -- one "level changed" card, the same on every machine
        open_menu()
    elseif smoke.frames == 12 then
        love.graphics.captureScreenshot("smoke-menu.png")
    elseif smoke.frames >= 13 then
        print("SMOKE OK")
        love.event.quit(0)
    end
end

local function menu_keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "up" or key == "w" then
        menu.move(game.menu, -1)
    elseif key == "down" or key == "s" then
        menu.move(game.menu, 1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        open_selected()
    end
end

local function play_keypressed(key)
    if key == "escape" then
        open_menu()
    elseif key == "r" then
        load_level(game.index)
    elseif key == "g" then
        game.guide = not game.guide
    elseif key == "p" then
        game.paused = not game.paused
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
    end
    if smoke.enabled then smoke_step() end
end

function love.keypressed(key)
    if game.mode == MODE.play then
        play_keypressed(key)
    elseif game.mode == MODE.menu then
        menu_keypressed(key)
    end
end
