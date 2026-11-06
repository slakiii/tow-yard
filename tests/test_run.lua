-- Recording an attempt. The properties here are the ones a ghost depends on:
-- one frame per physics step, frames that the sim actually consumed, a hard cap,
-- and a run that stops growing once it has been parked.

local H = require("tests.helper")
local levels = require("lib.levels")
local session = require("lib.session")
local run = require("lib.run")

local M = { order = {
    "one_frame_per_step",
    "frames_hold_what_the_sim_consumed",
    "a_finished_run_ignores_more_input",
    "record_is_capped",
} }

local DT = 1 / 120

function M.one_frame_per_step()
    local r = run.new(levels.get(1))
    for _ = 1, 300 do
        run.record(r, { steer = 0, throttle = 0, brake = 1, handbrake = false })
    end
    H.expect(run.frames(r) == 300, "300 steps, 300 frames -- got " .. run.frames(r))
    H.expect(r.level_id == "straight-back", "the run remembers which level it belongs to")
end

function M.frames_hold_what_the_sim_consumed()
    -- Whatever the caller passes, the frame is what session.update will see: a
    -- raw 0.37 must not reach the file as 0.37, because the sim never used it.
    local r = run.new(levels.get(1))
    run.record(r, { steer = 0.37, throttle = 0.61, brake = 0.13, handbrake = true })

    local frame = r.frames[1]
    local expected = session.quantise({ steer = 0.37, throttle = 0.61, brake = 0.13 })
    H.expect(frame.steer == expected.steer, "steer must be on the grid")
    H.expect(frame.throttle == expected.throttle, "throttle must be on the grid")
    H.expect(frame.brake == expected.brake, "brake must be on the grid")
    H.expect(frame.handbrake == true, "handbrake rides along as a boolean")
end

function M.a_finished_run_ignores_more_input()
    local lvl = levels.get(1)
    local s = session.new(lvl)
    session.place_caravan(s, lvl.bay.x, lvl.bay.y, lvl.bay.angle)
    for _ = 1, 60 do session.update(s, { steer = 0, throttle = 0, brake = 0, handbrake = true }, DT) end
    H.expect(s.parked, "fixture: the placed caravan must park")

    local r = run.new(lvl)
    for _ = 1, 40 do run.record(r, { steer = 0, throttle = 0, brake = 1, handbrake = false }) end
    run.finish(r, s)
    H.expect(run.frames(r) == 40, "finish keeps what was driven")

    for _ = 1, 40 do run.record(r, { steer = 0, throttle = 0, brake = 0, handbrake = true }) end
    H.expect(run.frames(r) == 40, "a parked run must not keep growing while the card is up")
    H.expect(r.time == s.final.time and r.bumps == s.final.bumps, "the claimed numbers ride along")
end

function M.record_is_capped()
    local r = run.new(levels.get(1))
    -- filled densely: `#` on a table with a hole is undefined, and a sparse
    -- fixture reported a length of 1 here
    for i = 1, run.MAX_FRAMES do
        r.frames[i] = { steer = 0, throttle = 0, brake = 0, handbrake = false }
    end
    run.record(r, { steer = 0, throttle = 1, brake = 0, handbrake = false })
    H.expect(run.frames(r) == run.MAX_FRAMES, "the cap holds: " .. run.frames(r))
    H.expect(run.MAX_FRAMES == 120 * 300, "five minutes of steps at 120 Hz")
end

return M
