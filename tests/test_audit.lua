-- The level audit is a development instrument, so it is worth exactly as much as
-- the confidence that it still runs. These tests exercise the parts that broke
-- while it was being written: the park test it targets, the honesty of a failed
-- approach, and the replay cross-check.

local H = require("tests.helper")
local audit = require("lib.audit")
local levels = require("lib.levels")

local M = { order = { "parks_level_1_from_a_clear_pose", "a_blocked_pose_is_not_a_park",
                      "search_finds_a_line_and_replays_it" } }

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

return M
