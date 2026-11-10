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
    "asking_what_is_under_the_cursor_does_not_select_it",
    "deselect_clears_the_selection_only",
    "move_and_rotate_touch_only_the_selection",
    "resize_starts_from_the_default_size",
    "things_with_one_size_refuse_to_stretch",
    "a_handle_drag_sets_an_absolute_size",
    "handles_appear_only_where_stretching_means_something",
    "a_corner_drag_pins_the_opposite_corner",
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

function M.asking_what_is_under_the_cursor_does_not_select_it()
    -- A press has to know whether it landed on the selection before it decides
    -- between dragging the prop and panning the map. `pick` cannot answer that:
    -- it answers by selecting, so merely asking would move the selection out
    -- from under the gesture.
    local d = doc.blank("test-hit")
    doc.add(d, "building", 10, 10)
    doc.add(d, "cone", 30, 30)
    d.selection = nil

    local hit = doc.hit(d, 10, 10, 0.2)
    H.expect(hit and hit.list == "walls" and hit.index == 1, "the building is under the cursor")
    H.expect(d.selection == nil, "asking must not select anything")
    H.expect(doc.hit(d, 30, 30, 0.2).list == "cones", "the cone is under the cursor")
    H.expect(doc.hit(d, 55, 35, 0.2) == nil, "empty ground is nothing")
    H.expect(d.selection == nil, "and still nothing is selected")

    -- and the answer is the same selection `pick` would make
    local p = doc.pick(d, 30, 30, 0.2)
    H.expect(p.list == "cones" and p.index == 1, "pick agrees with hit")
end

function M.deselect_clears_the_selection_only()
    local d = doc.blank("test-deselect")
    doc.add(d, "tent", 10, 10)
    local before = doc.snapshot(d)
    H.expect(d.selection ~= nil, "fixture: adding selects the new prop")

    H.expect(doc.deselect(d) == nil, "deselect says there is nothing selected any more")
    H.expect(d.selection == nil, "nothing stays selected")
    H.expect(doc.snapshot(d) == before, "clearing a selection is not an edit")
    H.expect(doc.deselect(d) == nil, "clearing twice is not a crash")
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
    H.expect(math.abs(after.h - before.h) < 1e-9,
        "a hedge is length only -- pulling its width out makes a field: " .. after.h)

    local b = doc.add(d, "building", 10, 10)
    local fb = props.footprint(b)
    doc.resize(d, 2, 1)
    H.expect(math.abs(props.footprint(b).w - (fb.w + 2)) < 1e-9, "a building widens")
    H.expect(math.abs(props.footprint(b).h - (fb.h + 1)) < 1e-9, "and deepens")
end

function M.things_with_one_size_refuse_to_stretch()
    local d = doc.blank("test-noresize")
    for _, kind in ipairs({ "car", "rv", "chair", "cone", "firepit" }) do
        local e = doc.add(d, kind, 20, 20)
        local fp = props.footprint(e)
        H.expect(doc.resize_mode(d) == "none", kind .. " must not be resizable")
        local ok, why = doc.resize(d, 2, 2)
        H.expect(ok == nil, kind .. " refused a nudge: " .. tostring(ok))
        H.expect(tostring(why):find("one size") ~= nil, kind .. ": the reason is stated")
        H.expect(doc.resize_to(d, 9, 9) == nil, kind .. " refused a handle drag")
        if fp.shape == "circle" then
            H.expect(math.abs(props.footprint(e).r - fp.r) < 1e-9, kind .. " kept its radius")
        else
            H.expect(math.abs(props.footprint(e).w - fp.w) < 1e-9, kind .. " kept its width")
        end
    end

    -- the spawn and the bay: one fixed size, one stretchable
    doc.select(d, "spawn")
    H.expect(doc.resize_mode(d) == "none", "the spawn has no size")
    H.expect(doc.resize(d, 1, 1) == nil, "and refuses")
    doc.select(d, "bay")
    H.expect(doc.resize_mode(d) == "free", "the bay is authorable")
end

