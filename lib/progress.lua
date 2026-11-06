-- What each level has earned: best time, stars, and whether a ghost exists.
--
-- Pure over an injected filesystem (read/write/remove), so a corrupt file, a
-- stale content hash and a better run are all headless cases -- and `main.lua`
-- owns the love.filesystem wiring, which is the one part no test can cross.
--
-- Two rules, and they come straight from the format layer having two keys:
--   * a second run only improves: min time, max stars, and the ghost is kept.
--   * a level whose CONTENT changed keeps only "completed". Its time and stars
--     were earned against geometry that no longer exists, and showing them
--     would be the menu telling a lie that never expires.
--
-- The file is a small index, not a database: ghosts live beside it in
-- ghosts/<content_hash>.tyrun, so one corrupt blob cannot take the whole
-- progress file with it. An edited ghost is simply never looked up again.

local levelfmt = require("lib.levelfmt")
local session = require("lib.session")

local M = {}

M.FILE = "progress.txt"
M.HEADER = "TOWYARD PROGRESS "
M.VERSION = 1

local function tokens(line)
    local t = {}
    for s in line:gmatch("%S+") do t[#t + 1] = s end
    return t
end

local function parse_line(line)
    local t = tokens(line)
    if #t ~= 6 or t[1] ~= "level" then return nil end
    local id = t[2]
    if not id:match("^[a-z0-9][a-z0-9%-]*$") then return nil end
    local stars = tonumber(t[3])
    local best = tonumber(t[4])
    if not (stars and best) then return nil end
    if stars < 0 or stars > 3 or stars ~= math.floor(stars) then return nil end
    if best ~= best or best <= 0 then return nil end
    if not t[6]:match("^%x%x+$") then return nil end
    return { id = id, stars = stars, best = best, ghost = t[5] == "1", content = t[6] }
end

-- Never raises. A file that is not ours is ignored wholesale; a single bad line
-- is skipped and the rest is kept, because losing every best time to one
-- unreadable byte is a worse failure than losing that line.
function M.load(self, raw)
    self.entries, self.warnings = {}, {}
    local first = true
    for raw_line in raw:gmatch("[^\n]+") do
        local line = raw_line:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            if first then
                first = false
                if line ~= M.HEADER .. M.VERSION then
                    self.warnings[#self.warnings + 1] = "not a progress file; starting empty"
                    return self
                end
            else
                local entry = parse_line(line)
                if entry then
                    self.entries[entry.id] = entry
                else
                    self.warnings[#self.warnings + 1] = "skipped a line: " .. line
                end
            end
        end
    end
    return self
end

function M.open(disk)
    local self = { disk = disk, entries = {}, warnings = {}, dirty = false }
    local raw = disk and disk.read(M.FILE)
    if raw then M.load(self, raw) end
    return self
end

local function serialise(self)
    local ids = {}
    for id in pairs(self.entries) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = { M.HEADER .. M.VERSION }
    for _, id in ipairs(ids) do
        local e = self.entries[id]
        out[#out + 1] = string.format("level %s %d %.2f %d %s",
            e.id, e.stars or 0, e.best or 0, e.ghost and 1 or 0, e.content or string.rep("0", 64))
    end
    return table.concat(out, "\n") .. "\n"
end

-- The content hash of a level, memoised on the level table. mark() is called
-- per frame from the menu and a sha256 per level per frame is pure waste; a
-- shipped level is immutable once loaded (the editor hashes its own document).
local function content_of(self, level)
    self.hashes = self.hashes or {}
    local h = self.hashes[level]
    if not h then
        h = levelfmt.content_hash(level)
        self.hashes[level] = h
    end
    return h
end

-- Record a parked attempt. Returns the entry and whether it beat the stored
-- time -- the result card needs that answer to say NEW BEST.
function M.record(self, level, s)
    if not (s and s.parked and s.final) then return nil, false end
    if type(level.id) ~= "string" then return nil, false end

    local content = content_of(self, level)
    local entry = self.entries[level.id]
    if not entry or entry.content ~= content then
        -- new level, or one whose geometry moved under the stored numbers
        entry = { id = level.id, stars = 0, best = nil, ghost = false, content = content }
        self.entries[level.id] = entry
    end

    local improved = (not entry.best) or s.final.time < entry.best
    if improved then entry.best = s.final.time end
    entry.stars = math.max(entry.stars or 0, session.grade(s))
    entry.ghost = true
    self.dirty = true
    return entry, improved
end

-- What the menu shows for a level. Completion is a memory; the time, the stars
-- and the ghost are content-bound.
function M.mark(self, level)
    local entry = type(level.id) == "string" and self.entries[level.id]
    if not entry then return { completed = false } end
    if entry.content ~= content_of(self, level) then
        return { completed = true, stale = true }
    end
    return { completed = true, stars = entry.stars, best = entry.best, ghost = entry.ghost }
end

function M.save(self)
    if not self.disk or not self.dirty then return false end
    self.disk.write(M.FILE, serialise(self))
    self.dirty = false
    return true
end

return M
