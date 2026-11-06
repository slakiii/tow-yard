-- The level document: a level must survive a trip through text unchanged, and
-- the text must be the *authored* data -- a size that is already the kind's
-- default is not written out, or every hedge in the campaign starts carrying
-- numbers nobody chose and the file stops reading like the level.

local H = require("tests.helper")
local levels = require("lib.levels")
local levelfmt = require("lib.levelfmt")

local M = { order = {
    "every_shipped_level_round_trips",
    "default_sizes_are_not_written_out",
} }

function M.every_shipped_level_round_trips()
    for _, lvl in ipairs(levels.ALL) do
        local text = levelfmt.encode(lvl)
        local back, err = levelfmt.decode(text)
        H.expect(back ~= nil, lvl.name .. ": " .. tostring(err))
        H.expect(levelfmt.encode(back) == text, lvl.name .. ": not byte-stable")
    end
end

function M.default_sizes_are_not_written_out()
    local text = levelfmt.encode(levels.get(1))
    local line
    for l in text:gmatch("[^\n]+") do
        if l:match("^wall building") then line = l end
    end
    H.expect(line ~= nil, "level 1 should still have its clubhouse")
    local n = 0
    for _ in line:gmatch("%S+") do n = n + 1 end
    H.expect(n == 4, "a default-sized prop is kind, x, y -- got: " .. line)
end

return M
