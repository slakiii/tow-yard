function love.conf(t)
    -- Pure-logic tests: no window, no graphics, no audio.
    t.window = false
    t.modules.audio = false
    t.identity = "tow-yard-tests"
end
