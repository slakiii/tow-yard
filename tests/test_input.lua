-- Device layer: the stick curve and the sign conventions the physics expects.
-- Keyboard and gamepad must produce the same normalised steer target, or the
-- two devices stop being the same game.

local H = require("tests.helper")
local input = require("lib.input")

local M = { order = { "deadzone_kills_drift", "curve_is_monotonic", "curve_gives_fine_control_near_centre",
                      "stick_left_is_positive_steer", "keyboard_matches_pad_sign",
                      "pad_maps_stick_triggers_and_handbrake", "dpad_steers_when_the_stick_is_centred",
                      "pad_and_keyboard_merge_by_strongest_input", "idle_pad_changes_nothing" } }

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

local function empty()
    return { steer = 0, throttle = 0, brake = 0, handbrake = false, last_device = "keyboard" }
end

function M.pad_maps_stick_triggers_and_handbrake()
    local i = input.merge_pad(empty(), { leftx = -0.8, rt = 1, lt = 0, handbrake = true })
    H.expect(i.steer > 0, "stick left must steer left (+)")
    H.near(i.throttle, 1, 1e-9, "right trigger is throttle")
    H.near(i.brake, 0, 1e-9, "left trigger untouched")
    H.expect(i.handbrake, "A is the handbrake")
    H.expect(i.last_device == "gamepad", "pad input claims the HUD glyphs")
end

function M.dpad_steers_when_the_stick_is_centred()
    local left = input.merge_pad(empty(), { leftx = 0, dpleft = true })
    H.near(left.steer, 1, 1e-9, "d-pad left is full left lock")
    local right = input.merge_pad(empty(), { leftx = 0, dpright = true })
    H.near(right.steer, -1, 1e-9, "d-pad right is full right lock")
    -- a deflected stick wins over the d-pad
    local both = input.merge_pad(empty(), { leftx = -0.5, dpright = true })
    H.expect(both.steer > 0, "stick deflection must override the d-pad")
end

function M.pad_and_keyboard_merge_by_strongest_input()
    local held = { steer = 0, throttle = 1, brake = 0, handbrake = false, last_device = "keyboard" }
    local i = input.merge_pad(held, { rt = 0.4 })
    H.near(i.throttle, 1, 1e-9, "keyboard full throttle wins over a half trigger")
    local j = input.merge_pad({ steer = 0, throttle = 0, brake = 0, handbrake = false }, { rt = 0.4 })
    H.near(j.throttle, 0.4, 1e-9, "pad throttle applies when the keyboard is idle")
end

function M.idle_pad_changes_nothing()
    -- a resting pad must not claim the glyphs or nudge the steering: some pads
    -- idle their triggers at -1 and drift their sticks a little
    local i = input.merge_pad(empty(), { leftx = 0.05, lt = -1, rt = -1 })
    H.near(i.steer, 0, 1e-12, "deadzone must hold at rest")
    H.near(i.brake, 0, 1e-12, "a -1 resting trigger is not a brake")
    H.near(i.throttle, 0, 1e-12, "a -1 resting trigger is not a throttle")
    H.expect(i.last_device == "keyboard", "an idle pad must not steal the glyphs")
end

return M
