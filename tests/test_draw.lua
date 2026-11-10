-- Renderer detail that is pure enough to test headless. The hedge bump layout is
-- here because its first version took the bump radius from the hedge's HEIGHT:
-- level 2's vertical hedge is 0.8 x 34 m, which drew one green circle of radius
-- 25.5 m over the whole site. A vertical hedge must be as boring as a horizontal
-- one.

local H = require("tests.helper")
local draw = require("lib.draw")

local M = { order = { "hedge_bumps_fit_a_horizontal_hedge", "hedge_bumps_fit_a_vertical_hedge",
                      "hedge_bumps_scale_with_the_short_side", "speed_reads_in_km_h",
                      "the_rail_maps_a_click_to_a_tool" } }

local function check_inside(fp, label)
    local bumps = draw.hedge_bumps(fp)
    H.expect(#bumps > 1, label .. ": a hedge this long needs more than one bump")
    for i, b in ipairs(bumps) do
        H.expect(math.abs(b.lx) + b.r <= fp.w / 2 + 1e-9,
                 string.format("%s: bump %d pokes out sideways (|lx| %.2f + r %.2f > %.2f)",
                               label, i, math.abs(b.lx), b.r, fp.w / 2))
        H.expect(math.abs(b.ly) + b.r <= fp.h / 2 + 1e-9,
                 string.format("%s: bump %d pokes out forwards (|ly| %.2f + r %.2f > %.2f)",
                               label, i, math.abs(b.ly), b.r, fp.h / 2))
    end
end

function M.hedge_bumps_fit_a_horizontal_hedge()
    check_inside({ w = 46, h = 0.6 }, "46 x 0.6 m")
    check_inside({ w = 3, h = 0.7 }, "3 x 0.7 m")
end

function M.hedge_bumps_fit_a_vertical_hedge()
    -- the exact regression: this footprint used to produce a 25 m circle
    check_inside({ w = 0.8, h = 34 }, "0.8 x 34 m")
    check_inside({ w = 0.6, h = 18 }, "0.6 x 18 m")
end

function M.hedge_bumps_scale_with_the_short_side()
    -- the bumps are foliage on a strip: their size comes from thickness, and the
    -- count comes from length, so a long hedge is a scalloped run, not a blob
    local thin = draw.hedge_bumps({ w = 30, h = 0.6 })
    local fat = draw.hedge_bumps({ w = 30, h = 1.6 })
    H.expect(fat[1].r > thin[1].r, "a thicker hedge gets fatter bumps")
    H.expect(thin[1].r <= 0.3 + 1e-9, "bump radius stays under half the thickness")
    H.expect(#draw.hedge_bumps({ w = 60, h = 0.6 }) > #draw.hedge_bumps({ w = 6, h = 0.6 }),
             "a longer hedge gets more bumps")
end

function M.speed_reads_in_km_h()
    H.expect(draw.kmh(0) == "0 km/h", "standstill is 0")
    H.expect(draw.kmh(5.0) == "18 km/h", "the top of a yard is 18 km/h")
    H.expect(draw.kmh(1.8) == "6 km/h", "the reverse cap is 6.5 km/h, shown as 6")
    H.expect(draw.kmh(-3.6) == "13 km/h", "speed is a magnitude: reversing reads positive")
    H.expect(draw.kmh(1.8, 1) == "6.5 km/h", "the debug overlay keeps a decimal")
end

function M.the_rail_maps_a_click_to_a_tool()
    -- the rail is a grid now, so a click is arithmetic over a layout -- and the
    -- view and the click handler must use the same arithmetic, or a click on
    -- "cone" places a clubhouse and the editor reads as ignoring you.
    local palettedata = require("lib.edit.palette")
    local groups = palettedata.groups()
    local vw, vh = 1280, 720   -- not W/H: those hold the test helper

    local lay = draw.palette_layout(groups, vw, vh)
    H.expect(#lay.tiles == #palettedata.order(), "one tile per placeable tool")

    -- every tile, at its own centre, must answer with its own name
    for _, t in ipairs(lay.tiles) do
        local name = t.item.tool or t.item.kind
        local hit = draw.editor_tool_at(t.x + t.w / 2, t.y + t.h / 2, groups, vw, vh)
        H.expect(hit == name, "the centre of " .. name .. " answered " .. tostring(hit))
    end

    -- and every tile must be inside the rail, above the footer hints
    for _, t in ipairs(lay.tiles) do
        H.expect(t.x >= 0 and t.x + t.w <= draw.RAIL, "a tile sticks out of the rail")
    end
    H.expect(lay.bottom < vh - 120, "the grid must leave the panels and hints their room")

    local first = lay.tiles[1]
    H.expect(draw.editor_tool_at(first.x - 6, first.y + 2, groups, vw, vh) == nil,
             "the margin left of the grid is not a tool")
    H.expect(draw.editor_tool_at(vw / 2, vh / 2, groups, vw, vh) == nil, "the yard is not the rail")

    -- the minimum window height gets its own layout, tighter and with one
    -- footer line, because 720 px of grid in 560 px of window is a clipped rail
    local short = draw.palette_layout(groups, 800, 560)
    H.expect(short.compact, "560 px is the compact layout")
    H.expect(short.bottom + 40 <= 560, "the compact grid must leave the hint line room")
end

return M
