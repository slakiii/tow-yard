-- Rendering. Flat colours only: no assets, so the skeleton stays readable and
-- a level is nothing but data. Scenery is drawn per `kind` (see lib/props.lua)
-- from polygons and primitives in the same world frame as everything else --
-- no sprite sheets, and the shape you see is the shape the collision test used.

local geom = require("lib.geom")
local rig = require("lib.rig")
local session = require("lib.session")
local input = require("lib.input")
local props = require("lib.props")
local editdoc = require("lib.edit.doc")
local menu = require("lib.menu")

local D = {}

D.C = {
    ground = { 0.11, 0.12, 0.14 },
    grid = { 0.17, 0.18, 0.21 },
    wall = { 0.30, 0.32, 0.36 },
    wall_top = { 0.45, 0.48, 0.54 },
    bay = { 0.16, 0.38, 0.25 },
    bay_line = { 0.42, 0.82, 0.52 },
    car = { 0.82, 0.28, 0.24 },
    car_dark = { 0.55, 0.16, 0.14 },
    glass = { 0.55, 0.70, 0.80 },
    van = { 0.90, 0.86, 0.74 },
    van_dark = { 0.62, 0.58, 0.48 },
    cone = { 0.95, 0.55, 0.15 },
    guide = { 0.35, 0.75, 0.95 },
    ray = { 0.75, 0.80, 0.88 },
    tyre = { 0.16, 0.16, 0.18 },
    text = { 0.90, 0.92, 0.95 },
    dim = { 0.55, 0.58, 0.63 },
    warn = { 0.95, 0.32, 0.26 },
    good = { 0.45, 0.85, 0.55 },
    panel = { 0.07, 0.08, 0.10, 0.92 },
}

local fonts = {}

function D.init()
    fonts.big = love.graphics.newFont(34)
    fonts.mid = love.graphics.newFont(19)
    fonts.small = love.graphics.newFont(14)
end

local function set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function flat(pts)
    local out = {}
    for i = 1, #pts do
        out[#out + 1] = pts[i][1]
        out[#out + 1] = pts[i][2]
    end
    return out
end

local function at(x, y, ang, lx, ly)
    local c, s = math.cos(ang), math.sin(ang)
    return x + lx * c - ly * s, y + lx * s + ly * c
end

local function rot_rect(x, y, ang, lx, ly, w, h)
    local pts = {}
    for _, p in ipairs({ { -w / 2, -h / 2 }, { w / 2, -h / 2 }, { w / 2, h / 2 }, { -w / 2, h / 2 } }) do
        local wx, wy = at(x, y, ang, lx + p[1], ly + p[2])
        pts[#pts + 1] = wx
        pts[#pts + 1] = wy
    end
    return pts
end

-- ---------------------------------------------------------------------------
-- Scenery. Every kind draws its own footprint in the world frame, so the art is
-- the collision shape: nothing can drift from the box that actually hit you.
-- Kinds come from lib/props.lua; a kind with no art here still renders as its
-- plain footprint in its own colour rather than disappearing.
-- ---------------------------------------------------------------------------

local function shade(c, k)
    return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) }
end

local function box_fill(x, y, ang, lx, ly, w, h, colour, a)
    set(colour, a)
    love.graphics.polygon("fill", rot_rect(x, y, ang, lx, ly, w, h))
end

local function ridge(x, y, ang, from_x, to_x, colour, a)
    set(colour, a)
    love.graphics.setLineWidth(0.09)
    local ax, ay = at(x, y, ang, from_x, 0)
    local bx, by = at(x, y, ang, to_x, 0)
    love.graphics.line(ax, ay, bx, by)
end

local ART = {}

-- Tyres are the cheapest "this is a vehicle" cue at 15 px/m: the player's own
-- car is legible mostly because its wheels break the silhouette.
local function tyres(x, y, ang, fp, lxs, length)
    for _, lx in ipairs(lxs) do
        for _, side in ipairs({ 1, -1 }) do
            box_fill(x, y, ang, lx, side * (fp.h / 2 - 0.05), length or 0.72, 0.34,
                     D.C.tyre, 0.95)
        end
    end
end

ART.building = function(x, y, ang, fp, a)
    -- walls under the eaves, then the roof inset from them: the dark rim is
    -- what says "building" instead of "flat coloured plot"
    local inset = 0.45
    local w, h = fp.w - inset * 2, fp.h - inset * 2
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, shade(fp.colour, 0.55), a)
    box_fill(x, y, ang, 0, h * 0.24, w, h * 0.46, shade(fp.colour, 1.16), a)
    box_fill(x, y, ang, 0, -h * 0.24, w, h * 0.46, shade(fp.colour, 0.84), a)
    ridge(x, y, ang, -w / 2, w / 2, shade(fp.colour, 1.55), 0.7 * a)
    -- a chimney, so a clubhouse is not mistaken for a very large tent
    box_fill(x, y, ang, -w * 0.3, h * 0.1, 0.7, 0.7, shade(fp.colour, 0.4), a)
end

ART.rv = function(x, y, ang, fp, a)
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, fp.colour, a)
    -- cab: a narrower, darker box at the +x end, with the screen across its nose
    box_fill(x, y, ang, fp.w * 0.33, 0, fp.w * 0.3, fp.h * 0.9, shade(fp.colour, 0.82), a)
    box_fill(x, y, ang, fp.w * 0.455, 0, 0.14, fp.h * 0.8, D.C.glass, 0.6 * a)
    -- a lit habitation window on each side, plus the roof vent
    box_fill(x, y, ang, -fp.w * 0.08, fp.h * 0.5 - 0.1, fp.w * 0.5, 0.16, D.C.glass, 0.5 * a)
    box_fill(x, y, ang, -fp.w * 0.08, -fp.h * 0.5 + 0.1, fp.w * 0.5, 0.16, D.C.glass, 0.5 * a)
    box_fill(x, y, ang, -fp.w * 0.16, 0, 1.0, 0.6, shade(fp.colour, 1.25), 0.9 * a)
    tyres(x, y, ang, fp, { -fp.w * 0.3, fp.w * 0.3 })
end

ART.caravan = function(x, y, ang, fp, a)
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, fp.colour, a)
    box_fill(x, y, ang, 0, fp.h * 0.5 - 0.11, fp.w * 0.56, 0.18, D.C.glass, 0.55 * a)
    box_fill(x, y, ang, 0, -fp.h * 0.5 + 0.11, fp.w * 0.56, 0.18, D.C.glass, 0.55 * a)
    box_fill(x, y, ang, -fp.w * 0.2, 0, 0.9, 0.55, shade(fp.colour, 1.22), 0.85 * a)
    box_fill(x, y, ang, -fp.w * 0.42, 0, 0.16, fp.h * 0.45, shade(fp.colour, 0.7), a)
    tyres(x, y, ang, fp, { 0 })
end

