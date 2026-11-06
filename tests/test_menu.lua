-- The menu is data with a cursor: order, wrapping, confirm, and the marks the
-- progress store hands it. No heading rows exist in the model, so there is no
-- cursor position that cannot be confirmed.

local H = require("tests.helper")
local levels = require("lib.levels")
local menu = require("lib.menu")
local progress = require("lib.progress")
local fixtures = require("tests.fixtures")
local doc = require("lib.edit.doc")

local M = { order = {
    "series_follow_the_data",
    "within_a_series_levels_follow_their_order",
    "moving_wraps_at_both_ends",
    "confirm_returns_the_selected_level",
    "marks_come_from_the_progress_store",
    "an_empty_catalogue_has_no_cursor",
    "tabs_keep_their_own_cursor",
    "an_empty_tab_has_no_cursor",
    "rebuilding_after_a_delete_keeps_the_cursor_sane",
} }

local function ids_of(m)
    local out = {}
    for i, lvl in ipairs(menu.rows(m)) do out[i] = lvl.id end
    return table.concat(out, ",")
end

function M.series_follow_the_data()
    local m = menu.new(levels.ALL, {}, nil)
    H.expect(ids_of(m) ==
        "straight-back,long-way-back,angled-bay,tight-alley,fire-side,round-the-back,clean-line",
        "campaign order: " .. ids_of(m))
end

function M.within_a_series_levels_follow_their_order()
    -- A reversed catalogue reverses the SERIES (first appearance decides it) but
    -- must not reverse the levels inside one: `order` is the tiebreak, so the
    -- two rules are not the same rule.
    local reversed = {}
    for i = #levels.ALL, 1, -1 do reversed[#reversed + 1] = levels.get(i) end
    local m = menu.new(reversed, {}, nil)
    H.expect(ids_of(m) ==
        "round-the-back,clean-line,tight-alley,fire-side,straight-back,long-way-back,angled-bay",
        "series order from the list, level order from `order`: " .. ids_of(m))
end

function M.moving_wraps_at_both_ends()
    local m = menu.new(levels.ALL, {}, nil)
    H.expect(menu.current(m).id == "straight-back", "the cursor starts at the first level")
    menu.move(m, -1)
    H.expect(menu.current(m).id == "clean-line", "up from the first wraps to the last")
    menu.move(m, 1)
    H.expect(menu.current(m).id == "straight-back", "down from the last wraps to the first")
    menu.move(m, 2)
    H.expect(menu.current(m).id == "angled-bay", "and it steps by more than one")
end

function M.confirm_returns_the_selected_level()
    local m = menu.new(levels.ALL, {}, nil)
    menu.move(m, 1)
    H.expect(menu.confirm(m) == levels.get(2), "confirm opens what the cursor is on")
    H.expect(menu.count(m) == 7, "and the menu knows how many levels it has")
end

function M.marks_come_from_the_progress_store()
    local lvl = levels.get(1)
    local p = progress.open(fixtures.fake_disk())
    local s = fixtures.parked(lvl, 20)
    H.expect(s.parked, "fixture: the placed caravan must park")
    progress.record(p, lvl, s)

    local m = menu.new(levels.ALL, {}, p)
    local played = menu.mark(m, lvl)
    H.expect(played.completed == true and played.stars == 3 and played.best == 20,
             "a park shows up on the card")
    H.expect(played.stale == nil, "and is not stale: nothing changed")
    H.expect(menu.mark(m, levels.get(2)).completed == false, "an unplayed level does not")
end

function M.an_empty_catalogue_has_no_cursor()
    local m = menu.new({}, {}, nil)
    H.expect(menu.count(m) == 0, "no levels, no rows")
    H.expect(menu.current(m) == nil, "no cursor")
    H.expect(menu.confirm(m) == nil, "and nothing to open")
    menu.move(m, 1)          -- must not raise on an empty menu
    menu.move(m, -1)
    H.expect(menu.current(m) == nil, "moving an empty menu stays empty")
end

local function a_custom_level(id, name)
    return doc.level(doc.blank(id, name))
end

function M.tabs_keep_their_own_cursor()
    local mine = a_custom_level("my-level", "Mine")
    local m = menu.new(levels.ALL, { mine }, nil)
    H.expect(menu.count(m) == 7, "the campaign tab holds the shipped levels")
    H.expect(menu.current_tab(m) == "campaign", "and is the one you start on")

    menu.move(m, 1)
    menu.move(m, 1)
    local campaign_row = menu.current(m).id

    H.expect(menu.switch_tab(m, "custom"), "the custom tab exists")
    H.expect(menu.count(m) == 1, "with the imported level")
    H.expect(menu.current(m).id == "my-level", "which is the one under the cursor")

    menu.switch_tab(m, "campaign")
    H.expect(menu.current(m).id == campaign_row, "and the campaign cursor did not move")
    H.expect(menu.switch_tab(m, "nope") == false, "a tab that does not exist is refused")
end

function M.an_empty_tab_has_no_cursor()
    local m = menu.new(levels.ALL, {}, nil)
    menu.switch_tab(m, "custom")
    H.expect(menu.count(m) == 0, "no imports, no rows")
    H.expect(menu.current(m) == nil, "and nothing to open")
    menu.move(m, 1)                       -- must not raise
    H.expect(menu.current(m) == nil, "moving an empty tab stays empty")

    H.expect(menu.cycle_tab(m, 1) == true, "cycling wraps")
    H.expect(menu.current_tab(m) == "campaign", "from the custom tab back to the campaign")
    H.expect(menu.current(m) ~= nil, "where there is something to open")
end

function M.rebuilding_after_a_delete_keeps_the_cursor_sane()
    local a = a_custom_level("a", "A")
    local b = a_custom_level("b", "B")
    local m = menu.new(levels.ALL, { a, b }, nil)
    menu.switch_tab(m, "custom")
    menu.move(m, 1)
    H.expect(menu.current(m).id == "b", "fixture: the cursor is on the second row")

    menu.rebuild(m, levels.ALL, { a })
    H.expect(menu.current_tab(m) == "custom", "deleting must not throw you back to the campaign")
    H.expect(menu.current(m).id == "a", "and the cursor falls back to a row that exists")

    menu.rebuild(m, levels.ALL, {})
    H.expect(menu.current(m) == nil, "deleting the last level leaves nothing to open")
    H.expect(menu.count(m) == 0, "and an empty tab")
end

return M
