-- Session state: clock, gear gating, collisions, parking.
-- Pure: no love.* anywhere.

local rig = require("lib.rig")
local geom = require("lib.geom")

local M = {}

M.DWELL = 0.12        -- hold the brake at a standstill this long to engage reverse
M.PARK_SPEED = 0.05   -- m/s, must be stopped to count
M.PARK_HOLD = 0.25    -- seconds of stillness before the park is accepted

-- A clipped cone costs time, not the attempt. Two seconds is ~7-9% of a par run
-- and a cone-rich line can never be the record line; a body contact is the
-- thing that voids an attempt (see revert()). This lives in the sim, not in the
-- shell, because a stored ghost's time is recomputed from its replay: put the
-- price in the card and the replay would score a different run.
M.CONE_PENALTY = 2.0

-- The input grid. Every number the sim consumes is snapped to one of these, so a
-- run recorded live and a run replayed from a file feed the physics exactly the
-- same values -- "the replay matches" becomes structural instead of a tolerance
-- somebody has to defend when the steering ramp changes.
-- 1/127 of lock is 0.24 deg at full lock: finer than any hand can aim.
M.STEER_STEPS = 127
M.PEDAL_STEPS = 255

local function snap(v, steps)
    return math.floor((v or 0) * steps + 0.5) / steps
end

-- Idempotent by construction: a value already on the grid snaps to itself, so
-- quantising on both sides of a function boundary is harmless.
function M.quantise(input)
    if not input then return { steer = 0, throttle = 0, brake = 0, handbrake = false } end
    return {
        steer = snap(input.steer, M.STEER_STEPS),
        throttle = snap(input.throttle, M.PEDAL_STEPS),
        brake = snap(input.brake, M.PEDAL_STEPS),
        handbrake = input.handbrake and true or false,
        -- the HUD prints the device name; dropping it makes the glyphs flicker
        last_device = input.last_device,
    }
end

local function clone_cones(src)
    local out = {}
    for i, c in ipairs(src or {}) do
        -- `kind` rides along: the renderer draws cones from session state (they
        -- carry `hit`), and a knocked-over chair must still look like a chair.
        out[i] = { x = c.x, y = c.y, r = c.r or 0.35, kind = c.kind, hit = false }
    end
    return out
end

-- Something happened. The session is the only module that knows WHEN: a wall
-- revert, the dwell gate catching, the clock crossing par. The shell drains
-- this list after its step loop, so "did that bump make a sound, once" stays a
-- headless question -- diffing state in the shell is where cues double-fire
-- (bump_flash ticks down over 0.35 s) and where they get missed entirely.
local function cue(s, ev)
    s.cues[#s.cues + 1] = ev
end

-- Hand the queued events to the caller and start a fresh list.
function M.drain(s)
    local out = s.cues
    s.cues = {}
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
        cone_hits = 0,        -- knockables clipped: the penalty is priced per hit
        damaged = false,      -- a body contact: voids the attempt, not the park
        damage = nil,         -- which body contact ("wall" / "jackknife")
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
        cues = {},
        gear_seen = nil,      -- label the last step reported, so the R transition is an edge
        par_cued = false,
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
-- Used by the reversing guide arc, which must not advance game state. Quantised
-- like the real path: the arc has to show where the rig will actually go, not
-- where it would go with infinitely fine steering.
function M.preview(s, input)
    input = M.quantise(input)
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
    -- captured before the rebuild: the bump's volume is the speed at impact, and
    -- after this line the rig is stopped
    local impact = math.abs(s.rig.v)
    if s.prev then
        s.rig.x, s.rig.y = s.prev.x, s.prev.y
        s.rig.th, s.rig.ph = s.prev.th, s.prev.ph
    end
    s.rig.v = 0
    s.bumps = s.bumps + 1
    s.bump_flash = 0.35
    s.last_bump = reason
    -- Touching a wall or jackknifing is damage: the rig is rebuilt and the
    -- attempt can no longer set a record. The park still counts (see check_park).
    s.damaged = true
    s.damage = reason
    cue(s, { kind = "bump", cause = reason, speed = impact })
end

function M.update(s, input, dt)
    if s.parked then return s end
    dt = math.min(dt, rig.TUNE.max_dt)
    input = M.quantise(input)

    if not s.started and ((input.throttle or 0) > 0 or (input.brake or 0) > 0) then
        s.started = true
        cue(s, { kind = "start" })
    end
    if s.started then
        s.t = s.t + dt
        -- The clock that counts: drive time plus the cones already clipped. The
        -- HUD shows this one, so the number you watch is the number the card
        -- reports, and the par cue closes on it too.
        if s.level.par and not s.par_cued
            and (s.t + s.cone_hits * M.CONE_PENALTY) > s.level.par then
            s.par_cued = true
            cue(s, { kind = "par" })
        end
    end

    local cmd = M.derive(s, input, dt)

    -- Edge, not level: the dwell gate engages R once, and the cue belongs on the
    -- step it engages -- afterwards the gear is simply R for the whole manoeuvre.
    local g = M.gear(s)
    if g ~= s.gear_seen then
        s.gear_seen = g
        if g == "R" then cue(s, { kind = "gear", gear = "R" }) end
    end

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

    -- The yard's edge is a wall. `bounds` only sizes the camera and the
    -- drawing area, so without this the rig drives straight out of the world
    -- with nothing to stop it -- measured: every shipped level let a straight
    -- run reach x = 56.6 (or 3.4 on level 3) with zero bumps. Reported as a
    -- wall contact so the sound and the result card agree with the cause.
    local b = s.level.bounds
    if b and (not geom.poly_in_rect(car, b.x0, b.y0, b.x1, b.y1)
              or not geom.poly_in_rect(van, b.x0, b.y0, b.x1, b.y1)) then
        revert(s, "wall")
        return s
    end

    for _, c in ipairs(s.cones) do
        if not c.hit and (geom.circle_overlap_poly(c.x, c.y, c.r, car)
            or geom.circle_overlap_poly(c.x, c.y, c.r, van)) then
            c.hit = true
            s.cone_hits = s.cone_hits + 1
            cue(s, { kind = "cone", speed = math.abs(s.rig.v), penalty = M.CONE_PENALTY })
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
            local penalties = s.cone_hits * M.CONE_PENALTY
            s.final = {
                -- the time that counts: the drive plus what the cones cost. Both
                -- terms ride along so the card can show the arithmetic and the
                -- replay scores the same run.
                time = s.t + penalties,
                driven = s.t,
                penalties = penalties,
                cone_hits = s.cone_hits,
                damaged = s.damaged or false,
                damage = s.damage,
                bumps = s.bumps,
                angle_err = math.deg(err),
            }
            cue(s, { kind = "park", stars = M.grade(s) })
        end
    else
        s.park_hold = 0
    end
end

-- 3 stars: clean and quick. 2: quick or clean. 1: parked, eventually.
function M.grade(s)
    if not s.parked then return 0 end
    local f = s.final
    -- a void attempt earns nothing: the card must not strike the time through and
    -- then hand out a star for it
    if f.damaged then return 0 end
    if f.bumps == 0 and f.time <= s.level.par then return 3 end
    if f.bumps == 0 or f.time <= s.level.par * 1.5 then return 2 end
    return 1
end

return M
