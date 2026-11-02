-- Thin shell: love callbacks, input wiring, camera, fixed-timestep loop.
-- All game rules live in lib/ and are covered by `love tests`.

local rig = require("lib.rig")
local session = require("lib.session")
local levels = require("lib.levels")
local input = require("lib.input")
local draw = require("lib.draw")

local DT = 1 / 120          -- physics step: fixed, or the unstable reverse
local MAX_STEPS = 12        -- never spiral past this in one frame

local smoke = { enabled = false, frames = 0 }

local game = {
    index = 1,
    guide = true,
    debug = false,
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

function love.load(args)
    for _, a in ipairs(args or {}) do
        if a == "--smoke" then smoke.enabled = true end
    end
    love.graphics.setBackgroundColor(0.05, 0.05, 0.06)
    draw.init()
    input.init(game.input)
    load_level(game.index)
end

function love.update(dt)
    local acts = input.poll_actions(game.input)
    if acts.reset then
        load_level(game.index)
        return
    end
    if acts.guide then game.guide = not game.guide end

    input.poll(game.input)

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

function love.draw()
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
        elseif smoke.frames >= 6 then
            print("SMOKE OK")
            love.event.quit(0)
        end
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        load_level(game.index)
    elseif key == "g" then
        game.guide = not game.guide
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
