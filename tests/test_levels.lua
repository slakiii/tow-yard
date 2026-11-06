-- Level data invariants, plus one end-to-end replay that proves the shipped
-- level 1 can actually be parked by driving real input through the session.
--
-- The rules themselves live in lib/levelcheck.lua, because the same question is
-- asked by the editor's save gate and by the importer -- a rule that exists only
-- in a test cannot stop a hand-authored level from shipping. What stays here is
-- the campaign's own policy: every level must be dressed (a bare level would
-- pass the vocabulary check vacuously) and level 1 must still park itself.

local H = require("tests.helper")
local levels = require("lib.levels")
local rig = require("lib.rig")
local session = require("lib.session")
local levelcheck = require("lib.levelcheck")
local fixtures = require("tests.fixtures")

local M = { order = { "every_level_is_well_formed", "every_level_has_typed_scenery",
                      "spawn_is_clear", "bay_apron_is_clear", "bay_inside_bounds",
                      "props_stay_inside_bounds", "discrete_props_do_not_intersect",
                      "paint_stays_inside_bounds", "the_bay_sits_on_a_painted_surface",
                      "levels_have_unique_names", "series_are_contiguous_and_ordered",
                      "catalog_errors_name_a_broken_series",
                      "levelcheck_rejects_a_bad_level",
                      "level_1_is_winnable_by_reversing_straight" } }

local DT = 1 / 120

-- Ask the library; do not re-derive the geometry here or the two drifts.
local function assert_rule_clean(rule)
    for _, lvl in ipairs(levels.ALL) do
        local errs = levelcheck.rules[rule](lvl)
        H.expect(#errs == 0, lvl.name .. ": " .. tostring(errs[1]))
    end
end

function M.every_level_is_well_formed()
    H.expect(#levels.ALL >= 3, "at least three levels")
    assert_rule_clean("structure")
end

function M.every_level_has_typed_scenery()
    for _, lvl in ipairs(levels.ALL) do
        local errs = levelcheck.rules.vocabulary(lvl)
        H.expect(#errs == 0, lvl.name .. ": " .. tostring(errs[1]))
        -- non-emptiness: a level with no props would pass the vocabulary check
        -- vacuously and say nothing about whether the site is dressed
        H.expect(#(lvl.walls or {}) >= 1, lvl.name .. ": needs at least one solid prop")
        H.expect(#(lvl.cones or {}) >= 1, lvl.name .. ": needs at least one knockable prop")
    end
    H.expect(#(levels.get(1).surfaces or {}) >= 2, "level 1 must be painted, not bare ground")
end

function M.spawn_is_clear()
    assert_rule_clean("spawn_clear")
end

function M.bay_apron_is_clear()
    assert_rule_clean("apron_clear")
end

function M.bay_inside_bounds()
    assert_rule_clean("bay_inside_bounds")
end

function M.props_stay_inside_bounds()
    assert_rule_clean("props_inside_bounds")
end

function M.discrete_props_do_not_intersect()
    assert_rule_clean("props_disjoint")
end

function M.paint_stays_inside_bounds()
    assert_rule_clean("paint_inside_bounds")
end

function M.the_bay_sits_on_a_painted_surface()
    assert_rule_clean("bay_on_paint")
end

function M.levels_have_unique_names()
    local errs = levelcheck.catalog_errors(levels.ALL)
    H.expect(#errs == 0, tostring(errs[1]))
end

function M.series_are_contiguous_and_ordered()
    -- Every level belongs to a series, orders inside a series run 1..n, and a
    -- series appears in one unbroken run: the menu, Tab and the audit all derive
    -- their order from this list, so a split series makes them disagree.
    local errs = levelcheck.catalog_errors(levels.ALL)
    H.expect(#errs == 0, tostring(errs[1]))

    local seen = {}
    for _, lvl in ipairs(levels.ALL) do
        H.expect(type(lvl.series) == "string" and lvl.series ~= "", lvl.name .. " needs a series")
        H.expect(type(lvl.order) == "number" and lvl.order >= 1, lvl.name .. " needs an order")
        seen[lvl.series] = true
    end
    H.expect(seen.training and seen.basics and seen.tricky, "the three campaign series exist")
end

function M.catalog_errors_name_a_broken_series()
    local broken = fixtures.deep_copy(levels.ALL)

    -- a level without a series
    local no_series = fixtures.deep_copy(levels.ALL)
    no_series[1].series = nil
    H.expect(#levelcheck.catalog_errors(no_series) > 0, "a level with no series is an error")

    -- two levels claiming the same slot
    local twice = fixtures.deep_copy(levels.ALL)
    twice[2].order = twice[1].order
    local errs = levelcheck.catalog_errors(twice)
    H.expect(#errs > 0 and tostring(errs[1]):find("order") ~= nil,
             "a duplicate order must be named, got: " .. tostring(errs[1]))

    -- a series that resumes after another one (level 1 moved to the end)
    local split = fixtures.deep_copy(levels.ALL)
    local first = table.remove(split, 1)
    split[#split + 1] = first
    errs = levelcheck.catalog_errors(split)
    H.expect(#errs > 0 and tostring(errs[1]):find("contiguous") ~= nil,
             "a split series must be named, got: " .. tostring(errs[1]))

    -- and the unmodified copy is still clean, so the fixture itself is honest
    H.expect(#levelcheck.catalog_errors(broken) == 0, "the copy was already broken before mutating")
end

function M.levelcheck_rejects_a_bad_level()
    -- A car parked on the spawn must be refused by the same code the editor's
    -- save gate and the importer call, and the reason must name the culprit.
    local lvl = levels.get(1)
    local broken = {
        id = "broken", name = "broken", bounds = lvl.bounds, spawn = lvl.spawn, bay = lvl.bay,
        walls = { { x = lvl.spawn.x, y = lvl.spawn.y, w = 4, h = 4, kind = "car" } },
        cones = {}, surfaces = {}, par = 10, apron = 0,
    }
    local errs = levelcheck.errors(broken)
    H.expect(#errs > 0, "a prop on the spawn must be an error")
    H.expect(tostring(errs[1]):find("spawn"), "the reason must name the spawn, got: " .. tostring(errs[1]))
end

function M.level_1_is_winnable_by_reversing_straight()
    -- Level 1 is deliberately dead straight: hold the brake, let the dwell
    -- engage reverse, and the rig should park itself. If this fails, either the
    -- physics, the gear gate, the collision shapes or the bay test is broken.
    local s = session.new(levels.get(1))
    local reverse = { steer = 0, throttle = 0, brake = 1, handbrake = false }
    local stop = { steer = 0, throttle = 0, brake = 0, handbrake = true }
    -- rig.x that puts the caravan's midpoint on the bay centre
    local stop_x = levels.get(1).bay.x - (rig.CARAVAN.coupling - rig.CARAVAN.length / 2)
    local t = 0
    while s.rig.x > stop_x and t < 60 do
        session.update(s, reverse, DT)
        t = t + DT
    end
    while not s.parked and t < 60 do
        session.update(s, stop, DT)
        t = t + DT
    end
    H.expect(s.parked, "level 1 was not parked after 60 s of straight reversing")
    H.expect(s.final.bumps == 0, "a straight reverse should not touch anything, bumps=" .. s.final.bumps)
    H.expect(s.final.time <= levels.get(1).par, "par time should be beatable by a clean straight reverse")
end

return M
