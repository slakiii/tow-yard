-- The editor's palette as data: the rail's groups, their order, and what each
-- tile says. Pure, so the view (pixels), the shell (clicks, [ ] cycling) and
-- this module cannot disagree about what the rail holds.
--
-- The grouping is derived from the vocabulary: solid kinds are structures,
-- knockable kinds are camp, surfaces are ground paint, and the order comes from
-- props.PALETTE. A kind added there appears on the rail; a kind added nowhere
-- is caught by tests/test_props.lua.
local props = require("lib.props")

local M = {}

M.GROUPS = {
    { id = "tool", label = "TOOL" },
    { id = "level", label = "LEVEL" },
    { id = "structures", label = "STRUCTURES" },
    { id = "camp", label = "CAMP" },
    { id = "ground", label = "GROUND" },
}

-- The rail's own tools. They are not prop kinds, so they carry their own words.
local TOOLS = {
    { tool = "select", label = "select", title = "Select",
      detail = "click a prop to select it; drag moves; Q/E turns" },
    { tool = "bay", label = "bay", title = "Parking bay",
      detail = "the goal; free resize; apron says how much room it needs" },
    { tool = "spawn", label = "start", title = "Start position",
      detail = "one pose; no resize; where the rig begins" },
}

local MEMBERS = {
    tool = { "select" },
    level = { "bay", "spawn" },
}

local RESIZE_WORDS = {
    none = "one size",
    length = "stretches along its length only",
    free = "free resize",
}

local function kind_item(kind)
    local def = props.get(kind) or props.SURFACES[kind]
    if not def then return nil end
    local size
    if def.r then
        size = string.format("r %.2f m", def.r)
    elseif def.w and def.h then
        size = string.format("%.1f x %.1f m", def.w, def.h)
    else
        -- a surface: it has a colour and a resize, not a footprint
        size = "paint only"
    end
    return {
        kind = kind,
        label = def.short or def.label,
        title = def.label or kind,
        detail = size .. " - " .. (RESIZE_WORDS[props.resize_mode(kind)] or "free resize"),
    }
end

local function tool_item(name)
    for _, t in ipairs(TOOLS) do
        if t.tool == name then return t end
    end
    return nil
end

-- Every group, in rail order. Each item is { tool = name } or { kind = kind },
-- plus the words a tile and its tooltip need.
function M.groups()
    local out = {}
    for _, g in ipairs(M.GROUPS) do
        local group = { id = g.id, label = g.label, items = {} }
        local names = MEMBERS[g.id]
        if names then
            for _, name in ipairs(names) do
                local it = tool_item(name)
                if it then group.items[#group.items + 1] = it end
            end
        else
            for _, kind in ipairs(props.PALETTE[g.id] or {}) do
                local it = kind_item(kind)
                if it then group.items[#group.items + 1] = it end
            end
        end
        if #group.items > 0 then out[#out + 1] = group end
    end
    return out
end

-- The tile's name for the shell: `e.tool` is one of these strings.
function M.name(item)
    return item.tool or item.kind
end

-- The flat order, for [ ] cycling and for anything that asks "what is next".
function M.order()
    local names = {}
    for _, group in ipairs(M.groups()) do
        for _, item in ipairs(group.items) do names[#names + 1] = M.name(item) end
    end
    return names
end

return M
