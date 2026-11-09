-- What the game sounds like: which cue, how loud, how high.
--
-- Pure over an injected audio device (play / loop / master), so the mixer's
-- rules -- the pitch curve, the beep cadence, the star tally -- are headless
-- cases. lib/audio_device.lua owns love.audio, which is the one part no test
-- can cross.
--
-- The cues come from lib/session.lua, not from diffing state here: the session
-- is what knows a bump happened, and only once.

local rig = require("lib.rig")
local session = require("lib.session")

local M = {}

M.MASTER = 0.75
M.BEEP_EVERY = 0.55      -- seconds between reverse beeps: brisk, not a lullaby
M.IDLE = 0.10            -- the engine's floor, so the level is never silent
M.STAR_PITCH = { 1.00, 1.26, 1.50 }   -- a rising third, so 3 stars reads as 3

-- Data, not code paths: the device loads exactly these files.
M.FILES = {
    engine_idle = "assets/sfx/engine_idle.wav",
    reverse_beep = "assets/sfx/reverse_beep.wav",
    gear_clunk = "assets/sfx/gear_clunk.wav",
    wall_thud = "assets/sfx/wall_thud.wav",
    jackknife = "assets/sfx/jackknife.wav",
    cone_knock = "assets/sfx/cone_knock.wav",
    tyre_skid = "assets/sfx/tyre_skid.wav",
    park_chime = "assets/sfx/park_chime.wav",
    star_blip = "assets/sfx/star_blip.wav",
    par_tick = "assets/sfx/par_tick.wav",
    ui_tick = "assets/sfx/ui_tick.wav",
    ui_confirm = "assets/sfx/ui_confirm.wav",
}

function M.new(device)
    return {
        device = device,
        mute = false,
        engine = nil,        -- looping handles, created on attach
        scuff = nil,
        beep_t = 0,
        at = 0,              -- the mixer's own clock, for anything deferred
        pending = {},
    }
end

-- Reverse caps at 1.8 m/s and forward at 11. One linear map over |v| spends
-- almost all of its range on a straight the player crosses once, and puts the
-- whole manoeuvre the game is about into a 6% band -- the engine then sounds
-- stuck exactly when the player is listening to it. Two slopes, joined at rest.
function M.pitch(v)
    local a = math.abs(v or 0)
    local vrev, vmax = rig.TUNE.vrev, rig.TUNE.vmax
    if a <= vrev then return 0.85 + (a / vrev) * 0.45 end
    local over = math.min(1, (a - vrev) / (vmax - vrev))
    return 1.30 + over * 0.90
end

function M.drive_volume(v)
    return M.IDLE + 0.14 * math.min(1, math.abs(v or 0) / 6)
end

-- A loose-surface scuff needs speed AND lock; either alone is a rig that is not
-- scrubbing anything, and a scuff at 1 m/s is a lie (the reverse cap is 1.8).
function M.scuff_volume(v, lock)
    local speed = math.min(1, math.max(0, (math.abs(v or 0) - 2.5) / 4))
    local steer = math.min(1, math.max(0, (math.abs(lock or 0) - 0.35) / 0.65))
    return 0.22 * speed * steer
end

local function play(self, name, volume, pitch)
    if self.mute then return end
    self.device.play(name, { volume = volume, pitch = pitch })
end

-- Idempotent. The loops live for the whole session and are silenced by volume
-- rather than stopped, so entering and leaving a level cannot click.
function M.attach(self)
    if not self.engine then self.engine = self.device.loop("engine_idle") end
    if not self.scuff then self.scuff = self.device.loop("tyre_skid") end
    self.device.master(self.mute and 0 or M.MASTER)
    return self
end

function M.toggle(self)
    self.mute = not self.mute
    self.device.master(self.mute and 0 or M.MASTER)
    return self.mute
end

-- Physics events -> sounds. Volume follows the cue's own numbers: an impact is
-- as loud as the speed it happened at, which is why revert() captures it.
function M.cues(self, list)
    for _, c in ipairs(list or {}) do
        if c.kind == "start" then
            play(self, "ui_tick", 0.40, 0.80)            -- the clock is running
        elseif c.kind == "gear" then
            play(self, "gear_clunk", 0.75)
            self.beep_t = M.BEEP_EVERY                   -- clunk, then beep at once
        elseif c.kind == "bump" then
            if c.cause == "jackknife" then
                play(self, "jackknife", 0.90)
            else
                play(self, "wall_thud", 0.30 + 0.65 * math.min(1, (c.speed or 0) / 4))
            end
        elseif c.kind == "cone" then
            play(self, "cone_knock", 0.20 + 0.45 * math.min(1, (c.speed or 0) / 4))
        elseif c.kind == "park" then
            play(self, "park_chime", 0.85)
            -- three tones at once is a chord; a chord does not say "three stars"
            local stars = math.min(3, math.max(0, math.floor(c.stars or 0)))
            for i = 1, stars do
                self.pending[#self.pending + 1] = {
                    at = self.at + 0.30 + (i - 1) * 0.22,
                    name = "star_blip", volume = 0.55, pitch = M.STAR_PITCH[i],
                }
            end
        elseif c.kind == "par" then
            play(self, "par_tick", 0.55)
        end
    end
end

-- One call per frame. `active` is false outside play and while paused, which
-- silences the loops without stopping them.
function M.update(self, s, active, dt)
    dt = dt or 0
    self.at = self.at + dt

    local v, lock = 0, 0
    if active and s and s.rig then
        v = s.rig.v or 0
        lock = (s.rig.steer or 0) / rig.CAR.max_steer
    end
    if self.engine then self.engine.set(active and M.drive_volume(v) or 0, M.pitch(v)) end
    if self.scuff then self.scuff.set(active and M.scuff_volume(v, lock) or 0, 1.0) end

    local reversing = active and s ~= nil and math.abs(v) > 0.05 and session.gear(s) == "R"
    if reversing then
        self.beep_t = self.beep_t + dt
        if self.beep_t >= M.BEEP_EVERY then
            self.beep_t = self.beep_t - M.BEEP_EVERY
            play(self, "reverse_beep", 0.45)
        end
    else
        self.beep_t = M.BEEP_EVERY      -- the first beep lands the moment R engages
    end

    local i = 1
    while i <= #self.pending do
        if self.pending[i].at <= self.at then
            local p = table.remove(self.pending, i)
            play(self, p.name, p.volume, p.pitch)
        else
            i = i + 1
        end
    end
end

return M
