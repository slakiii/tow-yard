-- The gamepad path, driven by a fake pad.
--
-- This file exists because "dpadup" shipped: LÖVE has no such button, and
-- isGamepadDown RAISES on an unknown name, so plugging a controller in and
-- pressing nothing at all crashed the level select. The suite had never had a
-- controller attached, so every line below this one had executed in play and
-- none of it in a test.
--
-- The fake validates the names it is asked for, which is the point: a wrong name
-- becomes a failing test instead of a crash at the kitchen table.

local H = require("tests.helper")
local input = require("lib.input")

local M = { order = {
    "the_vocabulary_is_what_love_calls_these",
    "a_fake_pad_drives_the_car",
    "a_drifting_pad_does_not_override_a_held_key",
    "menu_directions_fire_once_per_press",
    "menu_edges_ignore_a_resting_stick",
    "pad_buttons_are_edge_triggered",
    "an_unknown_button_name_fails_here_not_in_a_game",
} }

local function vocabulary()
    local ok, axes = {}, {}
    for _, name in pairs(input.BUTTONS) do ok[name] = true end
    for _, name in pairs(input.AXES) do axes[name] = true end
    return ok, axes
end

-- A pad that refuses to be asked for something LÖVE does not have.
local function fake_pad(opts)
    opts = opts or {}
    local buttons, axes = vocabulary()
    local pad = {
        name = opts.name or "Fake Pad",
        down = opts.down or {},
        axis = opts.axis or {},
        connected = true,
        gamepad = true,
        vibe = opts.vibe or false,
    }
    function pad:isConnected() return self.connected end
    function pad:isGamepad() return self.gamepad end
    function pad:getName() return self.name end
    function pad:isVibrationSupported() return self.vibe end
    function pad:setVibration(l, r) self.vibrated = { l, r } end
    function pad:isGamepadDown(name)
        H.expect(buttons[name], "not a LÖVE gamepad button: " .. tostring(name))
        return self.down[name] or false
    end
    function pad:getGamepadAxis(name)
        H.expect(axes[name], "not a LÖVE gamepad axis: " .. tostring(name))
        return self.axis[name] or 0
    end
    return pad
end

local function with_pad(pad)
    local saved = input.get_joysticks
    input.get_joysticks = function() return pad and { pad } or {} end
    local st = input.new_state()
    input.init(st)
    return st, function() input.get_joysticks = saved end
end

function M.the_vocabulary_is_what_love_calls_these()
    -- the documented LÖVE 11 GamepadButton set
    local real = {
        a = true, b = true, x = true, y = true, back = true, guide = true,
        start = true, leftstick = true, rightstick = true, leftshoulder = true,
        rightshoulder = true, dpup = true, dpdown = true, dpleft = true, dpright = true,
    }
    for key, name in pairs(input.BUTTONS) do
        H.expect(real[name], "input.BUTTONS." .. key .. " is not a real button: " .. name)
    end
    for key, name in pairs(input.MENU_PAD) do
        H.expect(real[name], "MENU_PAD." .. key .. " is not a real button: " .. name)
    end
    for key, name in pairs(input.PAD) do
        H.expect(real[name], "PAD." .. key .. " is not a real button: " .. name)
    end
    -- the four directions a menu needs must all be bound
    for _, dir in ipairs({ "up", "down", "left", "right", "confirm", "cancel" }) do
        H.expect(input.MENU_PAD[dir], "MENU_PAD is missing " .. dir)
    end
end

function M.a_fake_pad_drives_the_car()
    local pad = fake_pad({
        down = { [input.PAD.handbrake] = true },
        axis = { leftx = -0.9, triggerright = 1, triggerleft = 0 },
    })
    local st, done = with_pad(pad)
    input.poll(st)
    done()

    H.expect(st.throttle == 1, "the right trigger is the throttle: " .. st.throttle)
    H.expect(st.handbrake == true, "the handbrake button is the handbrake")
    -- stick left is -1 in LÖVE; +steer is "wheel turned left" (module header),
    -- so the two signs are opposite on purpose
    H.expect(st.steer > 0.5, "stick left steers left: " .. st.steer)
    H.expect(st.last_device == "gamepad",
        "a pad that moves something is the last device -- it is what the on-screen "
        .. "hints key off: " .. tostring(st.last_device))

    -- and when the pad is idle the attribution stays where it was
    input.poll(st)
    H.expect(st.last_device == "gamepad", "no keyboard input does not steal it back")
