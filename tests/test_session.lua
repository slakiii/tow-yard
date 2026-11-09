-- Session state: clock, gear gating, collisions, parking.
-- Mechanic tests run on a synthetic empty field so each one isolates a single
-- rule; the real levels are covered separately in tests/test_levels.lua.

local H = require("tests.helper")
local session = require("lib.session")
local fixtures = require("tests.fixtures")
local rig = require("lib.rig")

local M = { order = {
    "clock_waits_for_input",
    "reverse_needs_a_dwell",
    "gear_reads_back",
    "wall_collision_reverts_and_counts",
    "cone_is_knocked_over",
    "jackknife_ends_the_run",
    "no_false_jackknife_in_normal_reversing",
    "parked_accepts_correct_pose",
    "parked_rejects_wrong_angle",
    "parked_rejects_reversed_facing",
    "parked_rejects_a_moving_caravan",
    "guide_visible_only_when_not_driving_forward",
    "quantise_is_idempotent",
    "quantise_snaps_to_its_grid",
    "quantised_input_still_parks_level_1",
    "drain_empties_the_queue",
    "start_cue_fires_once_on_the_first_pedal",
    "gear_cue_fires_when_reverse_engages",
    "wall_bump_cue_carries_the_impact_speed",
    "jackknife_cue_is_not_a_wall_bump",
    "cone_cue_fires_once",
    "park_cue_carries_the_stars",
    "par_cue_fires_once",
} }

local DT = 1 / 120

local function idle() return { steer = 0, throttle = 0, brake = 0, handbrake = false } end
local function forward() return { steer = 0, throttle = 1, brake = 0, handbrake = false } end
local function backward() return { steer = 0, throttle = 0, brake = 1, handbrake = false } end

local function step(s, input, n)
    for _ = 1, n do session.update(s, input, DT) end
end

-- Place the caravan's centre at the bay centre, facing the bay's axis.
local function place_in_bay(s, angle_offset)
    local bay = s.level.bay
    session.place_caravan(s, bay.x, bay.y, bay.angle + (angle_offset or 0))
end

function M.clock_waits_for_input()
    local s = session.new(fixtures.field())
    step(s, idle(), 120)
    H.near(s.t, 0, 1e-9, "clock before input")
    step(s, forward(), 120)
    H.near(s.t, 1, 1e-6, "clock after 1 s of input")
end

function M.reverse_needs_a_dwell()
    local s = session.new(fixtures.field())
    step(s, backward(), 12)          -- 0.1 s: not yet
    H.expect(s.rig.v > -1e-6, "reverse engaged before the dwell elapsed")
    step(s, backward(), 24)          -- +0.2 s: now
    H.expect(s.rig.v < -0.05, "reverse did not engage after the dwell")
end

function M.gear_reads_back()
    local s = session.new(fixtures.field())
    H.expect(session.gear(s) == "N", "resting gear is N")
    step(s, forward(), 60)
    H.expect(session.gear(s) == "D", "moving forward is D")
    step(s, backward(), 240)
    H.expect(session.gear(s) == "R", "reversing is R")
end

function M.wall_collision_reverts_and_counts()
    local lvl = fixtures.field()
    lvl.walls = { { x = 0, y = 6, w = 12, h = 1 } }
    local s = session.new(lvl)
    s.rig.th, s.rig.ph = math.pi / 2, math.pi / 2
    step(s, forward(), 480)
    H.expect(s.bumps > 0, "driving into a wall must count a bump")
    H.expect(s.last_bump == "wall", "bump reason should be wall, got " .. tostring(s.last_bump))
    H.expect(s.rig.v == 0, "a wall stops the rig")
    H.expect(s.rig.y < 4.7, "the rig must not pass through the wall, y=" .. s.rig.y)
end

function M.cone_is_knocked_over()
    local lvl = fixtures.field()
    lvl.cones = { { x = 0, y = 4, r = 0.35 } }
    local s = session.new(lvl)
    s.rig.th, s.rig.ph = math.pi / 2, math.pi / 2
    step(s, forward(), 360)
    H.expect(s.cones[1].hit, "the cone should be knocked over")
    H.expect(s.bumps > 0, "a knocked cone is a bump")
    H.expect(s.last_bump == "cone", "bump reason should be cone")
end

function M.jackknife_ends_the_run()
    local s = session.new(fixtures.field())
    s.rig.ph = math.rad(85)          -- well past the geometric limit
    session.update(s, idle(), DT)
    H.expect(s.last_bump == "jackknife", "over-articulation must register as a jackknife")
    H.expect(s.rig.v == 0, "a jackknife stops the rig")
end

function M.no_false_jackknife_in_normal_reversing()
    -- Guards the tapered-body regression: a full-width rectangle from the
    -- coupling reports a collision at ~25 deg, which would make the game
    -- impossible to play.
    local s = session.new(fixtures.field())
    s.rig.ph = math.rad(55)
    session.update(s, idle(), DT)
    H.expect(s.last_bump ~= "jackknife", "55 deg must not jackknife")
