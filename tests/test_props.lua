-- The scenery vocabulary. A level's walls and cones stay collision shapes; the
-- `kind` says what they are, and lib/props.lua is the only place that says so.
-- These tests pin the vocabulary, not the artwork: whether a clubhouse reads as
-- a clubhouse is settled by a screenshot, not by an assertion.

local H = require("tests.helper")
local props = require("lib.props")

local M = { order = {
    "vocabulary_is_well_formed",
    "solid_kinds_are_boxes_knockable_are_circles",
    "linear_kinds_are_solid_scenery",
    "scenery_recedes_and_hazards_stay_loud",
    "footprint_uses_defaults_and_overrides",
    "check_accepts_a_typed_level",
    "check_rejects_an_untyped_prop",
    "check_rejects_an_unknown_kind",
    "check_rejects_a_kind_on_the_wrong_list",
    "check_rejects_a_bad_size",
    "check_rejects_an_unknown_surface_kind",
    "every_kind_has_a_renderer",
    "the_campsite_furniture_has_the_right_contact_path",
    "the_palette_names_real_kinds",
} }

local function level_with(walls, cones, surfaces)
    return {
        name = "props test level",
        walls = walls or {},
        cones = cones or {},
        surfaces = surfaces or {},
    }
end

local function colour_ok(c)
    if type(c) ~= "table" or #c ~= 3 then return false end
    for i = 1, 3 do
        if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end

