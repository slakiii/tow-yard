-- Recording an attempt. The properties here are the ones a ghost depends on:
-- one frame per physics step, frames that the sim actually consumed, a hard cap,
-- and a run that stops growing once it has been parked.

local H = require("tests.helper")
local levels = require("lib.levels")
local session = require("lib.session")
local rig = require("lib.rig")
local run = require("lib.run")
local codec = require("lib.codec").love_data()

local M = { order = {
    "one_frame_per_step",
    "frames_hold_what_the_sim_consumed",
    "a_finished_run_ignores_more_input",
    "record_is_capped",
    "recording_starts_with_the_first_action",
    "steering_at_standstill_counts_but_does_not_start_the_clock",
    "a_stored_run_loses_its_idle_prefix",
    "the_ghost_waits_for_the_player",
    "the_ghost_stays_level_with_a_pre_roll",
    "a_run_round_trips_through_text",
    "encode_is_byte_stable",
    "a_run_stays_small",
    "a_body_of_the_wrong_length_is_rejected",
    "a_frame_count_over_the_cap_is_rejected",
    "a_bad_run_header_is_rejected",
    "replay_reproduces_the_drive_exactly",
    "replay_stops_at_the_park",
    "verify_accepts_a_real_park",
    "verify_refuses_other_geometry_and_other_builds",
    "verify_refuses_a_run_that_does_not_park",
    "verify_ignores_the_claimed_time",
    "a_ghost_keeps_driving_after_the_player_parks",
    "follow_steps_at_the_fixed_cadence",
    "a_replay_scores_the_run_the_way_it_was_driven",
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

-- A three-frame run with values off the grid on purpose: record quantises, and
-- the document must carry those quantised values without loss.
local function three_frame_run()
    local r = run.new(levels.get(1))
    run.record(r, { steer = 0, throttle = 0, brake = 1, handbrake = false })
    run.record(r, { steer = 0.5, throttle = 0, brake = 0.25, handbrake = true })
    run.record(r, { steer = -0.75, throttle = 0.5, brake = 0, handbrake = false })
    r.time, r.bumps = 12.34, 0
    return r
end

function M.the_ghost_stays_level_with_a_pre_roll()
    -- The regression: a run can hold frames the player's clock never counted.
    -- run.recording() keeps the frames where the player only steered at a
    -- standstill ("the wheel position is physics state"), but session.update()
    -- only starts the clock on a pedal. So the run has a pre-roll the player's
    -- step count does not, and advancing the ghost to the player's count leaves
    -- it replaying its own pre-roll while the player has already driven --
    -- measured at 3.6 m apart after a two-second setup.
    --
    -- The fix is to advance the ghost to ITS OWN clock start plus the player's
    -- steps: the two clocks then run on the same beat.
    local lvl = levels.get(1)

    -- a player who sets the angle up before committing to the reverse
    local ps, pr = session.new(lvl), run.new(lvl)
    local setup = { steer = 0.4, throttle = 0, brake = 0, handbrake = false }
    local drive = { steer = 0, throttle = 0, brake = 1, handbrake = false }
    local hold = { steer = 0, throttle = 0, brake = 0, handbrake = true }
    for _ = 1, 240 do
        run.record(pr, setup); session.update(ps, setup, DT)
    end
    H.expect(ps.started == false, "fixture: the setup must not start the clock")
    H.expect(#pr.frames == 240, "fixture: but it IS recorded: " .. #pr.frames)

    local steps = 0
    for _ = 1, 1200 do
        local inp = (ps.rig.x > 24) and drive or hold
        run.record(pr, inp)
        session.update(ps, inp, DT)
        if ps.started then steps = steps + 1 end
        if ps.parked then break end
    end
    H.expect(#pr.frames > steps, "fixture: the run holds more frames than the clock counts")

    -- the same drive, replayed as a ghost
    local ghost = { run = pr, s = session.new(lvl), step = 0 }

    -- the FIXED way: the ghost's own clock start plus the player's steps
    run.advance_aligned(ghost, steps)
    H.expect(math.abs(ghost.s.rig.x - ps.rig.x) < 0.01,
        string.format("the ghost must sit where the player sits, got %.3f m apart",
            math.abs(ghost.s.rig.x - ps.rig.x)))
    H.expect(math.abs(ghost.s.rig.ph - ps.rig.ph) < 0.01,
        string.format("with the same articulation, got %.3f deg apart",
            math.deg(math.abs(ghost.s.rig.ph - ps.rig.ph))))

    -- and the OLD way -- advancing to the raw player count -- is what this test
    -- exists to prevent. It leaves the ghost replaying its own pre-roll.
    local old = { run = pr, s = session.new(lvl), step = 0 }
    run.advance(old, steps)
    H.expect(math.abs(old.s.rig.x - ps.rig.x) > 0.5,
        string.format("fixture: the raw count must misalign, got %.3f m",
            math.abs(old.s.rig.x - ps.rig.x)))
end

function M.a_run_round_trips_through_text()
    local r = three_frame_run()
    local text = run.encode(r, codec)
    H.expect(type(text) == "string" and #text > 0, "encode must produce a document")

    local back, err = run.decode(text, codec)
    H.expect(back ~= nil, tostring(err))
    H.expect(run.frames(back) == 3, "three frames in, three out")
    for i = 1, 3 do
        H.expect(back.frames[i].steer == r.frames[i].steer, "steer " .. i .. " must be exact")
        H.expect(back.frames[i].throttle == r.frames[i].throttle, "throttle " .. i .. " must be exact")
        H.expect(back.frames[i].brake == r.frames[i].brake, "brake " .. i .. " must be exact")
        H.expect(back.frames[i].handbrake == r.frames[i].handbrake, "handbrake " .. i)
    end
    H.expect(back.level_id == "straight-back", "the document names its level")
    H.expect(back.content == r.content, "and carries the content hash")
    H.expect(back.build == r.build, "and the build stamp")
    H.expect(math.abs(back.time - 12.34) < 0.005 and back.bumps == 0, "the claimed numbers ride along")
end

function M.encode_is_byte_stable()
    local r = three_frame_run()
    local a = run.encode(r, codec)
    H.expect(run.encode(r, codec) == a, "encoding the same run twice must give the same bytes")
    local back = run.decode(a, codec)
    H.expect(back ~= nil, "fixture: the document must decode")
    H.expect(run.encode(back, codec) == a, "and decode/encode must be a fixed point")
end

function M.a_run_stays_small()
    -- A run is meant to travel in a chat message. 600 identical frames is 2400
    -- raw bytes; if compression ever stops working the feature quietly becomes
    -- "paste this 15 KB".
    local r = run.new(levels.get(1))
    for _ = 1, 600 do run.record(r, { steer = 0, throttle = 0, brake = 1, handbrake = false }) end
    local text = run.encode(r, codec)
    H.expect(#text < 600 * 4 / 2, "600 frames must compress below half of raw, got " .. #text)
end

function M.a_body_of_the_wrong_length_is_rejected()
    local text = run.encode(three_frame_run(), codec)
    local data = text:match("data ([^\n]+)")
    H.expect(data ~= nil, "fixture: the document must have a data line")
    local short = text:gsub("data [^\n]+", "data " .. data:sub(1, #data - 8))
    local back, err = run.decode(short, codec)
    H.expect(back == nil, "a truncated body must not decode into a run")
    H.expect(tostring(err):find("decompress") ~= nil or tostring(err):find("length") ~= nil,
             "the reason should say what is wrong, got: " .. tostring(err))
end

function M.a_frame_count_over_the_cap_is_rejected()
    local text = run.encode(three_frame_run(), codec)
    local big = text:gsub("frames %d+", "frames 99999")
    local back, err = run.decode(big, codec)
    H.expect(back == nil, "a document claiming 99999 frames must be refused")
    H.expect(tostring(err):find("too many") ~= nil, "and say so, got: " .. tostring(err))
end

function M.a_bad_run_header_is_rejected()
    local text = run.encode(three_frame_run(), codec)
    local bad = text:gsub("^TOWYARD RUN 1", "TOWYARD RUN 9")
    H.expect(run.decode(bad, codec) == nil, "an unknown version must be refused")
    H.expect(run.decode(text) == nil, "and a missing codec is an error, not a crash")
end

-- Drive level 1 to a real park, recording. The run every verification test
-- needs, produced the way the game produces one.
local function drive_level_1()
    local lvl = levels.get(1)
    local s, r = session.new(lvl), run.new(lvl)
    local stop_x = lvl.bay.x - (rig.CARAVAN.coupling - rig.CARAVAN.length / 2)
    local t = 0
    while t < 60 and not s.parked do
        local inp = (s.rig.x > stop_x)
            and { steer = 0, throttle = 0, brake = 1, handbrake = false }
            or { steer = 0, throttle = 0, brake = 0, handbrake = true }
        run.record(r, inp)
        session.update(s, inp, DT)
        t = t + DT
    end
    run.finish(r, s)
    H.expect(s.parked, "fixture: level 1 must park")
    return lvl, s, r
end

function M.replay_reproduces_the_drive_exactly()
    -- A curved drive, not a straight line: the steering changes every step, so a
    -- lossy document or a rounding step would show up immediately.
    local lvl = levels.get(1)
    local s, r = session.new(lvl), run.new(lvl)
    for i = 1, 900 do
        local inp = { steer = math.sin(i / 90) * 0.6, throttle = 0, brake = 1, handbrake = false }
        run.record(r, inp)
        session.update(s, inp, DT)
    end
    local back = run.decode(run.encode(r, codec), codec)
    H.expect(back ~= nil, "fixture: the run must survive the document")
    local again = run.replay(lvl, back)
    H.expect(again.rig.x == s.rig.x, "x must match exactly, not nearly")
    H.expect(again.rig.y == s.rig.y, "y must match exactly")
    H.expect(again.rig.th == s.rig.th, "th must match exactly")
    H.expect(again.rig.ph == s.rig.ph, "ph must match exactly")
    H.expect(again.t == s.t, "the clock must match exactly")
end

function M.replay_stops_at_the_park()
    -- A shell that keeps recording after the park, or a hand-edited file, must
    -- not move the ghost: the park ends the drive.
    local lvl, s, r = drive_level_1()
    local px, py = s.rig.x, s.rig.y
    for _ = 1, 200 do
        r.frames[#r.frames + 1] = { steer = 0.5, throttle = 1, brake = 0, handbrake = false }
    end
    local again = run.replay(lvl, r)
    H.expect(again.parked, "the replay is still parked")
    H.expect(again.rig.x == px and again.rig.y == py, "and the trailing frames did not move it")
end

function M.verify_accepts_a_real_park()
    local lvl, s, r = drive_level_1()
    local ok, final = run.verify(lvl, run.decode(run.encode(r, codec), codec))
    H.expect(ok == true, tostring(final))
    H.expect(math.abs(final.time - s.final.time) < 1e-9, "the replay's final is the drive's final")
end

function M.verify_refuses_other_geometry_and_other_builds()
    local lvl, _, r = drive_level_1()
    local copy = run.decode(run.encode(r, codec), codec)

    copy.content = string.rep("ab", 32)
    local ok, why = run.verify(lvl, copy)
    H.expect(ok == false and tostring(why):find("geometry") ~= nil, "geometry: " .. tostring(why))

    copy.content = r.content
    copy.build = string.rep("cd", 32)
    ok, why = run.verify(lvl, copy)
    H.expect(ok == false and tostring(why):find("build") ~= nil, "build: " .. tostring(why))

    copy.build = r.build
    copy.level_id = "clean-line"
    ok, why = run.verify(lvl, copy)
    H.expect(ok == false and tostring(why):find("different level") ~= nil, "level: " .. tostring(why))
end

function M.verify_refuses_a_run_that_does_not_park()
    local lvl = levels.get(1)
    local r = run.new(lvl)
    for _ = 1, 20 do run.record(r, { steer = 0, throttle = 0, brake = 1, handbrake = false }) end
    local ok, why = run.verify(lvl, r)
    H.expect(ok == false, "twenty frames of reversing is not a park")
    H.expect(tostring(why):find("does not park") ~= nil, "and says so: " .. tostring(why))
end

function M.verify_ignores_the_claimed_time()
    local lvl, s, r = drive_level_1()
    r.time = 9.00                        -- a lie in the header
    local ok, final = run.verify(lvl, run.decode(run.encode(r, codec), codec))
    H.expect(ok, tostring(final))
    H.expect(math.abs(final.time - s.final.time) < 1e-9,
             "the recomputed time must win, got " .. tostring(final.time))
    H.expect(math.abs(final.time - 9.00) > 1, "and the header's 9.00 must never be reported")
end

function M.recording_starts_with_the_first_action()
    local lvl = levels.get(1)
    local s = session.new(lvl)
    local r = run.new(lvl)
    local idle = { steer = 0, throttle = 0, brake = 0, handbrake = false }

    -- two seconds of nobody touching anything: no frames, no clock
    for _ = 1, 240 do
        if run.recording(s, idle) then run.record(r, idle) end
        session.update(s, idle, 1 / 120)
    end
    H.expect(#r.frames == 0, "waiting is not a run: " .. #r.frames .. " frames")
    H.expect(s.started == false, "and the clock has not started")

    local drive = { steer = 0, throttle = 1, brake = 0, handbrake = false }
    for _ = 1, 60 do
        if run.recording(s, drive) then run.record(r, drive) end
        session.update(s, drive, 1 / 120)
    end
    H.expect(#r.frames == 60, "the run starts on the first action: " .. #r.frames)

    -- and once it has started, letting go is still part of the run
    for _ = 1, 30 do
        if run.recording(s, idle) then run.record(r, idle) end
        session.update(s, idle, 1 / 120)
    end
    H.expect(#r.frames == 90, "coasting is recorded: " .. #r.frames)
end

function M.steering_at_standstill_counts_but_does_not_start_the_clock()
    local s = session.new(levels.get(1))
    local steer = { steer = -1, throttle = 0, brake = 0, handbrake = false }

    -- the wheel is physics state: a run that dropped these frames would replay
    -- with the wheels straight and diverge from what actually happened
    H.expect(run.recording(s, steer), "turning the wheel is recorded")
    session.update(s, steer, 1 / 120)
    H.expect(s.started == false, "but it does not start the clock")
    H.expect(s.t == 0, "so no time is charged for it: " .. s.t)
end

function M.a_stored_run_loses_its_idle_prefix()
    local lvl = levels.get(1)
    local s, r = session.new(lvl), run.new(lvl)
    local idle = { steer = 0, throttle = 0, brake = 0, handbrake = false }
    local drive = { steer = 0, throttle = 1, brake = 0, handbrake = false }

    -- a run recorded the old way: the level opens, then the player acts
    for _ = 1, 120 do run.record(r, idle); session.update(s, idle, 1 / 120) end
    for _ = 1, 60 do run.record(r, drive); session.update(s, drive, 1 / 120) end
    H.expect(#r.frames == 180, "fixture: 180 frames")

    local dropped = run.trim(r)
    H.expect(dropped == 120, "the idle prefix is dropped: " .. dropped)
    H.expect(#r.frames == 60, "and what is left is the drive")

    -- replaying it reaches the same place at the same time: the prefix carried no
    -- input, so removing it cannot change the outcome
    local replay = run.replay(lvl, r)
    H.expect(math.abs(replay.t - s.t) < 1e-9,
        "same clock after the trim: " .. tostring(replay.t) .. " vs " .. tostring(s.t))
    H.expect(math.abs(replay.rig.x - s.rig.x) < 1e-9
        and math.abs(replay.rig.y - s.rig.y) < 1e-9
        and math.abs(replay.rig.th - s.rig.th) < 1e-9
        and math.abs(replay.rig.ph - s.rig.ph) < 1e-9,
        "and the same pose")

    -- a pause in the middle of the run is not a prefix: only the front is trimmed
    local s2, r2 = session.new(lvl), run.new(lvl)
    for _ = 1, 10 do run.record(r2, drive); session.update(s2, drive, 1 / 120) end
    for _ = 1, 10 do run.record(r2, idle); session.update(s2, idle, 1 / 120) end
    H.expect(run.trim(r2) == 0, "coasting after the start stays in the run")
end

function M.the_ghost_waits_for_the_player()
    local lvl = levels.get(1)
    local s, r = session.new(lvl), run.new(lvl)
    local drive = { steer = 0, throttle = 1, brake = 0, handbrake = false }
    for _ = 1, 20 do
        run.record(r, drive)
        session.update(s, drive, 1 / 120)
    end

    local ghost = { run = r, s = session.new(lvl), step = 0 }

    -- before the player moves, the ghost does not move: no time, no frames
    H.expect(run.advance(ghost, 0) == 0, "nothing happens before the start")
    H.expect(ghost.step == 0, "and the ghost is still on its first frame")

    -- then it follows the player's step count, one frame per step
    H.expect(run.advance(ghost, 5) == 5, "five steps, five frames")
    H.expect(ghost.s.started, "which starts the ghost's own clock")

    -- asking for more than the run holds stops at the end, not past it
    H.expect(run.advance(ghost, 500) == 15, "the rest of the run: " .. ghost.step)
    H.expect(ghost.step == #r.frames, "and no further: " .. ghost.step)

    -- a paused game does not call advance at all, so the ghost cannot run ahead;
    -- and neither can it if the player's count goes backwards
    H.expect(run.advance(ghost, 3) == 0, "never backwards")
end

function M.a_ghost_keeps_driving_after_the_player_parks()
    -- The regression: the player's step count stops at the park, so a ghost that
    -- only followed that count froze mid-line at the exact moment the result card
    -- said "new best". A ghost that quits when you beat it is not a rival.
    local lvl, _, r = drive_level_1()
    H.expect(#r.frames > 60, "fixture: the drive is long enough to be cut short")

    local ghost = { run = r, s = session.new(lvl), step = 0 }
    run.advance(ghost, 30)
    H.expect(ghost.step == 30, "fixture: the ghost is 30 steps in: " .. ghost.step)
    H.expect(not ghost.s.parked, "fixture: and it has not parked yet")

    -- the player's clock is stopped at the park, so the shell feeds the ghost
    -- frame time instead; it must drive to the end of its own line
    local guard = 0
    while run.follow(ghost, 0.1, DT, 12) > 0 and guard < 100000 do guard = guard + 1 end
    H.expect(ghost.step == #r.frames,
        "the ghost consumed its whole run: " .. ghost.step .. "/" .. #r.frames)
    H.expect(ghost.s.parked, "and reached its own park")
end

function M.follow_steps_at_the_fixed_cadence()
    local lvl, _, r = drive_level_1()
    local ghost = { run = r, s = session.new(lvl), step = 0 }

    -- six frame-times of stall is six frames: after the park the ghost keeps
    -- driving in real time instead of teleporting to the end of its run
    local moved, left = run.follow(ghost, 6 * DT, DT, 12)
    H.expect(moved == 6, "six steps of time, six frames: " .. moved)
    H.expect(ghost.step == 6, "and the ghost is six frames in: " .. ghost.step)
    H.expect(math.abs(left) < 1e-12, "leaving no accumulated time: " .. tostring(left))

    -- the same per-frame cap as the player's loop: a long stall cannot spiral
    H.expect(run.follow(ghost, 5.0, DT, 12) == 12, "a long stall is capped like the sim")

    -- a spent ghost or no ghost at all moves nothing, and does not crash
    local spent = { run = { frames = {} }, s = session.new(lvl), step = 0 }
    H.expect(run.follow(spent, 6 * DT, DT, 12) == 0, "a spent run has nothing to drive")
    H.expect(run.follow(nil, 6 * DT, DT, 12) == 0, "and no ghost is not a crash")
end

-- A straight run at the bay with one cone on the line: the price of the clip has
-- to survive the round trip through the document.
local function penalty_level()
    return {
        id = "penalty-fixture",
        name = "Penalty fixture",
        hint = "",
        bounds = { x0 = -20, y0 = -20, x1 = 50, y1 = 20 },
        spawn = { x = 0, y = 0, th = 0 },
        bay = { x = 30, y = 0, w = 20, h = 20, angle = 0, tol = math.rad(6) },
        walls = {},
        cones = { { x = 12, y = 0, r = 0.6, kind = "cone" } },
        par = 10,
        apron = 0,
    }
end

function M.a_replay_scores_the_run_the_way_it_was_driven()
    -- The penalty lives in the sim, so the ghost's card is the run's own numbers.
    -- Put the price in the shell instead and a stored run would replay to a
    -- different score than the one that was recorded.
    local lvl = penalty_level()
    local s, r = session.new(lvl), run.new(lvl)

    local drive = { steer = 0, throttle = 1, brake = 0, handbrake = false }
    local coast = { steer = 0, throttle = 0, brake = 1, handbrake = false }
    local hold = { steer = 0, throttle = 0, brake = 0, handbrake = true }

    local guard = 0
    while s.rig.x < 27 and guard < 2400 do
        run.record(r, drive); session.update(s, drive, DT); guard = guard + 1
    end
    guard = 0
    while s.rig.v > 0.12 and guard < 1200 do
        run.record(r, coast); session.update(s, coast, DT); guard = guard + 1
    end
    guard = 0
    while not s.parked and guard < 1200 do
        run.record(r, hold); session.update(s, hold, DT); guard = guard + 1
    end
    run.finish(r, s)

    H.expect(s.parked, "fixture: the drive must park")
    H.expect(s.final.cone_hits == 1, "fixture: it clipped the cone: " .. s.final.cone_hits)
    H.expect(s.final.time > s.final.driven, "fixture: the counted time carries the penalty")

    local back = run.decode(run.encode(r, codec), codec)
    H.expect(back ~= nil, "fixture: the run must survive the document")
    local again = run.replay(lvl, back)
    H.expect(again.parked, "the replay parks")
    H.expect(again.final.time == s.final.time, "the replay scores the same time exactly")
    H.expect(again.final.penalties == s.final.penalties,
        "and the same penalty: " .. tostring(again.final.penalties))
    H.expect(again.final.damaged == false, "a cone is not damage")
end

return M
