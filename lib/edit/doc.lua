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

-- Is this the same level as that one, by content? After an autosave is found on
-- disk, the question "does it differ from what we just opened?" decides whether
-- restoring it is a rescue or an annoyance. Pure, so the rule is a test.
function M.same_level(a, b)
    if not a or not b then return false end
    return levelfmt.content_hash(levelfmt.resolve(a)) == levelfmt.content_hash(levelfmt.resolve(b))
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

    -- Carry the kind's sizes explicitly. The document is what gets written, and
    -- the encoder writes the AUTHORED form: a cone with no radius encodes as
    -- "cone cone 20 20 0", which the parser (rightly) refuses. Sizes equal to the
    -- kind default are still omitted from the file by the encoder, so nothing
    -- gets noisier -- it just cannot be lost on the way out.
    local fp = props.footprint(entry)
    if fp then
        if fp.shape == "circle" then
            entry.r = fp.r
        else
            entry.w, entry.h = fp.w, fp.h
        end
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

    -- The start and the goal come before paint. A dressed level covers its whole
    -- yard with surfaces, so while surfaces were picked first, the bay was
    -- unpickable on every real level -- which is exactly how it felt.
    if (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2 <= (1.2 + tol) ^ 2 then
        doc.selection = { list = "spawn" }
        return doc.selection
    end
    if geom.point_in_poly(x, y, geom.rect_poly(lvl.bay.x, lvl.bay.y, lvl.bay.w, lvl.bay.h, lvl.bay.angle)) then
        doc.selection = { list = "bay" }
        return doc.selection
    end

    -- paint last: it is ground, it is huge, and it is almost never the thing you
    -- are pointing at
    for i = #lvl.surfaces, 1, -1 do
        local s = lvl.surfaces[i]
        if geom.point_in_poly(x, y, geom.rect_poly(s.x, s.y, s.w, s.h, s.angle or 0)) then
            doc.selection = { list = "surfaces", index = i }
            return doc.selection
        end
    end

    -- and the props still win, because they are small and sit on top

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

-- Can the current selection be stretched? nil when nothing is selected.
function M.resize_mode(doc)
    local s = doc.selection
    if not s then return nil end
    if s.list == "bay" then return "free" end
    if s.list == "spawn" then return "none" end
    if SINGLE[s.list] then return "none" end
    if s.list == "surfaces" then return "free" end
    local entry = (doc.level[s.list] or {})[s.index]
    return props.resize_mode(entry and entry.kind)
end

-- Where the resize handles are, in world coordinates. The view draws squares at
-- these points and the mouse hit-tests them; keeping the geometry here means the
-- one thing that can be wrong (which end is the length) is a test.
--
-- Returns {} when there is nothing storable to drag: no selection, or a kind with
-- one size -- a car must not grow handles.
function M.resize_handles(doc)
    local entry, s = selected(doc)
    if not entry then return {} end
    local mode = M.resize_mode(doc)
    if mode == "none" then return {} end

    local x, y, w, h, angle = entry.x, entry.y, nil, nil, 0
    if s.list == "bay" then
        w, h, angle = entry.w, entry.h, entry.angle or 0
    elseif s.list == "surfaces" or s.list == "walls" then
        local fp = props.footprint(entry) or { w = entry.w, h = entry.h }
        w, h, angle = fp.w, fp.h, entry.angle or 0
    else
        return {}
    end

    local c, sn = math.cos(angle), math.sin(angle)
    local hw, hh = w / 2, h / 2
    local function at(lx, ly)
        return { x = x + lx * c - ly * sn, y = y + lx * sn + ly * c }
    end

    if mode == "length" then
        -- two handles, on the ends of the longer axis
        if w >= h then
            return { { x = at(-hw, 0).x, y = at(-hw, 0).y, axis = "x" },
                     { x = at(hw, 0).x, y = at(hw, 0).y, axis = "x" } }
        end
        return { { x = at(0, -hh).x, y = at(0, -hh).y, axis = "y" },
                 { x = at(0, hh).x, y = at(0, hh).y, axis = "y" } }
    end

    local out = {}
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            local p = at(sx * hw, sy * hh)
            out[#out + 1] = { x = p.x, y = p.y, axis = "both" }
        end
    end
    return out
end

-- Absolute size, for a mouse drag on a handle. Sizes are symmetric about the
-- centre: the prop stays where you put it and grows around itself, which is what
-- you want when lining a hedge up against a kerb.
function M.resize_to(doc, w, h)
    local entry, s = selected(doc)
    if not entry then return nil, "nothing selected" end
    local mode = M.resize_mode(doc)
    if mode == "none" then return nil, "this kind has one size" end

    w = math.min(500, math.max(0.2, w or 0.2))
    h = math.min(500, math.max(0.2, (h or w)))

    if s.list == "cones" or (props.footprint(entry) or {}).shape == "circle" then
        entry.r = math.max(0.1, w / 2)
        return entry
    end

    if mode == "length" then
        -- the local axis that is currently longer is the length; the other side
        -- is the kind's own and does not move. A square hedge has no length yet,
        -- so the drag decides which way it grows -- otherwise a hedge dragged
        -- upwards would refuse to get taller.
        local fp = props.footprint(entry) or { w = w, h = h }
        local cw, ch = fp.w or 1, fp.h or 1
        local long_is_w
        if cw > ch then long_is_w = true
        elseif ch > cw then long_is_w = false
        else long_is_w = (w or 0) >= (h or 0) end
        if long_is_w then h = ch else w = cw end
    end

    entry.w, entry.h = w, h
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
    local mode = M.resize_mode(doc)
    if mode == "none" then return nil, "this kind has one size" end

    if s.list == "cones" then
        entry.r = math.max(0.1, current.r + dw)
        return entry
    end

    local w = math.max(0.5, current.w + dw)
    local h = math.max(0.5, current.h + (dh or 0))
    if mode == "length" then
        if current.w >= current.h then h = current.h else w = current.w end
    end
    entry.w, entry.h = w, h
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
