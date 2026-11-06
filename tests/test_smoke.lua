-- Every pure module loads and exposes the expected surface, and the one
-- mechanism no pure test can reach -- love.filesystem, where progress lives --
-- behaves the way the store assumes it does.

local H = require("tests.helper")

local M = { order = { "modules_load", "no_love_calls_at_module_level",
                      "the_save_directory_round_trips", "a_missing_save_file_reads_as_nil" } }

-- Everything the game's rules live in. Drawing, input and the shell are not
-- here: they are allowed to touch love.* and are verified by --smoke.
local PURE = {
    "lib.geom", "lib.rig", "lib.session", "lib.levels", "lib.props",
    "lib.audit", "lib.levelcheck", "lib.levelfmt", "lib.hash", "lib.progress", "lib.run",
}

function M.modules_load()
    for _, name in ipairs(PURE) do
        local ok, mod = pcall(require, name)
        H.expect(ok, "failed to load " .. name .. ": " .. tostring(mod))
        H.expect(type(mod) == "table", name .. " did not return a table")
    end
end

function M.no_love_calls_at_module_level()
    -- Pure modules must not touch love.* while loading: the test runner has no
    -- window, and more importantly the rules have to stay device- and
    -- renderer-independent. A module that hashes or reads a file at load time
    -- would break this, which is why lib/hash.lua only calls love.data inside a
    -- function.
    local saved = love
    love = setmetatable({}, { __index = function(_, k)
        error("module-level love." .. tostring(k) .. " access", 2)
    end })
    local ok, err = pcall(function()
        for _, name in ipairs(PURE) do package.loaded[name] = nil end
        for _, name in ipairs(PURE) do require(name) end
    end)
    love = saved
    H.expect(ok, tostring(err))
end

function M.the_save_directory_round_trips()
    -- The mechanism, not the game's identity: this runs in the test save
    -- directory, so nothing here can pollute a player's progress.
    local name = "round-trip.txt"
    H.expect(love.filesystem.write(name, "hello"), "write must succeed")
    H.expect(love.filesystem.read(name) == "hello", "read must return what was written")
    love.filesystem.remove(name)
    H.expect(love.filesystem.read(name) == nil, "remove must actually remove")
end

function M.a_missing_save_file_reads_as_nil()
    -- progress.open() depends on a missing file being nil plus a reason, not an
    -- error the shell has to catch: a first launch is the common case.
    local data, reason = love.filesystem.read("no-such-progress-file.txt")
    H.expect(data == nil, "a missing file must read as nil, not raise")
    H.expect(type(reason) == "string", "and carry a reason")
end

return M
