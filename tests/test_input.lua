-- Device layer: the stick curve and the sign conventions the physics expects.
-- Keyboard and gamepad must produce the same normalised steer target, or the
-- two devices stop being the same game.

local H = require("tests.helper")
local input = require("lib.input")

local M = { order = { "deadzone_kills_drift", "curve_is_monotonic", "curve_gives_fine_control_near_centre",
                      "stick_left_is_positive_steer", "keyboard_matches_pad_sign" } }

function M.deadzone_kills_drift()
    H.near(input.apply_curve(0.05), 0, 1e-12, "small drift")
    H.near(input.apply_curve(-0.11), 0, 1e-12, "drift the other way")
    H.expect(input.apply_curve(0.5) > 0, "half deflection steers")
end

function M.curve_is_monotonic()
    local prev = -1
    for i = 0, 100 do
        local v = input.apply_curve(i / 100)
        H.expect(v >= prev - 1e-12, "curve must be monotonic at " .. i)
        prev = v
    end
    H.near(input.apply_curve(1), 1, 1e-9, "full deflection")
end

function M.curve_gives_fine_control_near_centre()
    -- A 20% deflection must stay well under a linear mapping (0.20): that is the
    -- resolution the reverse maneuver lives on.
    H.expect(input.apply_curve(0.20) < 0.12, "20% stick should give well under 20% lock")
    H.expect(input.apply_curve(0.20) > 0.01, "20% stick must still steer")
end

function M.stick_left_is_positive_steer()
    -- +steer is the wheel turned left (CCW); a stick pushed left is negative x.
    H.expect(input.steer_from_stick(-0.8) > 0, "stick left must be positive steer")
    H.expect(input.steer_from_stick(0.8) < 0, "stick right must be negative steer")
end

function M.keyboard_matches_pad_sign()
    local function down(keys)
        return function(k)
            for _, v in ipairs(keys) do if v == k then return true end end
            return false
        end
    end
    H.near(input.steer_from_keys(down({ "a" })), 1, 1e-9, "A is left")
    H.near(input.steer_from_keys(down({ "left" })), 1, 1e-9, "Left arrow is left")
    H.near(input.steer_from_keys(down({ "d" })), -1, 1e-9, "D is right")
    H.near(input.steer_from_keys(down({})), 0, 1e-9, "no keys, centred")
    H.near(input.steer_from_keys(down({ "a", "d" })), 0, 1e-9, "both keys cancel")
end

return M
