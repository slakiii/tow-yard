-- Session state: clock, gear gating, collisions, parking.
-- Pure: no love.* anywhere.

local rig = require("lib.rig")
local geom = require("lib.geom")

local M = {}

M.DWELL = 0.12        -- hold the brake at a standstill this long to engage reverse
M.PARK_SPEED = 0.05   -- m/s, must be stopped to count
M.PARK_HOLD = 0.25    -- seconds of stillness before the park is accepted

local function clone_cones(src)
    local out = {}
    for i, c in ipairs(src or {}) do
        out[i] = { x = c.x, y = c.y, r = c.r or 0.35, hit = false }
    end
    return out
end

function M.new(level)
    local r = rig.new(level.spawn.x, level.spawn.y, level.spawn.th)
    local walls = {}
    for i, w in ipairs(level.walls or {}) do
        walls[i] = geom.rect_poly(w.x, w.y, w.w, w.h, w.angle or 0)
    end
    return {
        level = level,
        rig = r,
        walls = walls,
        bay_poly = geom.rect_poly(level.bay.x, level.bay.y, level.bay.w, level.bay.h, level.bay.angle),
        cones = clone_cones(level.cones),
        t = 0,
        started = false,
        dwell = 0,
        bumps = 0,
        bump_flash = 0,
        last_bump = nil,
        park_hold = 0,
        parked = false,
        final = nil,
        prev = nil,
    }
end

-- Raw device input -> rig command. The gear gate lives here, not in the
-- physics: one pedal axis, and reverse only after a deliberate dwell.
function M.derive(s, input, dt)
    local steer = input.steer or 0
    local throttle = input.throttle or 0
    local brake = input.brake or 0

    if input.handbrake then
        s.dwell = 0
        return { steer = steer, pedal = 0, handbrake = true }
    end
    if throttle > 0 and brake <= 0 then
        s.dwell = 0
        return { steer = steer, pedal = throttle }
    end
    if brake > 0 then
        if s.rig.v > 0.10 then
            s.dwell = 0
            return { steer = steer, pedal = -1 }
        end
        s.dwell = s.dwell + dt
        if s.dwell >= M.DWELL then
            return { steer = steer, pedal = -brake }
        end
        return { steer = steer, pedal = 0 }
    end
    s.dwell = 0
    return { steer = steer, pedal = 0 }
end

-- Same command derive would produce, without touching the dwell timer.
-- Used by the reversing guide arc, which must not advance game state.
function M.preview(s, input)
    local steer = input.steer or 0
    local throttle = input.throttle or 0
    local brake = input.brake or 0
    if input.handbrake then return { steer = steer, pedal = 0, handbrake = true } end
    if throttle > 0 and brake <= 0 then return { steer = steer, pedal = throttle } end
    if brake > 0 then
        if s.rig.v > 0.10 then return { steer = steer, pedal = -1 } end
        if s.dwell >= M.DWELL then return { steer = steer, pedal = -brake } end
        return { steer = steer, pedal = 0 }
    end
    return { steer = steer, pedal = 0 }
end

-- The guide arc predicts motion; standing still there is no pedal to predict
-- from, and a blank arc at a stop is useless. Predict at full scale in the
-- direction the rig is already going (reverse at rest), the way a reversing
-- camera shows a fixed arc rather than nothing.
function M.guide_command(s, input)
    local cmd = M.preview(s, input)
    if (cmd.pedal or 0) == 0 then
        cmd.pedal = (s.rig.v <= 0) and -1 or 1
    end
    return cmd
end

function M.gear(s)
    if s.rig.v < -0.02 then return "R" end
    if s.rig.v > 0.02 then return "D" end
    if s.dwell >= M.DWELL then return "R" end
    return "N"
end

