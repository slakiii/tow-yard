-- Level data. Everything here is authoring data: a spawn transform, a parking
-- bay, scenery, ground paint and a par time.
--
-- walls: axis-aligned boxes, blocking, each naming a `kind` from lib/props.lua.
-- cones: circles, knocked over on contact and charged as a bump, same rule.
-- surfaces: painted ground only -- no collision, drawn under everything.
-- apron: clearance required around the bay (metres) -- tight levels lower it.
--
-- A level is a space first and a campsite second: the props dress a layout that
-- already demands a plan. Anything you could point at as one object sits clear
-- of the winning line, so the manoeuvre stays the level and the scenery only
-- explains why the place is tight (tests/test_levels.lua enforces both).
--
-- Par on "Fire side", "Round the back" and "Clean line" is provisional: it is a
-- machine line (a headless audit probe that reverses in and parks) times ~1.5,
-- not a playtest. Re-measure it after the first human run and never scale it.

local levelfmt = require("lib.levelfmt")

local M = {}

-- Authored data: a prop says what it is (`kind`) and, only when it differs from
-- the kind's default, how big it is.
--
-- `id` is identity: stable forever, what a best time and a ghost are stored
-- under. `series` + `order` are presentation: which row of the menu the level
-- sits in and where. Neither reaches the content hash, so re-sorting the
-- campaign cannot invalidate a run that was driven against the same geometry.
local RAW = {
    {
        id = "straight-back",
        series = "training",
        order = 1,
        name = "Straight back",
        hint = "Reverse straight back into the bay. The caravan will not stay straight on its own.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 46, y = 20, th = 0 },
        bay = { x = 22, y = 20, w = 9, h = 4, angle = 0, tol = math.rad(6) },
        walls = {
            { x = 29, y = 14, w = 46, h = 0.6, kind = "hedge" },
            { x = 29, y = 26, w = 46, h = 0.6, kind = "hedge" },
            -- the verges: none of this is on the straight-reverse line, it only
            -- says what kind of place the yard is
            { x = 8, y = 33, kind = "building" },
            { x = 20, y = 34, kind = "rv" },
            { x = 33, y = 33.5, kind = "caravan" },
            { x = 44, y = 34, kind = "tent" },
            { x = 14, y = 6, kind = "pool" },
            { x = 30, y = 7, kind = "car" },
        },
        cones = {
            { x = 33, y = 17.2, r = 0.35, kind = "cone" },
            { x = 33, y = 22.8, r = 0.35, kind = "cone" },
            { x = 40, y = 15.8, kind = "firepit" },
            { x = 39.5, y = 24.2, kind = "chair" },
            { x = 41.2, y = 23.4, kind = "chair" },
        },
        surfaces = {
            { x = 30, y = 20, w = 60, h = 14, kind = "gravel" },
            { x = 30, y = 6.5, w = 60, h = 13, kind = "grass" },
            { x = 30, y = 33.5, w = 60, h = 13, kind = "grass" },
            { x = 8, y = 36.5, w = 10, h = 5, kind = "deck" },
        },
        par = 22,
        apron = 2.0,
    },
    {
        id = "long-way-back",
        series = "training",
        order = 2,
        name = "Long way back",
        hint = "It is further than it looks. Correct early: the error grows as you reverse.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 52, y = 20, th = 0 },
        bay = { x = 16, y = 21.5, w = 10, h = 6, angle = 0, tol = math.rad(8) },
        walls = {
            { x = 30, y = 13.7, w = 56, h = 0.7, kind = "hedge" },
            { x = 30, y = 30.3, w = 56, h = 0.7, kind = "hedge" },
            { x = 8, y = 36, kind = "tent" },
            { x = 34, y = 35.5, kind = "rv" },
            { x = 10, y = 6, kind = "car" },
        },
        cones = {
            { x = 40, y = 16.2, kind = "cone" },
            { x = 30, y = 27.4, kind = "cone" },
        },
        surfaces = {
            { x = 30, y = 22, w = 60, h = 18, kind = "gravel" },
            { x = 30, y = 6.5, w = 60, h = 13, kind = "grass" },
            { x = 30, y = 35, w = 60, h = 10, kind = "grass" },
            { x = 16, y = 21.5, w = 12, h = 8, kind = "deck" },
        },
        -- par is the audit's machine line (19.48 s, full grid, re-measured after
        -- input quantisation) times 1.5 until a playtest replaces it; never scale it
        par = 30,
        apron = 2.0,
    },
{
    id = "angled-bay",
    series = "training",
    order = 3,
    name = "Angled bay",
    hint = "The bay is sideways. Set the angle up before you commit to the reverse.",
    bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
    spawn = { x = 48.5, y = 10, th = math.rad(180) },
    bay = { x = 23, y = 24, w = 8, h = 4, angle = math.rad(270), tol = math.rad(7) },
    par = 30,
    apron = 2,
    walls = {
        { x = 30, y = 36.5, w = 60, h = 0.8, kind = "hedge" },
        { x = 30, y = 3.5, w = 60, h = 0.8, kind = "hedge" },
        { x = 36.5, y = 29, w = 9.5, h = 6, kind = "pool" },
        { x = 51, y = 20, w = 12, h = 5.5, kind = "building" },
        { x = 13.5, y = 18, kind = "rv" },
        { x = 27, y = 6, kind = "car" },
        { x = 31.5, y = 19, w = 4, h = 3.5, angle = math.rad(-90), kind = "tent" },
        { x = 37, y = 19, w = 2, h = 2, angle = math.rad(270), kind = "tent" },
    },
    cones = {
        { x = 20.5, y = 18.5, kind = "cone" },
        { x = 25.5, y = 18.5, kind = "cone" },
    },
    surfaces = {
        { x = 30, y = 9.5, w = 60, h = 11, kind = "gravel" },
        { x = 23, y = 25, w = 8, h = 20, kind = "gravel" },
        { x = 30, y = 37.5, w = 60, h = 5, kind = "grass" },
        { x = 43.5, y = 25, w = 33, h = 20, kind = "grass" },
        { x = 9.5, y = 25, w = 19, h = 20, kind = "grass" },
        { x = 30, y = 2, w = 60, h = 4, kind = "grass" },
    },
},
    {
        id = "tight-alley",
        series = "basics",
        order = 1,
        name = "Tight alley",
        hint = "Six metres of alley. The caravan's wheels cut inside your line, so watch the inner wall.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 50, y = 20, th = 0 },
        bay = { x = 14, y = 20, w = 7, h = 3.6, angle = 0, tol = math.rad(5) },
        walls = {
            { x = 29, y = 16.6, w = 52, h = 0.6, kind = "hedge" },
            { x = 29, y = 23.4, w = 52, h = 0.6, kind = "hedge" },
            { x = 14, y = 12.2, w = 18, h = 0.6, kind = "hedge" },
        },
        cones = {
            { x = 36, y = 18.4, r = 0.35, kind = "cone" },
            { x = 36, y = 21.6, r = 0.35, kind = "cone" },
        },
        par = 26,
        apron = 0.7,
    },
    {
        id = "fire-side",
        series = "basics",
        order = 2,
        name = "Fire side",
        hint = "The bay is off to the left. Swing the caravan's tail toward the bay, not toward the fire.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 50, y = 20, th = 0 },
        bay = { x = 18, y = 21.5, w = 9, h = 4, angle = 0, tol = math.rad(6) },
        walls = {
            { x = 30, y = 13.7, w = 52, h = 0.7, kind = "hedge" },
            { x = 30, y = 30.3, w = 52, h = 0.7, kind = "hedge" },
            { x = 8, y = 36, kind = "building" },
            { x = 24, y = 36, kind = "rv" },
            { x = 44, y = 35.5, kind = "tent" },
            { x = 14, y = 6, kind = "pool" },
            { x = 34, y = 6.5, kind = "car" },
        },
        cones = {
            -- the fire sits on the side the tail must NOT swing to
            { x = 29, y = 15.4, kind = "firepit" },
            { x = 31.6, y = 15.5, kind = "chair" },
            { x = 23, y = 25.9, kind = "chair" },
        },
        surfaces = {
            { x = 30, y = 20, w = 60, h = 20, kind = "gravel" },
            { x = 30, y = 7, w = 60, h = 12, kind = "grass" },
            { x = 30, y = 34.5, w = 60, h = 11, kind = "grass" },
            { x = 8, y = 36, w = 10, h = 6, kind = "deck" },
        },
        par = 30,
        apron = 2.0,
    },
    {
        id = "round-the-back",
        series = "tricky",
        order = 1,
        name = "Round the back",
        hint = "The bay is behind the gate. Line the rig up before it, then reverse straight through.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 52, y = 20, th = 0 },
        bay = { x = 12, y = 20, w = 9, h = 4, angle = 0, tol = math.rad(6) },
        walls = {
            { x = 30, y = 13.7, w = 54, h = 0.7, kind = "hedge" },
            { x = 30, y = 26.3, w = 54, h = 0.7, kind = "hedge" },
            -- the gate: a 5.6 m gap between two stubs, and the caravan is 2.1 m
            { x = 30, y = 15.45, w = 0.8, h = 3.5, kind = "hedge" },
            { x = 30, y = 24.55, w = 0.8, h = 3.5, kind = "hedge" },
            { x = 8, y = 35, kind = "building" },
            { x = 30, y = 35.5, kind = "rv" },
            { x = 46, y = 35, kind = "tent" },
            { x = 12, y = 6, kind = "pool" },
            { x = 40, y = 6.5, kind = "car" },
        },
        cones = {
            { x = 36, y = 16.8, kind = "cone" },
            { x = 36, y = 23.2, kind = "cone" },
            { x = 20, y = 25.3, kind = "chair" },
        },
        surfaces = {
            { x = 30, y = 20, w = 60, h = 16, kind = "gravel" },
            { x = 30, y = 6.5, w = 60, h = 13, kind = "grass" },
            { x = 30, y = 33.5, w = 60, h = 13, kind = "grass" },
            { x = 8, y = 35, w = 9, h = 5, kind = "deck" },
        },
        par = 32,
        apron = 2.0,
    },
    {
        id = "clean-line",
        series = "tricky",
        order = 2,
        name = "Clean line",
        hint = "Two fires this time, with a chair run inside them. Thread it without touching anything.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 52, y = 20, th = 0 },
        bay = { x = 14, y = 20, w = 9, h = 4, angle = 0, tol = math.rad(5) },
        walls = {
            { x = 30, y = 14.2, w = 54, h = 0.7, kind = "hedge" },
            { x = 30, y = 25.8, w = 54, h = 0.7, kind = "hedge" },
            { x = 8, y = 35, kind = "building" },
            { x = 26, y = 35.5, kind = "rv" },
            { x = 40, y = 35.5, kind = "caravan" },
            { x = 52, y = 35, kind = "tent" },
            { x = 12, y = 6, kind = "pool" },
            { x = 36, y = 6.5, kind = "car" },
        },
        cones = {
            { x = 34, y = 16.7, kind = "firepit" },
            { x = 34, y = 23.3, kind = "firepit" },
            { x = 27, y = 17.5, kind = "chair" },
            { x = 27, y = 22.5, kind = "chair" },
            { x = 21.5, y = 24.6, kind = "chair" },
        },
        surfaces = {
            { x = 30, y = 20, w = 60, h = 16, kind = "gravel" },
            { x = 30, y = 6.5, w = 60, h = 13, kind = "grass" },
            { x = 30, y = 33.5, w = 60, h = 13, kind = "grass" },
            { x = 8, y = 35, w = 9, h = 5, kind = "deck" },
        },
        par = 30,
        apron = 2.0,
    },
}

-- Defaults are filled by the format layer: the same resolve() that turns a
-- decoded document into a level, so a shipped level and an imported one cannot
-- disagree about what a hedge's default size is.
M.ALL = {}
for i, level in ipairs(RAW) do
    M.ALL[i] = levelfmt.resolve(level)
end

function M.get(i)
    return M.ALL[i] or M.ALL[1]
end

-- The menu holds levels, not indices: opening a card has to find the level the
-- shop list is showing, and an id is stable where a position is not.
function M.find(id)
    for i, lvl in ipairs(M.ALL) do
        if lvl.id == id then return i end
    end
    return nil
end

return M
