-- A recorded attempt: the input stream the sim consumed, one frame per physics
-- step, and nothing else.
--
-- That is all a run needs to be, because the sim is deterministic: the same
-- level plus the same numbers always produce the same drive. Record enough to
-- replay, and let the replay be the proof -- a stored "time" is a comment, not
-- evidence.
--
-- The document is text with a base64 body, and the body is four bytes per frame:
-- steer as a byte offset by 127, the two pedals, and a flags byte. Those are
-- exactly the grids session.quantise snaps to, so encoding is lossless by
-- construction rather than by careful rounding.
--
-- Record quantises what it is given, the same way session.update does. Both are
-- idempotent, so a caller that already snapped its input is not punished, and a
-- caller that forgot cannot put a value in the file that the sim never saw.

local session = require("lib.session")
local rig = require("lib.rig")
local levelfmt = require("lib.levelfmt")
local hash = require("lib.hash")

local M = {}

M.VERSION = 1
M.HEADER = "TOWYARD RUN "

-- Five minutes of physics steps. A longer attempt is not a run; the cap also
-- bounds what a hostile file can ask the parser to allocate.
M.MAX_FRAMES = 120 * 300

function M.new(level)
    return {
        level_id = level and level.id,
        -- what the run was driven against, so a ghost can be refused rather than
        -- silently drawn on geometry it was not recorded on
        content = level and levelfmt.content_hash(level),
        build = hash.build_hash(),
        frames = {},
    }
end

-- Does this frame belong in the run?
--
-- Recording starts with the first thing the player does, not when the level
-- opens. A run that begins with eight seconds of nobody touching the controls is
-- eight seconds of ghost standing still, and a replay that watches you wait.
--
-- Steer counts even though it does not start the clock: the wheel position is
-- physics state, and dropping the frames where the player turned it at a standstill
-- would make the replay diverge from what happened.
function M.recording(s, input)
    if s and s.started then return true end
    local i = input or {}
    return (i.throttle or 0) > 0 or (i.brake or 0) > 0
        or i.handbrake == true or math.abs(i.steer or 0) > 1e-6
end

local function idle_frame(f)
    return not f or ((f.throttle or 0) == 0 and (f.brake or 0) == 0
        and (f.steer or 0) == 0 and f.handbrake ~= true)
end

-- Drop the frames before the first thing the player did. Runs recorded before
-- recording started with the first action carry that prefix; replaying it would
-- make the ghost hesitate at the start line while the player drives, and it costs
-- nothing to remove: those frames have no input, so the pose does not change.
function M.trim(run)
    local dropped = 0
    while #run.frames > 0 and idle_frame(run.frames[1]) do
        table.remove(run.frames, 1)
        dropped = dropped + 1
    end
    return dropped
end

function M.record(run, input)
    if run.closed or #run.frames >= M.MAX_FRAMES then return run end
    local q = session.quantise(input)
    run.frames[#run.frames + 1] = {
        steer = q.steer, throttle = q.throttle, brake = q.brake, handbrake = q.handbrake,
    }
    return run
end

-- Close the run on the park. The claimed numbers ride along for the document
-- header, but they are informational: anything that reads a run recomputes them
-- by replaying it.
function M.finish(run, s)
    run.closed = true
    if s and s.final then
        run.time, run.bumps, run.angle_err = s.final.time, s.final.bumps, s.final.angle_err
    end
    return run
end

function M.frames(run)
    return #run.frames
end

-- The drive the run describes. The break on park is defence in depth: session
-- already freezes a parked rig, but a replay should not depend on that, and a
-- mutation test showed the guard is invisible to the suite (the session is what
-- actually guarantees it) -- so this comment is the record of that finding.
function M.replay(level, run)
    local s = session.new(level)
    for _, f in ipairs(run.frames) do
        if s.parked then break end
        session.update(s, f, rig.STEP)
    end
    return s
end

-- One frame of the ghost's own drive. False when there is nothing left to
-- drive: the run is spent, or the replay itself has parked.
function M.step(ghost)
    if not ghost or ghost.s.parked then return false end
    local f = ghost.run.frames[ghost.step + 1]
    if not f then return false end
    ghost.step = ghost.step + 1
    session.update(ghost.s, f, rig.STEP)
    return true
end

-- Advance a ghost to the player's own step count.
--
-- Never with wall-clock time: pausing must not let it drive off, and it must not
-- start before the player does -- the whole point of both counters starting at
-- the first action is that you and the ghost leave the line together.
function M.advance(ghost, steps)
    local moved = 0
    while ghost.step < (steps or 0) do
        if not M.step(ghost) then break end
        moved = moved + 1
    end
    return moved
end

-- The player's clock stops at the park; the ghost's does not.
--
-- A best run that was still on the road when you beat it has frames left. Cut
-- off at the player's step count it froze mid-line at the moment of victory,
-- which reads as the ghost quitting rather than losing. Feed it the frame time
-- the player's loop no longer consumes, on the same fixed cadence, until its own
-- line ends. Returns frames driven and the time left unconsumed.
function M.follow(ghost, acc, dt, max_steps)
    local moved, left = 0, acc or 0
    while left >= dt and moved < (max_steps or 12) do
        if not M.step(ghost) then break end
        left = left - dt
        moved = moved + 1
    end
    return moved, left
