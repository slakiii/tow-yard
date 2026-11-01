# Tow Yard

A top-down game about towing a caravan: drive it to the pitch, then reverse it
in. Reversing a trailer is an unstable control problem — forward motion
straightens the caravan by itself, reverse motion makes any error grow — so the
game is entirely about setting up a maneuver before you commit to it.

```
love .            # play
love tests        # headless test suite, exit 0 = green
love . --smoke    # render every screen once and quit (boot check)
```

Keyboard: `WASD` / arrows to drive, `Space` handbrake, `G` guide arc,
`R` reset, `F1` debug, `Esc` quit.
Gamepad: left stick steer, `RT` forward, `LT` brake then reverse, `A`
handbrake, `Y` guide, `B` reset, `Start` pause. Rumble warns you as the
articulation approaches the jackknife angle.

Levels: `Tab` cycles. Three are shipped; see `.hermes/plans/tow-yard.md` for the
design notes, the tuning numbers and the roadmap.

## Layout

| Path | What it is |
|---|---|
| `lib/rig.lua` | kinematic car + caravan model (pure) |
| `lib/session.lua` | clock, gear gate, collisions, parking rules (pure) |
| `lib/levels.lua` | level data: spawn, bay, walls, cones, par |
| `lib/geom.lua` | polygon transforms, SAT overlap, containment (pure) |
| `lib/input.lua` | keyboard + gamepad -> one normalised input table |
| `lib/draw.lua` | flat-colour renderer, HUD, result card |
| `main.lua` | thin shell: callbacks, camera, fixed-timestep loop |
| `tests/` | headless suite, run with `love tests` |
