-- Headless test runner: run from repo root with `love tests`.
-- Each listed module returns { order = { names... }, test_name = function }.
-- Exit code 0 = all passed, 1 = at least one failure.

local MODULES = {
    "tests/test_smoke",
    "tests/test_geom",
    "tests/test_rig",
    "tests/test_session",
    "tests/test_levels",
    "tests/test_props",
    "tests/test_draw",
    "tests/test_audit",
    "tests/test_input",
    "tests/test_hash",
    "tests/test_levelfmt",
    "tests/test_progress",
    "tests/test_menu",
    "tests/test_run",
    "tests/test_share",
    "tests/test_edit_doc",
    "tests/test_input_pad",
    "tests/test_edit_undo",
    "tests/test_edit_autosave",
}

local function runModule(name)
    local mod = require(name)
    local results = {}
    for _, testName in ipairs(mod.order or {}) do
        local fn = mod[testName]
        local ok, err = pcall(fn)
        table.insert(results, { name = name .. "." .. testName, ok = ok, err = err })
    end
    return results
end

function love.load()
    local passed, failed = 0, 0

    for _, name in ipairs(MODULES) do
        local ok, modOrErr = pcall(require, name)
        if not ok then
            print("MODULE LOAD FAILED: " .. name)
            print(modOrErr)
            failed = failed + 1
        else
            for _, r in ipairs(runModule(name)) do
                if r.ok then
                    passed = passed + 1
                    print("PASS " .. r.name)
                else
                    failed = failed + 1
                    print("FAIL " .. r.name .. "\n  " .. tostring(r.err))
                end
            end
        end
    end

    print(string.format("\n%d passed, %d failed", passed, failed))
    love.event.quit(failed > 0 and 1 or 0)
end
