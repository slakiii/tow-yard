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

local session = require("lib.session")

-- A parked session at a chosen clock reading, produced the way the game
-- produces one: put the caravan in the bay and let check_park accept it after
-- its hold. The handbrake keeps the clock still, so `t` is the time the run
-- "took". A fixture that set `parked = true` by hand could not tell you whether
-- the code reads the real state.
function F.parked(lvl, t)
    local s = session.new(lvl)
    session.place_caravan(s, lvl.bay.x, lvl.bay.y, lvl.bay.angle)
    s.t = t or 0
    local hold = { steer = 0, throttle = 0, brake = 0, handbrake = true }
    for _ = 1, 60 do session.update(s, hold, 1 / 120) end
    return s
end

-- An in-memory filesystem for the modules that take an injected disk.
function F.fake_disk(files)
    local disk = { files = files or {}, writes = 0 }
    function disk.read(name) return disk.files[name] end
    function disk.write(name, data)
        disk.files[name] = data
        disk.writes = disk.writes + 1
    end
    function disk.remove(name) disk.files[name] = nil end
    return disk
end

function F.deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = F.deep_copy(val) end
    return out
end

return F
