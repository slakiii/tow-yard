-- The portable level document: a level as text, and back.
--
-- Two rules shape the format:
--   * The document is the AUTHORED data. A size that is already the kind's
--     default is not written out, so `wall building 8 33` reads as "the
--     clubhouse is there" instead of three numbers nobody chose. resolve()
--     fills the defaults back in on the way in.
--   * Encoding is canonical: the same level always produces the same bytes.
--     A content hash is computed over the resolved level, but a document that
--     reshuffled its own whitespace would still make diffs and share codes
--     useless.
--
-- Angles are degrees in the file and radians in memory: 90 is readable, and
-- 1.570796 is a question.
--
-- Not implemented here yet (Task 4): the caps and the strict type checks that
-- make a hostile document harmless. Today the parser rejects a bad header, an
-- unknown key and a malformed number, which is what the round trip needs.

local props = require("lib.props")

local M = {}

M.VERSION = 1
M.HEADER = "TOWYARD LEVEL "

-- ---------------------------------------------------------------- encoding

-- Integers plain, everything else at 4 decimals with trailing zeros trimmed.
-- 4 decimals is 0.1 mm in metres and 0.0001 deg of heading -- past the point
-- where a level can express anything.
local function num(v)
    if type(v) ~= "number" then return "0" end
    if v == 0 then return "0" end
    if v == math.floor(v) and math.abs(v) < 1e9 then
        return string.format("%d", v)
    end
    local s = string.format("%.4f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function degrees(rad)
    return num(math.deg(rad or 0))
end

local function quote(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    return '"' .. s .. '"'
end

local function prop_line(head, entry, def)
    local parts = { head, entry.kind, num(entry.x), num(entry.y) }
    return parts
end

function M.encode(level)
    local out = { M.HEADER .. M.VERSION }
    local function add(s) out[#out + 1] = s end

    if level.id then add("id " .. level.id) end
    add("name " .. quote(level.name))
    if level.hint then add("hint " .. quote(level.hint)) end
    if level.series then add("series " .. level.series) end
    if level.order then add("order " .. num(level.order)) end

    local b, sp, bay = level.bounds, level.spawn, level.bay
    add("bounds " .. num(b.x0) .. " " .. num(b.y0) .. " " .. num(b.x1) .. " " .. num(b.y1))
    add("spawn " .. num(sp.x) .. " " .. num(sp.y) .. " " .. degrees(sp.th))
    add("bay " .. num(bay.x) .. " " .. num(bay.y) .. " " .. num(bay.w) .. " " .. num(bay.h)
        .. " " .. degrees(bay.angle) .. " " .. degrees(bay.tol))
    add("par " .. num(level.par))
    if level.apron then add("apron " .. num(level.apron)) end

    for _, w in ipairs(level.walls or {}) do
        local parts = prop_line("wall", w)
        local def = props.get(w.kind)
        local angle = w.angle or 0
        local default_size = def and def.w == w.w and def.h == w.h
        if not default_size or angle ~= 0 then
            parts[#parts + 1] = num(w.w)
            parts[#parts + 1] = num(w.h)
            if angle ~= 0 then parts[#parts + 1] = degrees(angle) end
        end
        add(table.concat(parts, " "))
    end

    for _, c in ipairs(level.cones or {}) do
        local parts = prop_line("cone", c)
        local def = props.get(c.kind)
        if not (def and def.r == c.r) then parts[#parts + 1] = num(c.r) end
        add(table.concat(parts, " "))
    end

    for _, s in ipairs(level.surfaces or {}) do
        local parts = prop_line("surface", s)
        parts[#parts + 1] = num(s.w)
        parts[#parts + 1] = num(s.h)
        if (s.angle or 0) ~= 0 then parts[#parts + 1] = degrees(s.angle) end
        add(table.concat(parts, " "))
    end

    return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------- decoding

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", n = "\n" }

local function unquote(s)
    if #s < 2 or s:sub(1, 1) ~= '"' then return nil, "expected a quoted string" end
    if s:sub(-1) ~= '"' then return nil, "unbalanced quote" end
    local body = s:sub(2, -2)
    return (body:gsub("\\(.)", function(c) return ESCAPES[c] or ("\\" .. c) end))
end

local function tokens(rest)
    local t = {}
    for s in rest:gmatch("%S+") do t[#t + 1] = s end
    return t
end

-- Every number on a line, or the reason it is not a line full of numbers.
local function numbers(rest, min, max)
    local t = tokens(rest)
    if #t < min or (max and #t > max) then
        return nil, string.format("expected %d..%d numbers, got %d", min, max or min, #t)
    end
    local out = {}
    for i, s in ipairs(t) do
        local v = tonumber(s)
        if not v then return nil, "not a number: " .. s end
        out[i] = v
    end
    return out
end

local function put_wall(level, rest)
    local t = tokens(rest)
    if #t < 3 then return nil, "wall needs a kind, x and y" end
    local kind = t[1]
    local wall = { kind = kind }
    local nums = {}
    for i = 2, #t do
        local v = tonumber(t[i])
        if not v then return nil, "not a number: " .. t[i] end
        nums[#nums + 1] = v
    end
    wall.x, wall.y = nums[1], nums[2]
    if #nums > 2 then
        if not (nums[3] and nums[4]) then
            return nil, "wall needs w and h together, or neither"
        end
        wall.w, wall.h = nums[3], nums[4]
        if nums[5] then wall.angle = math.rad(nums[5]) end
    end
    level.walls[#level.walls + 1] = wall
    return true
end

local function put_cone(level, rest)
    local t = tokens(rest)
    if #t < 3 then return nil, "cone needs a kind, x and y" end
    local nums = {}
    for i = 2, #t do
        local v = tonumber(t[i])
        if not v then return nil, "not a number: " .. t[i] end
        nums[#nums + 1] = v
    end
    level.cones[#level.cones + 1] = {
        kind = t[1], x = nums[1], y = nums[2], r = nums[3],
    }
    return true
end

local function put_surface(level, rest)
    local t = tokens(rest)
    if #t < 5 then return nil, "surface needs a kind, x, y, w and h" end
    local nums = {}
    for i = 2, #t do
        local v = tonumber(t[i])
        if not v then return nil, "not a number: " .. t[i] end
        nums[#nums + 1] = v
    end
    level.surfaces[#level.surfaces + 1] = {
        kind = t[1], x = nums[1], y = nums[2], w = nums[3], h = nums[4],
        angle = nums[5] and math.rad(nums[5]) or nil,
    }
    return true
end

local FIELDS = {
    id = function(level, rest) level.id = rest end,
    series = function(level, rest) level.series = rest end,
    name = function(level, rest)
        local s, err = unquote(rest)
        if not s then return nil, err end
        level.name = s
        return true
    end,
    hint = function(level, rest)
        local s, err = unquote(rest)
        if not s then return nil, err end
        level.hint = s
        return true
    end,
    order = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        level.order = n[1]
        return true
    end,
    bounds = function(level, rest)
        local n, err = numbers(rest, 4, 4)
        if not n then return nil, err end
        level.bounds = { x0 = n[1], y0 = n[2], x1 = n[3], y1 = n[4] }
        return true
    end,
    spawn = function(level, rest)
        local n, err = numbers(rest, 3, 3)
        if not n then return nil, err end
        level.spawn = { x = n[1], y = n[2], th = math.rad(n[3]) }
        return true
    end,
    bay = function(level, rest)
        local n, err = numbers(rest, 6, 6)
        if not n then return nil, err end
        level.bay = { x = n[1], y = n[2], w = n[3], h = n[4],
                      angle = math.rad(n[5]), tol = math.rad(n[6]) }
        return true
    end,
    par = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        level.par = n[1]
        return true
    end,
    apron = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        level.apron = n[1]
        return true
    end,
    wall = function(level, rest) return put_wall(level, rest) end,
    cone = function(level, rest) return put_cone(level, rest) end,
    surface = function(level, rest) return put_surface(level, rest) end,
}

function M.decode(text)
    if type(text) ~= "string" then return nil, "not a document" end

    local level = { walls = {}, cones = {}, surfaces = {} }
    local header = false
    local n = 0

    for raw in text:gmatch("[^\n]*") do
        n = n + 1
        local line = raw:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            if not header then
                if line ~= M.HEADER .. M.VERSION then
                    return nil, "line " .. n .. ": bad header: " .. line
                end
                header = true
            else
                local key, rest = line:match("^(%S+)%s*(.*)$")
                local field = FIELDS[key]
                if not field then return nil, "line " .. n .. ": unknown key: " .. tostring(key) end
                local ok, err = field(level, rest)
                if not ok then return nil, "line " .. n .. ": " .. tostring(err) end
            end
        end
    end

    if not header then return nil, "empty document" end
    if not level.name then return nil, "no name" end
    if not level.bounds then return nil, "no bounds" end
    if not level.spawn then return nil, "no spawn" end
    if not level.bay then return nil, "no bay" end
    if not level.par then return nil, "no par" end

    return M.resolve(level)
end

-- ------------------------------------------------------------- resolution

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- Fill every prop's size from its kind once, so the session, the renderer and
-- the invariants all read explicit numbers while the authoring data stays
-- terse. Defaults live in lib/props.lua and nowhere else. An unknown kind is
-- left unfilled on purpose: props.check names it, and the suite fails before a
-- level like that can be played.
function M.resolve(level)
    local out = copy(level)
    out.walls = {}
    for i, wall in ipairs(level.walls or {}) do
        local fp = props.footprint(wall)
        local e = copy(wall)
        if fp then e.w, e.h = fp.w, fp.h else e.w, e.h = wall.w, wall.h end
        out.walls[i] = e
    end
    out.cones = {}
    for i, cone in ipairs(level.cones or {}) do
        local fp = props.footprint(cone)
        local e = copy(cone)
        e.r = fp and fp.r or cone.r
        out.cones[i] = e
    end
    out.surfaces = {}
    for i, zone in ipairs(level.surfaces or {}) do
        out.surfaces[i] = copy(zone)
    end
    return out
end

return M
