-- The only place love.audio is touched, the way lib/codec.lua is the only place
-- zlib/base64 is. Everything above it takes a device table (play / loop /
-- master), so lib/sfx.lua's mix decisions stay a headless question.
--
-- A cue that fails to load is reported and then skipped: a missing sound must
-- cost a sound, never the game.

local M = {}

-- A cue that cannot be loaded costs a sound, never the game, so the device is
-- built before anything can play -- and it hands back a table of functions,
-- which is the shape lib/sfx.lua takes.
function M.new(files, opts)
    local self = { sources = {}, live = {}, missing = {}, log = opts and opts.log }
    local loaded = 0
    for name, path in pairs(files) do
        local ok, src = pcall(love.audio.newSource, path, "static")
        if ok and src then
            self.sources[name] = src
            loaded = loaded + 1
        else
            self.missing[#self.missing + 1] = path
        end
    end
    -- Counted, not read back with `#`: sources is keyed by cue name, and `#` on
    -- a string-keyed table is 0 -- which reads exactly like "nothing loaded".
    self.loaded = loaded
    table.sort(self.missing)
    for _, path in ipairs(self.missing) do print("audio: could not load " .. path) end
    return M.bind(self)
end

function M.master(self, volume)
    love.audio.setVolume(volume)
end

function M.play(self, name, opts)
    local base = self.sources[name]
    if not base then return false end
    local src = base:clone()
    src:setVolume(opts and opts.volume or 1)
    src:setPitch(opts and opts.pitch or 1)
    src:play()
    if self.log then self.log[#self.log + 1] = name end
    -- A source that nothing references is collected mid-play, so a clone lives
    -- in this list until it finishes. Pruning here, not on a timer, keeps it to
    -- one pass over the cues currently audible.
    for i = #self.live, 1, -1 do
        if not self.live[i]:isPlaying() then table.remove(self.live, i) end
    end
    self.live[#self.live + 1] = src
    return true
end

-- A loop handle: volume and pitch are set every frame, so entering a menu or
-- stopping the rig cannot leave a drone behind.
function M.loop(self, name)
    local base = self.sources[name]
    if not base then
        return { set = function() end, stop = function() end }
    end
    local src = base:clone()
    src:setLooping(true)
    src:setVolume(0)
    src:play()
    self.live[#self.live + 1] = src
    return {
        set = function(volume, pitch)
            src:setVolume(volume or 0)
            if pitch then src:setPitch(pitch) end
        end,
        stop = function() src:stop() end,
    }
end

-- The three methods are bound onto the instance on purpose: lib/sfx.lua takes a
-- device TABLE (the fake in the tests is one), so the seam stays a table of
-- functions instead of a module plus an instance every call has to thread
-- through. A plain data table here fails as "attempt to call field 'loop'",
-- which is the shape of every instance/method mistake in this codebase.
function M.bind(self)
    self.master = function(volume) return M.master(self, volume) end
    self.play = function(name, opts) return M.play(self, name, opts) end
    self.loop = function(name) return M.loop(self, name) end
    return self
end

return M