ART.car = function(x, y, ang, fp, a)
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, fp.colour, a)
    box_fill(x, y, ang, fp.w * 0.06, 0, fp.w * 0.42, fp.h * 0.86, shade(fp.colour, 1.18), a)
    box_fill(x, y, ang, fp.w * 0.3, 0, 0.14, fp.h * 0.76, D.C.glass, 0.55 * a)
    box_fill(x, y, ang, -fp.w * 0.12, 0, 0.14, fp.h * 0.76, D.C.glass, 0.4 * a)
    tyres(x, y, ang, fp, { -fp.w * 0.3, fp.w * 0.3 }, 0.62)
end

ART.tent = function(x, y, ang, fp, a)
    -- Two slopes off a bright ridge, pegged at the corners, with a dark flap at
    -- one end of the ridge. The first version put a wide dark wedge there and it
    -- read as an arrow, so the opening is now a narrow slot.
    box_fill(x, y, ang, 0, fp.h * 0.22, fp.w, fp.h * 0.5, shade(fp.colour, 1.18), a)
    box_fill(x, y, ang, 0, -fp.h * 0.22, fp.w, fp.h * 0.5, shade(fp.colour, 0.78), a)
    ridge(x, y, ang, -fp.w / 2, fp.w / 2, shade(fp.colour, 1.55), 0.9 * a)
    box_fill(x, y, ang, fp.w * 0.44, 0, 0.5, fp.h * 0.22, shade(fp.colour, 0.3), a)
    set({ 0.16, 0.14, 0.13 }, a * 0.9)
    for _, lx in ipairs({ -1, 1 }) do
        for _, ly in ipairs({ -1, 1 }) do
            local qx, qy = at(x, y, ang, lx * (fp.w / 2 - 0.28), ly * (fp.h / 2 - 0.28))
            love.graphics.circle("fill", qx, qy, 0.12)
        end
    end
end

