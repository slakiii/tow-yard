-- Device layer. Keyboard and gamepad both produce the same normalised input
-- table, so the physics never learns which device is in use.
--
-- sign convention: +steer is the wheel turned LEFT (counter-clockwise), which
-- is what the caravan model expects.

local M = {}

M.DEADZONE = 0.12
M.EXPO = 1.4
M.TRIGGER_MIN = 0.02   -- ignore trigger resting noise (some pads idle at -1)

M.KEYS = {
    forward = { "w", "up" },
    backward = { "s", "down" },
    left = { "a", "left" },
    right = { "d", "right" },
    handbrake = { "space" },
}

M.PAD = {
    reset = "b",
    guide = "y",
    pause = "start",
    handbrake = "a",
}

-- Remap-friendly: everything above is data, nothing is hardcoded in a callback.

function M.apply_curve(x)
    local ax = math.abs(x)
    if ax <= M.DEADZONE then return 0 end
    local t = (ax - M.DEADZONE) / (1 - M.DEADZONE)
    return (t ^ M.EXPO) * (x < 0 and -1 or 1)
end

-- A stick pushed left is negative x on screen; the physics wants positive.
function M.steer_from_stick(x)
    return -M.apply_curve(x)
end

function M.steer_from_keys(down)
    local left = 0
    for _, k in ipairs(M.KEYS.left) do
        if down(k) then left = left + 1 break end
    end
    local right = 0
    for _, k in ipairs(M.KEYS.right) do
        if down(k) then right = right + 1 break end
    end
    return left - right
end

local function any_down(list)
    for _, k in ipairs(list) do
        if love.keyboard.isDown(k) then return true end
    end
    return false
end

-- Merge one pad's axes and buttons into a normalised input, no love.* calls so
-- the mapping can be tested without hardware. The stronger of the two devices
-- wins per axis, so the pad and the keyboard can be held at the same time.
function M.merge_pad(input, pad)
    input = input or { steer = 0, throttle = 0, brake = 0, handbrake = false }
    local steer = M.steer_from_stick(pad.leftx or 0)
    if steer == 0 then
        -- D-pad is a digital fallback for pads without a usable stick
        steer = (pad.dpleft and 1 or 0) - (pad.dpright and 1 or 0)
    end
    if steer ~= 0 then
        input.steer = steer
        input.last_device = "gamepad"
    end
    local rt = math.max(0, pad.rt or 0)
    local lt = math.max(0, pad.lt or 0)
    if rt > M.TRIGGER_MIN then
        input.throttle = math.max(input.throttle or 0, rt)
        input.last_device = "gamepad"
    end
    if lt > M.TRIGGER_MIN then
        input.brake = math.max(input.brake or 0, lt)
        input.last_device = "gamepad"
    end
    if pad.handbrake then
        input.handbrake = true
        input.last_device = "gamepad"
    end
    return input
end

function M.new_state()
    return {
        steer = 0, throttle = 0, brake = 0, handbrake = false,
        last_device = "keyboard",
        prev_pad = {},
        joystick = nil,
    }
end

function M.init(st)
    local list = love.joystick.getJoysticks()
    st.joystick = list[1]
end

-- Called on love.joystickadded / love.joystickremoved. Re-fetching instead of
-- caching matters: LÖVE invalidates joystick handles on reconnect.
function M.refresh(st)
    local list = love.joystick.getJoysticks()
    st.joystick = list[1]
end

