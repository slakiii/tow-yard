-- Level data invariants, plus one end-to-end replay that proves the shipped
-- level 1 can actually be parked by driving real input through the session.

local H = require("tests.helper")
local levels = require("lib.levels")
local geom = require("lib.geom")
local rig = require("lib.rig")
local session = require("lib.session")

local M = { order = { "every_level_is_well_formed", "spawn_is_clear", "bay_apron_is_clear",
                      "bay_inside_bounds", "levels_have_unique_names",
                      "level_1_is_winnable_by_reversing_straight" } }

local DT = 1 / 120

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