end

function M.parked_accepts_correct_pose()
    local s = session.new(fixtures.field())
    place_in_bay(s, 0)
    step(s, idle(), 60)
    H.expect(s.parked, "a stationary caravan inside the bay must count as parked")
    H.expect(s.final and s.final.time, "parking records a final time")
end

function M.parked_rejects_wrong_angle()
    local s = session.new(fixtures.field())
    place_in_bay(s, math.rad(15))     -- inside the 20x20 bay, but way off axis
    step(s, idle(), 120)
    H.expect(not s.parked, "a caravan at 15 deg must not count as parked")
end

function M.parked_rejects_reversed_facing()
    -- The bay has a required facing. Both orientations fit the rectangle, so
    -- only the heading rule can tell them apart -- and the carrier has to SHOW
    -- which one it wants, or this reads as a bug (see the bay arrow).
    local s = session.new(fixtures.field())
    local bay = s.level.bay
    session.place_caravan(s, bay.x, bay.y, bay.angle + math.pi)
    step(s, idle(), 120)
    H.expect(not s.parked, "a caravan parked 180 deg round must not count")

    session.place_caravan(s, bay.x, bay.y, bay.angle)
    step(s, idle(), 120)
    H.expect(s.parked, "the correct facing must park")
end

function M.parked_rejects_a_moving_caravan()
    local s = session.new(fixtures.field())
    place_in_bay(s, 0)
    s.rig.v = 1.0                     -- still rolling through the bay
    for _ = 1, 20 do session.update(s, idle(), DT) end
    H.expect(not s.parked, "a rolling caravan must not count as parked")
end

-- The arc is a 10 s prediction. Reverse at 1.8 m/s is ~18 m, which is the
-- manoeuvre; forward at 11 m/s is ~90 m, which is longer than the yard and
-- reads as decoration over the whole scene. Visible at rest and in reverse.
function M.guide_visible_only_when_not_driving_forward()
    local s = session.new(fixtures.field())
    H.expect(session.guide_visible(s), "the arc must be visible at rest -- it previews the reverse")

    step(s, forward(), 60)
    H.expect(s.rig.v > 0.5, "fixture: the rig should be rolling forward")
    H.expect(not session.guide_visible(s), "the arc must be hidden while driving forward")

    step(s, backward(), 240)
    H.expect(s.rig.v < -0.5, "fixture: the rig should be reversing")
    H.expect(session.guide_visible(s), "the arc must be visible in reverse")
end

-- A recorded run is a list of numbers; a replay is only exact if the sim
-- consumes the same numbers it was recorded with. So the input is snapped to a
-- grid BEFORE the physics sees it, and snapping twice must change nothing.
function M.quantise_is_idempotent()
    local raw = { steer = 0.37, throttle = 0.61, brake = 0.13, handbrake = true }
    local once = session.quantise(raw)
    local twice = session.quantise(once)
    H.expect(once.steer == twice.steer and once.throttle == twice.throttle
             and once.brake == twice.brake,
             "quantising twice must equal quantising once, or replay cannot be exact")
    H.expect(once.handbrake == true, "the handbrake must survive the copy")
    H.expect(once.last_device == raw.last_device, "so must the device label (the HUD reads it)")
end

function M.quantise_snaps_to_its_grid()
    local q = session.quantise({ steer = 0.37, throttle = 0.61, brake = 0 })
    local steer_step, pedal_step = 1 / session.STEER_STEPS, 1 / session.PEDAL_STEPS
    H.expect(math.abs(q.steer - 0.37) <= steer_step / 2, "steer lands within half a step")
    H.expect(math.abs(q.throttle - 0.61) <= pedal_step / 2, "pedals land within half a step")
    H.expect(q.steer ~= 0.37, "and actually snaps: 0.37 is not already on the grid")
    -- the grid must be finer than anything the player can feel: one step of lock
    H.expect(steer_step * rig.CAR.max_steer < math.rad(0.5),
             "a steer step must be under half a degree of lock")
end

function M.quantised_input_still_parks_level_1()
    -- The proof that quantisation is not a physics change: the straight reverse
    -- that parks level 1 must still park it, with no bumps, on the grid.
    local levels = require("lib.levels")
    local lvl = levels.get(1)
    local s = session.new(lvl)
    local reverse = session.quantise({ steer = 0, throttle = 0, brake = 1, handbrake = false })
    local stop = session.quantise({ steer = 0, throttle = 0, brake = 0, handbrake = true })
    local stop_x = lvl.bay.x - (rig.CARAVAN.coupling - rig.CARAVAN.length / 2)
    local t = 0
    while s.rig.x > stop_x and t < 60 do
        session.update(s, reverse, DT)
        t = t + DT
    end
    while not s.parked and t < 60 do
        session.update(s, stop, DT)
        t = t + DT
    end
    H.expect(s.parked, "level 1 must still park on quantised input")
    H.expect(s.final.bumps == 0, "and still without touching anything")