function M.poll(st)
    local steer = M.steer_from_keys(function(k) return love.keyboard.isDown(k) end)
    local throttle = any_down(M.KEYS.forward) and 1 or 0
    local brake = any_down(M.KEYS.backward) and 1 or 0
    local handbrake = any_down(M.KEYS.handbrake)
    local touched = steer ~= 0 or throttle > 0 or brake > 0 or handbrake

    local input = {
        steer = steer, throttle = throttle, brake = brake, handbrake = handbrake,
        last_device = touched and "keyboard" or st.last_device,
    }

    local js = st.joystick
    if js and js:isConnected() and js:isGamepad() then
        M.merge_pad(input, {
            leftx = js:getGamepadAxis("leftx"),
            lt = js:getGamepadAxis("triggerleft"),
            rt = js:getGamepadAxis("triggerright"),
            dpleft = js:isGamepadDown("dpleft"),
            dpright = js:isGamepadDown("dpright"),
            handbrake = js:isGamepadDown(M.PAD.handbrake),
        })
    end

    st.steer, st.throttle, st.brake, st.handbrake = input.steer, input.throttle, input.brake, input.handbrake
    st.last_device = input.last_device or st.last_device
    return st
end

-- Human-readable state of the attached pad, for the debug overlay: "is the
-- controller even seen?" is the first question of every controller bug report.
function M.pad_status(st)
    local js = st.joystick
    if not js or not js:isConnected() then return "no joystick" end
    if not js:isGamepad() then return js:getName() .. " (not a gamepad)" end
    return js:getName() .. (js:isVibrationSupported() and " +rumble" or "")
end

-- Edge-triggered pad buttons (keyboard equivalents are handled in love.keypressed).
function M.poll_actions(st)
    local acts = {}
    local js = st.joystick
    local down = {}
    if js and js:isConnected() and js:isGamepad() then
        for name, button in pairs({ reset = M.PAD.reset, guide = M.PAD.guide, pause = M.PAD.pause }) do
            down[name] = js:isGamepadDown(button)
            acts[name] = down[name] and not st.prev_pad[name]
        end
    end
    st.prev_pad = down
    return acts
end

-- Edge-triggered pad actions for the menus: a held direction must move the
-- cursor once, not scroll it every frame.
M.MENU_PAD = {
    up = "dpadup", down = "dpaddown", left = "dpadleft", right = "dpadright",
    confirm = "a", cancel = "b",
}
M.MENU_NAMES = { "up", "down", "left", "right", "confirm", "cancel" }
M.MENU_STICK = 0.55   -- a stick must cross this to count as a direction

-- Pure, so a resting pad can be shown to produce nothing without hardware.
function M.menu_edges(prev, now)
    local acts = {}
    for _, name in ipairs(M.MENU_NAMES) do
        acts[name] = (now[name] and not prev[name]) or false
    end
    return acts
end

function M.poll_menu(st)
    local now = {}
    local js = st.joystick
    if js and js:isConnected() and js:isGamepad() then
        for _, name in ipairs(M.MENU_NAMES) do
            now[name] = js:isGamepadDown(M.MENU_PAD[name]) and true or false
        end
        -- sticks as four directions, with a threshold: an analogue axis at rest
        -- drifts a few percent and would otherwise walk the menu by itself
        local lx = js:getGamepadAxis("leftx")
        local ly = js:getGamepadAxis("lefty")
        if lx < -M.MENU_STICK then now.left = true
        elseif lx > M.MENU_STICK then now.right = true end
        if ly < -M.MENU_STICK then now.up = true
        elseif ly > M.MENU_STICK then now.down = true end
    end
    local acts = M.menu_edges(st.prev_menu or {}, now)
    st.prev_menu = now
    return acts
end

-- Haptics: articulation is the thing a real driver feels through the seat, so
-- the rumble doubles as the instability warning.
function M.rumble(st, articulation, impact)
    local js = st.joystick
    if not js or not js:isConnected() or not js:isVibrationSupported() then return end
    local left, right = 0, 0
    local warn = (math.abs(articulation) - math.rad(45)) / math.rad(27)
    if warn > 0 then
        left = math.min(1, warn * 0.8)
        right = math.min(1, warn * 0.4)
    end
    if impact and impact > 0 then
        left = 1
        right = 1
    end
    js:setVibration(left, right)
end

return M
