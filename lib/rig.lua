-- Kinematic model of a car towing a caravan. Pure: no love.* anywhere.
--
-- The caravan is a first-order trailer on a rigid drawbar. Forward motion is
-- self-stabilising, reverse motion is an unstable equilibrium -- that single
-- property is the game, so the numbers here are the difficulty dials:
--
--   * reverse divergence time constant is drawbar / |v|
--   * steering rate scales down with speed, which is what makes keyboard
--     reversing possible at all

local geom = require("lib.geom")

local M = {}

M.CAR = {
    wheelbase = 2.50,
    front_oh = 0.90,      -- rear axle to front bumper
    rear_oh = 0.80,       -- rear axle to rear bumper
    half_width = 0.875,
    max_steer = math.rad(30),
}

M.CARAVAN = {
    coupling = -1.15,     -- coupling position along the car axis, relative to the rear axle
    drawbar = 3.60,       -- coupling to caravan axle
    length = 4.60,        -- coupling to the caravan's rear
    half_width = 1.05,
    taper = 1.20,         -- the drawbar reaches full width this far back
    tip_half_width = 0.12,
}

M.TUNE = {
    steer_rate = 2.0,     -- rad/s at speed
    center_rate = 3.0,    -- rad/s when straightening
    accel = 3.0,          -- real cars do 2.5-3 m/s^2; 1.6 read as a dead pedal
    brake = 6.5,
    rev_accel = 3.0,
    vmax = 11.0,
    vrev = 1.8,
    jackknife = math.rad(72),
    max_dt = 1 / 30,
}

-- Body shapes in local frames (x forward, y left).
-- front_oh is the overhang past the FRONT axle, so the nose sits at
-- wheelbase + front_oh. Using front_oh directly shortened the car to 1.7 m and
-- left the front wheels hanging in front of the body.
M.CAR.front_x = M.CAR.wheelbase + M.CAR.front_oh

M.CAR_BODY = {
    { M.CAR.front_x, M.CAR.half_width },
    { M.CAR.front_x, -M.CAR.half_width },
    { -M.CAR.rear_oh, -M.CAR.half_width },
    { -M.CAR.rear_oh, M.CAR.half_width },
}

-- Tapered: a full-width rectangle starting at the coupling would report a
-- jackknife at ~25 deg, which is a collision that cannot actually happen.
M.CARAVAN_BODY = {
    { 0, M.CARAVAN.tip_half_width },
    { 0, -M.CARAVAN.tip_half_width },
    { -M.CARAVAN.taper, -M.CARAVAN.half_width },
    { -M.CARAVAN.length, -M.CARAVAN.half_width },
    { -M.CARAVAN.length, M.CARAVAN.half_width },
    { -M.CARAVAN.taper, M.CARAVAN.half_width },
}

local function approach(v, target, step)
    if v < target then return math.min(target, v + step) end
    return math.max(target, v - step)
end

function M.new(x, y, th)
    th = th or 0
    return { x = x or 0, y = y or 0, th = th, ph = th, v = 0, steer = 0 }
end

function M.coupling_xy(s)
    local c = M.CARAVAN.coupling
    return s.x + c * math.cos(s.th), s.y + c * math.sin(s.th)
end

function M.caravan_centre(s)
    local cx, cy = M.coupling_xy(s)
    local half = M.CARAVAN.length / 2
    return cx - half * math.cos(s.ph), cy - half * math.sin(s.ph)
end

function M.art(s)
    return geom.wrap(s.th - s.ph)
end

-- cmd = { steer = -1..1 (target lock), pedal = -1..1, handbrake = bool }
function M.step(s, cmd, dt)
    dt = math.min(dt or 1 / 120, M.TUNE.max_dt)

    -- Steering: rate limited toward the target, faster when straightening up.
    local target = (cmd.steer or 0) * M.CAR.max_steer
    local scale = 0.45 + 0.55 * math.min(1, math.abs(s.v) / 6)
    local centering = math.abs(target) < math.abs(s.steer) and target * s.steer >= 0
    local rate = (centering and M.TUNE.center_rate or M.TUNE.steer_rate) * scale
    local dmax = rate * dt
    local ds = target - s.steer
    s.steer = s.steer + math.max(-dmax, math.min(dmax, ds))

    -- Longitudinal: one pedal axis, direction decides accelerate vs brake.
    local pedal = cmd.pedal or 0
    if cmd.handbrake then
        s.v = approach(s.v, 0, M.TUNE.brake * 2 * dt)
        if math.abs(s.v) < 0.03 then s.v = 0 end
    elseif pedal > 0 then
        if s.v < -0.02 then
            s.v = math.min(0, s.v + M.TUNE.brake * dt)
        else
            s.v = approach(s.v, pedal * M.TUNE.vmax, M.TUNE.accel * dt)
        end
    elseif pedal < 0 then
        if s.v > 0.02 then
            s.v = math.max(0, s.v - M.TUNE.brake * dt)
        else
            s.v = approach(s.v, pedal * M.TUNE.vrev, M.TUNE.rev_accel * dt)
        end
    else
        s.v = approach(s.v, 0, M.TUNE.brake * 0.35 * dt)
    end

    -- Kinematics. The trailer term is the standard first-order model with a
    -- hitch offset, so a coupling behind the rear axle cuts the corner.
    local thd = s.v * math.tan(s.steer) / M.CAR.wheelbase
    local phd = (s.v / M.CARAVAN.drawbar) * math.sin(s.th - s.ph)
        + (M.CARAVAN.coupling / M.CARAVAN.drawbar) * thd * math.cos(s.th - s.ph)

    s.x = s.x + s.v * math.cos(s.th) * dt
    s.y = s.y + s.v * math.sin(s.th) * dt
    s.th = s.th + thd * dt
    s.ph = s.ph + phd * dt
    return s
end

function M.car_poly(s)
    return geom.poly_world(M.CAR_BODY, s.x, s.y, s.th)
end

function M.caravan_poly(s)
    local cx, cy = M.coupling_xy(s)
    return geom.poly_world(M.CARAVAN_BODY, cx, cy, s.ph)
end

-- Where the caravan's rear centre would go if the driver held this command.
-- This is the reversing-camera arc: the assist that makes an unstable system
-- learnable.
function M.guide(s, cmd, horizon, samples)
    horizon = horizon or 6
    samples = samples or 240
    local ghost = { x = s.x, y = s.y, th = s.th, ph = s.ph, v = s.v, steer = s.steer }
    local dt = horizon / samples
    local pts = {}
    for i = 1, samples do
        M.step(ghost, cmd, dt)
        local cx, cy = M.coupling_xy(ghost)
        pts[i] = {
            cx - M.CARAVAN.length * math.cos(ghost.ph),
            cy - M.CARAVAN.length * math.sin(ghost.ph),
        }
    end
    return pts
end

return M
