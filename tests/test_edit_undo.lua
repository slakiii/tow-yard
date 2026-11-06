-- Snapshot undo. The properties: a snapshot restores the level exactly, the
-- stack is bounded in both depth and bytes, and undo past the beginning is a
-- no-op rather than a crash.

local H = require("tests.helper")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")
local doc = require("lib.edit.doc")
local undo = require("lib.edit.undo")

local M = { order = {
    "a_snapshot_restores_the_level_exactly",
    "the_stack_is_bounded_in_depth",
    "the_stack_is_bounded_in_bytes",
    "undo_past_the_beginning_is_a_no_op",
} }

function M.a_snapshot_restores_the_level_exactly()
    local d = doc.new(levels.get(1))
    local u = undo.new()
    local before = levelfmt.content_hash(doc.level(d))

    undo.push(u, doc.snapshot(d))
    doc.add(d, "cone", 30, 20)
    doc.set_bay(d, { x = 40 })
    H.expect(levelfmt.content_hash(doc.level(d)) ~= before, "fixture: the edits must change the level")

    local text = undo.back(u)
    H.expect(text ~= nil, "back must return the snapshot")
    H.expect(doc.restore(d, text), "and it must decode")
    H.expect(levelfmt.content_hash(doc.level(d)) == before, "restoring must be exact")
    H.expect(undo.can_undo(u) == false, "and the stack is spent")
end

function M.the_stack_is_bounded_in_depth()
    local u = undo.new()
    for i = 1, undo.DEPTH + 8 do undo.push(u, "doc " .. i) end
    H.expect(undo.depth(u) == undo.DEPTH, "depth is capped: " .. undo.depth(u))
    H.expect(u.dropped == 8, "and the eight oldest were dropped: " .. u.dropped)
    -- the most RECENT past survives; that is the part anyone wants back
    local deepest = nil
    while true do
        local text = undo.back(u)
        if not text then break end
        deepest = text
    end
    H.expect(deepest == "doc 9", "the oldest surviving snapshot is the ninth: " .. tostring(deepest))
end

function M.the_stack_is_bounded_in_bytes()
    local u = undo.new()
    local big = string.rep("x", math.floor(undo.BUDGET / 2))
    for i = 1, 5 do undo.push(u, big .. i) end
    H.expect(u.bytes <= undo.BUDGET, "bytes are capped: " .. u.bytes)
    H.expect(undo.depth(u) >= 1, "but at least one snapshot always survives")
end

function M.undo_past_the_beginning_is_a_no_op()
    local u = undo.new()
    H.expect(undo.back(u) == nil, "an empty stack returns nothing")
    H.expect(undo.can_undo(u) == false, "and says so")
    undo.push(u, "one")
    H.expect(undo.back(u) == "one", "one push, one back")
    H.expect(undo.back(u) == nil, "then empty again")
end

return M