-- Foliage bumps for a hedge, in the prop's own local frame. Pure and exported
-- because the first version assumed the long axis was x: it took the bump radius
-- from fp.h, so level 2's vertical hedge (0.8 x 34 m) drew ONE green circle of
-- radius 0.75*34 = 25.5 m over the whole site. Anything derived from a hedge
-- must come from its thickness, and anything placed along it from its length.
function D.hedge_bumps(fp)
    local long = math.max(fp.w, fp.h)
    local thick = math.min(fp.w, fp.h)
    local r = thick * 0.38
    -- touching rather than spaced: bumps further apart than their own diameter
    -- read as a dotted line, not as a hedge. Capped so a 60 m boundary does not
    -- cost hundreds of draw calls.
    local step = r * 2.2
    local n = math.max(1, math.min(80, math.floor(long / step)))
    local out = {}
    for i = 0, n - 1 do
        local t = -long / 2 + (i + 0.5) * (long / n)
        local side = ((i % 2 == 0) and 0.1 or -0.1) * thick
        if fp.w >= fp.h then
            out[#out + 1] = { lx = t, ly = side, r = r }
        else
            out[#out + 1] = { lx = side, ly = t, r = r }
        end
    end
    return out
end

ART.hedge = function(x, y, ang, fp, a)
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, fp.colour, a)
    set(shade(fp.colour, 0.7), a)
    love.graphics.setLineWidth(0.06)
    love.graphics.polygon("line", rot_rect(x, y, ang, 0, 0, fp.w, fp.h))
    set(shade(fp.colour, 1.35), a * 0.85)
    for _, bump in ipairs(D.hedge_bumps(fp)) do
        local bx, by = at(x, y, ang, bump.lx, bump.ly)
        love.graphics.circle("fill", bx, by, bump.r)
    end
end

ART.pool = function(x, y, ang, fp, a)
    box_fill(x, y, ang, 0, 0, fp.w, fp.h, shade(fp.colour, 1.7), a)
    box_fill(x, y, ang, 0, 0, fp.w - 0.7, fp.h - 0.7, fp.colour, a)
    set(props.SURFACES.water.colour, 0.55 * a)
    love.graphics.setLineWidth(0.08)
    for i = 1, 3 do
        local ly = -fp.h * 0.25 + (i - 1) * fp.h * 0.25
        local lx = fp.w * 0.16 * ((i % 2 == 0) and 1 or -1)
        local ax, ay = at(x, y, ang, lx - fp.w * 0.12, ly)
        local bx, by = at(x, y, ang, lx + fp.w * 0.12, ly)
        love.graphics.line(ax, ay, bx, by)
    end
end

ART.cone = function(x, y, ang, fp, a)
    set(fp.colour, a)
    love.graphics.circle("fill", x, y, fp.r)
    set({ 1, 0.96, 0.90 }, 0.85 * a)
    love.graphics.setLineWidth(0.08)
    love.graphics.circle("line", x, y, fp.r * 0.55)
end

ART.firepit = function(x, y, ang, fp, a)
    -- A ring of stones around an ember bed. The stones are grey-brown, not
    -- orange: an all-orange disc with a bright centre read as a coin, and a
    -- pool of flame with no ring read as "fire", not "fire pit".
    set({ 0.18, 0.16, 0.15 }, a)
    love.graphics.circle("fill", x, y, fp.r)
    for i = 0, 5 do
        local q = (i / 6) * math.pi * 2
        local sx, sy = at(x, y, ang, math.cos(q) * fp.r * 0.74, math.sin(q) * fp.r * 0.74)
        set(shade({ 0.46, 0.42, 0.38 }, 1.0 + 0.12 * (i % 2)), a)
        love.graphics.circle("fill", sx, sy, fp.r * 0.32)
    end
    set({ 0.30, 0.24, 0.20 }, a)
    love.graphics.circle("fill", x, y, fp.r * 0.5)
    set({ 1.0, 0.62, 0.22 }, a * 0.95)
    love.graphics.circle("fill", x, y, fp.r * 0.28)
end

ART.chair = function(x, y, ang, fp, a)
    -- the seat fills the footprint: a chair whose collision circle is bigger
    -- than its picture is a bump the player cannot see coming
    set(shade(fp.colour, 0.55), a)
    love.graphics.circle("fill", x, y, fp.r)
    box_fill(x, y, ang, 0, 0, fp.r * 1.15, fp.r * 1.15, fp.colour, a)
    box_fill(x, y, ang, -fp.r * 0.62, 0, fp.r * 0.3, fp.r * 1.2, shade(fp.colour, 1.35), a)
end

function D.prop(x, y, ang, fp, alpha)
    local art = ART[fp.kind]
    if art then return art(x, y, ang, fp, alpha or 1) end
    set(fp.colour, alpha)
    if fp.shape == "box" then
        love.graphics.polygon("fill", rot_rect(x, y, ang or 0, 0, 0, fp.w, fp.h))
    else
        love.graphics.circle("fill", x, y, fp.r)
    end
end

-- Ground paint. Under everything, over nothing: a zone has no collision, so it
-- may be overlapped by anything without changing the manoeuvre.
function D.surfaces(lvl)
    for _, zone in ipairs(lvl.surfaces or {}) do
        local def = props.SURFACES[zone.kind]
        if def then
            set(def.colour)
            love.graphics.polygon("fill", flat(geom.rect_poly(zone.x, zone.y, zone.w, zone.h,
                                                            zone.angle or 0)))
        end
    end
end

D.ART = ART

-- The goal, drawn once and used by both the game and the editor. The editor must
-- not have its own idea of what a bay looks like: what you author is what you
-- play, and an editor that draws a plain green rectangle teaches the wrong thing.
--
-- Split in two because the order matters in play: the fill sits under the props
-- and the rig, the arrow sits over them ("it has to be visible when the caravan
-- is parked on top of it").
local function bay_fill(bay, o)
    o = o or {}
    local poly = geom.rect_poly(bay.x, bay.y, bay.w, bay.h, bay.angle)
    local state = o.state or "idle"

    set(D.C.bay, o.fill_alpha or 0.45)
    love.graphics.polygon("fill", flat(poly))
    if state == "wrong" then
        set(D.C.warn, 0.85)
    elseif state == "good" then
        set(D.C.bay_line, 1)
    else
        set(D.C.bay_line, o.line_alpha or 0.55)
    end
    -- widths are in METRES here: the transform multiplies them by px/m, so 0.12
    -- is ~2 px at the game's scale and a "2" would be a 30 px green border
    love.graphics.setLineWidth(o.line or 0.12)
    love.graphics.polygon("line", flat(poly))
    love.graphics.setLineWidth(1)
    return poly
end

-- The bay has a REQUIRED FACING, so it has to show it: without the arrow the
-- same rectangle accepts one orientation and rejects the mirror of it, which
-- reads as a bug rather than as a rule.
local function bay_arrow(bay, o)
    o = o or {}
    local state = o.state or "idle"
    local c, sn = math.cos(bay.angle), math.sin(bay.angle)
    local reach = bay.w * (o.reach or 0.30)
    local head_x, head_y = bay.x + c * reach, bay.y + sn * reach
    local neck_x, neck_y = bay.x + c * reach * 0.45, bay.y + sn * reach * 0.45
    local alpha = (o.alpha or 1) * ((state == "good") and 0.30 or 1.0)
    local acol = state == "wrong" and D.C.warn or D.C.bay_line
    local nx, ny = -sn, c

    -- dark halo underneath, so the arrow survives being drawn over the caravan
    set(D.C.ground, 0.75 * alpha)
    love.graphics.setLineWidth(o.halo or 0.34)
    love.graphics.line(bay.x - c * reach, bay.y - sn * reach, neck_x, neck_y)
    love.graphics.polygon("fill", head_x, head_y,
        neck_x + nx * 0.62, neck_y + ny * 0.62,
        neck_x - nx * 0.62, neck_y - ny * 0.62)
    set(acol, 0.95 * alpha)
    love.graphics.setLineWidth(o.line or 0.18)
    love.graphics.line(bay.x - c * reach, bay.y - sn * reach, neck_x, neck_y)
    love.graphics.polygon("fill", head_x, head_y,
        neck_x + nx * 0.5, neck_y + ny * 0.5,
        neck_x - nx * 0.5, neck_y - ny * 0.5)
    love.graphics.setLineWidth(1)
    return c, sn
end

function D.scene(lvl, s, opts)
    local b = lvl.bounds

    set(D.C.ground)
    love.graphics.rectangle("fill", b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)

    D.surfaces(lvl)

    set(D.C.grid, 0.8)
    love.graphics.setLineWidth(0.02)
    for x = math.ceil(b.x0 / 5) * 5, b.x1, 5 do love.graphics.line(x, b.y0, x, b.y1) end
    for y = math.ceil(b.y0 / 5) * 5, b.y1, 5 do love.graphics.line(b.x0, y, b.x1, y) end

    -- parking bay. The bay has a REQUIRED FACING (bay.angle), so it has to show
    -- it: without the arrow the same rectangle accepts one orientation and
    -- rejects the mirror of it, which reads as a bug rather than a rule.
    local bay = lvl.bay
    local bay_poly = geom.rect_poly(bay.x, bay.y, bay.w, bay.h, bay.angle)
    local vcx, vcy = rig.caravan_centre(s.rig)
    local in_bay = geom.point_in_poly(vcx, vcy, bay_poly)
    local angle_off = math.abs(geom.wrap(s.rig.ph - bay.angle))
    local aligned = angle_off <= bay.tol
    local state = (not in_bay) and "idle" or (aligned and "good" or "wrong")

    bay_fill(bay, { state = state, fill_alpha = s.park_hold > 0 and 0.75 or 0.45 })

    -- walls
    for _, w in ipairs(lvl.walls) do
        local fp = props.footprint(w)
            or { shape = "box", w = w.w, h = w.h, colour = D.C.wall }
        D.prop(w.x, w.y, w.angle or 0, fp, 1)
    end

    -- cones and other knockables: a hit one stays on the ground, dimmed, so the
    -- bump the player paid for keeps explaining itself
    for _, c in ipairs(s.cones) do
        local fp = props.footprint(c) or { shape = "circle", r = c.r, colour = D.C.cone }
        if c.hit then
            D.prop(c.x, c.y, 0, fp, 0.32)
            set(D.C.dim, 0.7)
            love.graphics.setLineWidth(0.08)
            love.graphics.circle("line", c.x, c.y, fp.r * 1.7)
        else
            D.prop(c.x, c.y, 0, fp, 1)
        end
    end

    -- the reversing guide arc: reverse (and at rest) only, see session.guide_visible
    if opts.guide and session.guide_visible(s) then
        local cmd = session.guide_command(s, opts.input)
        local pts = rig.guide(s.rig, cmd, 10, 300)
        set(D.C.guide, 0.6)
        for i = 1, #pts, 10 do
            love.graphics.circle("fill", pts[i][1], pts[i][2], 0.14)
        end
    end

    -- caravan
    local van = rig.caravan_poly(s.rig)
    set(D.C.van)
    love.graphics.polygon("fill", flat(van))
    set(D.C.van_dark)
    love.graphics.setLineWidth(0.07)
    love.graphics.polygon("line", flat(van))

    local cx, cy = rig.coupling_xy(s.rig)
    set(D.C.van_dark, 0.9)
    love.graphics.setLineWidth(0.14)
    love.graphics.line(cx, cy, at(cx, cy, s.rig.ph, -rig.CARAVAN.taper, 0))
    -- hitch tongue across the coupling overhang to the car's rear bumper
    local bx, by = at(s.rig.x, s.rig.y, s.rig.th, -rig.CAR.rear_oh, 0)
    set(D.C.wall_top)
    love.graphics.setLineWidth(0.18)
    love.graphics.line(bx, by, cx, cy)
    -- window band
    set(D.C.glass, 0.5)
    love.graphics.polygon("fill", rot_rect(cx, cy, s.rig.ph, -2.9, 0, 1.5, 1.55))
    -- wheels at the caravan axle
    set(D.C.van_dark)
    love.graphics.polygon("fill", rot_rect(cx, cy, s.rig.ph, -rig.CARAVAN.drawbar, 1.02, 0.62, 0.28))
    love.graphics.polygon("fill", rot_rect(cx, cy, s.rig.ph, -rig.CARAVAN.drawbar, -1.02, 0.62, 0.28))

    -- car
    local car = rig.car_poly(s.rig)
    set(D.C.car)
    love.graphics.polygon("fill", flat(car))
    set(D.C.car_dark)
    love.graphics.setLineWidth(0.07)
    love.graphics.polygon("line", flat(car))
    -- windscreen sits ahead of the front axle, on the nose
    set(D.C.glass, 0.55)
    love.graphics.polygon("fill", rot_rect(s.rig.x, s.rig.y, s.rig.th, rig.CAR.wheelbase - 0.1, 0, 0.55, 1.45))
    set(D.C.glass, 0.35)
    love.graphics.polygon("fill", rot_rect(s.rig.x, s.rig.y, s.rig.th, 0, 0, 0.75, 1.45))

    -- headlights: the nose has to read as the front at 15 px/m
    set(D.C.ray, 0.85)
    for _, side in ipairs({ 1, -1 }) do
        love.graphics.polygon("fill",
            rot_rect(s.rig.x, s.rig.y, s.rig.th, rig.CAR.front_x - 0.12, side * 0.55, 0.16, 0.34))
    end

    -- wheels: rear fixed, front steered about their own centre (rotating about
    -- the car origin would slide them sideways out from under the body)
    set(D.C.tyre)
    for _, side in ipairs({ 1, -1 }) do
        love.graphics.polygon("fill", rot_rect(s.rig.x, s.rig.y, s.rig.th, 0, side * 0.88, 0.62, 0.30))
    end
    local steer_rays = math.abs(s.rig.steer) > math.rad(1)
    for _, side in ipairs({ 1, -1 }) do
        local wx, wy = at(s.rig.x, s.rig.y, s.rig.th, rig.CAR.wheelbase, side * 0.86)
        set(D.C.tyre)
        love.graphics.polygon("fill", rot_rect(wx, wy, s.rig.th + s.rig.steer, 0, 0, 0.62, 0.30))
        -- the wheel plane, extended: the two rays converge on the turn centre,
        -- so the angle is legible at this scale instead of being 3 px of rubber
        if steer_rays then
            local dx, dy = math.cos(s.rig.th + s.rig.steer), math.sin(s.rig.th + s.rig.steer)
            set(D.C.ray, 0.45)
            love.graphics.setLineWidth(0.05)
            love.graphics.line(wx, wy, wx + dx * 2.8, wy + dy * 2.8)
        end
    end

    -- coupling
    set(D.C.wall_top)
    love.graphics.circle("fill", cx, cy, 0.16)

    -- required facing overlay, drawn last so the rig cannot hide it
    -- arrow along the bay axis, pointing the way the
    -- caravan's coupling has to end up
    local c, sn = bay_arrow(bay, { state = state })

    -- ghost of the correct pose, but only while the caravan is sitting in the
    -- bay the wrong way round. Permanent training wheels would give away the
    -- maneuver; this shows up exactly when the player is confused.
    if state == "wrong" then
        local half = rig.CARAVAN.length / 2
        local ghost = geom.poly_world(rig.CARAVAN_BODY, bay.x + half * c, bay.y + half * sn, bay.angle)
        set(D.C.bay_line, 0.16)
        love.graphics.polygon("fill", flat(ghost))
        set(D.C.bay_line, 0.85)
        love.graphics.setLineWidth(0.10)
        love.graphics.polygon("line", flat(ghost))
    end


    if s.bump_flash > 0 then
        set(D.C.warn, math.min(0.35, s.bump_flash))
        love.graphics.rectangle("fill", b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)
    end
end

local function fmt_time(t)
    local m = math.floor(t / 60)
    local sec = t - m * 60
    return string.format("%d:%05.2f", m, sec)
end

-- Speed reads in km/h on screen; the model stays SI. The conversion belongs at
-- the edge, where a human reads it, and it has one home: 1 km/h is 0.28 m/s, so
-- whole kilometres are fine granularity at reversing speeds (0-6 km/h) and keep
-- the readout from twitching in the last digit while the rig creeps.
function D.kmh(v, decimals)
    return string.format("%." .. (decimals or 0) .. "f km/h", math.abs(v or 0) * 3.6)
end

function D.hud(s, game)
    local W, H = love.graphics.getDimensions()

    love.graphics.setFont(fonts.big)
    set(D.C.text)
    love.graphics.print(s.level.name, 24, 18)

    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print(s.level.hint or "", 24, 58)

    love.graphics.setFont(fonts.big)
    set(s.started and D.C.text or D.C.dim)
    local time = fmt_time(s.t)
    love.graphics.print(time, W - 24 - fonts.big:getWidth(time), 18)

    love.graphics.setFont(fonts.small)
    local gear = session.gear(s)
    local gear_color = gear == "R" and D.C.guide or (gear == "D" and D.C.good or D.C.dim)
    set(gear_color)
    love.graphics.print(gear .. "  " .. D.kmh(s.rig.v), W - 24 - 130, 60)
    set(D.C.dim)
    love.graphics.print(string.format("par %ds   bumps %d", s.level.par, s.bumps), W - 24 - 150, 82)

    -- articulation meter: where the jackknife lives
    local art = math.abs(math.deg(rig.art(s.rig)))
    local bw, bh = 260, 12
    local bx, by = 24, H - 46
    set(D.C.wall, 0.9)
    love.graphics.rectangle("fill", bx, by, bw, bh, 3)
    local frac = math.min(1, art / 75)
    set(art > 55 and D.C.warn or (art > 40 and D.C.cone or D.C.good))
    love.graphics.rectangle("fill", bx, by, bw * frac, bh, 3)
    set(D.C.dim)
    love.graphics.rectangle("fill", bx + bw * (45 / 75), by - 3, 2, bh + 6)
    love.graphics.rectangle("fill", bx + bw * (72 / 75), by - 5, 3, bh + 10)
    love.graphics.setFont(fonts.small)
    love.graphics.print(string.format("articulation %.0f deg", art), bx, by - 22)

    -- steering gauge: which way the wheels point, and are they straight
    local gx, gw, gh = bx + bw + 40, 170, bh
    set(D.C.wall, 0.9)
    love.graphics.rectangle("fill", gx, by, gw, gh, 3)
    local gcx = gx + gw / 2
    local frac = s.rig.steer / rig.CAR.max_steer
    set(math.abs(frac) > 0.9 and D.C.cone or D.C.good)
    if math.abs(frac) > 0.01 then
        local dx = (gw / 2 - 2) * frac
        love.graphics.rectangle("fill", math.min(gcx, gcx + dx), by, math.abs(dx), gh, 3)
    end
    set(D.C.text, 0.7)
    love.graphics.rectangle("fill", gcx - 1, by - 3, 2, gh + 6)
    local deg = math.abs(math.deg(s.rig.steer))
    local side = math.abs(frac) < 0.06 and "straight"
        or (s.rig.steer > 0 and "left" or "right")
    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print(string.format("wheels %.0f %s", deg, side), gx, by - 22)

    -- control hints
    local pad = game.input and game.input.last_device == "gamepad"
    local hint = pad
        and "LS/D-pad steer   RT forward   LT brake/reverse   A handbrake   Y guide   B reset   Start pause"
        or "WASD drive   Space handbrake   G guide   R reset   P pause   F1 debug   Esc menu"
    set(D.C.dim, 0.9)
    love.graphics.print(hint, 24, H - 26)

    if game and game.toast and game.toast.expires and love.timer.getTime() < game.toast.expires then
        love.graphics.setFont(fonts.small)
        set(D.C.text, 0.92)
        local t = game.toast.text
        love.graphics.print(t, W / 2 - fonts.small:getWidth(t) / 2, 26)
    end

    if game.paused then
        love.graphics.setFont(fonts.mid)
        set(D.C.text)
        love.graphics.print("PAUSED", W / 2 - 34, H / 2 - 10)
        love.graphics.setFont(fonts.small)
        set(D.C.dim)
        love.graphics.print("P or Start to resume", W / 2 - 62, H / 2 + 16)
    end
end

-- Three pips, filled from the left. A triangle at 14 px reads as a mark where a
-- five-point star reads as noise.
local function pips(x, y, n)
    local r = 6
    for i = 1, 3 do
        local cx = x + (i - 1) * (r * 2 + 7)
        local pts = { cx, y - r, cx - r * 0.95, y + r * 0.75, cx + r * 0.95, y + r * 0.75 }
        if i <= (n or 0) then
            set(D.C.cone)
            love.graphics.polygon("fill", pts)
        else
            set(D.C.dim, 0.55)
            love.graphics.polygon("line", pts)
        end
    end
end

-- The level select. A list with series headings rather than a grid of cards: the
-- headings are derived from the model's series changes, so there is no cursor
-- position that points at a heading, and the whole thing works at any window
-- width with no reflow arithmetic.
function D.menu(model, game)
    local W, H = love.graphics.getDimensions()
    local x = 64
    local y = 44
    -- ask the model, never its fields: the rows belong to the current tab, and
    -- reading model.rows directly was how a whole screen went blank after tabs
    -- were introduced
    local rows = menu.rows(model)
    local cursor = model.index[model.tab]

    love.graphics.setFont(fonts.big)
    set(D.C.text)
    love.graphics.print("TOW YARD", x, y)

    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print("reverse the caravan into the bay", x + 3, y + 44)

    local parked, total = 0, 0
    for _, lvl in ipairs(rows) do
        total = total + 1
        if menu.mark(model, lvl).completed then parked = parked + 1 end
    end
    if total > 0 then
        local text = string.format("%d of %d parked", parked, total)
        love.graphics.print(text, W - x - fonts.small:getWidth(text), y + 44)
    end

    -- the tabs. Two words, one of them underlined: the cheapest way to say "there
    -- is another list over here" without a menu inside a menu.
    local tabs = { { "campaign", "Campaign" }, { "custom", "Custom levels" } }
    local tx = x
    for _, t in ipairs(tabs) do
        local active = (model.tab == t[1])
        love.graphics.setFont(fonts.mid)
        set(active and D.C.text or D.C.dim, active and 1 or 0.7)
        love.graphics.print(t[2], tx, y + 74)
        if active then
            set(D.C.bay_line)
            love.graphics.rectangle("fill", tx, y + 100, fonts.mid:getWidth(t[2]), 2)
        end
        tx = tx + fonts.mid:getWidth(t[2]) + 34
    end

    y = y + 130
    local last_series = nil
    for i, lvl in ipairs(rows) do
        if lvl.series ~= last_series then
            if last_series ~= nil then y = y + 12 end
            love.graphics.setFont(fonts.small)
            set(D.C.dim)
            love.graphics.print(string.upper(lvl.series or "custom"), x, y)
            y = y + 30
            last_series = lvl.series
        end

        local mark = menu.mark(model, lvl)
        local selected = (i == cursor)
        local right = W - x - 10

        if selected then
            set(D.C.bay_line, 0.13)
            love.graphics.rectangle("fill", x - 16, y - 7, W - (x - 16) * 2, 40, 8)
            set(D.C.bay_line)
            love.graphics.rectangle("line", x - 16, y - 7, W - (x - 16) * 2, 40, 8)
        end

        love.graphics.setFont(fonts.mid)
        set(D.C.text, mark.completed and 1 or 0.78)
        love.graphics.print(lvl.name, x + 4, y)

        -- a stale row has no stars to show, and the warning text needs the room:
        -- drawing empty pips there put "level changed" on top of them
        if not mark.stale then pips(W - 300, y + 13, mark.stars) end

        love.graphics.setFont(fonts.small)
        if mark.stale then
            -- a level that changed under the player's time: say so, do not show
            -- a number earned on geometry that no longer exists
            set(D.C.cone, 0.9)
            local text = "level changed"
            love.graphics.print(text, right - 108 - fonts.small:getWidth(text), y + 5)
        elseif mark.best then
            set(D.C.dim)
            local text = fmt_time(mark.best)
            love.graphics.print(text, right - 108 - fonts.small:getWidth(text), y + 5)
        end

        if mark.completed then
            set(D.C.good, mark.stale and 0.35 or 0.9)
            local tx = right - 96
            love.graphics.line(tx, y + 13, tx + 5, y + 19, tx + 13, y + 5)
        end

        y = y + 46
    end

    if total == 0 then
        love.graphics.setFont(fonts.mid)
        set(D.C.text, 0.9)
        if model.tab == "custom" then
            love.graphics.print("No custom levels yet.", x, y)
            love.graphics.setFont(fonts.small)
            set(D.C.dim)
            love.graphics.print("I pastes a share code, or drop a .towyard file on the window.", x, y + 30)
            love.graphics.print("They live in " .. love.filesystem.getSaveDirectory() .. "/custom/", x, y + 50)
        else
            love.graphics.print("No levels.", x, y)
        end
    end

    love.graphics.setFont(fonts.small)
    set(D.C.dim, 0.9)
    local pad = game and game.input and game.input.last_device == "gamepad"
    local hint
    if game and game.confirm_delete then
        set(D.C.warn, 0.95)
        hint = "delete " .. tostring(game.confirm_delete.name) .. "?    Enter confirms    Esc cancels"
        love.graphics.print(hint, x, H - 30)
        return
    end
    if pad then
        hint = "D-pad choose    A open    LB/RB tab    B quit"
    elseif model.tab == "custom" then
        hint = "W/S choose    Enter open    Tab switch tab    X delete    I paste a code    Esc quit"
    else
        hint = "W/S choose    Enter open    Tab switch tab    Esc quit"
    end
    love.graphics.print(hint, x, H - 30)
end

-- The ghost. Two modes, because one is honest and one is comfortable: the trail
-- shows where the caravan's tail has been (legible in a 6.8 m alley, where a
-- 35% alpha caravan sits exactly on top of yours), and `rig` shows the shape
-- itself when there is room to see it.
-- Violet, not the guide's blue: the reversing assist is the player's own line
-- and the ghost is somebody else's, and two blue lines on one yard read as one
-- system until you have watched them both move.
D.GHOST = { 0.74, 0.46, 0.88 }

function D.ghost(ghost, mode)
    if mode == "rig" then
        local rigged = ghost.s.rig
        local van = rig.caravan_poly(rigged)
        local car = rig.car_poly(rigged)

        -- A silhouette, not a diagram: one flat shape per body, plus the hitch
        -- between them so it reads as a rig. Widths are METRES here (the transform
        -- multiplies them), which is why the trail used to be a 30 px rope.
        set(D.GHOST, 0.24)
        love.graphics.polygon("fill", flat(van))
        love.graphics.polygon("fill", flat(car))

        set(D.GHOST, 0.10)
        love.graphics.setLineWidth(0.10)
        love.graphics.polygon("line", flat(van))
        love.graphics.polygon("line", flat(car))
        local hx, hy = rig.coupling_xy(rigged)
        local bx, by = at(rigged.x, rigged.y, rigged.th, -rig.CAR.rear_oh, 0)
        love.graphics.line(hx, hy, bx, by)
        love.graphics.setLineWidth(1)
        return
    end

    local pts = ghost.trail or {}
    local upto = math.min(#pts, math.ceil((ghost.step or 0) / 6))
    if upto >= 2 then
        local line = {}
        for i = 1, upto do
            line[#line + 1] = pts[i][1]
            line[#line + 1] = pts[i][2]
        end
        set(D.GHOST, 0.5)
        love.graphics.setLineWidth(0.12)   -- 2 px at the game's scale, not 30
        love.graphics.line(line)
        love.graphics.setLineWidth(1)
    end
    if pts[upto] then
        set(D.GHOST, 0.85)
        love.graphics.circle("fill", pts[upto][1], pts[upto][2], 0.30)
    end
end

-- ---------------------------------------------------------------- editor
--
-- The editor's world view. It draws AUTHORED data (what the file says), not the
-- resolved level, because the point of the screen is to show what you are
-- about to write: a hedge with no numbers is still a hedge of its default size,
-- but the moment you resize it the numbers appear in the file.

-- Corner brackets instead of a rectangle. A full frame drawn at the prop's own
-- edge hides the very thing you are lining up: the first version was a 3 px
-- solid orange box 0.25 m outside the footprint, which at 15 px/m is a frame you
-- cannot see through. Four short L's say "this one" and leave the middle clear.
local function brackets(poly, arm, wide)
    arm, wide = arm or 0.8, wide or 0.1
    local n = #poly / 2
    love.graphics.setLineWidth(wide)
    for k = 0, n - 1 do
        local i = k * 2
        local x, y = poly[i + 1], poly[i + 2]
        local pi = ((k - 1) % n) * 2
        local ni = ((k + 1) % n) * 2
        local px, py = poly[pi + 1], poly[pi + 2]
        local nx, ny = poly[ni + 1], poly[ni + 2]
        -- arms are a LENGTH in metres, clamped to the edge they run along, so a
        -- small prop gets brackets of its own size instead of brackets bigger
        -- than the prop
        local lp = math.min(arm, math.sqrt((px - x) ^ 2 + (py - y) ^ 2) * 0.45)
        local ln = math.min(arm, math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2) * 0.45)
        love.graphics.line(x, y, x + (px - x) / math.max(1e-9, math.sqrt((px - x) ^ 2 + (py - y) ^ 2)) * lp,
            y + (py - y) / math.max(1e-9, math.sqrt((px - x) ^ 2 + (py - y) ^ 2)) * lp)
        love.graphics.line(x, y, x + (nx - x) / math.max(1e-9, math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)) * ln,
            y + (ny - y) / math.max(1e-9, math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)) * ln)
    end
    love.graphics.setLineWidth(1)
end

local function safe_handles(doc)
    local ok, handles = pcall(function() return editdoc.resize_handles(doc) end)
    return ok and handles or {}
end

-- Snapping is a placement rule, so it lives where the ghost preview needs it; the
-- click in main.lua snaps the same way with the same step.
local function snap_to(state, x, y)
    local step = state and state.snap
    if not step or step <= 0 then return x, y end
    return math.floor(x / step + 0.5) * step, math.floor(y / step + 0.5) * step
end

function D.editor_world(doc, state)
    local lvl = doc.level
    local b = lvl.bounds
    -- Line widths are multiplied by the camera scale: a "2" is 30 px at 15 px/m.
    -- Everything below is expressed in screen pixels and divided back by the
    -- zoom, so the border is the same border at 6 px/m and at 40 px/m.
    local scale = (state and state.cam and state.cam.scale) or 15
    local u = 1 / scale

    set(D.C.ground)
    love.graphics.rectangle("fill", b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)

    D.surfaces(lvl)

    -- The grid goes OVER the paint: a dressed level covers its whole yard with
    -- surfaces, so a grid drawn first is a grid nobody ever sees (it was, on the
    -- first frame of this screen). 1 m thin, 5 m brighter, because a level is
    -- authored in metres and nothing else.
    love.graphics.setLineWidth(u)
    for x = math.ceil(b.x0), math.floor(b.x1) do
        local major = (math.floor(x + 0.5) % 5 == 0)
        set(D.C.text, major and 0.24 or 0.10)
        love.graphics.line(x, b.y0, x, b.y1)
    end
    for y = math.ceil(b.y0), math.floor(b.y1) do
        local major = (math.floor(y + 0.5) % 5 == 0)
        set(D.C.text, major and 0.24 or 0.10)
        love.graphics.line(b.x0, y, b.x1, y)
    end
    love.graphics.setLineWidth(1)

    for _, w in ipairs(lvl.walls or {}) do
        local fp = props.footprint(w)
        if fp then D.prop(w.x, w.y, w.angle or 0, fp) end
    end
    for _, c in ipairs(lvl.cones or {}) do
        local fp = props.footprint(c)
        if fp then D.prop(c.x, c.y, c.angle or 0, fp) end
    end

    -- the goal, drawn by the same function the game uses: same fill, same
    -- outline, same required-facing arrow. Authoring must look like playing.
    local bay = lvl.bay
    bay_fill(bay, { line = 2 * u, line_alpha = 0.7 })
    bay_arrow(bay, { line = 2 * u, halo = 4 * u })

    -- where the rig starts, and which way it points. An outlined car, not a
    -- filled one: at 15 px/m a filled car is a 65 x 30 px slab of warm colour
    -- sitting in the middle of the yard you are trying to author.
    local rigged = rig.new(lvl.spawn.x, lvl.spawn.y, lvl.spawn.th)
    local car = rig.car_poly(rigged)
    set(D.C.car, 0.10)
    love.graphics.polygon("fill", flat(car))
    set(D.C.car, 0.95)
    love.graphics.setLineWidth(2 * u)
    love.graphics.polygon("line", flat(car))
    set(D.C.text, 0.85)
    love.graphics.line(lvl.spawn.x, lvl.spawn.y,
        lvl.spawn.x + 2.2 * math.cos(lvl.spawn.th),
        lvl.spawn.y + 2.2 * math.sin(lvl.spawn.th))
    local nx, ny = -math.sin(lvl.spawn.th), math.cos(lvl.spawn.th)
    local hx = lvl.spawn.x + 2.6 * math.cos(lvl.spawn.th)
    local hy = lvl.spawn.y + 2.6 * math.sin(lvl.spawn.th)
    love.graphics.polygon("fill", hx, hy,
        hx - 0.7 * math.cos(lvl.spawn.th) + 0.35 * nx, hy - 0.7 * math.sin(lvl.spawn.th) + 0.35 * ny,
        hx - 0.7 * math.cos(lvl.spawn.th) - 0.35 * nx, hy - 0.7 * math.sin(lvl.spawn.th) - 0.35 * ny)
    love.graphics.setLineWidth(1)

    -- what a click would put down, drawn faintly under the cursor: the cheapest
    -- possible answer to "how do I add something"
    if state and state.tool and state.tool ~= "select" then
        local mx, my = love.mouse.getPosition()
        if mx > D.RAIL then
            local W, H = love.graphics.getDimensions()
            local sx, sy = snap_to(state, state.cam.x + (mx - W / 2) / scale,
                state.cam.y - (my - H / 2) / scale)
            local def = props.get(state.tool)
            if def then
                local fp = props.footprint({ kind = state.tool, x = sx, y = sy })
                if fp then D.prop(sx, sy, 0, fp, 0.34) end
            elseif props.SURFACES[state.tool] then
                local col = props.SURFACES[state.tool].colour
                set({ col[1], col[2], col[3] }, 0.5)
                love.graphics.rectangle("fill", sx - 3, sy - 2, 6, 4)
            end
        end
    end

    -- resize handles, if this kind can be stretched at all: a small filled square
    -- at each grab point, sized in screen pixels like everything else here
    set(D.C.cone)
    for _, h in ipairs(safe_handles(doc)) do
        love.graphics.rectangle("fill", h.x - 4 * u, h.y - 4 * u, 8 * u, 8 * u)
    end

    -- the selection, drawn last so nothing sits on top of it
    local sel = doc.selection
    if sel then
        -- 10 px arms, 1.5 px wide, whatever the zoom: the frame says "this one"
        -- and gives the element back the moment you stop looking at it
        set(D.C.cone)
        local arm, wide = 10 * u, 1.5 * u + 0
        if sel.list == "bay" then
            brackets(flat(geom.rect_poly(bay.x, bay.y, bay.w, bay.h, bay.angle)), arm, wide)
        elseif sel.list == "spawn" then
            love.graphics.setLineWidth(wide)
            love.graphics.circle("line", lvl.spawn.x, lvl.spawn.y, 1.6)
        else
            local entry = (lvl[sel.list] or {})[sel.index]
            local fp = entry and props.footprint(entry)
            if fp then
                if fp.shape == "circle" then
                    love.graphics.setLineWidth(wide)
                    love.graphics.circle("line", entry.x, entry.y, fp.r + 0.05)
                else
                    brackets(flat(geom.rect_poly(entry.x, entry.y, fp.w, fp.h,
                        entry.angle or 0)), arm, wide)
                end
            end
        end
        love.graphics.setLineWidth(1)
    end
end

-- The rails: what is selected, what is wrong, and every key that does something.
-- Text rather than icons, because the editor is a dev tool first and an icon
-- toolkit is a week of work for a screen four people will use.
D.RAIL = 232            -- width of the tool rail, in pixels
local TOOL_Y, TOOL_ROW = 156, 22

-- Which tool is under the cursor. The rail is clickable because telling somebody
-- to cycle a palette with [ and ] is not telling them how to add a prop: the
-- first thing three people asked was "how do I put something down".
function D.editor_tool_at(x, y, palette)
    if x > D.RAIL or y < TOOL_Y then return nil end
    local i = math.floor((y - TOOL_Y) / TOOL_ROW) + 1
    return (palette or {})[i]
end

function D.editor_ui(doc, state, game)
    local W, H = love.graphics.getDimensions()
    local a = (state and state.alpha) or 0.92

    love.graphics.setColor(0.04, 0.04, 0.05, 0.88)
    love.graphics.rectangle("fill", 0, 0, D.RAIL, H)
    love.graphics.rectangle("fill", 0, H - 92, W, 92)

    -- the level's own name, big enough to read: it is what you are authoring
    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print("TOW YARD  editor", 16, 14)
    love.graphics.setFont(fonts.mid)
    if state and state.typing then
        set(D.C.bay_line)
        love.graphics.print(state.typing.buffer .. "|", 16, 44)
        love.graphics.setFont(fonts.small)
        set(D.C.dim, 0.8)
        love.graphics.print("Enter keeps   Esc cancels", 16, 82)
    else
        set(D.C.text)
        love.graphics.print(tostring(doc.level.name or "?"), 16, 44)
        love.graphics.setFont(fonts.small)
        set(D.C.dim, 0.8)
        love.graphics.print("F2 rename    " .. tostring(doc.level.id), 16, 82)
    end

    love.graphics.setFont(fonts.small)
    set(D.C.dim, 0.9)
    love.graphics.print("add: pick a tool, then click the yard", 16, 108)
    set(D.C.text)
    love.graphics.print("TOOLS", 16, 136)

    -- the editor's own toasts: saved / renamed / copied. These were drawn only by
    -- the play HUD, so every message the editor said went nowhere.
    if game and game.toast and game.toast.expires and love.timer.getTime() < game.toast.expires then
        love.graphics.setFont(fonts.small)
        set(D.C.text, 0.92)
        local t = game.toast.text
        love.graphics.print(t, D.RAIL + (W - D.RAIL - fonts.small:getWidth(t)) / 2, 18)
    end

    local mx, my = love.mouse.getPosition()
    local hovered = D.editor_tool_at(mx, my, state.palette)

    local y = TOOL_Y
    for _, name in ipairs(state.palette or {}) do
        local active = (name == state.tool)
        if active then
            set(D.C.bay_line, 0.22)
            love.graphics.rectangle("fill", 10, y - 3, D.RAIL - 20, TOOL_ROW, 4)
        elseif name == hovered then
            set(D.C.text, 0.07)
            love.graphics.rectangle("fill", 10, y - 3, D.RAIL - 20, TOOL_ROW, 4)
        end
        set(active and D.C.bay_line or D.C.dim, active and 1 or 0.85)
        -- the kind is what the file says; the label is what the thing is. Show
        -- both when they differ, or a level reads as a list of nouns.
        local def = props.get(name)
        local text = name
        if def and def.label and def.label ~= name then text = name .. "  " .. def.label end
        love.graphics.print(text, 18, y)
        y = y + TOOL_ROW
    end

    y = y + 6
    set(D.C.dim)
    love.graphics.print("snap " .. ((state.snap and state.snap > 0) and (state.snap .. " m") or "off"), 18, y)
    if doc.selection then
        local mode = editdoc.resize_mode(doc)
        if mode == "none" then
            y = y + 16
            set(D.C.warn, 0.85)
            love.graphics.print("this kind has one size", 18, y)
        elseif mode == "length" then
            y = y + 16
            set(D.C.dim, 0.8)
            love.graphics.print("stretches along its length only", 18, y)
        end
    end

    y = y + 12
    set(D.C.text, 0.9)
    love.graphics.print("SELECTION", 16, y)
    y = y + 22
    set(D.C.dim)
    local sel = doc.selection
    if sel then
        local entry = (doc.level[sel.list] or {})[sel.index]
        if entry then
            love.graphics.print(string.format("%s %d  %.1f, %.1f",
                sel.list, sel.index, entry.x, entry.y), 18, y)
        else
            love.graphics.print(tostring(sel.list), 18, y)
        end
    else
        love.graphics.print("nothing", 18, y)
    end

    y = y + 26
    set(D.C.text, 0.9)
    love.graphics.print("ERRORS", 16, y)
    y = y + 22
    local errors = (state and state.errors) or {}
    if #errors == 0 then
        set(D.C.good, 0.9)
        love.graphics.print("none  -  savable", 18, y)
    else
        set(D.C.warn, 0.95)
        for i = 1, math.min(3, #errors) do
            love.graphics.print(errors[i], 18, y)
            y = y + 18
        end
        if #errors > 3 then love.graphics.print("+" .. (#errors - 3) .. " more", 18, y) end
    end

    love.graphics.setFont(fonts.small)
    set(D.C.dim, a)
    local hint = "[ ] tool   click add   drag move   Q/E rotate   drag a handle to size   "
        .. "Del remove   ctrl+Z undo   G snap   wheel zoom"
    love.graphics.print(hint, 16, H - 52)
    set(D.C.text, 0.85)
    local keys = "V verify   P play   S save   L levels.lua   O share   F2 name   Esc select"
    love.graphics.print(keys, 16, H - 28)

    love.graphics.setFont(fonts.small)
    if state and state.typing then
        -- the caret is a bar, not a blinking cursor: this is a one-line field
        set(D.C.bay_line)
        love.graphics.print("NAME  " .. state.typing.buffer .. "|", W - 420, 14)
        set(D.C.dim, 0.7)
        love.graphics.print("Enter keeps   Esc cancels", W - 420, 32)
    else
        set(D.C.dim, 0.9)
        love.graphics.print(string.format("%s  %s  %.0f px/m", tostring(doc.level.name),
            tostring(doc.level.id), (state and state.cam and state.cam.scale) or 0), W - 420, 14)
    end
end

-- The question the editor has to ask before it lets go of your work. Drawn over
-- the canvas but under the rails, so the level stays visible while you decide.
function D.editor_prompt(state, game)
    if not state or not state.prompt then return end
    local W, H = love.graphics.getDimensions()
    local box_w, box_h = 460, 116
    local x, y = (W - box_w) / 2, (H - box_h) / 2

    love.graphics.setColor(0.02, 0.02, 0.03, 0.72)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(0.07, 0.08, 0.09, 0.98)
    love.graphics.rectangle("fill", x, y, box_w, box_h, 6)
    set(D.C.text)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, box_w, box_h, 6)

    love.graphics.setFont(fonts.mid)
    love.graphics.print("Unsaved changes", x + 20, y + 16)
    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print("S  save to custom levels", x + 20, y + 50)
    love.graphics.print("Esc  leave without saving (a copy is kept in drafts/)", x + 20, y + 70)
    love.graphics.print("Enter  keep editing", x + 20, y + 90)
end

function D.overlay(s, game)
    local W = love.graphics.getWidth()
    local w, h = 360, 196
    local x, y = W - w - 24, 118
    love.graphics.setColor(D.C.panel)
    love.graphics.rectangle("fill", x, y, w, h, 10)
    set(D.C.bay_line)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 10)

    love.graphics.setFont(fonts.big)
    set(D.C.good)
    love.graphics.print("PARKED", x + 22, y + 14)

    if game and game.new_best then
        love.graphics.setFont(fonts.small)
        set(D.C.cone)
        local text = "NEW BEST"
        if game.gain and game.gain > 0.005 then
            text = text .. string.format("   -%.2f s", game.gain)
        end
        love.graphics.print(text, x + 22, y + 46)
    end

    love.graphics.setFont(fonts.mid)
    set(D.C.text)
    love.graphics.print("time  " .. fmt_time(s.final.time), x + 22, y + 66)
    love.graphics.print("bumps " .. s.final.bumps, x + 22, y + 94)
    love.graphics.print(string.format("angle %.1f deg", s.final.angle_err), x + 22, y + 122)

    local stars = session.grade(s)
    set(D.C.cone)
    love.graphics.print(string.rep("*", stars) .. string.rep("-", 3 - stars), x + 230, y + 66)

    love.graphics.setFont(fonts.small)
    set(D.C.dim)
    love.graphics.print("R retry    N next level", x + 22, y + h - 30)
