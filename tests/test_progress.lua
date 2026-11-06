-- What a level has earned, and what an edit costs it.
--
-- The store is pure over an injected disk, so a corrupt file, a stale content
-- hash and a faster run are all headless cases. Every parked session here comes
-- from the game's own park rule (place the caravan in the bay, let check_park
-- hold it) rather than from setting `s.parked = true` by hand: a fixture that
-- fakes the state cannot tell you the store reads the real one.

local H = require("tests.helper")
local levels = require("lib.levels")
local session = require("lib.session")
local levelfmt = require("lib.levelfmt")
local fixtures = require("tests.fixtures")
local progress = require("lib.progress")

local M = { order = {
    "fresh_store_is_empty",
    "corrupt_store_reads_as_empty",
    "a_park_is_remembered",
    "best_time_only_improves",
    "edited_level_keeps_completion_loses_time",
} }

local function fake_disk(files)
    local disk = { files = files or {}, writes = 0 }
    function disk.read(name) return disk.files[name] end
    function disk.write(name, data)
        disk.files[name] = data
        disk.writes = disk.writes + 1
    end
    function disk.remove(name) disk.files[name] = nil end
    return disk
end

-- A parked session at a chosen clock reading. `t` is set before the hold so the
-- test can talk about "a 20 second run"; the handbrake keeps the clock still.
local function parked(lvl, t)
    local s = session.new(lvl)
    session.place_caravan(s, lvl.bay.x, lvl.bay.y, lvl.bay.angle)
    s.t = t
    local hold = { steer = 0, throttle = 0, brake = 0, handbrake = true }
    for _ = 1, 60 do session.update(s, hold, 1 / 120) end
    H.expect(s.parked, "fixture: a caravan placed in the bay must park")
    return s
end

function M.fresh_store_is_empty()
    local disk = fake_disk()
    local p = progress.open(disk)
    H.expect(next(p.entries) == nil, "a first launch has no entries")
    H.expect(progress.mark(p, levels.get(1)).completed == false, "nothing is completed yet")
    H.expect(progress.save(p) == false, "an untouched store writes nothing")
    H.expect(disk.writes == 0, "not even a header")
end

function M.corrupt_store_reads_as_empty()
    local disk = fake_disk({ ["progress.txt"] = "\0\0garbage\nand more nonsense\n" })
    local p = progress.open(disk)
    H.expect(next(p.entries) == nil, "garbage reads as an empty store, not a crash")
    H.expect(#p.warnings > 0, "and says so instead of pretending it loaded")

    -- one unreadable line must not cost the player every other best time
    local good = levelfmt.content_hash(levels.get(1))
    local mixed = fake_disk({ ["progress.txt"] =
        progress.HEADER .. progress.VERSION .. "\n"
        .. "level straight-back 3 13.20 1 " .. good .. "\n"
        .. "level broken\n" })
    local q = progress.open(mixed)
    H.expect(q.entries["straight-back"] ~= nil, "a good line survives a bad neighbour")
    H.expect(#q.warnings > 0, "the bad line is reported")
end

function M.a_park_is_remembered()
    local lvl = levels.get(1)
    local disk = fake_disk()
    local p = progress.open(disk)

    local entry, improved = progress.record(p, lvl, parked(lvl, 20))
    H.expect(improved == true, "the first run is necessarily an improvement")
    H.expect(entry.stars == 3, "20 s is inside par 22 with no bumps: three stars")
    H.expect(entry.best == 20, "and the time is recorded")

    H.expect(progress.save(p) == true, "a new best is written")
    local again = progress.mark(progress.open(disk), lvl)
    H.expect(again.completed == true and again.stale == nil, "it survives a restart")
    H.expect(again.best == 20 and again.stars == 3 and again.ghost == true, "with its numbers intact")
end

function M.best_time_only_improves()
    local lvl = levels.get(1)
    local p = progress.open(fake_disk())
    progress.record(p, lvl, parked(lvl, 20))

    local entry, improved = progress.record(p, lvl, parked(lvl, 25))
    H.expect(improved == false, "a slower run is not an improvement")
    H.expect(entry.best == 20, "the best time stands")

    entry, improved = progress.record(p, lvl, parked(lvl, 16))
    H.expect(improved == true and entry.best == 16, "a faster run takes over")

    -- 30 s is outside par, so this run is worth two stars
    entry = progress.record(p, lvl, parked(lvl, 30))
    H.expect(entry.best == 16, "a slower run does not touch the time")
    H.expect(entry.stars == 3, "and a clean run never lowers the stars you already have")
end

function M.edited_level_keeps_completion_loses_time()
    local lvl = levels.get(1)
    local p = progress.open(fake_disk())
    progress.record(p, lvl, parked(lvl, 20))

    local edited = fixtures.deep_copy(lvl)
    edited.walls[1].h = edited.walls[1].h + 0.01

    local mark = progress.mark(p, edited)
    H.expect(mark.completed == true, "you did park this level")
    H.expect(mark.stale == true, "but against geometry that no longer exists")
    H.expect(mark.best == nil and mark.stars == nil and mark.ghost == nil,
             "a time and stars earned on other geometry are not shown")

    -- parking the edited level replaces the entry instead of merging into it
    local entry = progress.record(p, edited, parked(edited, 40))
    H.expect(entry.best == 40, "the new time belongs to the new geometry")
    H.expect(entry.stars == 2, "40 s is outside par")
    H.expect(progress.mark(p, lvl).stale == true, "and the old content's number is gone")
end

return M
