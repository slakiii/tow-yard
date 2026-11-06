-- Rendering. Flat colours only: no assets, so the skeleton stays readable and
-- a level is nothing but data. Scenery is drawn per `kind` (see lib/props.lua)
-- from polygons and primitives in the same world frame as everything else --
-- no sprite sheets, and the shape you see is the shape the collision test used.

local geom = require("lib.geom")
local rig = require("lib.rig")
local session = require("lib.session")
local input = require("lib.input")
local props = require("lib.props")

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

    set(D.C.bay, s.park_hold > 0 and 0.75 or 0.45)
    love.graphics.polygon("fill", flat(bay_poly))
    if state == "wrong" then
        set(D.C.warn, 0.85)
    elseif state == "good" then
        set(D.C.bay_line, 1)
    else
        set(D.C.bay_line, 0.55)
    end
    love.graphics.setLineWidth(0.12)
    love.graphics.polygon("line", flat(bay_poly))

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
    local c, sn = math.cos(bay.angle), math.sin(bay.angle)
    local reach = bay.w * 0.30
    local head_x, head_y = bay.x + c * reach, bay.y + sn * reach
    local neck_x, neck_y = bay.x + c * reach * 0.45, bay.y + sn * reach * 0.45
    local arrow_alpha = (state == "good") and 0.30 or 1.0
    local acol = state == "wrong" and D.C.warn or D.C.bay_line
    local nx, ny = -sn, c
    -- dark halo underneath, so the arrow survives being drawn over the caravan
    set(D.C.ground, 0.75 * arrow_alpha)
    love.graphics.setLineWidth(0.34)
    love.graphics.line(bay.x - c * reach, bay.y - sn * reach, neck_x, neck_y)
    love.graphics.polygon("fill", head_x, head_y,
        neck_x + nx * 0.62, neck_y + ny * 0.62,
        neck_x - nx * 0.62, neck_y - ny * 0.62)
    set(acol, 0.95 * arrow_alpha)
    love.graphics.setLineWidth(0.18)
    love.graphics.line(bay.x - c * reach, bay.y - sn * reach, neck_x, neck_y)
    love.graphics.polygon("fill", head_x, head_y,
        neck_x + nx * 0.5, neck_y + ny * 0.5,
        neck_x - nx * 0.5, neck_y - ny * 0.5)

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
    love.graphics.print(gear .. "  " .. string.format("%.1f m/s", math.abs(s.rig.v)),
                        W - 24 - 110, 60)
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
        or "WASD drive   Space handbrake   G guide   R reset   P pause   F1 debug   Esc quit"
    set(D.C.dim, 0.9)
    love.graphics.print(hint, 24, H - 26)

    if game.paused then
        love.graphics.setFont(fonts.mid)
        set(D.C.text)
        love.graphics.print("PAUSED", W / 2 - 34, H / 2 - 10)
        love.graphics.setFont(fonts.small)
        set(D.C.dim)
        love.graphics.print("P or Start to resume", W / 2 - 62, H / 2 + 16)
    end
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
        string.format("art %.1f deg   steer %.1f deg   v %.2f m/s",
            math.deg(rig.art(s.rig)), math.deg(s.rig.steer), s.rig.v),
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
