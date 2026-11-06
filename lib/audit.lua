-- Level audit: can this level be parked at all, and what is the shortest line a
-- machine can find?
--
-- This is a development instrument, not game code: it never runs during play.
-- It exists because a hand-authored level can be unwinnable and "it looks fine"
-- is not evidence. Run it with `love . --audit N` (or `--audit all`).
--
-- Method: drive from the spawn to a staging pose on a grid along the bay axis,
-- reverse in with an articulation-bounded controller, and let the game's own
-- park test decide. The best line is then replayed through a FRESH session and
-- the final pose compared, so a park is reproduced rather than reported -- a
-- probe that only agrees with itself is worth nothing.
--
-- What it does NOT prove: that a human enjoys the line, or that the approach it
-- used is the one a player would find. Level 2 defeats it outright (its spawn
-- faces a hedge 0.7 m away and this controller cannot do a three-point turn).
-- A "no line found" verdict therefore means "needs a playtest", not
-- "unwinnable" -- but a line that IS found is real, in the shipped physics.
--
-- Pure: no love.* at all, so `love tests` can drive it.

local session = require("lib.session")
local rig = require("lib.rig")
local geom = require("lib.geom")

local M = {}

M.DT = 1 / 120
M.APPROACH_T = 26        -- seconds allowed to reach a staging pose
M.REVERSE_T = 45         -- seconds allowed to reverse in and park

