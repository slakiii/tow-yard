-- The editor's document, headless: every operation the mouse will call, called
-- with exact metres instead. If these pass, the view can only be wrong about
-- pixels and gestures -- not about what an edit means.

local H = require("tests.helper")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")
local props = require("lib.props")
local doc = require("lib.edit.doc")

local M = { order = {
    "a_document_does_not_mutate_its_level",
    "add_files_each_kind_where_it_belongs",
    "pick_finds_what_is_under_the_cursor",
    "move_and_rotate_touch_only_the_selection",
    "resize_starts_from_the_default_size",
    "remove_deletes_and_clears_the_selection",
    "bay_and_spawn_can_be_set",
    "a_document_survives_a_snapshot",
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

return M
