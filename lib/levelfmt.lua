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
-- The reader is strict because these files arrive from strangers: an unknown
-- key, a non-finite number, an unknown kind or a document over the caps is
-- refused with a reason. Nothing here executes, allocates per line without a
-- bound, or trusts a count the file claims about itself.

local props = require("lib.props")
local hash = require("lib.hash")

local M = {}

M.VERSION = 1
M.HEADER = "TOWYARD LEVEL "

-- Caps. A document that asks for a 10 km yard or a million props is a denial of
-- service with a level file extension, and nothing legitimate comes near these.
-- Text lengths are BYTES, not characters (LuaJIT has no utf8 library), so an
-- accented Hungarian name counts double against `name`.
M.LIMITS = {
    name = 60,
    hint = 200,
    id = 32,
    series = 24,
    walls = 2000,
    cones = 2000,
    surfaces = 500,
    side = { 4, 500 },      -- bounds width/height, metres
    par = { 1, 600 },       -- seconds
    tol = { 0.5, 30 },      -- bay angle tolerance, degrees
    apron = { 0, 10 },      -- metres
    coord = 1e5,            -- no coordinate is further than 100 km
}

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

local function prop_head(head, entry)
    return { head, entry.kind, num(entry.x), num(entry.y) }
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
        local parts = prop_head("wall", w)
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
        local parts = prop_head("cone", c)
        local def = props.get(c.kind)
        if not (def and def.r == c.r) then parts[#parts + 1] = num(c.r) end
        add(table.concat(parts, " "))
    end

    for _, s in ipairs(level.surfaces or {}) do
        local parts = prop_head("surface", s)
        parts[#parts + 1] = num(s.w)
        parts[#parts + 1] = num(s.h)
        if (s.angle or 0) ~= 0 then parts[#parts + 1] = degrees(s.angle) end
        add(table.concat(parts, " "))
    end

    return table.concat(out, "\n") .. "\n"
end

-- A level as a lib/levels.lua entry: the editor's "export to the campaign".
-- Same authored form as the document -- default sizes omitted, angles in
-- degrees wrapped in math.rad -- because the point is that it pastes into the
-- data file and reads like the entries already there.
local function lua_string(s)
    return string.format("%q", tostring(s or ""))
end

local function angle_lua(rad)
    if (rad or 0) == 0 then return "0" end
    return "math.rad(" .. num(math.deg(rad)) .. ")"
end

function M.to_lua(level)
    local out = { "{" }
    local function add(s) out[#out + 1] = "    " .. s end
    local function prop(parts) add("    { " .. table.concat(parts, ", ") .. " },") end

    if level.id then add("id = " .. lua_string(level.id) .. ",") end
    if level.series then add("series = " .. lua_string(level.series) .. ",") end
    if level.order then add("order = " .. num(level.order) .. ",") end
    add("name = " .. lua_string(level.name) .. ",")
    if level.hint then add("hint = " .. lua_string(level.hint) .. ",") end

    local b, sp, bay = level.bounds, level.spawn, level.bay
    add(string.format("bounds = { x0 = %s, y0 = %s, x1 = %s, y1 = %s },",
        num(b.x0), num(b.y0), num(b.x1), num(b.y1)))
    add(string.format("spawn = { x = %s, y = %s, th = %s },",
        num(sp.x), num(sp.y), angle_lua(sp.th)))
    add(string.format("bay = { x = %s, y = %s, w = %s, h = %s, angle = %s, tol = %s },",
        num(bay.x), num(bay.y), num(bay.w), num(bay.h), angle_lua(bay.angle), angle_lua(bay.tol)))
    add("par = " .. num(level.par) .. ",")
    if level.apron then add("apron = " .. num(level.apron) .. ",") end

    add("walls = {")
    for _, w in ipairs(level.walls or {}) do
        local parts = { "x = " .. num(w.x), "y = " .. num(w.y) }
        local def = props.get(w.kind)
        if not (def and def.w == w.w and def.h == w.h) then
            parts[#parts + 1] = "w = " .. num(w.w)
            parts[#parts + 1] = "h = " .. num(w.h)
        end
        if (w.angle or 0) ~= 0 then parts[#parts + 1] = "angle = " .. angle_lua(w.angle) end
        parts[#parts + 1] = "kind = " .. lua_string(w.kind)
        prop(parts)
    end
    add("},")

    add("cones = {")
    for _, c in ipairs(level.cones or {}) do
        local parts = { "x = " .. num(c.x), "y = " .. num(c.y) }
        local def = props.get(c.kind)
        if not (def and def.r == c.r) then parts[#parts + 1] = "r = " .. num(c.r) end
        parts[#parts + 1] = "kind = " .. lua_string(c.kind)
        prop(parts)
    end
    add("},")

    add("surfaces = {")
    for _, s in ipairs(level.surfaces or {}) do
        local parts = { "x = " .. num(s.x), "y = " .. num(s.y),
                        "w = " .. num(s.w), "h = " .. num(s.h) }
        if (s.angle or 0) ~= 0 then parts[#parts + 1] = "angle = " .. angle_lua(s.angle) end
        parts[#parts + 1] = "kind = " .. lua_string(s.kind)
        prop(parts)
    end
    add("},")

    out[#out + 1] = "}"
    return table.concat(out, "\n")
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

-- A number that is actually a number. tonumber("nan") succeeds in LuaJIT and
-- would make every overlap test in geom compare false, so a level would look
-- valid and collide with nothing; "1e999" becomes inf and does the same.
local function finite(v, raw)
    if v ~= v or v == math.huge or v == -math.huge then
        return nil, "not a finite number: " .. tostring(raw)
    end
    if math.abs(v) > M.LIMITS.coord then
        return nil, "coordinate out of range: " .. tostring(raw)
    end
    return true
end

-- Every number on a line, or the reason it is not a line full of numbers.
local function numbers(rest, min, max)
    local t = tokens(rest)
    max = max or min
    if #t < min or #t > max then
        return nil, string.format("expected %d..%d numbers, got %d", min, max, #t)
    end
    local out = {}
    for i, s in ipairs(t) do
        local v = tonumber(s)
        if not v then return nil, "not a number: " .. s end
        local ok, err = finite(v, s)
        if not ok then return nil, err end
        out[i] = v
    end
    return out
end

local function in_range(v, range, label)
    if v < range[1] or v > range[2] then
        return nil, string.format("%s must be %g..%g, got %g", label, range[1], range[2], v)
    end
    return true
end

local function slug(s, max, label)
    s = s or ""
    if #s == 0 then return nil, label .. " is empty" end
    if #s > max then return nil, label .. " is too long (max " .. max .. ")" end
    if not s:match("^[a-z0-9][a-z0-9%-]*$") then
        return nil, label .. " must be lowercase letters, digits and dashes: " .. s
    end
    return true
end

local function check_kind(kind, list, shape)
    local def = props.get(kind)
    if not def then return nil, "unknown kind: " .. tostring(kind) end
    if def.shape ~= shape then
        return nil, kind .. " is a " .. def.shape .. " and cannot sit on the " .. list .. " list"
    end
    return def
end

-- The numbers after a kind, finite and in the count the list allows.
local function parse_nums(t, from, max)
    local out = {}
    for i = from, #t do
        local v = tonumber(t[i])
        if not v then return nil, "not a number: " .. t[i] end
        local ok, err = finite(v, t[i])
        if not ok then return nil, err end
        out[#out + 1] = v
    end
    if #out > max then
        return nil, string.format("takes at most %d numbers after the kind, got %d", max, #out)
    end
    return out
end

local function put_wall(level, rest)
    if #level.walls >= M.LIMITS.walls then
        return nil, "too many walls (max " .. M.LIMITS.walls .. ")"
    end
    local t = tokens(rest)
    if #t < 3 then return nil, "wall needs a kind, x and y" end
    local def, kerr = check_kind(t[1], "wall", "box")
    if not def then return nil, kerr end
    local nums, nerr = parse_nums(t, 2, 5)
    if not nums then return nil, nerr end
    if #nums == 3 then return nil, "wall needs w and h together, or neither" end

    local wall = { kind = t[1], x = nums[1], y = nums[2] }
    if nums[3] then
        if nums[3] <= 0 or nums[4] <= 0 then return nil, "wall sizes must be positive" end
        wall.w, wall.h = nums[3], nums[4]
        if nums[5] then wall.angle = math.rad(nums[5]) end
    end

    level.walls[#level.walls + 1] = wall
    return true
end

local function put_cone(level, rest)
    if #level.cones >= M.LIMITS.cones then
        return nil, "too many cones (max " .. M.LIMITS.cones .. ")"
    end
    local t = tokens(rest)
    if #t < 3 then return nil, "cone needs a kind, x and y" end
    local def, kerr = check_kind(t[1], "cone", "circle")
    if not def then return nil, kerr end
    local nums, nerr = parse_nums(t, 2, 3)
    if not nums then return nil, nerr end

    local cone = { kind = t[1], x = nums[1], y = nums[2] }
    if nums[3] then
        if nums[3] <= 0 then return nil, "cone radius must be positive" end
        cone.r = nums[3]
    end

    level.cones[#level.cones + 1] = cone
    return true
end

local function put_surface(level, rest)
    if #level.surfaces >= M.LIMITS.surfaces then
        return nil, "too many surfaces (max " .. M.LIMITS.surfaces .. ")"
    end
    local t = tokens(rest)
    if #t < 5 then return nil, "surface needs a kind, x, y, w and h" end
    if not props.SURFACES[t[1]] then
        return nil, "unknown surface kind: " .. tostring(t[1])
    end
    local nums, nerr = parse_nums(t, 2, 5)
    if not nums then return nil, nerr end
    if #nums < 4 then return nil, "surface needs x, y, w and h" end
    if nums[3] <= 0 or nums[4] <= 0 then return nil, "surface sizes must be positive" end

    level.surfaces[#level.surfaces + 1] = {
        kind = t[1], x = nums[1], y = nums[2], w = nums[3], h = nums[4],
        angle = nums[5] and math.rad(nums[5]) or nil,
    }
    return true
end

local FIELDS = {
    id = function(level, rest)
        local ok, err = slug(rest, M.LIMITS.id, "id")
        if not ok then return nil, err end
        level.id = rest
        return true
    end,
    series = function(level, rest)
        local ok, err = slug(rest, M.LIMITS.series, "series")
        if not ok then return nil, err end
        level.series = rest
        return true
    end,
    name = function(level, rest)
        local s, err = unquote(rest)
        if not s then return nil, err end
        if #s == 0 then return nil, "name is empty" end
        if #s > M.LIMITS.name then return nil, "name is too long (max " .. M.LIMITS.name .. ")" end
        level.name = s
        return true
    end,
    hint = function(level, rest)
        local s, err = unquote(rest)
        if not s then return nil, err end
        if #s > M.LIMITS.hint then return nil, "hint is too long (max " .. M.LIMITS.hint .. ")" end
        level.hint = s
        return true
    end,
    order = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        if n[1] ~= math.floor(n[1]) or n[1] < 1 then
            return nil, "order must be a whole number, got " .. tostring(n[1])
        end
        level.order = n[1]
        return true
    end,
    bounds = function(level, rest)
        local n, err = numbers(rest, 4, 4)
        if not n then return nil, err end
        local w, h = n[3] - n[1], n[4] - n[2]
        if w <= 0 or h <= 0 then return nil, "bounds must have x1 > x0 and y1 > y0" end
        local ok, rerr = in_range(w, M.LIMITS.side, "bounds width")
        if not ok then return nil, rerr end
        ok, rerr = in_range(h, M.LIMITS.side, "bounds height")
        if not ok then return nil, rerr end
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
        if n[3] <= 0 or n[4] <= 0 then return nil, "bay needs a positive w and h" end
        local ok, rerr = in_range(n[6], M.LIMITS.tol, "bay angle tolerance")
        if not ok then return nil, rerr end
        level.bay = { x = n[1], y = n[2], w = n[3], h = n[4],
                      angle = math.rad(n[5]), tol = math.rad(n[6]) }
        return true
    end,
    par = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        local ok, rerr = in_range(n[1], M.LIMITS.par, "par")
        if not ok then return nil, rerr end
        level.par = n[1]
        return true
    end,
    apron = function(level, rest)
        local n, err = numbers(rest, 1, 1)
        if not n then return nil, err end
        local ok, rerr = in_range(n[1], M.LIMITS.apron, "apron")
        if not ok then return nil, rerr end
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
    if not level.id then return nil, "no id" end
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

-- ------------------------------------------------------------- custom levels

-- Imported levels live in the save directory, listed by an index of ids. The
-- index rather than a directory scan because the disk interface stays three
-- calls wide (read/write/remove) and a fake disk in a test needs no directory
-- emulation; the cost is that a file with no index entry is invisible, which is
-- the failure mode that cannot crash anything.
M.CUSTOM_DIR = "custom/"
M.CUSTOM_INDEX = "custom/index.txt"

function M.custom_ids(disk)
    local ids = {}
    local raw = disk and disk.read(M.CUSTOM_INDEX)
    for line in (raw or ""):gmatch("[^\n]+") do
        local id = line:match("^%s*([%w%-]+)%s*$")
        if id then ids[#ids + 1] = id end
    end
    return ids
end

function M.save_custom(disk, level)
    if not disk then return nil, "no disk" end
    if not (level and level.id) then return nil, "a level with no id cannot be stored" end
    if disk.mkdir then disk.mkdir(M.CUSTOM_DIR) end
    local name = M.CUSTOM_DIR .. level.id .. ".tylevel"
    disk.write(name, M.encode(level))

    local ids = M.custom_ids(disk)
    for _, id in ipairs(ids) do
        if id == level.id then return name end
    end
    ids[#ids + 1] = level.id
    disk.write(M.CUSTOM_INDEX, table.concat(ids, "\n") .. "\n")
    return name
end

-- Every readable custom level, plus a warning per file that is not. A broken
-- import must not take the rest of the list with it.
function M.scan_custom(disk)
    local levels, warnings = {}, {}
    for _, id in ipairs(M.custom_ids(disk)) do
        local text = disk.read(M.CUSTOM_DIR .. id .. ".tylevel")
        if not text then
            warnings[#warnings + 1] = "missing file for " .. id
        else
            local lvl, err = M.decode(text)
            if lvl then
                levels[#levels + 1] = lvl
            else
                warnings[#warnings + 1] = id .. ": " .. tostring(err)
            end
        end
    end
    return levels, warnings
end

-- The content of a level, and only the content. A ghost and a best time are
-- keyed to this: moving a wall or changing the par must invalidate them, while
-- renaming the id or re-sorting the level into another series must not -- those
-- are identity and presentation, not the thing a run was driven against.
function M.content_hash(level)
    local resolved = M.resolve(level)
    local body = {}
    for k, v in pairs(resolved) do
        if k ~= "id" and k ~= "series" and k ~= "order" then body[k] = v end
    end
    return hash.sha256(hash.canonical(body))
end

return M
