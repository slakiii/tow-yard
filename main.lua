-- Thin shell: love callbacks, input wiring, camera, fixed-timestep loop.
-- All game rules live in lib/ and are covered by `love tests`.

local rig = require("lib.rig")
local session = require("lib.session")
local levels = require("lib.levels")
local input = require("lib.input")
local draw = require("lib.draw")
local audit = require("lib.audit")

local DT = 1 / 120          -- physics step: fixed, or the unstable reverse
local MAX_STEPS = 12        -- never spiral past this in one frame

local smoke = { enabled = false, frames = 0, frozen = false }

-- A mode is a screen with its own update/draw/keys. The game began as a single
-- implicit state; the level select and the editor make the switch explicit, so a
-- key press cannot leak into the screen that is not showing.
local MODE = { play = "play" }

local game = {
    mode = MODE.play,
    index = 1,
    guide = true,
    debug = false,
    paused = false,
    acc = 0,
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
    game.input.steer, game.input.throttle, game.input.brake, game.input.handbrake = 0, 0, 0, false
    game.scale, game.ox, game.oy = camera(game.level)
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
    load_level(game.index)
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
    while game.acc >= DT and steps < MAX_STEPS do
        session.update(game.s, game.input, DT)
        game.acc = game.acc - DT
        steps = steps + 1
    end
    if steps >= MAX_STEPS then game.acc = 0 end

    local impact = game.s.bump_flash > 0.30 and 1 or nil
    input.rumble(game.input, rig.art(game.s.rig), impact)
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

    -- `love . --smoke` renders every screen once and exits: a boot check that
    -- actually exercises the draw path instead of just surviving 4 seconds.
    if smoke.enabled then
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
            -- level 2 in the bay, facing the wrong way: the frame that has to
            -- show the required-facing arrow and the corrective ghost
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
            -- driving forward: the guide arc must be absent (it is a reverse
            -- assist; forward it spanned the whole yard). Compare with
            -- smoke-scene.png, which is the same level at rest.
            game.paused = false
            load_level(1)
            -- freeze the sim: the state below is the frame, and a step before
            -- the capture would move the rig by an amount the clock chose
            smoke.frozen = true
            game.input.steer = 0.5
            game.s.rig.steer = rig.CAR.max_steer * 0.5
            game.s.rig.v = 5.0
            game.s.t = 3.0
            game.s.started = true
        elseif smoke.frames == 10 then
            love.graphics.captureScreenshot("smoke-forward.png")
        elseif smoke.frames >= 11 then
            print("SMOKE OK")
            love.event.quit(0)
        end
    end
end

local function play_keypressed(key)
    if key == "escape" then
        -- Quits for now; the menu takes this key over when it exists (Task 12).
        love.event.quit()
    elseif key == "r" then
        load_level(game.index)
    elseif key == "g" then
        game.guide = not game.guide
    elseif key == "p" then
        game.paused = not game.paused
    elseif key == "f1" then
        game.debug = not game.debug
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
-- the menu or the editor is a branch here, not a change to the play loop.
-- ---------------------------------------------------------------------------

function love.update(dt)
    if game.mode == MODE.play then update_play(dt) end
end

function love.draw()
    if game.mode == MODE.play then draw_play() end
end

function love.keypressed(key)
    if game.mode == MODE.play then play_keypressed(key) end
end
