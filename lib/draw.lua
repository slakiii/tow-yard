-- Rendering. Flat colours only: no assets, so the skeleton stays readable and
-- a level is nothing but data.

local geom = require("lib.geom")
local rig = require("lib.rig")
local session = require("lib.session")

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

function D.scene(lvl, s, opts)
    local b = lvl.bounds

    set(D.C.ground)
    love.graphics.rectangle("fill", b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)

    set(D.C.grid, 0.8)
    love.graphics.setLineWidth(0.02)
    for x = math.ceil(b.x0 / 5) * 5, b.x1, 5 do love.graphics.line(x, b.y0, x, b.y1) end
    for y = math.ceil(b.y0 / 5) * 5, b.y1, 5 do love.graphics.line(b.x0, y, b.x1, y) end

    -- parking bay
    local bay = geom.rect_poly(lvl.bay.x, lvl.bay.y, lvl.bay.w, lvl.bay.h, lvl.bay.angle)
    set(D.C.bay, s.park_hold > 0 and 0.75 or 0.45)
    love.graphics.polygon("fill", flat(bay))
    set(D.C.bay_line)
    love.graphics.setLineWidth(0.12)
    love.graphics.polygon("line", flat(bay))

    -- walls
    for _, w in ipairs(lvl.walls) do
        local wp = geom.rect_poly(w.x, w.y, w.w, w.h, w.angle or 0)
        set(D.C.wall)
        love.graphics.polygon("fill", flat(wp))
        set(D.C.wall_top, 0.6)
        love.graphics.setLineWidth(0.06)
        love.graphics.polygon("line", flat(wp))
    end

    -- cones
    for _, c in ipairs(s.cones) do
        if c.hit then set(D.C.dim, 0.45) else set(D.C.cone) end
        love.graphics.circle("fill", c.x, c.y, c.r)
    end

    -- the reversing guide arc
    if opts.guide then
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
    set(D.C.glass, 0.55)
    love.graphics.polygon("fill", rot_rect(s.rig.x, s.rig.y, s.rig.th, 0.35, 0, 1.1, 1.45))
    -- wheels, steered on the front axle
    set(D.C.car_dark)
    for _, side in ipairs({ 1, -1 }) do
        love.graphics.polygon("fill", rot_rect(s.rig.x, s.rig.y, s.rig.th, 0, side * 0.86, 0.62, 0.26))
        love.graphics.polygon("fill",
            rot_rect(s.rig.x, s.rig.y, s.rig.th + s.rig.steer, rig.CAR.wheelbase, side * 0.86, 0.62, 0.26))
    end

    -- coupling
    set(D.C.wall_top)
    love.graphics.circle("fill", cx, cy, 0.16)

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

    -- control hints
    local pad = game.input and game.input.last_device == "gamepad"
    local hint = pad
        and "LS steer   RT forward   LT brake/reverse   A handbrake   Y guide   B reset   Start pause"
        or "WASD drive   Space handbrake   G guide   R reset   F1 debug   Esc quit"
    set(D.C.dim, 0.9)
    love.graphics.print(hint, 24, H - 26)
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
