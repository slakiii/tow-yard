function love.conf(t)
    t.window.title = "Tow Yard"
    t.window.width = 1280
    t.window.height = 720
    -- No minwidth/minheight on purpose. On KWin/Wayland the compositor used the
    -- hint AS the size to create the window at (900x560 = exactly the minimum) and
    -- then ignored every resize of the mapped toplevel. Enforcing the floor from
    -- inside the game was worse -- a setMode during the user's own drag left the
    -- window fixed-size -- so there is no floor: the rail has a compact layout and
    -- below about 900x560 it clips rather than fighting the compositor.
    t.window.resizable = true
    t.identity = "tow-yard"
end