end

function D.debug(s, game)
    local W, H = love.graphics.getDimensions()
    local pad = game.input and game.input.last_device or "?"
    local lines = {
        string.format("art %.1f deg   steer %.1f deg   v %s",
            math.deg(rig.art(s.rig)), math.deg(s.rig.steer), D.kmh(s.rig.v, 1)),
        string.format("park_hold %.2f   dwell %.2f   device %s", s.park_hold, s.dwell, pad),
        string.format("x %.2f  y %.2f  th %.1f  ph %.1f", s.rig.x, s.rig.y,
            math.deg(s.rig.th), math.deg(s.rig.ph)),
        string.format("bump %s   jackknife %.0f deg", tostring(s.last_bump), math.deg(rig.TUNE.jackknife)),
        string.format("%d fps   dt %.1f ms   %d draw calls", love.timer.getFPS(),
            love.timer.getDelta() * 1000, love.graphics.getStats().drawcalls),
        "pad: " .. input.pad_status(game.input or {}),
    }
    love.graphics.setFont(fonts.small)
    for i, line in ipairs(lines) do
        local tw = fonts.small:getWidth(line)
        set(D.C.panel)
        love.graphics.rectangle("fill", W - tw - 34, 104 + (i - 1) * 18, tw + 18, 18, 3)
        set(D.C.text)
        love.graphics.print(line, W - tw - 26, 106 + (i - 1) * 18)
    end
end

return D
