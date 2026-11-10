-- The scenery vocabulary. A level's walls and cones stay plain collision
-- shapes; `kind` is what they are, and this table is the only place in the code
-- that says so.
--
-- Why a vocabulary and not new physics: the sim has exactly two contact paths
-- today -- a solid box that reverts the step, and a circle that is knocked once
-- and charged a bump. So a campsite needs no new collision code, only labels:
-- solid kinds are boxes on the wall list, knockable kinds are circles on the
-- cone list. A prop that is neither (a tree, a bollard) would need a third
-- contact path, and that is a physics feature, not a label.
--
-- Colours live here, not in lib/draw.lua, so one table answers "what is a
-- clubhouse" for both the renderer and the tests. Every solid kind is kept dim
-- (no channel above 0.62, no more than 0.20 of saturation): the player's red
-- car, cream caravan and the green bay have to remain the loudest things on the
-- ground or the manoeuvre stops reading at a glance. `loud` marks hazards, the
-- one class allowed to shout -- a fire pit is small and must be findable at
-- 15 px/m.
--
-- Pure: no love.* and no geometry. This module answers "is the kind valid and
-- how big is it by default"; where a prop may sit is a level invariant and is
-- checked in tests/test_levels.lua.

local M = {}

-- Extend the wall list (blocked, reverts on contact).
M.KINDS = {
    building = { class = "solid", shape = "box", w = 7.0, h = 5.0,
                 colour = { 0.38, 0.35, 0.32 }, label = "clubhouse", short = "club" },
    rv = { class = "solid", shape = "box", w = 7.2, h = 2.6,
           colour = { 0.50, 0.50, 0.53 }, label = "motorhome", short = "rv" },
    caravan = { class = "solid", shape = "box", w = 4.6, h = 2.1,
                colour = { 0.44, 0.40, 0.33 }, label = "pitched caravan", short = "caravan" },
    car = { class = "solid", shape = "box", w = 4.2, h = 1.75,
            colour = { 0.34, 0.36, 0.42 }, label = "parked car", short = "car" },
    tent = { class = "solid", shape = "box", w = 3.4, h = 3.0,
             colour = { 0.45, 0.38, 0.28 }, label = "tent", short = "tent" },
    hedge = { class = "solid", shape = "box", w = 6.0, h = 0.7, linear = true,
              colour = { 0.20, 0.30, 0.19 }, label = "hedge", short = "hedge" },
    pool = { class = "solid", shape = "box", w = 8.0, h = 5.0,
             colour = { 0.18, 0.30, 0.36 }, label = "pool", short = "pool" },
    table = { class = "solid", shape = "box", w = 2.4, h = 1.8,
              colour = { 0.44, 0.33, 0.28 }, label = "picnic table", short = "table" },

    -- Extend the cone list (knocked once, charged one bump).
    cone = { class = "knockable", shape = "circle", r = 0.35,
             colour = { 0.95, 0.55, 0.15 }, label = "traffic cone", short = "cone", loud = true },
    firepit = { class = "knockable", shape = "circle", r = 0.55,
                colour = { 0.96, 0.42, 0.10 }, label = "fire pit", short = "firepit", loud = true },
    chair = { class = "knockable", shape = "circle", r = 0.50,
              colour = { 0.40, 0.36, 0.38 }, label = "camp chair", short = "chair" },
    -- A beach umbrella is a pole and a canopy: the pole would let a rig drive
    -- through it if this were scenery, so it takes the knockable contact path and
    -- the whole 2.2 m canopy is the circle it is hit by.
    umbrella = { class = "knockable", shape = "circle", r = 1.10,
                 colour = { 0.34, 0.46, 0.50 }, label = "beach umbrella", short = "umbrella" },
}

-- Ground paint only: no collision, drawn under everything. Kinds are named here
-- so a level cannot invent a surface the renderer has never heard of.
M.SURFACES = {
    gravel = { colour = { 0.30, 0.28, 0.24 }, label = "gravel", short = "gravel" },
    grass = { colour = { 0.17, 0.26, 0.16 }, label = "grass", short = "grass" },
    deck = { colour = { 0.26, 0.22, 0.18 }, label = "decking", short = "deck" },
    water = { colour = { 0.13, 0.22, 0.28 }, label = "water", short = "water" },
}

