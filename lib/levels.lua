-- Level data. Everything here is authoring data: a level is a spawn transform,
-- a parking bay, walls, cones and a par time.
--
-- walls: axis-aligned boxes, blocking.
-- cones: circles, knocked over on contact and charged as a bump.
-- apron: clearance required around the bay (metres) -- tight levels lower it.

local M = {}

M.ALL = {
    {
        name = "Straight back",
        hint = "Reverse straight back into the bay. The caravan will not stay straight on its own.",
        bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
        spawn = { x = 46, y = 20, th = 0 },
        bay = { x = 22, y = 20, w = 9, h = 4, angle = 0, tol = math.rad(6) },
        walls = {
            { x = 29, y = 14, w = 46, h = 0.6 },
            { x = 29, y = 26, w = 46, h = 0.6 },
        },
        cones = {
            { x = 33, y = 17.2, r = 0.35 },
            { x = 33, y = 22.8, r = 0.35 },
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
            { x = 30, y = 36.5, w = 60, h = 0.8 },
            { x = 30, y = 3.5, w = 60, h = 0.8 },
            { x = 52.5, y = 20, w = 0.8, h = 34 },
        },
        cones = {
            { x = 33, y = 22, r = 0.35 },
            { x = 19, y = 22, r = 0.35 },
            { x = 26, y = 19, r = 0.35 },
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
            { x = 29, y = 16.6, w = 52, h = 0.6 },
            { x = 29, y = 23.4, w = 52, h = 0.6 },
            { x = 14, y = 12.2, w = 18, h = 0.6 },
        },
        cones = {
            { x = 36, y = 18.4, r = 0.35 },
            { x = 36, y = 21.6, r = 0.35 },
        },
        par = 26,
        apron = 0.7,
    },
}

function M.get(i)
    return M.ALL[i] or M.ALL[1]
end

return M
