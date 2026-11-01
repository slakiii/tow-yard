-- Every pure module loads and exposes the expected surface.

local H = require("tests.helper")

local M = { order = { "modules_load", "no_love_calls_at_module_level" } }

function M.modules_load()
    for _, name in ipairs({ "lib.geom", "lib.rig", "lib.session", "lib.levels", "lib.input" }) do
        local ok, mod = pcall(require, name)
        H.expect(ok, "failed to load " .. name .. ": " .. tostring(mod))
        H.expect(type(mod) == "table", name .. " did not return a table")
    end
end

function M.no_love_calls_at_module_level()
    -- Pure modules must not touch love.* while loading: the test runner has no
    -- window, and more importantly the physics has to stay device- and
    -- renderer-independent.
    local saved = love
    love = setmetatable({}, { __index = function(_, k)
        error("module-level love." .. tostring(k) .. " access", 2)
    end })
    local ok, err = pcall(function()
        package.loaded["lib.geom"] = nil
        package.loaded["lib.rig"] = nil
        package.loaded["lib.session"] = nil
        package.loaded["lib.levels"] = nil
        require("lib.geom"); require("lib.rig"); require("lib.session"); require("lib.levels")
    end)
    love = saved
    H.expect(ok, tostring(err))
end

return M