-- Palette order, by group: what the editor's rail offers, top to bottom.
-- Explicit because a palette's order is a design decision and `pairs` has none;
-- tests/test_props.lua walks the vocabulary against this table, so a kind added
-- to KINDS/SURFACES cannot silently go missing from the rail.
M.PALETTE = {
    structures = { "hedge", "building", "tent", "caravan", "rv", "car", "pool", "table" },
    camp = { "cone", "firepit", "chair", "umbrella" },
    ground = { "gravel", "grass", "deck" },
}

-- In the vocabulary, deliberately not offered in the editor. Water is drawn
-- inside the pool's own art and no level paints with it; move it into PALETTE
-- above when a level wants a pond.
M.UNPLACEABLE = { water = true }

function M.get(kind)
    return M.KINDS[kind]
end

-- Can this be stretched, and along which axis?
--
--   "none"   a thing with one real size: a car, a motorhome, a chair, a cone, a
--            fire pit. Stretching them is not authoring, it is distorting.
--   "length" one direction only: a hedge is long and thin, and pulling its width
--            out makes a hedge-shaped hedge into a field.
--   "free"   both: buildings, tents, pools, decking, gravel, grass, water.
--
-- Data rather than a shape rule, because the answer is a property of the thing.
local RESIZE = {
    hedge = "length",
    building = "free",
    tent = "free",
    pool = "free",
    car = "none",
    rv = "none",
    chair = "none",
    cone = "none",
    firepit = "none",
    table = "none",
    umbrella = "none",
}

function M.resize_mode(kind)
    if M.SURFACES[kind] then return "free" end
    return RESIZE[kind] or "free"
end

-- The kind's defaults with the entry's own sizes laid over them, so level data
-- can say `{ x = 40, y = 12, kind = "hedge", w = 26 }` and mean it. Returns nil
-- for an unknown kind: the renderer falls back to a plain box rather than
-- crashing, and check() is what stops the typo reaching a shipped level.
function M.footprint(entry)
    local def = entry and M.KINDS[entry.kind]
    if not def then return nil end
    return {
        kind = entry.kind,
        class = def.class,
        shape = def.shape,
        w = entry.w or def.w,
        h = entry.h or def.h,
        r = entry.r or def.r,
        colour = def.colour,
        label = def.label or entry.kind,
        loud = def.loud,
    }
end

local function positive(v)
    return type(v) == "number" and v > 0
end

local function size_errors(def, entry, where, errs)
    if def.shape == "box" then
        if not positive(entry.w or def.w) then
            errs[#errs + 1] = where .. " (" .. entry.kind .. "): w must be a positive number"
        end
        if not positive(entry.h or def.h) then
            errs[#errs + 1] = where .. " (" .. entry.kind .. "): h must be a positive number"
        end
    elseif not positive(entry.r or def.r) then
        errs[#errs + 1] = where .. " (" .. entry.kind .. "): r must be a positive number"
    end
end

-- Every error a level has in its scenery, as human-readable strings; empty when
-- the level is well-typed. Spatial invariants (bounds, apron, overlaps) are not
-- this function's business -- see tests/test_levels.lua.
function M.check(level)
    local errs = {}
    local lists = { { "wall", level.walls or {}, "box" }, { "cone", level.cones or {}, "circle" } }

    for _, list in ipairs(lists) do
        local where, entries, wanted = list[1], list[2], list[3]
        for i, entry in ipairs(entries) do
            local at = where .. " " .. i
            if entry.kind == nil then
                errs[#errs + 1] = at .. ": no kind (an untyped prop is a bug, not scenery)"
            else
                local def = M.KINDS[entry.kind]
                if not def then
                    errs[#errs + 1] = at .. ": unknown kind " .. tostring(entry.kind)
                elseif def.shape ~= wanted then
                    errs[#errs + 1] = at .. ": " .. entry.kind .. " is a " .. def.shape
                        .. " and cannot sit on the " .. where .. " list"
                else
                    size_errors(def, entry, at, errs)
                end
            end
        end
    end

    for i, zone in ipairs(level.surfaces or {}) do
        if zone.kind == nil then
            errs[#errs + 1] = "surface " .. i .. ": no kind"
        elseif not M.SURFACES[zone.kind] then
            errs[#errs + 1] = "surface " .. i .. ": unknown kind " .. tostring(zone.kind)
        end
    end

    return errs
end

return M
