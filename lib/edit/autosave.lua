-- Autosave for the editor, over an injected disk.
--
-- This exists because L was the only thing that ever wrote anything: edit a level
-- for twenty minutes, quit without pressing a key, and the work is gone. The
-- editor now writes the document as you go, and offers it back the next time that
-- id is opened.
--
-- The file is the same canonical text as a .tylevel, so it is readable by
-- anything that reads levels -- including a human, in a text editor, on a machine
-- where the game will not start.
--
-- Throttled, because a drag is a stream of edits and a disk write per frame is a
-- disk write per frame. Forced on exit, where the cost does not matter.

local M = {}

M.DIR = "drafts/"
M.EVERY = 2.0          -- seconds between writes unless forced

function M.path(id)
    return M.DIR .. tostring(id) .. ".autosave.tylevel"
end

-- `state` is { text = last written, at = when }, owned by the caller so this
-- module stays pure. Returns true when something was written.
function M.save(disk, id, text, state, now, force)
    if not (disk and id and text) then return false end
    state = state or {}
    now = now or 0
    -- identical text is never rewritten, force or not: exiting twice in a row is
    -- not two saves
    if text == state.text then return false end
    if not force and state.at and (now - state.at) < M.EVERY then return false end

    -- the disk adapter calls it mkdir; accept either name, because skipping the
    -- directory is what made every write fail quietly
    local mk = disk.mkdir or disk.createDirectory
    if mk then mk(M.DIR) end

    -- A write into a directory that does not exist fails quietly, and a quiet
    -- failure here costs a level. Report it.
    local ok, err = disk.write(M.path(id), text)
    if ok == false or (ok == nil and err) then
        return false, tostring(err or "write failed")
    end
    state.text, state.at = text, now
    return true
end

function M.load(disk, id)
    if not (disk and id) then return nil end
    local text = disk.read(M.path(id))
    if not text or text == "" then return nil end
    return text
end

function M.clear(disk, id)
    if not (disk and id) then return false end
    disk.remove(M.path(id))
    return true
end

return M