-- The guide arc is a 10 s prediction: reverse at 1.8 m/s is ~18 m (the
-- manoeuvre), forward at 11 m/s is ~90 m -- longer than a 60x40 m yard, so at
-- 15 px/m it smears dots over the whole scene and reads as decoration. The arc
-- exists to make an unstable system learnable; forward motion is already
-- stable. Visible at rest (it previews the reverse) and in reverse only.
function M.guide_visible(s)
    return M.gear(s) ~= "D"
end

local function revert(s, reason)
    if s.prev then
        s.rig.x, s.rig.y = s.prev.x, s.prev.y
        s.rig.th, s.rig.ph = s.prev.th, s.prev.ph
    end
    s.rig.v = 0
    s.bumps = s.bumps + 1
    s.bump_flash = 0.35
    s.last_bump = reason
end

function M.update(s, input, dt)
    if s.parked then return s end
    dt = math.min(dt, rig.TUNE.max_dt)

    if not s.started and ((input.throttle or 0) > 0 or (input.brake or 0) > 0) then
        s.started = true
    end
    if s.started then s.t = s.t + dt end

    local cmd = M.derive(s, input, dt)
    s.prev = { x = s.rig.x, y = s.rig.y, th = s.rig.th, ph = s.rig.ph }
    rig.step(s.rig, cmd, dt)

    if s.bump_flash > 0 then s.bump_flash = math.max(0, s.bump_flash - dt) end

    local car = rig.car_poly(s.rig)
    local van = rig.caravan_poly(s.rig)

    -- Jackknife: the two bodies cannot occupy the same space. The geometric
    -- limit is ~66-72 deg, which is what the rumble warning is tuned around.
    if geom.overlap(car, van) then
        revert(s, "jackknife")
        return s
    end

    for _, wp in ipairs(s.walls) do
        if geom.overlap(car, wp) or geom.overlap(van, wp) then
            revert(s, "wall")
            return s
        end
    end

    for _, c in ipairs(s.cones) do
        if not c.hit and (geom.circle_overlap_poly(c.x, c.y, c.r, car)
            or geom.circle_overlap_poly(c.x, c.y, c.r, van)) then
            c.hit = true
            s.bumps = s.bumps + 1
            s.bump_flash = 0.3
            s.last_bump = "cone"
            s.rig.v = s.rig.v * 0.55
        end
    end

    M.check_park(s, dt)
    return s
end

-- Place the rig so the caravan's body is centred on (px, py) pointing at
-- `angle`, with the car hitched and aligned. Used by tests and the render
-- smoke to jump straight to a pose instead of driving to it.
function M.place_caravan(s, px, py, angle, car_angle)
    local th = car_angle or angle
    local half = rig.CARAVAN.length / 2
    local cx, cy = px + half * math.cos(angle), py + half * math.sin(angle)
    s.rig.x = cx - rig.CARAVAN.coupling * math.cos(th)
    s.rig.y = cy - rig.CARAVAN.coupling * math.sin(th)
    s.rig.th, s.rig.ph = th, angle
    s.rig.v, s.rig.steer = 0, 0
    return s
end

function M.check_park(s, dt)
    local bay = s.level.bay
    local inside = geom.poly_in_poly(rig.caravan_poly(s.rig), s.bay_poly)
    local err = math.abs(geom.wrap(s.rig.ph - bay.angle))
    if inside and err <= bay.tol and math.abs(s.rig.v) < M.PARK_SPEED then
        s.park_hold = s.park_hold + dt
        if s.park_hold >= M.PARK_HOLD then
            s.parked = true
            s.final = { time = s.t, bumps = s.bumps, angle_err = math.deg(err) }
        end
    else
        s.park_hold = 0
    end
end

-- 3 stars: clean and quick. 2: quick or clean. 1: parked, eventually.
function M.grade(s)
    if not s.parked then return 0 end
    local f = s.final
    if f.bumps == 0 and f.time <= s.level.par then return 3 end
    if f.bumps == 0 or f.time <= s.level.par * 1.5 then return 2 end
    return 1
end

return M
