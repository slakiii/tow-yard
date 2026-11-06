-- Recording an attempt. The properties here are the ones a ghost depends on:
-- one frame per physics step, frames that the sim actually consumed, a hard cap,
-- and a run that stops growing once it has been parked.

local H = require("tests.helper")
local levels = require("lib.levels")
local session = require("lib.session")
local run = require("lib.run")
local codec = require("lib.codec").love_data()

local M = { order = {
    "one_frame_per_step",
    "frames_hold_what_the_sim_consumed",
    "a_finished_run_ignores_more_input",
    "record_is_capped",
    "a_run_round_trips_through_text",
    "encode_is_byte_stable",
    "a_run_stays_small",
    "a_body_of_the_wrong_length_is_rejected",
    "a_frame_count_over_the_cap_is_rejected",
    "a_bad_run_header_is_rejected",
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

return M
