-- The editor's document: a level being changed, plus what is selected.
--
-- Pure, so every operation is a headless test rather than a mouse gesture. The
-- view (Task 25) does pixels, snapping and mouse handling; this module does not
-- know a cursor exists, and it takes exact metres and degrees.
--
-- Selection is (list, index) rather than a bare number, because "prop 3" is
-- ambiguous the moment a level has three walls and three cones -- the classic
-- editor bug is deleting the thing next to the thing you meant.
--
-- A document is snapshot-able as canonical text (levelfmt.encode): undo is a
-- stack of those, which is cheap for a few-kilobyte level and eliminates a whole
-- class of command-pattern bugs (Task 24).

local props = require("lib.props")
local geom = require("lib.geom")
local levelfmt = require("lib.levelfmt")

local M = {}

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function deep(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deep(v) end
    return out
end

-- A blank site: a yard, a bay and a spawn, with nothing in the way. The editor
-- starts here rather than on level 1, so a new level is not a copy of one.
function M.blank(id, name)
    return {
        level = {
            id = id or "custom",
            name = name or "Untitled",
            hint = "",
            bounds = { x0 = 0, y0 = 0, x1 = 60, y1 = 40 },
            spawn = { x = 48, y = 20, th = 0 },
            bay = { x = 22, y = 20, w = 8, h = 4, angle = 0, tol = math.rad(6) },
            walls = {},
            cones = {},
            surfaces = {},
            par = 30,
            apron = 2.0,
        },
        selection = nil,
    }
end

-- A fresh id that nothing answers to. Ids key progress, ghosts and the custom
-- level's filename, so two levels called "untitled" are two levels sharing one
-- best time and one ghost.
function M.free_id(taken, base)
    base = base or "untitled"
    local used = {}
    for _, t in ipairs(taken or {}) do used[t] = true end
    if not used[base] then return base end
    local n = 1
    repeat n = n + 1 until not used[base .. "-" .. n]
    return base .. "-" .. n
end

function M.new(level)
    return { level = deep(level), selection = nil }
end

function M.list(doc, name)
    return doc.level[name] or {}
end

-- The playable form: defaults filled, ready for a session or levelcheck.
function M.level(doc)
    return levelfmt.resolve(doc.level)
end

function M.snapshot(doc)
    return levelfmt.encode(doc.level)
end

function M.restore(doc, text)
    local level, err = levelfmt.decode(text)
    if not level then return nil, err end
    -- decode resolves; the document wants the authored form back, which is what
    -- encode produced in the first place, so keep the sizes it wrote explicitly
    doc.level = level
    doc.selection = nil
    return true
end

-- bay and spawn are single records, not list entries: they are selectable like
-- anything else so they can be dragged, but they cannot be deleted or duplicated
-- (a level without a place to start or a place to finish is not a level).
local SINGLE = { bay = true, spawn = true }

local function selected(doc)
    local s = doc.selection
    if not s then return nil, nil end
    if SINGLE[s.list] then return doc.level[s.list], s end
    local entry = (doc.level[s.list] or {})[s.index]
    return entry, s
end

function M.select(doc, name)
    if name ~= "bay" and name ~= "spawn" then return nil, "not a single record" end
    doc.selection = { list = name }
    return doc.selection
end

local function shape_of(kind)
    local def = props.get(kind)
    if def then return def.shape, def end
    if props.SURFACES[kind] then return "surface", nil end
    return nil, nil
end

function M.add(doc, kind, x, y)
    local shape, def = shape_of(kind)
    if not shape then return nil, "unknown kind: " .. tostring(kind) end

    local entry = { kind = kind, x = x, y = y }
    local list
    if shape == "box" then
        list = "walls"
    elseif shape == "circle" then
        list = "cones"
    else
        list = "surfaces"
        entry.w, entry.h = 6, 4      -- paint needs a size to exist at all
    end

    local l = doc.level[list]
    l[#l + 1] = entry
    doc.selection = { list = list, index = #l }
    return entry
end

-- Topmost first: cones and walls are things you point at, paint is ground, and
-- within a list the last one drawn is the one on top.
function M.pick(doc, x, y, tol)
    tol = tol or 0.3
    local lvl = M.level(doc)
    local spawn = lvl.spawn

    for i = #lvl.cones, 1, -1 do
        local c = lvl.cones[i]
        if (c.x - x) ^ 2 + (c.y - y) ^ 2 <= (c.r + tol) ^ 2 then
            doc.selection = { list = "cones", index = i }
            return doc.selection
        end
    end

    for i = #lvl.walls, 1, -1 do
        local w = lvl.walls[i]
        if geom.point_in_poly(x, y, geom.rect_poly(w.x, w.y, w.w, w.h, w.angle or 0)) then
            doc.selection = { list = "walls", index = i }
            return doc.selection
        end
    end

    for i = #lvl.surfaces, 1, -1 do
        local s = lvl.surfaces[i]
        if geom.point_in_poly(x, y, geom.rect_poly(s.x, s.y, s.w, s.h, s.angle or 0)) then
            doc.selection = { list = "surfaces", index = i }
            return doc.selection
        end
    end

    -- the spawn marker is small and the bay is large, so the order here is the
    -- opposite of the props: a prop under the cursor is always the thing you meant
    if (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2 <= (1.2 + tol) ^ 2 then
        doc.selection = { list = "spawn" }
        return doc.selection
    end
    if geom.point_in_poly(x, y, geom.rect_poly(lvl.bay.x, lvl.bay.y, lvl.bay.w, lvl.bay.h, lvl.bay.angle)) then
        doc.selection = { list = "bay" }
        return doc.selection
    end

    doc.selection = nil
    return nil
end

function M.move(doc, dx, dy)
    local entry = selected(doc)
    if not entry then return nil, "nothing selected" end
    entry.x, entry.y = entry.x + dx, entry.y + dy
    return entry
end

-- The field that holds the heading differs per record: props use `angle`, the
-- spawn uses `th` (the level format's name for it). Writing `angle` on a spawn
-- would be a silent no-op that looks like a rotation.
local HEADING = { bay = "angle", spawn = "th" }

function M.rotate(doc, ddeg)
    local entry, s = selected(doc)
    if not entry then return nil, "nothing selected" end
    if s.list == "cones" then return nil, "a cone has no angle to turn" end
    local field = HEADING[s.list] or "angle"
    entry[field] = (entry[field] or 0) + math.rad(ddeg)
    return entry
end

-- Grow from the CURRENT size, which may be the kind's default: a hedge added
-- with no numbers is 6 x 0.7, and the first resize must start from that.
function M.resize(doc, dw, dh)
    local entry, s = selected(doc)
    if not entry then return nil, "nothing selected" end

    local lvl = M.level(doc)
    local current = (lvl[s.list] or {})[s.index]
    if not current then return nil, "selection is stale" end

    if SINGLE[s.list] then return nil, s.list .. " is resized by numbers, not by nudges" end

    if s.list == "cones" then
        entry.r = math.max(0.1, current.r + dw)
    else
        entry.w = math.max(0.5, current.w + dw)
        entry.h = math.max(0.5, current.h + (dh or 0))
    end
    return entry
end

function M.remove(doc)
    local entry, s = selected(doc)
    if not entry then return nil, "nothing selected" end
    if SINGLE[s.list] then return nil, "a level needs its " .. s.list end
    table.remove(doc.level[s.list], s.index)
    doc.selection = nil
    return entry
end

function M.set_bay(doc, fields)
    for k, v in pairs(fields or {}) do doc.level.bay[k] = v end
    return doc.level.bay
end

function M.set_spawn(doc, fields)
    for k, v in pairs(fields or {}) do doc.level.spawn[k] = v end
    return doc.level.spawn
end

return M
