-- Undo, as a stack of canonical documents.
--
-- Snapshot rather than command: a level is a few kilobytes, thirty-two of them
-- is under a quarter of a megabyte, and the command-pattern alternative (every
-- op implemented twice, once forward and once in reverse) is a class of bugs
-- this game does not need. If the editor ever wants drag-coalescing, it can be
-- added ON TOP of snapshots.
--
-- The stack records the state BEFORE an edit: push what you are about to change,
-- then change it. `back` returns the text to restore and forgets it.

local M = {}

M.DEPTH = 32
M.BUDGET = 256 * 1024      -- bytes; whichever limit bites first wins

function M.new()
    return { stack = {}, bytes = 0, dropped = 0 }
end

function M.push(undo, text)
    if not text then return undo end
    undo.stack[#undo.stack + 1] = text
    undo.bytes = undo.bytes + #text

    -- Oldest first: the recent past is the part a player wants.
    while #undo.stack > M.DEPTH or (undo.bytes > M.BUDGET and #undo.stack > 1) do
        local oldest = table.remove(undo.stack, 1)
        undo.bytes = undo.bytes - #oldest
        undo.dropped = undo.dropped + 1
    end
    return undo
end

function M.back(undo)
    if #undo.stack == 0 then return nil end
    local text = table.remove(undo.stack)
    undo.bytes = undo.bytes - #text
    return text
end

function M.can_undo(undo)
    return #undo.stack > 0
end

function M.depth(undo)
    return #undo.stack
end

return M
