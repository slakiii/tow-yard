-- The level audit is a development instrument, so it is worth exactly as much as
-- the confidence that it still runs. These tests exercise the parts that broke
-- while it was being written: the park test it targets, the honesty of a failed
-- approach, and the replay cross-check.

local H = require("tests.helper")
local audit = require("lib.audit")
local levels = require("lib.levels")

local M = { order = { "parks_level_1_from_a_clear_pose", "a_blocked_pose_is_not_a_park",
                      "search_finds_a_line_and_replays_it",
                      "the_instrument_sees_an_off_axis_bay",
                      "a_bay_beyond_reach_is_reported_as_unproven_not_unwinnable" } }

function M.parks_level_1_from_a_clear_pose()
    -- Level 1 is dead straight: a staging pose 10 m up the yard, nose along the
    -- bay axis, and the reverse should park with no contact at all.
    local r = audit.drive_in(levels.get(1), { x = 32, y = 20, th = 0 }, { pre = 0 })
    H.expect(r.reached, "the clear staging pose must be reachable from the spawn")
    H.expect(r.parked, "level 1 must park from a clear staging pose")
    H.expect(r.bumps == 0, "a straight reverse must not touch anything, bumps=" .. r.bumps)
end

function M.a_blocked_pose_is_not_a_park()
    -- Sending the rig at a pose inside the hedge must fail loudly. A solver that
    -- reports a park through a wall is the one failure mode that would let an
    -- unwinnable level ship.
    local r = audit.drive_in(levels.get(1), { x = 28, y = 13.9, th = 0 }, { pre = 0 })
    H.expect(not r.parked, "a pose inside the hedge must not report a park")
end

function M.search_finds_a_line_and_replays_it()
    -- One pose is enough for level 1, so the search can be tested in a fraction
    -- of a second instead of the full grid.
    local res = audit.solve(levels.get(1), {
        grid = { pre = { 0 }, dist = { 8, 11 }, off = { 0 }, dpsi = { 0 } },
    })
    H.expect(res.solved, "level 1 must have a line through a staging pose straight up the yard")
    H.expect(res.best and res.best.time > 0, "the line must have a time")
    H.expect(res.best.bumps == 0, "the best line must be contact-free")
    H.expect(res.best.replay ~= nil, "the search must cross-check its own line")
    H.expect(res.best.replay.ok, "the same line replayed must park again")
    H.expect(math.abs(res.best.replay.dx) < 0.01 and math.abs(res.best.replay.dy) < 0.01,
             string.format("replay must land on the same pose, got dx %.4f dy %.4f",
                           res.best.replay.dx, res.best.replay.dy))
    H.expect(res.best.replay.time <= res.best.time + 2.5,
             "replay must not take wildly longer than the searched line")
end

-- The calibration that matters, and the one that was missing: an EMPTY yard
-- with the bay turned away from the spawn->bay bearing must still be found.
--
-- The controller used to derive its target heading from the bearing to the
-- pose, so it could only ever arrive pointing along that bearing. The moment
-- the bay axis differed from the bearing, the arrival test was unsatisfiable
-- and the instrument reported NO LINE on a level a human parks first try --
-- measured at 30 degrees off-axis on an empty yard. A verdict the instrument
-- cannot earn is not a finding about the level, so this pins the blind spot.
local function bay_at(angle_deg)
    return {
        id = "synthetic", name = "Synthetic", hint = "",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 46, y = 20, th = 0 },
        bay = { x = 22, y = 20, w = 9, h = 4, angle = math.rad(angle_deg), tol = math.rad(6) },
        walls = {}, cones = {}, surfaces = {},
        par = 30, apron = 0,
    }
end

-- Measured reach: the two-segment search (a forward arc, a stop, a reverse)
-- finds a line for every off-axis bay up to 60 degrees. The angles below are
-- the ones the instrument is verified to see; the assertion is against that
-- measured range, not an aspiration.
local REACHABLE = { 0, 15, 30, 45, 60 }

function M.the_instrument_sees_an_off_axis_bay()
    -- An empty yard is the easiest possible level: no wall to clip, no cone to
    -- knock. If the instrument cannot find a line HERE, its verdict on a real
    -- level means nothing.
    for _, deg in ipairs(REACHABLE) do
        local lvl = bay_at(deg)
        local res = audit.solve(lvl, {
            grid = { pre = { 0 }, dist = { 8, 11 }, off = { 0 }, dpsi = { 0, 90, -90 } },
        })
        H.expect(res.solved,
            string.format("an empty yard with the bay at %d deg must have a line " ..
                          "(reached %d, parked %d) -- the instrument is blind, not the level",
                          deg, res.reached, res.parked))
        H.expect(res.best.bumps == 0,
            string.format("and the line must be contact-free at %d deg, got %d bumps",
                          deg, res.best.bumps))
    end
end

-- Beyond the measured reach the rig needs a three-point turn, which this
-- probe does not plan. The bug was never "the level is unwinnable" -- it was
-- that the instrument SAID so. It must now report a limit instead.
function M.a_bay_beyond_reach_is_reported_as_unproven_not_unwinnable()
    local lvl = bay_at(90)
    local res = audit.solve(lvl, {
        grid = { pre = { 0 }, dist = { 8, 11 }, off = { 0 }, dpsi = { 0, 90, -90 } },
    })
    H.expect(not res.solved, "a 90 deg bay is beyond the two-segment search")
    local text = table.concat(audit.format(res, 1), "\n")
    H.expect(text:find("UNPROVEN, not unwinnable", 1, true) ~= nil,
        "the report must say UNPROVEN, not unwinnable, when the search cannot express the level")
    H.expect(text:find("three%-point turn") ~= nil,
        "and it must name the manoeuvre it cannot plan")
    H.expect(text:find("two%-segment search") ~= nil,
        "and report what the two-segment search did manage")
end

return M
