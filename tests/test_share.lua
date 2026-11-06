-- A share bundle: one paste carrying a level, a run, or both, in text or as a
-- TY1: code. Everything here arrives from a stranger, so every failure is a
-- sentence and never a traceback.

local H = require("tests.helper")
local levels = require("lib.levels")
local session = require("lib.session")
local rig = require("lib.rig")
local run = require("lib.run")
local share = require("lib.share")
local codec = require("lib.codec").love_data()

local M = { order = {
    "a_bundle_carries_a_level_and_a_run",
    "a_level_alone_is_a_valid_bundle",
    "a_code_is_the_same_document",
    "a_broken_code_is_refused",
    "an_empty_bundle_is_refused",
} }

local DT = 1 / 120

local function parked_run(lvl)
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
    H.expect(s.parked, "fixture: the run must park")
    return r
end

function M.a_bundle_carries_a_level_and_a_run()
    local lvl = levels.get(1)
    local text = share.bundle(lvl, parked_run(lvl), codec)
    H.expect(type(text) == "string", "bundle must produce a document")

    local got, err = share.unpack(text, codec)
    H.expect(got ~= nil, tostring(err))
    H.expect(got.level ~= nil and got.level.id == "straight-back", "the level rides along")
    H.expect(got.level.name == lvl.name, "with its name")
    H.expect(got.run ~= nil and got.run.level_id == "straight-back", "and the run")
    H.expect(got.author == "user", "with an anonymous default author")
    -- a level rebuilt from a bundle must still be a legitimate level
    H.expect(#require("lib.levelcheck").errors(got.level) == 0, "the level must survive the trip intact")
end

function M.a_level_alone_is_a_valid_bundle()
    local got, err = share.unpack(share.bundle(levels.get(2), nil, codec), codec)
    H.expect(got ~= nil, tostring(err))
    H.expect(got.level.id == "long-way-back" and got.run == nil, "a level with no run is a bundle")
end

function M.a_code_is_the_same_document()
    local lvl = levels.get(1)
    local text = share.bundle(lvl, parked_run(lvl), codec)
    local code = share.code(text, codec)
    H.expect(code:sub(1, 4) == "TY1:", "the clipboard form is prefixed")
    H.expect(#code < 4096, "and short enough to paste into a chat: " .. #code .. " chars")

    local from_code = share.unpack(code, codec)
    local from_text = share.unpack(text, codec)
    H.expect(from_code and from_text, "both forms must unpack")
    H.expect(from_code.level.id == from_text.level.id, "identically")
    H.expect(#from_code.run.frames == #from_text.run.frames, "down to the frame count")
end

function M.a_broken_code_is_refused()
    local text = share.bundle(levels.get(1), nil, codec)
    local good = share.code(text, codec)

    local cut = good:sub(1, #good - 12)
    local got, err = share.unpack(cut, codec)
    H.expect(got == nil, "a truncated code must not unpack")
    H.expect(type(err) == "string" and #err > 0, "and say why")

    local not_a_share = share.unpack("hello there", codec)
    H.expect(not_a_share == nil, "plain text is not a bundle")
    H.expect(share.unpack(good) == nil, "a missing codec is an error, not a crash")
end

function M.an_empty_bundle_is_refused()
    H.expect(share.bundle(nil, nil, codec) == nil, "nothing to share is not a bundle")
    local bare = share.HEADER .. share.VERSION .. "\nauthor \"user\"\n"
    local got, err = share.unpack(bare, codec)
    H.expect(got == nil and tostring(err):find("no level") ~= nil, tostring(err))
end

return M
