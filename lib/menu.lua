-- The level select as data: two tabs of ordered levels, each with its own cursor.
--
-- The campaign and the custom levels are separate lists rather than one list with
-- a badge, because a level somebody imported is not part of the campaign and must
-- not be able to hide between two shipped ones.
--
-- There are no heading rows in the model, on purpose. A series heading is a
-- thing the cursor can point at but cannot open, and every menu bug of that
-- shape is a confirm that does nothing. The model holds only levels; the
-- renderer draws a heading whenever the series changes.
--
-- Order is derived, not stored twice: series appear in the order they first
-- appear in the catalogue, levels inside a series by their `order`. Move a level
-- to another series and the menu follows without a second table to keep in sync.

local progress = require("lib.progress")

local M = {}

local function ordered(shipped, custom)
    local list = {}
    for _, lvl in ipairs(shipped or {}) do list[#list + 1] = lvl end
    for _, lvl in ipairs(custom or {}) do list[#list + 1] = lvl end

    local series, seen = {}, {}
    for _, lvl in ipairs(list) do
        local s = lvl.series or ""
        if not seen[s] then
            seen[s] = true
            series[#series + 1] = s
        end
    end

    local rows = {}
    for _, s in ipairs(series) do
        local group = {}
        for _, lvl in ipairs(list) do
            if (lvl.series or "") == s then group[#group + 1] = lvl end
        end
        table.sort(group, function(a, b)
            -- an unordered level (a custom one) sorts last within its group
            local oa, ob = a.order or math.huge, b.order or math.huge
            if oa ~= ob then return oa < ob end
            return tostring(a.id) < tostring(b.id)
        end)
        for _, lvl in ipairs(group) do rows[#rows + 1] = lvl end
    end
    return rows
end

M.TABS = { "campaign", "custom" }

function M.new(shipped, custom, progress)
    local self = {
        progress = progress,
        tab = "campaign",
        -- each tab has its own cursor: switching tabs must not move the other
        -- one, or a player who peeks at their imports loses their place
        index = { campaign = nil, custom = nil },
        lists = { campaign = ordered(shipped, nil), custom = ordered(custom, nil) },
    }
    for name, rows in pairs(self.lists) do
        if #rows > 0 then self.index[name] = 1 end
    end
    return self
end

function M.rows(self) return self.lists[self.tab] or {} end

function M.count(self) return #M.rows(self) end

function M.current_tab(self) return self.tab end

-- Returns false when the tab does not exist, so a caller cannot invent one.
function M.switch_tab(self, name)
    if not self.lists[name] then return false end
    self.tab = name
    return true
end

function M.cycle_tab(self, d)
    for i, name in ipairs(M.TABS) do
        if name == self.tab then
            local n = #M.TABS
            return M.switch_tab(self, M.TABS[((i - 1 + (d or 1)) % n) + 1])
        end
    end
    return false
end

-- The cursor wraps, so holding down on the last level is not a dead key.
function M.move(self, d)
    local rows = M.rows(self)
    local n = #rows
    if n == 0 then
        self.index[self.tab] = nil
        return self
    end
    self.index[self.tab] = ((self.index[self.tab] or 1) - 1 + (d or 1)) % n + 1
    return self
end

-- Put the cursor on a level by id, in whichever tab holds it -- the level you
-- just played is the one you are most likely to want. Returns the tab it found,
-- or nil when that level is not in the menu any more (deleted, or a custom level
-- whose file is gone).
function M.focus(self, id)
    if not id then return nil end
    for _, name in ipairs(M.TABS) do
        for i, lvl in ipairs(self.lists[name] or {}) do
            if lvl.id == id then
                self.tab = name
                self.index[name] = i
                return name
            end
        end
    end
    return nil
end

function M.current(self)
    local i = self.index[self.tab]
    if not i then return nil end
    return self.lists[self.tab][i]
end

-- Rebuild after an import or a delete, keeping both cursors where they were.
function M.rebuild(self, shipped, custom)
    local tab, index = self.tab, self.index
    self.lists = { campaign = ordered(shipped, nil), custom = ordered(custom, nil) }
    for name, rows in pairs(self.lists) do
        local i = index[name]
        if not i or i > #rows then i = (#rows > 0) and 1 or nil end
        self.index[name] = i
    end
    self.tab = tab
    return self
end

function M.confirm(self)
    return M.current(self)
end

function M.mark(self, level)
    if not (self.progress and level) then return { completed = false } end
    -- the store is plain data; its functions live on the module, like every
    -- other pure module here (session.update(s, ...), not s:update())
    return progress.mark(self.progress, level)
end

return M
