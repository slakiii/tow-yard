-- Is this level legitimate? One implementation, asked by the test suite, by the
-- editor's save gate and by the importer.
--
-- It lives here because the rules used to live in tests/test_levels.lua, and a
-- rule that only exists in a test cannot stop a hand-authored or imported level
-- from shipping. Every rule returns a list of human-readable reasons, so a
-- caller can show them instead of asserting on them.
--
-- What this is NOT: a check that a level is *good*. It says nothing about par,
-- difficulty or whether the level has any scenery at all. "At least one solid
-- prop" is a campaign policy, not a legality rule -- an editor's empty document
-- must be legal to save, or every new level starts with a lie on screen.
--
-- Pure: no love.*, no geometry of its own beyond lib/geom.

local geom = require("lib.geom")
local props = require("lib.props")
local rig = require("lib.rig")

local M = {}

local function positive(v)
    return type(v) == "number" and v > 0
end

local function box_of(entry)
    local fp = props.footprint(entry)
    if not fp then return nil end
    return geom.rect_poly(entry.x, entry.y, fp.w, fp.h, entry.angle or 0)
end

local function radius_of(entry)
    local fp = props.footprint(entry)
    return fp and fp.r
end

local function is_linear(entry)
    local def = props.get(entry.kind)
    return def and def.linear
end