end

-- The same drive, sampled, for drawing a ghost trail: computing the whole line
-- up front costs one replay (milliseconds) and lets the trail be revealed as the
-- player advances instead of storing a pose per frame twice.
function M.trace(level, run, every)
    every = every or 6
    local s = session.new(level)
    local points = {}
    for i, f in ipairs(run.frames) do
        if s.parked then break end
        session.update(s, f, rig.STEP)
        if i % every == 0 then
            local cx, cy = rig.coupling_xy(s.rig)
            points[#points + 1] = {
                cx - rig.CARAVAN.length * math.cos(s.rig.ph),
                cy - rig.CARAVAN.length * math.sin(s.rig.ph),
            }
        end
    end
    return points, s
end

-- Is this run a park on THIS level, at THIS build? The claimed time is never
-- consulted: the answer is the replay's. A run recorded against other geometry
-- or another simulation is refused before it is replayed at all.
function M.verify(level, run)
    if run.level_id ~= level.id then
        return false, "this run belongs to a different level"
    end
    if run.content ~= levelfmt.content_hash(level) then
        return false, "this run was recorded on different geometry (the level has changed)"
    end
    if run.build ~= hash.build_hash() then
        return false, "this run was recorded on a different build"
    end
    local s = M.replay(level, run)
    if not s.parked then
        return false, "this run does not park on this build"
    end
    return true, s.final
end

-- ------------------------------------------------------------- serialisation

local function pack(frames)
    local parts = {}
    for i, f in ipairs(frames) do
        parts[i] = string.char(
            math.floor((f.steer or 0) * 127 + 0.5) + 127,
            math.floor((f.throttle or 0) * 255 + 0.5),
            math.floor((f.brake or 0) * 255 + 0.5),
            f.handbrake and 1 or 0)
    end
    return table.concat(parts)
end

local function unpack_frames(bytes)
    local frames = {}
    for i = 1, math.floor(#bytes / 4) do
        local a, b, c, d = bytes:byte((i - 1) * 4 + 1, i * 4)
        frames[i] = {
            steer = (a - 127) / 127,
            throttle = b / 255,
            brake = c / 255,
            handbrake = (d % 2) == 1,
        }
    end
    return frames
end

function M.encode(run, codec)
    if not codec then return nil, "no codec" end
    local body = codec.compress(pack(run.frames))
    local out = {
        M.HEADER .. M.VERSION,
        "level " .. tostring(run.level_id or ""),
        "content " .. tostring(run.content or string.rep("0", 64)),
        "build " .. tostring(run.build or string.rep("0", 64)),
        string.format("time %.2f", run.time or 0),
        string.format("bumps %d", run.bumps or 0),
        string.format("frames %d", #run.frames),
        "data " .. codec.encode(body),
    }
    return table.concat(out, "\n") .. "\n"
end

local KNOWN = {
    level = true, content = true, build = true,
    time = true, bumps = true, frames = true, data = true,
}

-- Strict, because a run arrives from another machine: the frame count is checked
-- against the cap BEFORE the body is touched, and every failure is a sentence.
function M.decode(text, codec)
    if type(text) ~= "string" then return nil, "not a document" end
    if not codec then return nil, "no codec" end

    local fields = {}
    local header = false
    local n = 0
    for raw in text:gmatch("[^\n]*") do
        n = n + 1
        local line = raw:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            if not header then
                if line ~= M.HEADER .. M.VERSION then
                    return nil, "line " .. n .. ": bad header: " .. line
                end
                header = true
            else
                local key, rest = line:match("^(%S+)%s*(.*)$")
                if not KNOWN[key] then
                    return nil, "line " .. n .. ": unknown key: " .. tostring(key)
                end
                fields[key] = rest
            end
        end
    end
    if not header then return nil, "empty document" end

    local count = tonumber(fields.frames)
    if not count or count < 1 or count ~= math.floor(count) then
        return nil, "no frame count"
    end
    if count > M.MAX_FRAMES then
        return nil, "too many frames: " .. tostring(count)
    end
    if not fields.data then return nil, "no data" end

    if not fields.level or fields.level == "" then return nil, "no level id" end
    local content = tostring(fields.content or "")
    if #content ~= 64 or not content:match("^%x+$") then return nil, "bad content hash" end

    local ok, blob = pcall(codec.decode, fields.data)
    if not ok or type(blob) ~= "string" then return nil, "data is not base64" end

    local ok2, bytes = pcall(codec.decompress, blob)
    if not ok2 or type(bytes) ~= "string" then return nil, "data does not decompress" end
    if #bytes ~= count * 4 then
        return nil, string.format("body length disagrees: %d bytes for %d frames", #bytes, count)
    end

    return {
        level_id = fields.level,
        content = content,
        build = fields.build,
        time = tonumber(fields.time),
        bumps = tonumber(fields.bumps),
        frames = unpack_frames(bytes),
    }
end

return M