function M.a_handle_drag_sets_an_absolute_size()
    local d = doc.blank("test-handle")

    -- free: both axes, symmetric about the centre, so the centre does not move
    local tent = doc.add(d, "tent", 30, 20)
    local cx, cy = tent.x, tent.y
    doc.resize_to(d, 9, 7)
    H.expect(math.abs(props.footprint(tent).w - 9) < 1e-9, "width set")
    H.expect(math.abs(props.footprint(tent).h - 7) < 1e-9, "height set")
    H.expect(tent.x == cx and tent.y == cy, "and the thing did not move out from under the cursor")

    -- length only: the short side is untouched whatever the drag says
    local hedge = doc.add(d, "hedge", 10, 10)
    doc.resize_to(d, 12, 3)
    H.expect(math.abs(props.footprint(hedge).w - 12) < 1e-9, "the length follows the drag")
    H.expect(math.abs(props.footprint(hedge).h - 0.7) < 1e-9, "the width does not")

    -- a vertical hedge has its length on the other axis
    local vert = doc.add(d, "hedge", 40, 10)
    doc.resize_to(vert and vert.w and d, 0.7, 0.7)  -- square first
    doc.resize_to(d, 0.7, 20)
    H.expect(math.abs(props.footprint(vert).h - 20) < 1e-9,
        "a hedge that is tall and thin stretches vertically: " .. props.footprint(vert).h)

    -- clamps: nothing becomes zero or negative
    doc.add(d, "pool", 20, 20)
    doc.resize_to(d, -5, 0)
    local fp = props.footprint(d.level.walls[#d.level.walls])
    H.expect(fp.w >= 0.2 and fp.h >= 0.2, "a drag past the centre clamps: " .. fp.w .. " x " .. fp.h)
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

function M.handles_appear_only_where_stretching_means_something()
    local d = doc.blank("handles")

    doc.add(d, "building", 20, 20)
    local corners = doc.resize_handles(d)
    H.expect(#corners == 4, "a building offers four corners: " .. #corners)
    local fp = props.footprint(d.level.walls[1])
    local far = corners[1]
    H.expect(math.abs(math.abs(far.x - 20) - fp.w / 2) < 1e-9, "at the footprint's corner x")
    H.expect(math.abs(math.abs(far.y - 20) - fp.h / 2) < 1e-9, "and its corner y")

    doc.add(d, "hedge", 30, 30)
    local ends = doc.resize_handles(d)
    H.expect(#ends == 2, "a hedge offers two ends: " .. #ends)
    H.expect(ends[1].axis == "x" and ends[2].axis == "x", "along its length")
    H.expect(math.abs(math.abs(ends[1].x - 30) - 3) < 1e-9, "at the ends, not the sides")

    for _, kind in ipairs({ "car", "rv", "chair", "cone", "firepit" }) do
        doc.add(d, kind, 5, 5)
        H.expect(#doc.resize_handles(d) == 0, kind .. " must have no handles")
    end

    doc.select(d, "spawn")
    H.expect(#doc.resize_handles(d) == 0, "and neither does the spawn")

    doc.select(d, "bay")
    H.expect(#doc.resize_handles(d) == 4, "the bay stretches, so it has corners")

    d.selection = nil
    H.expect(#doc.resize_handles(d) == 0, "nothing selected, nothing to grab")

    -- a rotated building's corners follow the rotation
    local rot = doc.add(d, "tent", 40, 20)
    rot.angle = math.pi / 2
    local hs = doc.resize_handles(d)
    local minx, maxx = math.huge, -math.huge
    for _, h in ipairs(hs) do minx = math.min(minx, h.x); maxx = math.max(maxx, h.x) end
    H.expect(math.abs((maxx - minx) - props.footprint(rot).h) < 1e-9,
        "a tent turned 90 degrees is as wide as it is deep now")
end

function M.a_corner_drag_pins_the_opposite_corner()
    -- The reason this exists: filling a gap. The far edge is the edge you
    -- already lined up, so grabbing a corner must grow the prop away from it, not
    -- around the centre (which moves both edges and re-opens the gap).
    local d = doc.blank("test-anchor")

    -- a free kind: grab the +x/+y corner, drag the box to 9 x 7
    local tent = doc.add(d, "tent", 30, 20)
    local corners = doc.resize_handles(d)
    H.expect(#corners == 4, "fixture: four corners")
    local grab = corners[4]
    H.expect(grab.sx == 1 and grab.sy == 1, "fixture: the last corner is +x/+y")

    -- the anchor is the opposite corner of the 3.4 x 3.0 default
    local ax, ay = 30 - 1.7, 20 - 1.5
    H.expect(doc.resize_to_cursor(d, grab, ax + 9, ay + 7, 0.5) ~= nil, "the drag applies")
    H.expect(math.abs(props.footprint(tent).w - 9) < 1e-9, "width follows the cursor: " .. props.footprint(tent).w)
    H.expect(math.abs(props.footprint(tent).h - 7) < 1e-9, "height follows the cursor: " .. props.footprint(tent).h)
    H.expect(math.abs(tent.x - (ax + 4.5)) < 1e-9 and math.abs(tent.y - (ay + 3.5)) < 1e-9,
        string.format("the centre moved with the new size, not the anchor (%.3f, %.3f)", tent.x, tent.y))

    -- the anchor itself: the corner opposite the grab has not moved a millimetre
    local after = doc.resize_handles(d)
    local pinned
    for _, h in ipairs(after) do
        if h.sx == -1 and h.sy == -1 then pinned = h end
    end
    H.expect(pinned and math.abs(pinned.x - ax) < 1e-9 and math.abs(pinned.y - ay) < 1e-9,
        string.format("the opposite corner drifted to (%.3f, %.3f), expected (%.3f, %.3f)",
            pinned and pinned.x or -1, pinned and pinned.y or -1, ax, ay))

    -- length only: the short side is untouched, and the grabbed end is the one
    -- that moves -- pulling a hedge wider still makes a field
    local hedge = doc.add(d, "hedge", 10, 10)      -- 6 x 0.7
    local ends = doc.resize_handles(d)
    H.expect(#ends == 2 and ends[2].sx == 1 and ends[2].sy == 0, "fixture: the right end is +x")
    doc.resize_to_cursor(d, ends[2], 15, 10, 0.5)
    H.expect(math.abs(props.footprint(hedge).w - 8) < 1e-9, "the length follows: " .. props.footprint(hedge).w)
    H.expect(math.abs(props.footprint(hedge).h - 0.7) < 1e-9,
        "the thickness is the kind's own and is never snapped: " .. props.footprint(hedge).h)
    H.expect(math.abs(hedge.x - 11) < 1e-9, "the centre moved half of what the end gained: " .. hedge.x)

    -- a rotated prop: pinning is in the prop's own frame, so the anchor is a
    -- world point and stays one
    local rot = doc.add(d, "building", 40, 20)     -- 7 x 5
    rot.angle = math.pi / 2
    local hs = doc.resize_handles(d)
    local cnr
    for _, h in ipairs(hs) do
        if h.sx == -1 and h.sy == 1 then cnr = h end
    end
    H.expect(cnr ~= nil, "fixture: a rotated prop still has four signed corners")
    -- the anchor is the (+1, -1) corner, which for a 90 degree turn is up-left
    local anc = nil
    for _, h in ipairs(hs) do
        if h.sx == 1 and h.sy == -1 then anc = h end
    end
    local wx = cnr.x + 2      -- any cursor; the anchor must survive it
    local wy = cnr.y - 1
    doc.resize_to_cursor(d, cnr, wx, wy, 0)
    hs = doc.resize_handles(d)
    local still = nil
    for _, h in ipairs(hs) do
        if h.sx == 1 and h.sy == -1 then still = h end
    end
    H.expect(still and math.abs(still.x - anc.x) < 1e-9 and math.abs(still.y - anc.y) < 1e-9,
        string.format("a rotated prop's pinned corner drifted: (%.3f, %.3f) vs (%.3f, %.3f)",
            still and still.x or -1, still and still.y or -1, anc.x, anc.y))

    -- the same rule for the bay, which is chosen by name
    doc.select(d, "bay")
    local bay_hs = doc.resize_handles(d)
    H.expect(#bay_hs == 4, "fixture: the bay has corners")
    local b = d.level.bay
    local bax, bay_ = b.x - b.w / 2, b.y - b.h / 2
    doc.resize_to_cursor(d, bay_hs[4], bax + 12, bay_ + 6, 0.5)
    H.expect(math.abs(b.w - 12) < 1e-9 and math.abs(b.h - 6) < 1e-9, "the bay resizes too")
    H.expect(math.abs((b.x - b.w / 2) - bax) < 1e-9 and math.abs((b.y - b.h / 2) - bay_) < 1e-9,
        "and its far corner is pinned")

    -- a drag past the anchor clamps at the minimum size, still without moving it
    doc.select(d, "bay")
    bax, bay_ = b.x - b.w / 2, b.y - b.h / 2
    doc.resize_to_cursor(d, doc.resize_handles(d)[4], bax - 50, bay_ - 50, 0.5)
    H.expect(b.w >= 0.2 and b.h >= 0.2, "a drag past the anchor clamps: " .. b.w .. " x " .. b.h)
    H.expect(math.abs((b.x - b.w / 2) - bax) < 1e-9 and math.abs((b.y - b.h / 2) - bay_) < 1e-9,
        "and the anchor still has not moved")

    -- nothing selected, or a kind with one size: no drag, no crash
    d.selection = nil
    H.expect(doc.resize_to_cursor(d, { sx = 1, sy = 1 }, 0, 0, 0.5) == nil, "nothing selected")
    doc.add(d, "car", 5, 5)
    H.expect(doc.resize_to_cursor(d, { sx = 1, sy = 1 }, 0, 0, 0.5) == nil, "a car has one size")
end

return M
