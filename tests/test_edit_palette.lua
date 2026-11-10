-- The editor's rail, as data. The palette is what stands between the vocabulary
-- and a click: a kind missing here is a kind nobody can place, and a kind listed
-- twice is a tile that quietly places the wrong thing.

local H = require("tests.helper")
local props = require("lib.props")
local palette = require("lib.edit.palette")

local M = { order = {
    "every_kind_is_on_the_rail_or_declared_unplaceable",
    "groups_follow_the_vocabulary_classes",
    "the_caravan_is_placeable_and_water_is_not",
    "the_flat_order_lists_every_tile_once",
    "every_tile_has_a_label_and_a_tooltip",
} }

local function items()
    local out = {}
    for _, g in ipairs(palette.groups()) do
        for _, it in ipairs(g.items) do out[#out + 1] = { group = g.id, item = it } end
    end
    return out
end

function M.every_kind_is_on_the_rail_or_declared_unplaceable()
    local seen = {}
    for _, e in ipairs(items()) do
        local kind = e.item.kind
        if kind then
            H.expect(seen[kind] == nil, "kind on the rail twice: " .. kind)
            seen[kind] = e.group
        end
    end

    local missing = {}
    for kind in pairs(props.KINDS) do
        if not seen[kind] and not props.UNPLACEABLE[kind] then missing[#missing + 1] = kind end
    end
    for kind in pairs(props.SURFACES) do
        if not seen[kind] and not props.UNPLACEABLE[kind] then missing[#missing + 1] = kind end
    end
    table.sort(missing)
    H.expect(#missing == 0, "the vocabulary has kinds the rail cannot place: "
             .. table.concat(missing, ", "))
end

function M.groups_follow_the_vocabulary_classes()
    -- the grouping is derived, so this is the assertion that keeps it derived:
    -- a solid in CAMP or a surface among the structures is a rail that lies
    -- about what a thing is.
    for _, e in ipairs(items()) do
        local kind = e.item.kind
        if kind and props.KINDS[kind] then
            local class = props.KINDS[kind].class
            if class == "solid" then
                H.expect(e.group == "structures", kind .. " is solid but sits in " .. e.group)
            else
                H.expect(e.group == "camp", kind .. " is " .. class .. " but sits in " .. e.group)
            end
        elseif kind then
            H.expect(e.group == "ground", kind .. " is a surface but sits in " .. e.group)
        end
    end
end

function M.the_caravan_is_placeable_and_water_is_not()
    local seen = {}
    for _, e in ipairs(items()) do
        if e.item.kind then seen[e.item.kind] = e.group end
    end
    -- level 1 parks a pitched caravan against a wall; before this the editor
    -- could not place the one kind the shipped levels already use
    H.expect(seen.caravan == "structures", "the caravan must be on the rail")
    -- water is only drawn inside the pool's own art; it becomes a palette item
    -- when a level paints with it, and UNPLACEABLE is where that decision lives
    H.expect(seen.water == nil, "water is not on the rail yet")
    H.expect(props.UNPLACEABLE.water == true, "and it says so where the vocabulary is")
end

function M.the_flat_order_lists_every_tile_once()
    local order = palette.order()
    local seen = {}
    for i, name in ipairs(order) do
        H.expect(seen[name] == nil, "appears twice in the [ ] order: " .. name)
        seen[name] = i
    end
    H.expect(order[1] == "select", "the cycle starts on select")
    H.expect(order[2] == "bay" and order[3] == "spawn", "then the level's own records")

    local n = #items()
    H.expect(#order == n, "the shortest path through the palette must reach every tile")
end

function M.every_tile_has_a_label_and_a_tooltip()
    for _, e in ipairs(items()) do
        local it = e.item
        H.expect(type(it.label) == "string" and #it.label > 0, "a tile needs a label")
        H.expect(type(it.title) == "string" and #it.title > 0, "a tooltip needs a name")
        H.expect(type(it.detail) == "string" and #it.detail > 0, "a tooltip needs its size")
        -- an 8 px label on a 46 px tile: a ninth character is a character cut in
        -- half, and the name is what makes four of the icons readable at all
        H.expect(#it.label <= 8, "label too long for a tile: " .. it.label)
    end
end

return M