local function bounds_poly(b)
    return geom.rect_poly((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, b.x1 - b.x0, b.y1 - b.y0, 0)
end

-- Every rule has the same shape: level -> list of reasons, empty when fine.
-- A rule whose prerequisite is missing returns nothing rather than raising;
-- `structure` is the rule that reports the missing field, so the caller always
-- gets a reason and never a crash from a half-parsed document.
M.rules = {}

function M.rules.vocabulary(level)
    -- An untyped or unknown prop is a typo, and every later rule would be
    -- guessing about its size. Run this first; errors() stops here if it fires.
    return props.check(level)
end

function M.rules.structure(level)
    local errs = {}
    if type(level.id) ~= "string" or level.id == "" then
        errs[#errs + 1] = "no id (a level with no identity cannot keep a best time)"
    end
    if type(level.name) ~= "string" or level.name == "" then
        errs[#errs + 1] = "no name"
    end
    local sp = level.spawn
    if type(sp) ~= "table" or type(sp.x) ~= "number" or type(sp.y) ~= "number" then
        errs[#errs + 1] = "no spawn position"
    elseif type(sp.th) ~= "number" then
        errs[#errs + 1] = "spawn has no heading"
    end
    local b = level.bay
    if type(b) ~= "table" or not positive(b.w) or not positive(b.h) then
        errs[#errs + 1] = "bay needs a positive w and h"
    else
        if type(b.angle) ~= "number" then errs[#errs + 1] = "bay has no angle" end
        if not positive(b.tol) then errs[#errs + 1] = "bay needs a positive angle tolerance" end
    end
    if not positive(level.par) then
        errs[#errs + 1] = "par must be a positive number"
    end
    local bd = level.bounds
    if type(bd) ~= "table" or not (bd.x1 > bd.x0 and bd.y1 > bd.y0) then
        errs[#errs + 1] = "bounds must have x1 > x0 and y1 > y0"
    end
    return errs
end

function M.rules.spawn_clear(level)
    local errs = {}
    local sp = level.spawn
    if type(sp) ~= "table" or type(sp.x) ~= "number" then return errs end
    local s = rig.new(sp.x, sp.y, sp.th)
    local car, van = rig.car_poly(s), rig.caravan_poly(s)
    for j, w in ipairs(level.walls or {}) do
        local wp = box_of(w)
        if wp and (geom.overlap(car, wp) or geom.overlap(van, wp)) then
            errs[#errs + 1] = "spawn overlaps wall " .. j .. " (" .. tostring(w.kind) .. ")"
        end
    end
    return errs
end

function M.rules.bay_inside_bounds(level)
    local errs = {}
    local b, bd = level.bay, level.bounds
    if type(b) ~= "table" or type(bd) ~= "table" then return errs end
    if not (positive(b.w) and positive(b.h)) then return errs end
    if b.x - b.w / 2 < bd.x0 or b.x + b.w / 2 > bd.x1 then
        errs[#errs + 1] = "bay x outside bounds"
    end
    if b.y - b.h / 2 < bd.y0 or b.y + b.h / 2 > bd.y1 then
        errs[#errs + 1] = "bay y outside bounds"
    end
    return errs
end

function M.rules.apron_clear(level)
    local errs = {}
    local b = level.bay
    if type(b) ~= "table" or not (positive(b.w) and positive(b.h)) then return errs end
    local apron = level.apron or 2.0
    local ring = geom.rect_poly(b.x, b.y, b.w + apron * 2, b.h + apron * 2, b.angle or 0)
    for j, w in ipairs(level.walls or {}) do
        local wp = box_of(w)
        if wp and geom.overlap(ring, wp) then
            errs[#errs + 1] = "wall " .. j .. " (" .. tostring(w.kind) .. ") intrudes on the bay apron"
        end
    end
    return errs
end

function M.rules.props_inside_bounds(level)
    local errs = {}
    local bd = level.bounds
    if type(bd) ~= "table" then return errs end
    local outer = bounds_poly(bd)
    for j, w in ipairs(level.walls or {}) do
        local wp = box_of(w)
        if wp and not geom.poly_in_poly(wp, outer) then
            errs[#errs + 1] = "wall " .. j .. " (" .. tostring(w.kind) .. ") escapes bounds"
        end
    end
    for j, c in ipairs(level.cones or {}) do
        local r = radius_of(c)
        if r then
            local inside = c.x - r >= bd.x0 and c.x + r <= bd.x1
                and c.y - r >= bd.y0 and c.y + r <= bd.y1
            if not inside then
                errs[#errs + 1] = "cone " .. j .. " (" .. tostring(c.kind) .. ") escapes bounds"
            end
        end
    end
    return errs
end

function M.rules.props_disjoint(level)
    -- Hedges are linear scenery and may join at a corner (level 2's T-junction
    -- is two of them meeting). Anything you could point at as one object must
    -- stay clear of everything: a motorhome drawn inside the clubhouse reads as
    -- a rendering bug, not as a tight site.
    local errs = {}
    local walls = level.walls or {}
    for i = 1, #walls do
        for j = i + 1, #walls do
            local a, b = walls[i], walls[j]
            if not (is_linear(a) and is_linear(b)) then
                local pa, pb = box_of(a), box_of(b)
                if pa and pb and geom.overlap(pa, pb) then
                    errs[#errs + 1] = "wall " .. i .. " (" .. tostring(a.kind) .. ") intersects wall "
                        .. j .. " (" .. tostring(b.kind) .. ")"
                end
            end
        end
    end
    for i, c in ipairs(level.cones or {}) do
        local r = radius_of(c)
        if r then
            for j, w in ipairs(walls) do
                local wp = box_of(w)
                if wp and geom.circle_overlap_poly(c.x, c.y, r, wp) then
                    errs[#errs + 1] = "cone " .. i .. " (" .. tostring(c.kind) .. ") intersects wall "
                        .. j .. " (" .. tostring(w.kind) .. ")"
                end
            end
            for j = i + 1, #(level.cones or {}) do
                local other = level.cones[j]
                local ro = radius_of(other)
                if ro then
                    local d = math.sqrt((c.x - other.x) ^ 2 + (c.y - other.y) ^ 2)
                    if not (d > r + ro) then
                        errs[#errs + 1] = "cone " .. i .. " intersects cone " .. j
                    end
                end
            end
        end
    end
    return errs
end

function M.rules.paint_inside_bounds(level)
    local errs = {}
    local bd = level.bounds
    if type(bd) ~= "table" then return errs end
    local outer = bounds_poly(bd)
    for i, zone in ipairs(level.surfaces or {}) do
        if not (positive(zone.w) and positive(zone.h)) then
            errs[#errs + 1] = "surface " .. i .. " needs a positive w and h"
        else
            local poly = geom.rect_poly(zone.x, zone.y, zone.w, zone.h, zone.angle or 0)
            if not geom.poly_in_poly(poly, outer) then
                errs[#errs + 1] = "surface " .. i .. " (" .. tostring(zone.kind) .. ") escapes bounds"
            end
        end
    end
    return errs
end

function M.rules.bay_on_paint(level)
    -- A bay floating over the background colour looks like a bug at a glance;
    -- paint is the site, so the goal has to stand on some of it. Only applies
    -- to a painted level: bare ground is legal, it just looks like a test bed.
    local errs = {}
    local b = level.bay
    if type(b) ~= "table" or #(level.surfaces or {}) == 0 then return errs end
    for _, zone in ipairs(level.surfaces) do
        local poly = geom.rect_poly(zone.x, zone.y, zone.w, zone.h, zone.angle or 0)
        if geom.point_in_poly(b.x, b.y, poly) then return errs end
    end
    errs[#errs + 1] = "the bay does not sit on any painted surface"
    return errs
end

-- Fixed order, so the first reason a caller shows is the one worth fixing first.
local ORDER = {
    "vocabulary", "structure", "spawn_clear", "bay_inside_bounds", "apron_clear",
    "props_inside_bounds", "props_disjoint", "paint_inside_bounds", "bay_on_paint",
}

function M.errors(level)
    if type(level) ~= "table" then return { "level is not a table" } end
    local errs = {}
    for _, name in ipairs(ORDER) do
        local found = M.rules[name](level)
        for _, e in ipairs(found) do errs[#errs + 1] = e end
        -- A vocabulary error makes every spatial rule a guess about a size that
        -- does not exist, so stop and let the typo be fixed first.
        if name == "vocabulary" and #found > 0 then return errs end
    end
    return errs
end

-- Invariants that need the whole catalogue rather than one level.
function M.catalog_errors(list)
    local errs = {}
    local names, ids = {}, {}
    for _, lvl in ipairs(list or {}) do
        if names[lvl.name] then
            errs[#errs + 1] = "duplicate level name: " .. tostring(lvl.name)
        end
        names[lvl.name] = true
        if lvl.id then
            if ids[lvl.id] then
                errs[#errs + 1] = "duplicate level id: " .. tostring(lvl.id)
            end
            ids[lvl.id] = true
        end
    end
    return errs
end

return M
