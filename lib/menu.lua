-- The level select as data: a flat, ordered list of levels plus a cursor.
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

function M.new(shipped, custom, progress)
    local self = { progress = progress, rows = ordered(shipped, custom) }
    self.index = (#self.rows > 0) and 1 or nil
    return self
end

function M.rows(self) return self.rows end

function M.count(self) return #(self.rows or {}) end

-- The cursor wraps, so holding down on the last level is not a dead key.
function M.move(self, d)
    local n = #(self.rows or {})
    if n == 0 then
        self.index = nil
        return self
    end
    self.index = ((self.index or 1) - 1 + (d or 1)) % n + 1
    return self
end

function M.current(self)
    if not self.index then return nil end
    return self.rows[self.index]
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
