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
`R` reset, `P` pause, `F1` debug, `Esc` quit.

Gamepad (any pad LÖVE recognises as a gamepad; hot-plug works): left stick or
`D-pad` to steer, `RT` forward, `LT` brake then reverse, `A` handbrake,
`Y` guide arc, `B` reset, `Start` pause. Rumble warns you as the articulation
approaches the jackknife angle. `F1` shows the detected pad and whether it
reports rumble support.

The two devices are live at the same time and merge per axis (strongest input
wins), and both feed the same rate-limited steering model — the pad only
supplies finer targets, never different physics.

Levels: `Tab` cycles. Three are shipped.

Plans live in `.hermes/plans/`:

- `tow-yard.md` — physics, controls, tuning numbers, level-design rules, verification.
- `enjoyment-roadmap.md` — where the game goes next: constraint rules, ghost replay,
  rig variants, sound, meta layer, and what is deliberately out of scope.

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
