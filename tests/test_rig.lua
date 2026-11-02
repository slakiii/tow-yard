-- Kinematic car + caravan. These tests ARE the feel spec: the numbers come
-- from an independent float64 integration of the same model, so a change that
-- makes the caravan drift calmer or twitchier has to be a deliberate one.

local H = require("tests.helper")
local rig = require("lib.rig")

local M = { order = {
    "aligned_reverse_stays_aligned",
    "reverse_is_unstable_at_the_measured_rate",
    "forward_is_self_stabilising",
    "left_steer_in_reverse_moves_caravan_tail_right",
    "steering_is_rate_limited_and_does_not_overshoot",
    "steering_is_slower_at_crawl_speed",
    "speed_caps_are_asymmetric",
    "min_turn_radius",
    "bodies_touch_near_jackknife_not_earlier",
    "fixed_step_determinism",
} }

local DT = 1 / 120

local function run(steps, cmd_fn, s)
    s = s or rig.new(0, 0, 0)
    for i = 1, steps do
        rig.step(s, cmd_fn and cmd_fn(i, s) or { steer = 0, pedal = 0 }, DT)
    end
    return s
end

function M.aligned_reverse_stays_aligned()
    local s = rig.new(0, 0, 0)
    for _ = 1, 120 * 5 do rig.step(s, { steer = 0, pedal = -1 }, DT) end
    H.near(math.deg(rig.art(s)), 0, 1e-9, "articulation while reversing straight")
    H.expect(s.x < -1, "rig reversed along -x")
end

function M.reverse_is_unstable_at_the_measured_rate()
    -- 2 deg of initial misalignment, full reverse from rest: 20 deg at ~4.9 s
    -- and 45 deg at ~6.6 s with no input at all. If the pedal response
    -- (accel/rev_accel) changes, these move -- re-measure, do not widen.
    local s = rig.new(0, 0, 0)
    s.ph = math.rad(2)
    local t20, t45, t = nil, nil, 0
    for _ = 1, 120 * 20 do
        rig.step(s, { steer = 0, pedal = -1 }, DT)
        t = t + DT
        if not t20 and math.abs(math.deg(rig.art(s))) > 20 then t20 = t end
        if t20 and not t45 and math.abs(math.deg(rig.art(s))) > 45 then t45 = t end
    end
    H.expect(t20 ~= nil, "articulation never reached 20 deg; reverse is not unstable")
    H.between(t20, 4.3, 5.6, "time to 20 deg")
    H.between(t45, 6.0, 7.4, "time to 45 deg")
end

function M.forward_is_self_stabilising()
    local s = rig.new(0, 0, 0)
    s.ph = math.rad(10)
    for _ = 1, 120 * 8 do rig.step(s, { steer = 0, pedal = 1 }, DT) end
    H.expect(math.abs(math.deg(rig.art(s))) < 1.0,
             "forward motion must align the caravan, got " .. math.deg(rig.art(s)))
end

function M.left_steer_in_reverse_moves_caravan_tail_right()
    -- The counter-steer rule the whole game teaches: wheel LEFT while
    -- reversing swings the caravan's tail to the car's RIGHT.
    local s = rig.new(0, 0, 0)
    local tail = function(st)
        local cx, cy = rig.coupling_xy(st)
        return cx - rig.CARAVAN.length * math.cos(st.ph), cy - rig.CARAVAN.length * math.sin(st.ph)
    end
    for _ = 1, 480 do rig.step(s, { steer = 0.27, pedal = -0.67 }, DT) end   -- 8 deg lock, reversing
    local _, ty = tail(s)
    -- Wheel left while reversing: the car's nose swings right, its tail swings
    -- left, that drags the caravan's nose left and throws its tail right. The
    -- caravan's heading therefore rotates CCW past the car's, so the
    -- articulation is NEGATIVE while the tail moves right.
    H.expect(rig.art(s) < 0, "wheel left in reverse must drive the articulation negative")
    H.expect(ty < -0.15, "caravan tail must swing to the car's right (-y), got " .. ty)

    -- mirror image: wheel right must throw the tail left
    local m = rig.new(0, 0, 0)
    for _ = 1, 480 do rig.step(m, { steer = -0.27, pedal = -0.67 }, DT) end
    local _, my = tail(m)
    H.expect(my > 0.15, "wheel right must throw the tail left, got " .. my)
