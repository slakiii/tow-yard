-- Autosave, headless. The properties that matter: an edit reaches the disk
-- without anybody pressing anything, a drag does not thrash it, and what comes
-- back is the same level.

local H = require("tests.helper")
local fixtures = require("tests.fixtures")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")
local doc = require("lib.edit.doc")
local autosave = require("lib.edit.autosave")

local M = { order = {
    "an_edit_reaches_the_disk_and_comes_back",
    "the_same_text_is_not_rewritten",
    "writes_are_throttled_but_exit_forces_one",
    "an_unchanged_document_is_not_offered_back",
    "a_changed_document_is",
    "clearing_removes_the_file",
    "a_failed_write_is_reported_not_swallowed",
} }

function M.an_edit_reaches_the_disk_and_comes_back()
    local disk = fixtures.fake_disk()
    local d = doc.new(levels.get(1))
    doc.add(d, "cone", 20, 20)

    local state = {}
    H.expect(autosave.save(disk, "straight-back", doc.snapshot(d), state, 100) == true,
        "the first save writes")

    local text = autosave.load(disk, "straight-back")
    H.expect(text ~= nil, "and it can be read back")
    local decoded, why = levelfmt.decode(text)
    H.expect(decoded ~= nil, "as a level the parser accepts: " .. tostring(why)
        .. " | first line: " .. tostring(text:match("^[^\n]*")))

    local back = doc.new(levels.get(1))
    H.expect(doc.restore(back, text), "restoring it works")
    H.expect(levelfmt.content_hash(doc.level(back)) == levelfmt.content_hash(doc.level(d)),
        "and it is the level that was being edited -- cone included")
end

function M.the_same_text_is_not_rewritten()
    local disk = fixtures.fake_disk()
    local state = {}
    local text = doc.snapshot(doc.new(levels.get(1)))

    autosave.save(disk, "x", text, state, 0, true)
    H.expect(autosave.save(disk, "x", text, state, 999, true) == false,
        "identical text is not written twice, even forced")
end

function M.writes_are_throttled_but_exit_forces_one()
    local disk = fixtures.fake_disk()
    local state = {}
    local d = doc.new(levels.get(1))

    doc.add(d, "cone", 1, 1)
    H.expect(autosave.save(disk, "x", doc.snapshot(d), state, 10) == true, "first write")
    doc.add(d, "cone", 2, 2)
    H.expect(autosave.save(disk, "x", doc.snapshot(d), state, 10.5) == false,
        "a drag inside the window does not write on every step")
    H.expect(autosave.save(disk, "x", doc.snapshot(d), state, 12.5) == true,
        "but once the window passes, it does")

    doc.add(d, "cone", 3, 3)
    H.expect(autosave.save(disk, "x", doc.snapshot(d), state, 12.6, true) == true,
        "and exiting forces the last one out")
    local text = autosave.load(disk, "x")
    H.expect(text:find("cone", 1, true) ~= nil, "the last edit is the one on disk")
end

function M.an_unchanged_document_is_not_offered_back()
    local lvl = levels.get(1)
    local disk = fixtures.fake_disk()
    autosave.save(disk, lvl.id, levelfmt.encode(lvl), {}, 0, true)

    local saved = levelfmt.decode(autosave.load(disk, lvl.id))
    H.expect(doc.same_level(saved, lvl),
        "an autosave of the level as it already is must not look like unsaved work")
end

function M.a_changed_document_is()
    local lvl = levels.get(1)
    local disk = fixtures.fake_disk()
    local d = doc.new(lvl)
    doc.add(d, "cone", 20, 20)
    autosave.save(disk, lvl.id, doc.snapshot(d), {}, 0, true)

    local saved = levelfmt.decode(autosave.load(disk, lvl.id))
    H.expect(doc.same_level(saved, lvl) == false, "an edited document is worth restoring")
    H.expect(#saved.cones == #lvl.cones + 1, "and it carries the edit")
end

function M.clearing_removes_the_file()
    local disk = fixtures.fake_disk()
    autosave.save(disk, "gone", "TOWYARD LEVEL 1\n", {}, 0, true)
    H.expect(autosave.load(disk, "gone") ~= nil, "fixture")
    autosave.clear(disk, "gone")
    H.expect(autosave.load(disk, "gone") == nil, "cleared means gone")
    H.expect(autosave.load(nil, "gone") == nil, "and no disk is not a crash")
end

function M.a_failed_write_is_reported_not_swallowed()
    -- love.filesystem.write returns nil + an error when the directory is missing,
    -- and the first version of this ignored that: the editor said "saved" while
    -- nothing was on disk. Losing a level is what that costs.
    local disk = fixtures.fake_disk()
    disk.write = function() return nil, "No such file or directory" end
    local ok, err = autosave.save(disk, "x", "TOWYARD LEVEL 1\n", {}, 0, true)
    H.expect(ok == false, "the failure is returned")
    H.expect(tostring(err):find("No such file") ~= nil, "with the reason: " .. tostring(err))

    -- the fake disk's write returns nothing at all, and that is a success
    local plain = fixtures.fake_disk()
    H.expect(autosave.save(plain, "y", "TOWYARD LEVEL 1\n", {}, 0, true) == true,
        "a write with no error is a success")
end

return M
