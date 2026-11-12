-- Pure 2D geometry: angle wrapping, polygon transforms, SAT overlap, containment.
-- No love.* anywhere in this module.

local M = {}

function M.wrap(a)
    a = a % (2 * math.pi)
    if a > math.pi then a = a - 2 * math.pi end
    return a
end

-- Points are { x, y } arrays. Entities are tables with named fields.

function M.poly_world(pts, x, y, ang)
    local c, s = math.cos(ang), math.sin(ang)
    local out = {}
    for i = 1, #pts do
        local p = pts[i]
        out[i] = { x + p[1] * c - p[2] * s, y + p[1] * s + p[2] * c }
    end
    return out
end

function M.rect_poly(x, y, w, h, ang)
    ang = ang or 0
    local hw, hh = w / 2, h / 2
    local c, s = math.cos(ang), math.sin(ang)
    local pts = { { -hw, -hh }, { hw, -hh }, { hw, hh }, { -hw, hh } }
    local out = {}
    for i = 1, #pts do
        out[i] = { x + pts[i][1] * c - pts[i][2] * s, y + pts[i][1] * s + pts[i][2] * c }
    end
    return out
end

local function axes(poly)
    local out = {}
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        local ex, ey = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(ex * ex + ey * ey)
        if len > 0 then out[#out + 1] = { -ey / len, ex / len } end
    end
    return out
end

local function project(poly, ax, ay)
    local mn, mx = math.huge, -math.huge
    for i = 1, #poly do
        local d = poly[i][1] * ax + poly[i][2] * ay
        if d < mn then mn = d end
        if d > mx then mx = d end
    end
    return mn, mx
end

-- Separating axis theorem for convex polygons.
function M.overlap(a, b)
    for _, poly in ipairs({ a, b }) do
        for _, ax in ipairs(axes(poly)) do
            local amin, amax = project(a, ax[1], ax[2])
            local bmin, bmax = project(b, ax[1], ax[2])
            if amax <= bmin or bmax <= amin then return false end
        end
    end
    return true
end

function M.point_in_poly(px, py, poly)
    local sign = 0
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        local cross = (b[1] - a[1]) * (py - a[2]) - (b[2] - a[2]) * (px - a[1])
        local s = cross >= 0 and 1 or -1
        if sign == 0 then
            sign = s
        elseif s ~= sign then
            return false
        end
    end
    return true
end

function M.poly_in_poly(inner, outer)
    for i = 1, #inner do
        if not M.point_in_poly(inner[i][1], inner[i][2], outer) then return false end
    end
    return true
end

-- Is the whole polygon inside the axis-aligned rectangle? Used to treat a
-- level's `bounds` as a real wall: `bounds` otherwise only sizes the camera, so
-- the rig drives straight out of the world with nothing to stop it.
function M.poly_in_rect(poly, x0, y0, x1, y1)
    for i = 1, #poly do
        local x, y = poly[i][1], poly[i][2]
        if x < x0 or x > x1 or y < y0 or y > y1 then return false end
    end
    return true
end

local function seg_dist2(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local wx, wy = px - ax, py - ay
    local len2 = vx * vx + vy * vy
    local t = 0
    if len2 > 0 then t = math.max(0, math.min(1, (wx * vx + wy * vy) / len2)) end
    local dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return dx * dx + dy * dy
end

function M.circle_overlap_poly(cx, cy, r, poly)
    if M.point_in_poly(cx, cy, poly) then return true end
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        if seg_dist2(cx, cy, a[1], a[2], b[1], b[2]) <= r * r then return true end
    end
    return false
end

return M