end

function M.steering_is_rate_limited_and_does_not_overshoot()
    -- From a standstill the crawl-speed governor halves the rate, so full lock
    -- takes ~0.58 s. At speed it is 0.26 s. Both numbers are the documented
    -- feel spec; if one moves, the other has to be re-measured too.
    local s = rig.new(0, 0, 0)
    local t, locked = 0, nil
    for _ = 1, 120 * 2 do
        rig.step(s, { steer = 1, pedal = 0 }, DT)
        t = t + DT
        if not locked and math.abs(s.steer - rig.CAR.max_steer) < 1e-6 then locked = t end
        H.expect(s.steer <= rig.CAR.max_steer + 1e-9, "steer exceeded max lock")
    end
    H.expect(locked ~= nil, "steer never reached full lock")
    H.between(locked, 0.50, 0.68, "full lock time from rest")

    local fast = rig.new(0, 0, 0)
    fast.v = 9
    local before = fast.steer
    rig.step(fast, { steer = 1, pedal = 0 }, DT)
    H.near((fast.steer - before) / DT, rig.TUNE.steer_rate, 0.05, "steer rate at speed")
end

function M.steering_is_slower_at_crawl_speed()
    local function rise(v)
        local s = rig.new(0, 0, 0); s.v = v
        local before = s.steer
        rig.step(s, { steer = 1, pedal = 0 }, DT)
        return (s.steer - before) / DT
    end
    H.expect(rise(1.2) < rise(9.0) * 0.7, "crawl-speed steering must be noticeably slower")
end

function M.speed_caps_are_asymmetric()
    local s = run(120 * 20, function() return { steer = 0, pedal = 1 } end)
    H.expect(s.v <= rig.TUNE.vmax + 1e-6, "forward speed capped")
    H.expect(s.v > rig.TUNE.vmax * 0.9, "long full throttle should approach the cap")
    local r = run(120 * 20, function() return { steer = 0, pedal = -1 } end)
    H.expect(r.v >= -(rig.TUNE.vrev + 1e-6), "reverse speed capped")
    H.expect(r.v < -rig.TUNE.vrev * 0.9, "long full reverse should approach the cap")
end

function M.min_turn_radius()
    local s = rig.new(0, 0, 0)
    s.steer = rig.CAR.max_steer
    -- circle centre for a left (CCW) turn from heading 0
    local cx, cy = 0, rig.CAR.wheelbase / math.tan(rig.CAR.max_steer)
    local rmin, rmax = math.huge, -math.huge
    for _ = 1, 120 * 12 do
        rig.step(s, { steer = 1, pedal = 1 }, DT)
        local r = math.sqrt((s.x - cx) ^ 2 + (s.y - cy) ^ 2)
        rmin = math.min(rmin, r); rmax = math.max(rmax, r)
    end
    H.near((rmin + rmax) / 2, rig.CAR.wheelbase / math.tan(rig.CAR.max_steer), 0.05, "turn radius")
    H.expect(rmax - rmin < 0.2, "steer was not held at full lock")
end

function M.bodies_touch_near_jackknife_not_earlier()
    -- A full-width rectangle starting at the coupling would fake a jackknife at
    -- ~25 deg. The caravan body has to be tapered, and the coupling has to sit
    -- behind the bumper, or large-angle poses report collisions that cannot
    -- happen and reversing becomes impossible.
    local touch = nil
    for deg = 20, 100 do
        local s = rig.new(0, 0, 0)
        s.ph = math.rad(deg)
        if require("lib.geom").overlap(rig.car_poly(s), rig.caravan_poly(s)) then
            touch = deg
            break
        end
    end
    H.expect(touch ~= nil, "bodies never touched up to 100 deg")
    H.between(touch, 60, 80, "jackknife angle")
end

function M.fixed_step_determinism()
    local function go()
        local s = rig.new(3, 4, 0.2)
        for i = 1, 600 do
            rig.step(s, { steer = math.sin(i / 30) * 0.8, pedal = (i % 7 < 4) and 0.6 or -0.4 }, DT)
        end
        return s
    end
    local a, b = go(), go()
    H.near(a.x, b.x, 0, "x"); H.near(a.y, b.y, 0, "y")
    H.near(a.th, b.th, 0, "th"); H.near(a.ph, b.ph, 0, "ph")
end

return M