end

-- The module header and the README both promise "the stronger of the two
-- devices wins per axis". merge_pad used to OVERWRITE the keyboard whenever the
-- stick cleared the deadzone, so a pad resting at a few percent of drift
-- steered the car by itself -- in the OPPOSITE lock to the key being held --
-- and stole the HUD's device glyph while the player was on the keyboard.
--
-- This is the case the old suite missed: `menu_edges_ignore_a_resting_stick`
-- only checks hands-off. "A resting pad changes nothing" is also satisfied by a
-- merge that ignores the pad entirely, which is the opposite bug, so both
-- halves are pinned here.
function M.a_drifting_pad_does_not_override_a_held_key()
    local drift = input.steer_from_stick(0.2)
    H.expect(math.abs(drift) > 0, "0.2 is past the deadzone, so it is real drift")
    H.expect(math.abs(drift) < 0.1, "and it is weak: " .. drift)

    -- keyboard held LEFT is +1 by the module's sign convention
    local held = { steer = 1, throttle = 0, brake = 0, handbrake = false,
                   last_device = "keyboard" }
    input.merge_pad(held, { leftx = 0.2 })
    H.expect(held.steer == 1,
        "a weak pad must not override a held key -- got " .. held.steer ..
        ", which would steer the car the opposite way")
    H.expect(held.last_device == "keyboard",
        "and a pad that did not win must not steal the device glyph: "
        .. tostring(held.last_device))

    -- the other half of the contract: a genuinely stronger stick still wins,
    -- or the "strongest wins" rule has been replaced by "keyboard always wins"
    local light = { steer = 0.2, throttle = 0, brake = 0, handbrake = false,
                    last_device = "keyboard" }
    input.merge_pad(light, { leftx = -0.9 })
    H.expect(light.steer > 0.5, "a strong stick must still win: " .. light.steer)
    H.expect(light.last_device == "gamepad", "and take the glyph when it does")
end

function M.menu_directions_fire_once_per_press()
    local pad = fake_pad({ down = { dpdown = true } })
    local st, done = with_pad(pad)

    local first = input.poll_menu(st)
    H.expect(first.down == true, "a fresh press is an edge")
    local second = input.poll_menu(st)
    H.expect(second.down == false, "and holding it is not a second press")

    pad.down.dpdown = false
    input.poll_menu(st)
    pad.down.dpdown = true
    H.expect(input.poll_menu(st).down == true, "releasing and pressing is a new edge")
    done()
end

function M.menu_edges_ignore_a_resting_stick()
    local pad = fake_pad({ axis = { leftx = 0.2, lefty = -0.1 } })  -- drift, at rest
    local st, done = with_pad(pad)
    local acts = input.poll_menu(st)
    for _, name in ipairs(input.MENU_NAMES) do
        H.expect(acts[name] == false, "a resting stick must not move the cursor: " .. name)
    end

    pad.axis.leftx = 0.9
    H.expect(input.poll_menu(st).right == true, "past the threshold it does")
    done()
end

function M.pad_buttons_are_edge_triggered()
    local pad = fake_pad({ down = { [input.PAD.reset] = true } })
    local st, done = with_pad(pad)
    H.expect(input.poll_actions(st).reset == true, "reset fires on the press")
    H.expect(input.poll_actions(st).reset == false, "and not again while held")
    done()
end

function M.an_unknown_button_name_fails_here_not_in_a_game()
    -- the regression itself: a pad asked for a button LÖVE does not have must
    -- raise inside the fake, which the runner reports as a failed test
    local pad = fake_pad()
    local ok, err = pcall(function() return pad:isGamepadDown("dpadup") end)
    H.expect(ok == false, "dpadup must not be accepted")
    H.expect(tostring(err):find("not a LÖVE gamepad button") ~= nil,
        "and the failure names the button: " .. tostring(err))

    -- and no pad at all is not a crash
    local st, done = with_pad(nil)
    input.poll(st)
    H.expect(input.poll_menu(st).down == false, "no pad, no menu input, no error")
    H.expect(input.pad_status(st) == "no joystick", "and it says so")
    done()
end

return M
