-- The editor's document, headless: every operation the mouse will call, called
-- with exact metres instead. If these pass, the view can only be wrong about
-- pixels and gestures -- not about what an edit means.

local H = require("tests.helper")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")
local props = require("lib.props")
local doc = require("lib.edit.doc")
local levelcheck = require("lib.levelcheck")
local fixtures = require("tests.fixtures")

local M = { order = {
    "a_document_does_not_mutate_its_level",
    "add_files_each_kind_where_it_belongs",
    "pick_finds_what_is_under_the_cursor",
    "move_and_rotate_touch_only_the_selection",
    "resize_starts_from_the_default_size",
    "remove_deletes_and_clears_the_selection",
    "bay_and_spawn_can_be_set",
    "a_document_survives_a_snapshot",
    "a_new_level_gets_an_id_nothing_answers_to",
    "a_blank_level_round_trips_through_the_custom_store",
    "the_bay_and_the_spawn_can_be_picked",
    "the_bay_and_the_spawn_can_be_moved_and_turned",
    "paint_never_hides_the_goal",
    "an_autosave_is_only_worth_restoring_when_it_differs",
    "everything_added_here_can_be_written_and_read_back",
} }

function M.a_document_does_not_mutate_its_level()
    local lvl = levels.get(1)
    local walls, cones = #lvl.walls, #lvl.cones
    local d = doc.new(lvl)
    doc.add(d, "hedge", 30, 20)
    doc.add(d, "cone", 10, 10)
    H.expect(#lvl.walls == walls and #lvl.cones == cones, "the shipped level must not change")
    H.expect(#doc.list(d, "walls") == walls + 1, "the document changed instead")
    H.expect(doc.level(d).id == "straight-back", "and it is still that level")
end

function M.add_files_each_kind_where_it_belongs()
    local d = doc.blank("test-add")
    doc.add(d, "hedge", 30, 20)
    H.expect(#d.level.walls == 1 and d.selection.list == "walls", "a hedge is a wall")
    doc.add(d, "cone", 10, 10)
    H.expect(#d.level.cones == 1 and d.selection.list == "cones", "a cone is a cone")
    doc.add(d, "gravel", 30, 20)
    H.expect(#d.level.surfaces == 1 and d.selection.list == "surfaces", "paint is a surface")

    local entry = doc.add(d, "unicorn", 0, 0)
    H.expect(entry == nil, "an unknown kind is refused, not invented")
end

function M.pick_finds_what_is_under_the_cursor()
    local d = doc.blank("test-pick")
    doc.add(d, "building", 10, 10)      -- 7 x 5, so it covers (10,10)
    doc.add(d, "cone", 30, 30)          -- r 0.35
    d.selection = nil

    H.expect(doc.pick(d, 10, 10, 0.2).list == "walls", "the building is under the cursor")
    H.expect(doc.pick(d, 30, 30, 0.2).list == "cones", "the cone is under the cursor")
    H.expect(doc.pick(d, 55, 35, 0.2) == nil, "empty ground clears the selection")
    H.expect(d.selection == nil, "and leaves nothing selected")
end

function M.move_and_rotate_touch_only_the_selection()
    local d = doc.blank("test-move")
    local a = doc.add(d, "building", 10, 10)
    doc.add(d, "tent", 40, 30)
    d.selection = { list = "walls", index = 1 }

    doc.move(d, 2.5, -1)
    H.expect(a.x == 12.5 and a.y == 9, "the selected prop moved")
    H.expect(d.level.walls[2].x == 40 and d.level.walls[2].y == 30, "the other one did not")

    doc.rotate(d, 15)
    H.expect(math.abs(math.deg(a.angle) - 15) < 1e-9, "rotate takes degrees and stores radians")

    doc.add(d, "cone", 5, 5)
    d.selection = { list = "cones", index = 1 }
    local ok, why = doc.rotate(d, 10)
    H.expect(ok == nil and tostring(why):find("cone") ~= nil, "a cone has no angle: " .. tostring(why))
end

function M.resize_starts_from_the_default_size()
    local d = doc.blank("test-resize")
    local hedge = doc.add(d, "hedge", 30, 20)      -- no size written: the default
    local before = props.footprint(hedge)
    H.expect(before.w == 6 and before.h == 0.7, "fixture: a hedge defaults to 6 x 0.7")

    doc.resize(d, 4, 0.3)
    local after = props.footprint(hedge)
    H.expect(math.abs(after.w - (before.w + 4)) < 1e-9, "w grows from the default: " .. after.w)
    H.expect(math.abs(after.h - (before.h + 0.3)) < 1e-9, "h grows from the default: " .. after.h)

    local cone = doc.add(d, "cone", 5, 5)
    doc.resize(d, -0.35, 0)
    H.expect(math.abs(props.footprint(cone).r - 0.1) < 1e-9, "a cone clamps at a tenth of a metre")
end

function M.remove_deletes_and_clears_the_selection()
    local d = doc.blank("test-remove")
    doc.add(d, "tent", 10, 10)
    doc.add(d, "rv", 20, 20)
    d.selection = { list = "walls", index = 1 }
    doc.remove(d)
    H.expect(#d.level.walls == 1, "one of two remains")
    H.expect(d.level.walls[1].kind == "rv", "and it is the other one")
    H.expect(d.selection == nil, "nothing stays selected")
    H.expect(doc.remove(d) == nil, "removing with no selection is refusal, not a crash")
end

function M.bay_and_spawn_can_be_set()
    local d = doc.blank("test-spawn")
    doc.set_bay(d, { x = 30, w = 12, angle = math.pi / 2 })
    H.expect(d.level.bay.x == 30 and d.level.bay.w == 12, "bay fields merge")
    H.expect(d.level.bay.y == 20, "and unspecified fields are kept")

    doc.set_spawn(d, { x = 50, y = 12, th = math.rad(90) })
    H.expect(d.level.spawn.x == 50 and math.abs(math.deg(d.level.spawn.th) - 90) < 1e-9, "spawn too")
end

function M.a_document_survives_a_snapshot()
    local d = doc.new(levels.get(1))
    local before = levelfmt.content_hash(doc.level(d))
    local text = doc.snapshot(d)

    doc.add(d, "cone", 20, 20)
    doc.set_bay(d, { x = 25 })
    H.expect(levelfmt.content_hash(doc.level(d)) ~= before, "fixture: the edit must change the level")

    H.expect(doc.restore(d, text) == true, "restore must succeed")
    H.expect(levelfmt.content_hash(doc.level(d)) == before, "and bring the level back exactly")
    H.expect(d.selection == nil, "with nothing selected")
end

function M.a_new_level_gets_an_id_nothing_answers_to()
    H.expect(doc.free_id({}, "untitled") == "untitled", "the preferred id when it is free")
    H.expect(doc.free_id({ "untitled" }, "untitled") == "untitled-2", "then numbered")
    H.expect(doc.free_id({ "untitled", "untitled-2" }, "untitled") == "untitled-3",
        "and it counts past ids that are already numbered")
    H.expect(doc.free_id({ "untitled-2" }, "untitled") == "untitled",
        "a taken suffix does not block the plain id")

    local id = doc.free_id({ "straight-back" }, "untitled")
    H.expect(id ~= "straight-back", "and never a shipped level's id")

    -- the generated id is usable as a document straight away
    local d = doc.blank(id, "Untitled")
    H.expect(doc.level(d).id == id, "a blank document takes that id")
    H.expect(doc.level(d).name == "Untitled", "and the name given to it")
end

function M.a_blank_level_round_trips_through_the_custom_store()
    local disk = fixtures.fake_disk()
    local d = doc.blank(doc.free_id({}, "untitled"), "Untitled")

    H.expect(#levelcheck.errors(doc.level(d)) == 0,
        "a blank site must be legal to save, or the editor starts you in an error")

    local saved = levelfmt.save_custom(disk, doc.level(d))
    H.expect(saved ~= nil, "it saves")

    local list = levelfmt.scan_custom(disk)
    H.expect(#list == 1, "and comes back: " .. #list)
    H.expect(list[1].id == "untitled", "with its id")
    H.expect(list[1].name == "Untitled", "and its name")

    -- and a second new level is a second level, not an overwrite
    local d2 = doc.blank(doc.free_id({ "untitled" }, "untitled"), "Untitled")
    levelfmt.save_custom(disk, doc.level(d2))
    H.expect(#levelfmt.scan_custom(disk) == 2, "two new levels are two files")
end

function M.the_bay_and_the_spawn_can_be_picked()
    local d = doc.blank("pick-special")
    H.expect(doc.pick(d, 22, 20, 0.2).list == "bay", "a click inside the bay selects the bay")
    H.expect(doc.pick(d, 48, 20, 0.2).list == "spawn", "a click on the start selects the spawn")

    -- a prop is always the thing you meant: it is small and it sits on top
    doc.add(d, "building", 22, 20)
    H.expect(doc.pick(d, 22, 20, 0.2).list == "walls", "a building over the bay wins")

    d.selection = nil
    H.expect(doc.pick(d, 55, 35, 0.2) == nil, "empty ground still clears the selection")
end

function M.the_bay_and_the_spawn_can_be_moved_and_turned()
    local d = doc.blank("move-special")
    local walls = #d.level.walls

    doc.select(d, "bay")
    doc.move(d, 3, -2)
    H.expect(d.level.bay.x == 25 and d.level.bay.y == 18, "the bay moved")
    H.expect(#d.level.walls == walls, "and nothing else did")
    H.expect(doc.rotate(d, 90), "the bay turns")
    H.expect(math.abs(math.deg(d.level.bay.angle) - 90) < 1e-9, "stored as radians")

    doc.select(d, "spawn")
    doc.move(d, -4, 1)
    H.expect(d.level.spawn.x == 44 and d.level.spawn.y == 21, "the spawn moved")
    doc.rotate(d, 90)
    H.expect(math.abs(math.deg(d.level.spawn.th) - 90) < 1e-9,
        "the spawn's heading is `th`, the format's name for it -- not `angle`")
    H.expect(d.level.spawn.angle == nil, "and no stray field was written")

    H.expect(doc.resize(d, 1, 1) == nil, "a spawn has no size to nudge")
    H.expect(doc.remove(d) == nil, "and cannot be deleted")
    H.expect(d.level.spawn ~= nil, "so the level still has a start")

    H.expect(doc.select(d, "walls") == nil, "only single records select by name")
end

function M.paint_never_hides_the_goal()
    -- a dressed level: the whole yard painted, which is every real level
    local d = doc.blank("painted")
    doc.add(d, "gravel", 30, 20)          -- 6 x 4 default, so cover the yard
    d.level.surfaces[1].w, d.level.surfaces[1].h = 60, 40

    H.expect(doc.pick(d, 22, 20, 0.2).list == "bay", "the goal is still pickable through paint")
    H.expect(doc.pick(d, 48, 20, 0.2).list == "spawn", "and so is the start")

    local sel = doc.pick(d, 5, 5, 0.2)
    H.expect(sel and sel.list == "surfaces", "but bare paint is still selectable")
end

function M.an_autosave_is_only_worth_restoring_when_it_differs()
    local lvl = levels.get(1)
    local d = doc.new(lvl)

    H.expect(doc.same_level(doc.level(d), lvl), "an untouched document is the level")
    H.expect(doc.same_level(nil, lvl) == false, "and nothing is not the level")

    -- an edit makes it different, so the autosave is worth offering
    doc.add(d, "cone", 20, 20)
    H.expect(doc.same_level(doc.level(d), lvl) == false, "an edited document is not")

    -- the name IS authored content: an unsaved rename is unsaved work, so it must
    -- read as different and be restorable. Only id/series/order are excluded.
    local renamed = doc.new(lvl)
    renamed.level.name = "Angled bay (mine)"
    H.expect(doc.same_level(doc.level(renamed), lvl) == false, "a rename is unsaved work")

    local moved = doc.new(lvl)
    moved.level.id = "some-other-id"
    H.expect(doc.same_level(doc.level(moved), lvl), "the id is identity, not content")
end

function M.everything_added_here_can_be_written_and_read_back()
    -- The document is encoded in the AUTHORED form, so a prop with no explicit
    -- size comes out as "... 0" and the parser refuses the whole level. Adding a
    -- cone and saving was producing an unreadable file.
    local d = doc.blank("added")
    doc.add(d, "hedge", 10, 10)
    doc.add(d, "building", 20, 10)
    doc.add(d, "cone", 30, 10)
    doc.add(d, "gravel", 40, 10)

    local text = doc.snapshot(d)
    local back, err = levelfmt.decode(text)
    H.expect(back ~= nil, "every kind the palette offers must encode: " .. tostring(err))
    H.expect(#back.walls == 2 and #back.cones == 1 and #back.surfaces == 1, "with every prop")
    H.expect(levelfmt.content_hash(levelfmt.resolve(back)) == levelfmt.content_hash(doc.level(d)),
        "and the same level that was on screen")
end

return M
