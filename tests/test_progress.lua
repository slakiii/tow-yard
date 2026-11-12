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
    "a_ghost_is_stored_and_expires_with_the_geometry",
    "an_imported_run_becomes_the_ghost_to_beat",
    "adopting_a_run_never_replaces_a_better_time",
    "a_damaged_park_cannot_improve_or_claim_a_ghost",
    "a_damaged_park_survives_a_restart",
} }

-- A parked session at a chosen clock reading; the fixture builds it through the
-- game's own park rule, and this wrapper keeps the assertion at the call site.
local function parked(lvl, t)
    local s = fixtures.parked(lvl, t)
    H.expect(s.parked, "fixture: a caravan placed in the bay must park")
    return s
end

local fake_disk = fixtures.fake_disk

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

function M.a_ghost_is_stored_and_expires_with_the_geometry()
    local lvl = levels.get(1)
    local disk = fixtures.fake_disk()
    local p = progress.open(disk)
    progress.record(p, lvl, parked(lvl, 20))

    H.expect(progress.ghost_text(p, lvl) == nil, "no ghost until one is stored")
    H.expect(progress.put_ghost(p, lvl, "TOWYARD RUN 1\nfake\n"), "storing must succeed")

    local name = progress.GHOST_DIR .. levelfmt.content_hash(lvl) .. ".tyrun"
    H.expect(disk.files[name] ~= nil, "the blob is named by the content hash: " .. name)
    H.expect(progress.ghost_text(p, lvl) ~= nil, "and reads back")

    local edited = fixtures.deep_copy(lvl)
    edited.walls[1].h = edited.walls[1].h + 0.01
    H.expect(progress.ghost_text(p, edited) == nil,
             "a ghost recorded on other geometry must not be offered")
end

function M.an_imported_run_becomes_the_ghost_to_beat()
    -- A share bundle carries a level and somebody's park. The ghost LOOKUP is
    -- keyed on a progress entry, so writing only the blob means the ghost is
    -- stored and never shown -- which is what an import used to do.
    local lvl = levels.get(1)
    local disk = fixtures.fake_disk()
    local p = progress.open(disk)
    local s = parked(lvl, 21.5)

    H.expect(progress.ghost_text(p, lvl) == nil, "fixture: no ghost before the import")
    local entry = progress.adopt(p, lvl, s.final)
    H.expect(entry ~= nil, "adopt returns the entry it created")
    H.expect(math.abs(entry.best - s.final.time) < 1e-9,
        "the sender's park is the time to beat: " .. tostring(entry.best))
    H.expect(entry.ghost == true, "and the entry claims the ghost, or ghost_text never looks")

    H.expect(progress.put_ghost(p, lvl, "TOWYARD RUN 1\nfake\n"), "the blob stores")
    H.expect(progress.ghost_text(p, lvl) ~= nil, "and the ghost is now offered")

    H.expect(progress.save(p), "the entry is persisted")
    local back = progress.open(disk)
    H.expect(back.entries[lvl.id] ~= nil, "it survives a restart")
    H.expect(back.entries[lvl.id].ghost == true, "with its ghost flag")
    H.expect(math.abs(progress.mark(back, lvl).best - s.final.time) < 1e-9, "and its time")

    H.expect(progress.adopt(p, lvl, nil) == nil, "adopting nothing is refused")
end

function M.adopting_a_run_never_replaces_a_better_time()
    local lvl = levels.get(1)
    local p = progress.open(fake_disk())
    progress.record(p, lvl, parked(lvl, 12))
    H.expect(math.abs(progress.mark(p, lvl).best - 12) < 1e-9, "fixture: 12 s is the best")

    progress.adopt(p, lvl, parked(lvl, 30).final)
    H.expect(math.abs(progress.mark(p, lvl).best - 12) < 1e-9,
        "a slower imported run must not replace it: " .. tostring(progress.mark(p, lvl).best))
    H.expect(progress.mark(p, lvl).ghost == true, "but the ghost claim stays")
end

-- A parked session whose rig has really hit something: a wall in front of the
-- spawn, a crash, then a normal park in the bay. Going through the sim (rather
-- than setting `damaged = true` by hand) is what keeps the test honest.
local function damaged_park(lvl, t)
    local blocked = fixtures.deep_copy(lvl)
    blocked.walls[#blocked.walls + 1] = {
        x = blocked.spawn.x + 8, y = blocked.spawn.y, w = 2, h = 10, kind = "hedge" }
    local s = session.new(blocked)
    local drive = { steer = 0, throttle = 1, brake = 0, handbrake = false }
    for _ = 1, 480 do session.update(s, drive, 1 / 120) end
    H.expect(s.damaged, "fixture: the wall contact must damage the rig")
    session.place_caravan(s, blocked.bay.x, blocked.bay.y, blocked.bay.angle)
    s.t = t or 0
    local hold = { steer = 0, throttle = 0, brake = 0, handbrake = true }
    for _ = 1, 60 do session.update(s, hold, 1 / 120) end
    H.expect(s.parked, "fixture: a damaged rig must still park")
    return s, blocked
end

function M.a_damaged_park_cannot_improve_or_claim_a_ghost()
    -- The park happened, so the level counts as completed; nothing earned on a
    -- damaged body stands, and the ghost it would have stored is not this run.
    local disk = fake_disk()
    local p = progress.open(disk)
    local s, used = damaged_park(levels.get(1), 9)

    local entry, improved = progress.record(p, used, s)
    H.expect(improved == false, "a damaged park cannot set a best")
    H.expect(entry.best == nil, "so there is no time: " .. tostring(entry.best))
    H.expect(entry.stars == 0, "no stars")
    H.expect(entry.ghost == false, "and it does not claim a ghost")
    H.expect(progress.mark(p, used).completed == true, "but the level counts as completed")

    -- a clean park on the same level afterwards owns the record
    local clean = parked(used, 21.5)
    local e2, ok = progress.record(p, used, clean)
    H.expect(ok == true, "a clean park improves")
    H.expect(math.abs(e2.best - clean.final.time) < 1e-9, "and takes the time: " .. tostring(e2.best))
    H.expect(e2.ghost == true, "with a ghost")
end

-- The gap the existing damaged-park test left open: it checked the store's
-- in-memory behaviour and never a save/load round trip.
--
-- serialise() writes "no time" as 0.00, and parse_line() rejected any best <= 0
-- -- so a damaged park was written and then thrown away on the next load, with
-- a "skipped a line" warning as the only trace. The player did park; the level
-- must still read as completed with nothing to show for it.
function M.a_damaged_park_survives_a_restart()
    local disk = fake_disk()
    local p = progress.open(disk)
    local s, used = damaged_park(levels.get(1), 9)

    progress.record(p, used, s)
    H.expect(progress.save(p) == true, "the park is written")

    local back = progress.open(disk)
    H.expect(#back.warnings == 0,
        "a damaged park must parse, not be skipped: " .. table.concat(back.warnings, "; "))

    local m = progress.mark(back, used)
    H.expect(m.completed == true, "a damaged park survives a restart")
    H.expect(m.best == nil, "with no time: " .. tostring(m.best))
    H.expect(m.stars == 0, "no stars: " .. tostring(m.stars))
    H.expect(m.ghost == false, "and no ghost")

    -- and the sentinel did not turn into a real time: a later clean park owns it
    local clean = parked(used, 21.5)
    local e, ok = progress.record(back, used, clean)
    H.expect(ok == true, "a clean park afterwards is an improvement")
    H.expect(math.abs(e.best - clean.final.time) < 1e-9,
        "and takes the time rather than losing to a phantom 0: " .. tostring(e.best))
end

return M
