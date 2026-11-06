-- Level data invariants, plus one end-to-end replay that proves the shipped
-- level 1 can actually be parked by driving real input through the session.
--
-- Two families live here: the vocabulary (lib/props.lua -- is every kind real,
-- every size positive) and the space (nothing escapes bounds, discrete props
-- never intersect, the bay keeps its apron, paint is only paint).

local H = require("tests.helper")
local levels = require("lib.levels")
local geom = require("lib.geom")
local rig = require("lib.rig")
local session = require("lib.session")
local props = require("lib.props")

local M = { order = { "every_level_is_well_formed", "every_level_has_typed_scenery",
                      "spawn_is_clear", "bay_apron_is_clear", "bay_inside_bounds",
                      "props_stay_inside_bounds", "discrete_props_do_not_intersect",
                      "paint_stays_inside_bounds", "the_bay_sits_on_a_painted_surface",
                      "levels_have_unique_names",
                      "level_1_is_winnable_by_reversing_straight" } }

local DT = 1 / 120

local function bounds_poly(b)
    return geom.rect_poly((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, b.x1 - b.x0, b.y1 - b.y0, 0)
end

local function box_of(entry)
    local fp = props.footprint(entry)
    return geom.rect_poly(entry.x, entry.y, fp.w, fp.h, entry.angle or 0)
end

local function radius_of(entry)
    return props.footprint(entry).r
end

local function is_linear(entry)
    local def = props.get(entry.kind)
    return def and def.linear
end

function M.every_level_is_well_formed()
    H.expect(#levels.ALL >= 3, "at least three levels")
    for i, lvl in ipairs(levels.ALL) do
        H.expect(type(lvl.name) == "string" and #lvl.name > 0, "level " .. i .. " name")
        H.expect(lvl.spawn and lvl.spawn.x and lvl.spawn.y, "level " .. i .. " spawn")
        H.expect(lvl.bay and lvl.bay.w and lvl.bay.h, "level " .. i .. " bay")
        H.expect(lvl.bay.tol and lvl.bay.tol > 0, "level " .. i .. " bay tolerance")
        H.expect(lvl.par and lvl.par > 0, "level " .. i .. " par time")
        H.expect(lvl.bounds, "level " .. i .. " bounds")
    end
end

function M.every_level_has_typed_scenery()
    for _, lvl in ipairs(levels.ALL) do
        local errs = props.check(lvl)
        H.expect(#errs == 0, lvl.name .. ": " .. tostring(errs[1]))
        -- non-emptiness: a level with no props would pass the vocabulary check
        -- vacuously and say nothing about whether the site is dressed
        H.expect(#(lvl.walls or {}) >= 1, lvl.name .. ": needs at least one solid prop")
        H.expect(#(lvl.cones or {}) >= 1, lvl.name .. ": needs at least one knockable prop")
    end
    H.expect(#(levels.get(1).surfaces or {}) >= 2, "level 1 must be painted, not bare ground")
end

function M.props_stay_inside_bounds()
    for _, lvl in ipairs(levels.ALL) do
        local b = lvl.bounds
        local outer = bounds_poly(b)
        for j, w in ipairs(lvl.walls or {}) do
            H.expect(geom.poly_in_poly(box_of(w), outer),
                     lvl.name .. ": wall " .. j .. " (" .. tostring(w.kind) .. ") escapes bounds")
        end
        for j, c in ipairs(lvl.cones or {}) do
            local r = radius_of(c)
            H.expect(c.x - r >= b.x0 and c.x + r <= b.x1 and c.y - r >= b.y0 and c.y + r <= b.y1,
                     lvl.name .. ": cone " .. j .. " (" .. tostring(c.kind) .. ") escapes bounds")
        end
    end
end

function M.discrete_props_do_not_intersect()
    -- Hedges are linear scenery and may join at a corner (level 2's T-junction
    -- is two of them meeting). Anything you could point at as one object must
    -- stay clear of everything: a motorhome drawn inside the clubhouse reads as
    -- a rendering bug, not as a tight site.
    for _, lvl in ipairs(levels.ALL) do
        local walls = lvl.walls or {}
        for i = 1, #walls do
            for j = i + 1, #walls do
                local a, b = walls[i], walls[j]
                if not (is_linear(a) and is_linear(b)) then
                    H.expect(not geom.overlap(box_of(a), box_of(b)),
                             lvl.name .. ": wall " .. i .. " (" .. tostring(a.kind) .. ") intersects wall "
                             .. j .. " (" .. tostring(b.kind) .. ")")
                end
            end
        end
        for i, c in ipairs(lvl.cones or {}) do
            local r = radius_of(c)
            for j, w in ipairs(walls) do
                H.expect(not geom.circle_overlap_poly(c.x, c.y, r, box_of(w)),
                         lvl.name .. ": cone " .. i .. " (" .. tostring(c.kind) .. ") intersects wall "
                         .. j .. " (" .. tostring(w.kind) .. ")")
            end
            for j = i + 1, #lvl.cones do
                local other = lvl.cones[j]
                local d = math.sqrt((c.x - other.x) ^ 2 + (c.y - other.y) ^ 2)
                H.expect(d > r + radius_of(other),
                         lvl.name .. ": cone " .. i .. " intersects cone " .. j)
            end
        end
    end
end

function M.paint_stays_inside_bounds()
    for _, lvl in ipairs(levels.ALL) do
        local outer = bounds_poly(lvl.bounds)
        for i, zone in ipairs(lvl.surfaces or {}) do
            H.expect(zone.w and zone.h and zone.w > 0 and zone.h > 0,
                     lvl.name .. ": surface " .. i .. " needs a positive w and h")
            local poly = geom.rect_poly(zone.x, zone.y, zone.w, zone.h, zone.angle or 0)
            H.expect(geom.poly_in_poly(poly, outer),
                     lvl.name .. ": surface " .. i .. " (" .. tostring(zone.kind) .. ") escapes bounds")
        end
    end
end

function M.the_bay_sits_on_a_painted_surface()
    -- A bay floating over the background colour looks like a bug at a glance;
    -- paint is the site, so the goal has to stand on some of it.
    for _, lvl in ipairs(levels.ALL) do
        if #(lvl.surfaces or {}) > 0 then
            local painted = false
            for _, zone in ipairs(lvl.surfaces) do
                local poly = geom.rect_poly(zone.x, zone.y, zone.w, zone.h, zone.angle or 0)
                if geom.point_in_poly(lvl.bay.x, lvl.bay.y, poly) then painted = true end
            end
            H.expect(painted, lvl.name .. ": the bay does not sit on any painted surface")
        end
    end
end

function M.spawn_is_clear()
    for _, lvl in ipairs(levels.ALL) do
        local s = rig.new(lvl.spawn.x, lvl.spawn.y, lvl.spawn.th)
        for j, w in ipairs(lvl.walls) do
            local wp = geom.rect_poly(w.x, w.y, w.w, w.h, w.angle or 0)
            H.expect(not geom.overlap(rig.car_poly(s), wp), lvl.name .. ": spawn overlaps wall " .. j)
            H.expect(not geom.overlap(rig.caravan_poly(s), wp),
                     lvl.name .. ": spawn caravan overlaps wall " .. j)
        end
    end
end

function M.bay_apron_is_clear()
    for _, lvl in ipairs(levels.ALL) do
        local apron = lvl.apron or 2.0
        local ring = geom.rect_poly(lvl.bay.x, lvl.bay.y, lvl.bay.w + apron * 2,
                                    lvl.bay.h + apron * 2, lvl.bay.angle)
        for j, w in ipairs(lvl.walls) do
            local wp = geom.rect_poly(w.x, w.y, w.w, w.h, w.angle or 0)
            H.expect(not geom.overlap(ring, wp),
                     lvl.name .. ": wall " .. j .. " intrudes on the bay apron")
        end
    end
end

function M.bay_inside_bounds()
    for _, lvl in ipairs(levels.ALL) do
        local b, bd = lvl.bay, lvl.bounds
        H.expect(b.x - b.w / 2 >= bd.x0 and b.x + b.w / 2 <= bd.x1, lvl.name .. ": bay x outside bounds")
        H.expect(b.y - b.h / 2 >= bd.y0 and b.y + b.h / 2 <= bd.y1, lvl.name .. ": bay y outside bounds")
    end
end

function M.levels_have_unique_names()
    local seen = {}
    for _, lvl in ipairs(levels.ALL) do
        H.expect(not seen[lvl.name], "duplicate level name: " .. lvl.name)
        seen[lvl.name] = true
    end
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
