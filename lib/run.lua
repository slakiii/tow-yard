-- A recorded attempt: the input stream the sim consumed, one frame per physics
-- step, and nothing else.
--
-- That is all a run needs to be, because the sim is deterministic: the same
-- level plus the same numbers always produce the same drive. Record enough to
-- replay, and let the replay be the proof -- a stored "time" is a comment, not
-- evidence.
--
-- Record quantises what it is given, the same way session.update does. Both are
-- idempotent, so a caller that already snapped its input is not punished, and a
-- caller that forgot cannot put a value in the file that the sim never saw.

local session = require("lib.session")

local M = {}

-- Five minutes of physics steps. A longer attempt is not a run; the cap also
-- bounds what a hostile file can ask the parser to allocate.
M.MAX_FRAMES = 120 * 300

function M.new(level)
    return { level_id = level and level.id, frames = {} }
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

return M
