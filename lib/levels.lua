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

local props = require("lib.props")

local M = {}

-- Authored data: a prop says what it is (`kind`) and, only when it differs from
-- the kind's default, how big it is.
local RAW = {
    {
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
        name = "Angled bay",
        hint = "The bay is sideways. Set the angle up before you commit to the reverse.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 48, y = 10, th = 0 },
        bay = { x = 26, y = 26, w = 10, h = 4.6, angle = math.pi / 2, tol = math.rad(7) },
        walls = {
            { x = 30, y = 36.5, w = 60, h = 0.8, kind = "hedge" },
            { x = 30, y = 3.5, w = 60, h = 0.8, kind = "hedge" },
            { x = 52.5, y = 20, w = 0.8, h = 34, kind = "hedge" },
        },
        cones = {
            { x = 33, y = 22, r = 0.35, kind = "cone" },
            { x = 19, y = 22, r = 0.35, kind = "cone" },
            { x = 26, y = 19, r = 0.35, kind = "cone" },
        },
        par = 30,
        apron = 2.0,
    },
    {
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

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Fill every prop's size from its kind once, at load, so the session, the
-- renderer and the level invariants all read explicit numbers while the
-- authoring data stays terse. Defaults live in lib/props.lua and nowhere else.
-- An unknown kind is left unfilled on purpose: props.check names it, and the
-- suite fails before a level like that can be played.
local function resolve(level)
    local out = copy(level)
    out.walls = {}
    for i, wall in ipairs(level.walls or {}) do
        local fp = props.footprint(wall)
        local e = copy(wall)
        if fp then e.w, e.h = fp.w, fp.h else e.w, e.h = wall.w, wall.h end
        out.walls[i] = e
    end
    out.cones = {}
    for i, cone in ipairs(level.cones or {}) do
        local fp = props.footprint(cone)
        local e = copy(cone)
        e.r = fp and fp.r or cone.r
        out.cones[i] = e
    end
    out.surfaces = {}
    for i, zone in ipairs(level.surfaces or {}) do
        out.surfaces[i] = copy(zone)
    end
    return out
end

M.ALL = {}
for i, level in ipairs(RAW) do
    M.ALL[i] = resolve(level)
end

function M.get(i)
    return M.ALL[i] or M.ALL[1]
end

return M