end

-- ---------------------------------------------------------------------------
-- Cues: the session is the only module that knows when something HAPPENED.
-- The shell drains this list after its step loop and hands it to the mixer, so
-- "did that bump make a sound" and "did it fire twice" stay headless questions
-- instead of something you check by listening.
-- ---------------------------------------------------------------------------

local function kinds(list, kind)
    local out = {}
    for _, c in ipairs(list) do if c.kind == kind then out[#out + 1] = c end end
    return out
end

function M.drain_empties_the_queue()
    local s = session.new(fixtures.field())
    step(s, forward(), 1)
    local first = session.drain(s)
    H.expect(#first > 0, "the first pedal must queue a cue")
    H.expect(#session.drain(s) == 0, "draining twice must not replay the same cues")
end

function M.start_cue_fires_once_on_the_first_pedal()
    local s = session.new(fixtures.field())
    step(s, idle(), 60)
    H.expect(#kinds(session.drain(s), "start") == 0, "waiting at the line is not a start")
    step(s, forward(), 60)
    H.expect(#kinds(session.drain(s), "start") == 1, "the first pedal starts exactly one clock")
    step(s, forward(), 60)
    H.expect(#kinds(session.drain(s), "start") == 0, "and only once")
end

function M.gear_cue_fires_when_reverse_engages()
    -- The dwell gate is invisible physics: without a cue at the transition the
    -- player has no way to know the gear caught, and "reverse does not work"
    -- is the report you get instead.
    local s = session.new(fixtures.field())
    local n, first_at = 0, nil
    for i = 1, 240 do
        session.update(s, backward(), DT)
        for _, c in ipairs(session.drain(s)) do
            if c.kind == "gear" and c.gear == "R" then n, first_at = n + 1, first_at or i end
        end
    end
    H.expect(s.rig.v < 0, "fixture: the rig should be reversing")
    H.expect(n == 1, "reverse must clunk once, got " .. n)
    H.expect(first_at and first_at <= 24, "the clunk must land at the transition, not later")
end

function M.wall_bump_cue_carries_the_impact_speed()
    -- revert() zeroes the speed, so the cue has to carry it: a scrape at 0.3 m/s
    -- and a slam at 11 m/s must not sound the same.
    local lvl = fixtures.field()
    lvl.walls = { { x = 0, y = 0, w = 4, h = 4 } }   -- already under the rig
    local s = session.new(lvl)
    s.rig.v = 3.0
    session.update(s, idle(), DT)
    local bumps = kinds(session.drain(s), "bump")
    H.expect(#bumps == 1, "a wall hit queues one bump, got " .. #bumps)
    H.expect(bumps[1].cause == "wall", "cause should be wall, got " .. tostring(bumps[1].cause))
    H.expect(bumps[1].speed > 2.5, "the cue carries the speed at impact, got " .. tostring(bumps[1].speed))
end

function M.jackknife_cue_is_not_a_wall_bump()
    local s = session.new(fixtures.field())
    s.rig.ph = math.rad(85)
    session.update(s, idle(), DT)
    local bumps = kinds(session.drain(s), "bump")
    H.expect(#bumps == 1 and bumps[1].cause == "jackknife",
        "over-articulation is its own sound: the fix is to straighten, not to back off")
end

function M.cone_cue_fires_once()
    local lvl = fixtures.field()
    lvl.cones = { { x = 0, y = 4, r = 0.35 } }
    local s = session.new(lvl)
    s.rig.th, s.rig.ph = math.pi / 2, math.pi / 2
    local n = 0
    for _ = 1, 360 do
        session.update(s, forward(), DT)
        n = n + #kinds(session.drain(s), "cone")
    end
    H.expect(s.cones[1].hit, "fixture: the cone should be knocked")
    H.expect(n == 1, "a knocked cone makes one sound, got " .. n)
end

function M.park_cue_carries_the_stars()
    local s = session.new(fixtures.field())
    place_in_bay(s, 0)
    local parks = {}
    for _ = 1, 60 do
        session.update(s, idle(), DT)
        for _, c in ipairs(session.drain(s)) do
            if c.kind == "park" then parks[#parks + 1] = c end
        end
    end
    H.expect(s.parked, "fixture: it must park")
    H.expect(#parks == 1, "one park, one chime, got " .. #parks)
    H.expect(parks[1].stars == session.grade(s), "the chime carries the grade it earned")
end

function M.par_cue_fires_once()
    local lvl = fixtures.field()
    lvl.par = 2
    local s = session.new(lvl)
    local n = 0
    for _ = 1, 480 do                      -- 4 s of driving, par is 2
        session.update(s, forward(), DT)
        n = n + #kinds(session.drain(s), "par")
    end
    H.expect(s.t > lvl.par, "fixture: the clock should be past par")
    H.expect(n == 1, "crossing par ticks once, got " .. n)
end

return M
