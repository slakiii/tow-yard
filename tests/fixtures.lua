-- Synthetic levels for mechanic tests: an empty field with the bay parked far
-- away, so a test can add exactly the wall or cone it is about.

local F = {}

function F.field()
    return {
        name = "fixture",
        bounds = { x0 = -50, y0 = -50, x1 = 50, y1 = 50 },
        spawn = { x = 0, y = 0, th = 0 },
        bay = { x = 40, y = 40, w = 20, h = 20, angle = 0, tol = math.rad(6) },
        walls = {},
        cones = {},
        par = 10,
        apron = 0,
    }
end

function F.deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = F.deep_copy(val) end
    return out
end

return F
