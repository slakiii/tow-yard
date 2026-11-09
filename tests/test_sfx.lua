-- The mixer's decisions, without a sound card: which cue, how loud, how high.
-- lib/sfx.lua takes an injected device for exactly this reason -- the mapping
-- from a physics event to a volume curve is the part that has rules in it.

local H = require("tests.helper")
local sfx = require("lib.sfx")
local session = require("lib.session")
local fixtures = require("tests.fixtures")
local rig = require("lib.rig")

local M = { order = {
    "pitch_keeps_the_manoeuvre_audible",
    "pitch_is_monotone_and_symmetric",
    "engine_volume_stays_under_the_cues",
    "scuff_needs_speed_and_lock",
    "no_beep_unless_reversing",
    "beep_lands_with_the_gear",
    "wall_bump_scales_with_the_impact",
    "jackknife_has_its_own_sound",
    "park_chimes_then_counts_stars_upward",
    "one_star_is_one_blip",
    "mute_silences_the_master",
} }

local DT = 1 / 120

-- Records what the mixer was asked to do. A device that returns nil would let a
-- wiring mistake pass silently, so every call is kept.
local function fake_device()
    local d = { plays = {}, loops = {}, master_v = 1 }
    function d.master(v) d.master_v = v end
    function d.play(name, opts)
        d.plays[#d.plays + 1] = { name = name, volume = opts and opts.volume or 1, pitch = opts and opts.pitch or 1 }
    end
    function d.loop(name)
        local h = { name = name, volume = 0, pitch = 1 }
        function h.set(vol, pitch) h.volume, h.pitch = vol, pitch end
        function h.stop() h.stopped = true end
        d.loops[name] = h
        return h
    end
    return d
end

local function count(plays, name)
    local n = 0
    for _, p in ipairs(plays) do if p.name == name then n = n + 1 end end
    return n
end

local function names(plays)
    local out = {}
    for _, p in ipairs(plays) do out[#out + 1] = p.name .. "@" .. string.format("%.2f", p.pitch) end
    return table.concat(out, " ")
end

local function reversing_session()
    local s = session.new(fixtures.field())
    for _ = 1, 240 do session.update(s, { steer = 0, throttle = 0, brake = 1 }, DT) end
    session.drain(s)
    return s
end

-- Reverse tops out at 1.8 m/s and forward at 11. One linear map over |v| puts
-- the whole manoeuvre -- the part the game is about -- in a 6% band of pitch,
-- so the engine sounds stuck while you park and screams on a straight.
function M.pitch_keeps_the_manoeuvre_audible()
    local at_rest = sfx.pitch(0)
    local at_reverse_cap = sfx.pitch(-rig.TUNE.vrev)
    H.expect(at_reverse_cap - at_rest > 0.35,
        string.format("reversing must move the pitch, got %.2f -> %.2f", at_rest, at_reverse_cap))
    H.expect(sfx.pitch(rig.TUNE.vmax) > at_reverse_cap + 0.5,
        "full forward must still be clearly above the reverse cap")
end

function M.pitch_is_monotone_and_symmetric()
    local prev = -math.huge
    for i = 0, 60 do
        local v = rig.TUNE.vmax * i / 60
        local p = sfx.pitch(v)
        H.expect(p > prev, "pitch must rise with speed at v=" .. string.format("%.2f", v))
        prev = p
    end
    for _, v in ipairs({ 0.4, 1.0, 1.8, 6 }) do
        H.near(sfx.pitch(v), sfx.pitch(-v), 1e-9, "reverse and forward of the same speed match")
    end
    H.near(sfx.pitch(0), 0.85, 0.10, "idle sits near the bottom of the range")
end

function M.engine_volume_stays_under_the_cues()
    H.expect(sfx.drive_volume(0) <= 0.12, "idle must be quiet")
    H.expect(sfx.drive_volume(rig.TUNE.vmax) <= 0.30, "and full speed must not drown the cues")
    H.expect(sfx.drive_volume(8) > sfx.drive_volume(2), "louder when moving")
end

function M.scuff_needs_speed_and_lock()
    H.near(sfx.scuff_volume(0, 1.0), 0, 1e-9, "standing at full lock scrubs nothing")
    H.near(sfx.scuff_volume(6, 0), 0, 1e-9, "straight ahead scrubs nothing")
    H.near(sfx.scuff_volume(0.5, 1.0), 0, 1e-9, "too slow to scrub")
    H.expect(sfx.scuff_volume(6, 1.0) > 0.05, "fast and locked must scrub")
    H.expect(sfx.scuff_volume(6, 0.8) < sfx.scuff_volume(6, 1.0), "more lock is more scuff")
end

function M.no_beep_unless_reversing()
    local d = fake_device()
    local x = sfx.new(d)
    local s = session.new(fixtures.field())
    local forward = { steer = 0, throttle = 1 }
    for _ = 1, 240 do
        session.update(s, forward, DT)
        sfx.update(x, s, true, DT)
    end
    session.drain(s)
    H.expect(session.gear(s) == "D", "fixture: should be driving forward")
    H.expect(count(d.plays, "reverse_beep") == 0, "the beeper belongs to reverse: " .. names(d.plays))
end

function M.beep_lands_with_the_gear()
    local d = fake_device()
    local x = sfx.new(d)
    local s = session.new(fixtures.field())
    local backward = { steer = 0, throttle = 0, brake = 1 }

    -- engage reverse: the clunk is the cue, and the beep follows it at once
    while session.gear(s) ~= "R" do
        session.update(s, backward, DT)
        sfx.cues(x, session.drain(s))
    end
    H.expect(count(d.plays, "gear_clunk") == 1, "engaging R clunks once: " .. names(d.plays))
    for _ = 1, 3 do
        session.update(s, backward, DT)
        sfx.update(x, s, true, DT)
    end
    H.expect(count(d.plays, "reverse_beep") >= 1, "the first beep must not wait for the cadence")

    -- and it keeps a cadence: about two per second
    local before = count(d.plays, "reverse_beep")
    for _ = 1, 240 do
        session.update(s, backward, DT)
        sfx.update(x, s, true, DT)
    end
    local got = count(d.plays, "reverse_beep") - before
    H.expect(got >= 3 and got <= 5, string.format("2 s of reversing should beep 3-5 times, got %d", got))
end

function M.wall_bump_scales_with_the_impact()
    local d = fake_device()
    local x = sfx.new(d)
    sfx.cues(x, { { kind = "bump", cause = "wall", speed = 0.4 } })
    sfx.cues(x, { { kind = "bump", cause = "wall", speed = 6 } })
    local soft = d.plays[1]
    local hard = d.plays[2]
    H.expect(soft and soft.name == "wall_thud", "a wall bump is a thud")
    H.expect(hard.volume > soft.volume + 0.2,
        string.format("a slam must be louder than a scrape: %.2f vs %.2f", hard.volume, soft.volume))
    H.expect(hard.volume <= 1.0, "and still inside the mix")
end

function M.jackknife_has_its_own_sound()
    local d = fake_device()
    local x = sfx.new(d)
    sfx.cues(x, { { kind = "bump", cause = "jackknife", speed = 2 } })
    H.expect(count(d.plays, "jackknife") == 1, "over-articulation grinds: " .. names(d.plays))
    H.expect(count(d.plays, "wall_thud") == 0, "and is not a wall: they need different fixes")
end

function M.park_chimes_then_counts_stars_upward()
    local d = fake_device()
    local x = sfx.new(d)
    sfx.cues(x, { { kind = "park", stars = 3 } })
    H.expect(count(d.plays, "park_chime") == 1, "parking chimes at once")
    H.expect(count(d.plays, "star_blip") == 0, "the stars follow the chime, not the same moment")

    for _ = 1, 8 do sfx.update(x, nil, true, 0.1) end     -- 0.8 s
    H.expect(count(d.plays, "star_blip") == 3, "three stars, three blips: " .. names(d.plays))
    local pitches = {}
    for _, p in ipairs(d.plays) do
        if p.name == "star_blip" then pitches[#pitches + 1] = p.pitch end
    end
    H.expect(pitches[2] > pitches[1] and pitches[3] > pitches[2],
        "the blips must climb, or three stars sounds like three of one")
end

function M.one_star_is_one_blip()
    local d = fake_device()
    local x = sfx.new(d)
    sfx.cues(x, { { kind = "park", stars = 1 } })
    for _ = 1, 10 do sfx.update(x, nil, true, 0.1) end
    H.expect(count(d.plays, "star_blip") == 1, "one star, one blip: " .. names(d.plays))
end

function M.mute_silences_the_master()
    local d = fake_device()
    local x = sfx.new(d)
    sfx.attach(x)
    H.near(d.master_v, sfx.MASTER, 1e-9, "attaching sets the master")
    sfx.toggle(x)
    H.near(d.master_v, 0, 1e-9, "mute silences the master")
    sfx.toggle(x)
    H.near(d.master_v, sfx.MASTER, 1e-9, "and unmute restores it")
end

return M
