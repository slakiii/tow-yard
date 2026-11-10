function love.conf(t)
    t.window.title = "Tow Yard"
    t.window.width = 1280
    t.window.height = 720
    -- No minwidth/minheight here on purpose: on KWin/Wayland that hint is what the
    -- window was being created AT (900x560 = exactly the minimum) while every
    -- setMode after it was ignored. The floor is enforced in love.resize instead,
    -- which gives the player the same guarantee without handing the compositor a
    -- size to start from.
    t.window.resizable = true
    t.identity = "tow-yard"
end
