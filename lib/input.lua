-- Device layer. Keyboard and gamepad both produce the same normalised input
-- table, so the physics never learns which device is in use.
--
-- sign convention: +steer is the wheel turned LEFT (counter-clockwise), which
-- is what the caravan model expects.

local M = {}

M.DEADZONE = 0.12
M.EXPO = 1.4

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
    local device = (steer ~= 0 or throttle > 0 or brake > 0 or handbrake) and "keyboard" or st.last_device

    local js = st.joystick
    if js and js:isConnected() and js:isGamepad() then
        local pad_steer = M.steer_from_stick(js:getGamepadAxis("leftx"))
        local rt = math.max(0, js:getGamepadAxis("triggerright"))
        local lt = math.max(0, js:getGamepadAxis("triggerleft"))

        if math.abs(pad_steer) > 0 then steer = pad_steer device = "gamepad" end
        if rt > 0.02 then throttle = math.max(throttle, rt) device = "gamepad" end
        if lt > 0.02 then brake = math.max(brake, lt) device = "gamepad" end
        if js:isGamepadDown(M.PAD.handbrake) then handbrake = true device = "gamepad" end
    end

    st.steer, st.throttle, st.brake, st.handbrake = steer, throttle, brake, handbrake
    st.last_device = device
    return st
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
