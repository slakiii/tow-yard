-- Pure 2D helpers: transforms, SAT overlap, containment.

local H = require("tests.helper")
local geom = require("lib.geom")

local M = { order = { "wrap_angle", "rect_corners", "transform", "overlap_and_separation",
                      "containment", "circle_vs_poly" } }

function M.wrap_angle()
    H.near(geom.wrap(math.pi * 1.5), -math.pi * 0.5, 1e-9, "wrap 3pi/2")
    H.near(geom.wrap(-math.pi * 2.2), -0.2 * math.pi, 1e-9, "wrap -2.2pi")
    H.near(geom.wrap(0), 0, 1e-12, "wrap 0")
end

function M.rect_corners()
    local p = geom.rect_poly(10, 5, 4, 2, 0)
    H.expect(#p == 4, "rect has 4 corners")
    local xs, ys = {}, {}
    for i, c in ipairs(p) do xs[i], ys[i] = c[1], c[2] end
    table.sort(xs); table.sort(ys)
    H.near(xs[1], 8, 1e-9, "min x"); H.near(xs[4], 12, 1e-9, "max x")
    H.near(ys[1], 4, 1e-9, "min y"); H.near(ys[4], 6, 1e-9, "max y")
end

function M.transform()
    local p = geom.poly_world({ { 2, 0 }, { 0, 1 } }, 10, 10, math.pi / 2)
    H.near(p[1][1], 10, 1e-9, "rotated x")
    H.near(p[1][2], 12, 1e-9, "rotated y")
    H.near(p[2][1], 9, 1e-9, "rotated x2")
    H.near(p[2][2], 10, 1e-9, "rotated y2")
end

function M.overlap_and_separation()
    local a = geom.rect_poly(0, 0, 4, 4, 0)
    local b = geom.rect_poly(3, 0, 4, 4, 0)
    local c = geom.rect_poly(6, 0, 4, 4, 0)
    H.expect(geom.overlap(a, b), "overlapping rects must report overlap")
    H.expect(not geom.overlap(a, c), "separated rects must not report overlap")
    -- touching edges is a boundary case: must not crash either way
    local d = geom.rect_poly(4, 0, 4, 4, 0)
    geom.overlap(a, d)
end

function M.containment()
    local outer = geom.rect_poly(0, 0, 10, 10, 0)
    local inner = geom.rect_poly(0, 0, 2, 2, 0)
    local straddle = geom.rect_poly(5, 0, 4, 4, 0)
    H.expect(geom.poly_in_poly(inner, outer), "inner rect must be contained")
    H.expect(not geom.poly_in_poly(straddle, outer), "straddling rect must not be contained")
end

function M.circle_vs_poly()
    local sq = geom.rect_poly(0, 0, 4, 4, 0)
    H.expect(geom.circle_overlap_poly(0, 0, 0.5, sq), "circle at centre overlaps")
    H.expect(geom.circle_overlap_poly(2.4, 0, 0.6, sq), "circle crossing the edge overlaps")
    H.expect(not geom.circle_overlap_poly(3.0, 0, 0.6, sq), "circle clear of the edge does not")
end

return M