-- Staging poses searched by default. 360 poses costs ~20 s per level with the
-- full grid; `--quick` trades coverage for a few seconds.
M.GRID = {
    pre = { 0, 4 },                                   -- metres reversed before trying
    dist = { 6, 8, 10, 13 },                          -- along the bay axis, past the bay
    off = { -7, -5, -3, -1.5, 0, 1.5, 3, 5, 7 },      -- sideways from the axis
    dpsi = { -30, -15, 0, 15, 30 },                   -- heading error to the axis, degrees
}
M.QUICK_GRID = {
    pre = { 0 },
    dist = { 8, 11 },
    off = { -3, 0, 3 },
    dpsi = { -20, 0, 20 },
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Back straight off the spawn for a few metres. Level 2 spawns 0.7 m from a
-- hedge, so "drive to a staging pose" has to include the first thing any driver
-- does there. Kept in the search rather than hardcoded because it costs time.
local function preamble(s, metres, max_t)
    local x0, y0 = s.rig.x, s.rig.y
    local t = 0
    while t < max_t do
        session.update(s, { steer = 0, throttle = 0, brake = 0.6, handbrake = false }, M.DT)
        t = t + M.DT
        if s.bumps > 0 then return false, t end
        local dx, dy = s.rig.x - x0, s.rig.y - y0
        if dx * dx + dy * dy >= metres * metres then
            for _ = 1, 60 do
                session.update(s, { steer = 0, throttle = 0, brake = 0, handbrake = true }, M.DT)
            end
            return s.bumps == 0, t + 0.5
        end
    end
    return false, t
end

local function approach(s, tx, ty, tth, max_t, force_reverse)
    local t = 0
    local reversing = force_reverse
    while t < max_t do
        local dx, dy = tx - s.rig.x, ty - s.rig.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local bearing = math.atan2(dy, dx)
        if reversing == nil then
            -- Decided once, not per frame: flipping gear on an overshoot makes
            -- the controller orbit a close pose forever.
            reversing = math.abs(geom.wrap(bearing - s.rig.th)) > math.rad(110)
        end
        local target_th = reversing and geom.wrap(bearing + math.pi) or bearing
        local err = geom.wrap(target_th - s.rig.th)
        local pedal = clamp(dist / 3 + 0.2, 0.3, 1)
        if math.abs(err) > 0.7 then pedal = math.min(pedal, 0.5) end
        if dist < 1.6 then pedal = math.min(pedal, 0.4) end

        if reversing then
            -- Drive the ARTICULATION, not the heading: steering a heading error
            -- at lock jackknifes in about 2 s (the rig already sits at 56 deg of
            -- articulation at full lock). And far from the target, holding the
            -- wheels straight is a real mode -- a steady 15 deg of articulation
            -- sweeps the tail metres sideways down an empty corridor.
            local art = rig.art(s.rig)
            local on_line = math.abs(geom.wrap(bearing + math.pi - s.rig.th)) < math.rad(20)
            local art_des
            if dist > 2.5 and on_line then
                art_des = 0
            else
                art_des = clamp(1.2 * err, -0.32, 0.32)
            end
            session.update(s, { steer = clamp(-3.0 * (art_des - art), -1, 1), throttle = 0,
                                brake = pedal, handbrake = false }, M.DT)
        else
            session.update(s, { steer = clamp(3.0 * err, -1, 1), throttle = pedal,
                                brake = 0, handbrake = false }, M.DT)
        end
        t = t + M.DT
        if s.bumps > 0 then return false, t end

        local arrived = dist < 0.9 and math.abs(geom.wrap(tth - s.rig.th)) < math.rad(14)
        if arrived and math.abs(rig.art(s.rig)) < math.rad(28) and math.abs(s.rig.v) < 0.6 then
            for _ = 1, 90 do
                session.update(s, { steer = 0, throttle = 0, brake = 0, handbrake = true }, M.DT)
            end
            return s.bumps == 0, t + 90 * M.DT
        end
    end
    return false, t
end

local function reverse_in(s, max_t)
    local bay = s.level.bay
    local ax, ay = math.cos(bay.angle), math.sin(bay.angle)
    local t = 0
    while t < max_t do
        -- The game's own park rule: the body fully inside the bay polygon. A
        -- centre-in-bay test stops early with the tail hanging out and never
        -- parks, which looks like a solver bug and is really a target bug.
        local inside = geom.poly_in_poly(rig.caravan_poly(s.rig), s.bay_poly)
        local aligned = math.abs(geom.wrap(s.rig.ph - bay.angle)) < bay.tol * 0.8
        if inside and aligned then
            session.update(s, { steer = 0, throttle = 0, brake = 0, handbrake = true }, M.DT)
            if s.parked then return true, t end
        else
            local mx, my = rig.caravan_centre(s.rig)
            local along = (mx - bay.x) * ax + (my - bay.y) * ay
            if along < -bay.w / 2 - 2.5 then return false, t end    -- overshot
            -- Aim the trailer at the BAY, not merely at the bay's angle: with
            -- only the angle error, a rig a metre off the axis drives parallel
            -- to it forever. Close in, the bearing goes jittery, so hand back to
            -- the bay angle.
            local d_bay = math.sqrt((bay.x - mx) ^ 2 + (bay.y - my) ^ 2)
            local target_ph = (d_bay > 4) and math.atan2(bay.y - my, bay.x - mx) or bay.angle
            local e = geom.wrap(target_ph - s.rig.ph)
            local art_des = clamp(1.4 * e, -0.45, 0.45)
            local th_err = geom.wrap(s.rig.ph + art_des - s.rig.th)
            -- creep for the last metres: the park tolerance is tighter than the
            -- gap between "nearly in" and "tail hanging out"
            local near = 1 - clamp(math.abs(along) / 5, 0, 1)
            session.update(s, { steer = clamp(-3.0 * th_err, -1, 1), throttle = 0,
                                brake = 1 - 0.6 * near, handbrake = false }, M.DT)
        end
        t = t + M.DT
        if s.bumps > 0 then return false, t end
    end
    return false, t
end

-- One attempt: (optionally back off), reach the pose, reverse in.
function M.drive_in(level, pose, opts)
    opts = opts or {}
    local s = session.new(level)
    local elapsed = 0

    if opts.pre and opts.pre > 0 then
        local ok, t = preamble(s, opts.pre, 8)
        if not ok then return { reached = false, parked = false, bumps = s.bumps, time = t } end
        elapsed = elapsed + t
    end

    local reached, ta = approach(s, pose.x, pose.y, pose.th, M.APPROACH_T, opts.force_reverse)
    elapsed = elapsed + ta
    if not reached then
        return { reached = false, parked = false, bumps = s.bumps, time = elapsed }
    end

    local parked, tb = reverse_in(s, M.REVERSE_T)
    return {
        reached = true,
        parked = parked and s.parked or false,
        time = elapsed + tb,
        bumps = s.bumps,
        x = s.rig.x, y = s.rig.y, th = s.rig.th, ph = s.rig.ph,
    }
end

-- Search the staging grid. Returns a result table; see M.format for the report.
function M.solve(level, opts)
    opts = opts or {}
    local grid = opts.grid or M.GRID
    local bay = level.bay
    local a = bay.angle
    local ax, ay = math.cos(a), math.sin(a)
    local nx, ny = -ay, ax

    local best, tried, reached, solved = nil, 0, 0, 0

    for _, pre in ipairs(grid.pre) do
        for _, dist in ipairs(grid.dist) do
            for _, off in ipairs(grid.off) do
                for _, dpsi in ipairs(grid.dpsi) do
                    local pose = {
                        x = bay.x + ax * dist + nx * off,
                        y = bay.y + ay * dist + ny * off,
                        th = a + math.rad(dpsi),
                    }
                    tried = tried + 1
                    -- forwards first, then the same pose reached in reverse
                    local r = M.drive_in(level, pose, { pre = pre })
                    if not r.reached then r = M.drive_in(level, pose, { pre = pre, force_reverse = true }) end
                    if r.reached then reached = reached + 1 end
                    if r.parked then
                        solved = solved + 1
                        if not best or r.time < best.time then
                            best = {
                                time = r.time, bumps = r.bumps, pose = pose, pre = pre,
                                x = r.x, y = r.y, th = r.th, ph = r.ph,
                            }
                        end
                    end
                end
            end
        end
    end

    if best then
        -- The cross-check: same pose, same approach, fresh session. Same inputs
        -- must reproduce the same park, or the probe is measuring itself.
        local again = M.drive_in(level, best.pose, { pre = best.pre })
        best.replay = {
            ok = again.parked,
            time = again.time,
            dx = (again.x or 0) - best.x,
            dy = (again.y or 0) - best.y,
            dth = (again.th or 0) - best.th,
            dph = (again.ph or 0) - best.ph,
        }
    end

    return { level = level, solved = best ~= nil, best = best,
             tried = tried, reached = reached, parked = solved }
end

function M.format(res, index)
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    add("level %s  %s: %s", index and tostring(index) or "?", res.level.name,
        res.solved and "winnable" or "NO LINE FOUND")
    add("  poses tried %d, staging pose reached %d, parked %d",
        res.tried, res.reached, res.parked)
    if res.best then
        add("  best %.2f s, %d bumps, par %s", res.best.time, res.best.bumps,
            tostring(res.level.par))
        if res.best.replay then
            local r = res.best.replay
            add("  replay %s  dx %.4f dy %.4f dth %.4f dph %.4f",
                r.ok and "parked" or "FAILED", r.dx, r.dy, r.dth, r.dph)
        end
    end
    return lines
end

return M
