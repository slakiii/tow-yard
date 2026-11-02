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

return M
