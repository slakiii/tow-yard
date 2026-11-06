-- Content identity. A level's ghost, its best time and a shared run's validity
-- all reduce to "hash this data", so the dump and the digest live in one place
-- and cannot disagree with each other.
--
-- Two kinds of hash, never conflated:
--   * canonical()/sha256() answer "is this the same content?" -- a level edit
--     changes it, whitespace and table order do not.
--   * build_hash() answers "is this the same simulation?" -- it covers the
--     constants that decide whether an input stream parks.
--
-- Not a signature. A run is trusted because it is replayed through the physics,
-- not because of its hash, so never describe this as anti-cheat.
--
-- Pure apart from the one love.data.hash call: no RNG, no os.time, no os.clock.
-- canonical() expects plain data (numbers, strings, booleans, tables); anything
-- else is marked by type rather than raising, because a hash is called from the
-- draw path and a crash there is worse than a hash that cannot be reproduced.

local rig = require("lib.rig")
local session = require("lib.session")

local M = {}

function M.sha256(s)
    -- love.data.hash returns the raw digest; hex is what goes in a document
    return love.data.encode("string", "hex", love.data.hash("sha256", s))
end

-- Hex prefix, for filenames and log lines. 8 chars is plenty to tell two levels
-- apart in a directory listing.
function M.short(hex, n)
    if type(hex) ~= "string" then return "" end
    return hex:sub(1, n or 8)
end

-- Stable text dump: sorted keys, fixed-precision numbers, quoted strings.
-- %.6f is a micrometre in metres and ~0.00006 deg in radians -- far below
-- anything a level can express, and coarse enough that float noise in a
-- computed coordinate cannot fork an otherwise identical level.
function M.canonical(v)
    local out = {}

    local function dump(x)
        local t = type(x)
        if t == "number" then
            local s = string.format("%.6f", x)
            -- -0.0 and 0.0 are the same coordinate; one of them must not hash
            if s == "-0.000000" then s = "0.000000" end
            out[#out + 1] = s
        elseif t == "string" then
            out[#out + 1] = string.format("%q", x)
        elseif t == "boolean" then
            out[#out + 1] = x and "true" or "false"
        elseif t == "table" then
            local keys = {}
            for k in pairs(x) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            out[#out + 1] = "{"
            for _, k in ipairs(keys) do
                out[#out + 1] = tostring(k)
                out[#out + 1] = "="
                dump(x[k])
                out[#out + 1] = ";"
            end
            out[#out + 1] = "}"
        else
            out[#out + 1] = "<" .. t .. ">"
        end
    end

    dump(v)
    return table.concat(out)
end

-- Copy `live` over `base` (both string-keyed constant tables).
local function merge(live, base)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    for k, v in pairs(live or {}) do out[k] = v end
    return out
end

-- The fingerprint of the simulation a run was recorded against: geometry, the
-- speed/steering dials and the parking rules. `override` replaces values one
-- level deep, so a test can move one constant without copying the world.
-- Quantisation steps default to their Task-14 values so this hash does not move
-- when the quantiser is added with the same numbers.
function M.build_hash(override)
    local consts = {
        step = rig.STEP,
        car = merge(rig.CAR),
        caravan = merge(rig.CARAVAN),
        tune = merge(rig.TUNE),
        session = merge({
            DWELL = session.DWELL,
            PARK_SPEED = session.PARK_SPEED,
            PARK_HOLD = session.PARK_HOLD,
            STEER_STEPS = session.STEER_STEPS or 127,
            PEDAL_STEPS = session.PEDAL_STEPS or 255,
        }),
    }

    for name, patch in pairs(override or {}) do
        consts[name] = merge(patch, consts[name])
    end

    return M.sha256(M.canonical(consts))
end

return M