function M.vocabulary_is_well_formed()
    local solids, knockables = 0, 0
    local names = {}
    for kind, def in pairs(props.KINDS) do
        H.expect(not names[kind], "duplicate kind " .. tostring(kind))
        names[kind] = true
        H.expect(kind:match("^[a-z][a-z0-9_]*$"), "kind name not snake_case: " .. kind)
        H.expect(def.class == "solid" or def.class == "knockable",
                 kind .. ": class must be solid or knockable, got " .. tostring(def.class))
        if def.class == "solid" then solids = solids + 1 else knockables = knockables + 1 end
        H.expect(type(def.label) == "string" and #def.label > 0, kind .. ": needs a display label")
        H.expect(colour_ok(def.colour), kind .. ": colour must be three channels in [0,1]")
    end
    H.expect(solids >= 5, "at least five solid kinds, got " .. solids)
    H.expect(knockables >= 2, "at least two knockable kinds, got " .. knockables)

    local surfaces = 0
    for kind, def in pairs(props.SURFACES) do
        surfaces = surfaces + 1
        H.expect(kind:match("^[a-z][a-z0-9_]*$"), "surface kind not snake_case: " .. kind)
        H.expect(colour_ok(def.colour), kind .. ": surface colour must be three channels in [0,1]")
        H.expect(type(def.label) == "string" and #def.label > 0, kind .. ": surface needs a label")
    end
    H.expect(surfaces >= 3, "at least three surface kinds, got " .. surfaces)
end

function M.solid_kinds_are_boxes_knockable_are_circles()
    -- The physics has exactly two contact paths: a box that reverts the step
    -- and a circle that is knocked and charged one bump. A prop that is neither
    -- would need a third contact path, which is a physics feature, not a label.
    for kind, def in pairs(props.KINDS) do
        if def.class == "solid" then
            H.expect(def.shape == "box", kind .. ": solid kinds must be boxes (the wall path)")
            H.expect(type(def.w) == "number" and def.w > 0, kind .. ": box needs a default w")
            H.expect(type(def.h) == "number" and def.h > 0, kind .. ": box needs a default h")
        else
            H.expect(def.shape == "circle", kind .. ": knockable kinds must be circles (the cone path)")
            H.expect(type(def.r) == "number" and def.r > 0, kind .. ": circle needs a default r")
        end
    end
end

function M.linear_kinds_are_solid_scenery()
    -- A hedge (or a fence) is one long run of scenery, not an object: two of
    -- them meeting at a corner is a T-junction, not a bug. Everything else is
    -- discrete and must never intersect anything -- see
    -- tests/test_levels.lua:discrete_props_do_not_intersect.
    local linear = 0
    for kind, def in pairs(props.KINDS) do
        if def.linear then
            linear = linear + 1
            H.expect(def.class == "solid", kind .. ": linear scenery is always solid")
            H.expect(def.shape == "box", kind .. ": linear scenery is drawn as a box run")
        end
    end
    H.expect(linear >= 1, "the vocabulary needs a linear kind (a hedge, a fence)")
end

function M.scenery_recedes_and_hazards_stay_loud()
    -- The player's red car, cream caravan and the green bay must stay the
    -- loudest things on the ground, or the manoeuvre stops reading at a glance.
    local loud = 0
    for kind, def in pairs(props.KINDS) do
        local r, g, b = def.colour[1], def.colour[2], def.colour[3]
        local hi = math.max(r, g, b)
        local lo = math.min(r, g, b)
        if def.loud then
            loud = loud + 1
            H.expect(hi >= 0.85, kind .. ": a loud kind must be saturated enough to find at 15 px/m")
        else
            H.expect(hi <= 0.62, kind .. ": scenery channel " .. kind .. " is too bright to recede")
            H.expect(hi - lo <= 0.20, kind .. ": scenery colour " .. kind .. " is too gaudy to recede")
        end
    end
    H.expect(loud >= 1, "the vocabulary needs at least one loud hazard")
end

function M.footprint_uses_defaults_and_overrides()
    H.expect(props.get("rv") ~= nil, "props.get finds a known kind")
    H.expect(props.get("castle") == nil, "props.get returns nil for an unknown kind")

    local rv = props.footprint({ x = 3, y = 4, kind = "rv" })
    H.expect(rv ~= nil, "footprint of a known kind")
    H.expect(rv.class == "solid" and rv.shape == "box", "footprint carries class and shape")
    H.expect(rv.w == props.KINDS.rv.w, "footprint falls back to the default width")
    H.expect(rv.h == props.KINDS.rv.h, "footprint falls back to the default height")
    H.expect(rv.colour == props.KINDS.rv.colour, "footprint carries the palette")

    local wide = props.footprint({ kind = "rv", w = 9.5 })
    H.expect(wide.w == 9.5, "an explicit width overrides the default")
    H.expect(wide.h == props.KINDS.rv.h, "the untouched dimension keeps its default")

    local fire = props.footprint({ kind = "firepit" })
    H.expect(fire.shape == "circle" and fire.r == props.KINDS.firepit.r, "circle footprint uses r")
    H.expect(props.footprint({ kind = "castle" }) == nil, "unknown kind has no footprint")
    H.expect(props.footprint(nil) == nil, "nil entry has no footprint")
end

function M.check_accepts_a_typed_level()
    local lvl = level_with(
        { { x = 10, y = 10, kind = "building" },
          { x = 20, y = 10, kind = "hedge", w = 12, h = 0.7 } },
        { { x = 15, y = 15, kind = "firepit" } },
        { { x = 20, y = 20, w = 30, h = 20, kind = "gravel" } })
    local errs = props.check(lvl)
    H.expect(type(errs) == "table", "check returns a list")
    H.expect(#errs == 0, "a well-typed level has no errors, got: " .. tostring(errs[1]))
end

function M.check_rejects_an_untyped_prop()
    local errs = props.check(level_with({ { x = 10, y = 10, w = 4, h = 4 } }))
    H.expect(#errs == 1, "an untyped wall is one error, got " .. #errs)
    H.expect(errs[1]:find("wall 1"), "the error names the entry: " .. errs[1])
    H.expect(errs[1]:find("kind"), "the error asks for a kind: " .. errs[1])

    local cone_errs = props.check(level_with({}, { { x = 1, y = 1, r = 0.4 } }))
    H.expect(#cone_errs == 1 and cone_errs[1]:find("cone 1"), "an untyped cone is one error")
end

function M.check_rejects_an_unknown_kind()
    local errs = props.check(level_with({ { x = 1, y = 1, kind = "castle" } }))
    H.expect(#errs == 1, "unknown wall kind is one error")
    H.expect(errs[1]:find("castle"), "the error names the bad kind: " .. errs[1])

    local cone_errs = props.check(level_with({}, { { x = 1, y = 1, kind = "castle" } }))
    H.expect(#cone_errs == 1 and cone_errs[1]:find("cone"), "unknown cone kind is one error")
end

function M.check_rejects_a_kind_on_the_wrong_list()
    local box_on_cones = props.check(level_with({}, { { x = 1, y = 1, kind = "rv" } }))
    H.expect(#box_on_cones == 1, "a box kind on the cone list is an error")
    H.expect(box_on_cones[1]:find("rv"), "the error names the kind: " .. box_on_cones[1])

    local circle_on_walls = props.check(level_with({ { x = 1, y = 1, kind = "firepit" } }))
    H.expect(#circle_on_walls == 1, "a circle kind on the wall list is an error")
    H.expect(circle_on_walls[1]:find("firepit"), "the error names the kind")
end

function M.check_rejects_a_bad_size()
    H.expect(#props.check(level_with({ { x = 0, y = 0, kind = "building", w = 0 } })) == 1,
             "a zero width is an error")
    H.expect(#props.check(level_with({ { x = 0, y = 0, kind = "building", h = -2 } })) == 1,
             "a negative height is an error")
    H.expect(#props.check(level_with({ { x = 0, y = 0, kind = "hedge", w = "wide" } })) == 1,
             "a non-numeric width is an error")
    H.expect(#props.check(level_with({}, { { x = 0, y = 0, kind = "chair", r = 0 } })) == 1,
             "a zero radius is an error")
end

function M.check_rejects_an_unknown_surface_kind()
    local errs = props.check(level_with({}, {}, { { x = 0, y = 0, w = 10, h = 10, kind = "lava" } }))
    H.expect(#errs == 1, "unknown surface kind is one error")
    H.expect(errs[1]:find("lava"), "the error names the bad surface kind: " .. errs[1])

    local untyped = props.check(level_with({}, {}, { { x = 0, y = 0, w = 10, h = 10 } }))
    H.expect(#untyped == 1 and untyped[1]:find("kind"), "an untyped surface is an error")
end

function M.every_kind_has_a_renderer()
    -- draw.lua's module body is pure (love is only touched inside its
    -- functions), so the art table is checkable headless. A kind with no art
    -- still renders as a plain footprint -- a silent degrade whose symptom is
    -- "the campsite looks like grey boxes", which is exactly what this catches
    -- before a playtest has to.
    local draw = require("lib.draw")
    local seen = 0
    for kind in pairs(props.KINDS) do
        seen = seen + 1
        H.expect(draw.ART[kind] ~= nil, "no art for kind " .. kind)
    end
    H.expect(seen >= 8, "the vocabulary shrank: only " .. seen .. " kinds")
end

function M.the_campsite_furniture_has_the_right_contact_path()
    -- A picnic table is something that stops you; a beach umbrella is something
    -- you knock over. Both have one real size, so neither grows resize handles:
    -- stretching a table is distorting, not authoring.
    local table_def = props.get("table")
    H.expect(table_def ~= nil, "there must be a table kind")
    H.expect(table_def.class == "solid", "a table stops the rig (the wall path)")
    H.expect(props.resize_mode("table") == "none", "a table has one size")

    local umbrella = props.get("umbrella")
    H.expect(umbrella ~= nil, "there must be an umbrella kind")
    H.expect(umbrella.class == "knockable", "an umbrella is knocked over (the cone path)")
    H.expect(umbrella.shape == "circle" and umbrella.r >= 1.0,
        "the canopy, not the pole, is the circle the rig is hit by: " .. tostring(umbrella.r))
    H.expect(props.resize_mode("umbrella") == "none", "an umbrella has one size")
end

function M.the_palette_names_real_kinds()
    -- the rail's order lives in the vocabulary, so a typo there is a tile that
    -- places nothing rather than a missing tile -- both silent, both cheap to
    -- catch here
    for group, names in pairs(props.PALETTE) do
        H.expect(#names > 0, "palette group " .. group .. " is empty")
        for _, kind in ipairs(names) do
            H.expect(props.KINDS[kind] or props.SURFACES[kind],
                     "the palette names a kind the vocabulary does not have: " .. kind)
        end
    end
    for kind in pairs(props.UNPLACEABLE) do
        H.expect(props.KINDS[kind] or props.SURFACES[kind],
                 "unplaceable names a kind the vocabulary does not have: " .. kind)
    end
end

return M
