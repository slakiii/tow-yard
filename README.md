# Tow Yard

A top-down game about towing a caravan: drive it to the pitch, then reverse it
in. Reversing a trailer is an unstable control problem — forward motion
straightens the caravan by itself, reverse motion makes any error grow — so the
game is entirely about setting up a maneuver before you commit to it.

```
love .            # play
love tests        # headless test suite, exit 0 = green
love . --smoke    # render every screen once and quit (boot check)
love . --audit 4  # is level 4 parkable at all? exit 0 = a line exists
```

Keyboard: `WASD` / arrows to drive, `Space` handbrake, `G` guide arc,
`R` reset, `P` pause, `H` ghost (off / trail / rig), `Y` copy a share code,
`I` import the clipboard, `F1` debug, `Esc` back to the level select.
Drop a `.towyard` file on the window to import it.

Editor (dev tool for now): `love . --edit`.

| Mouse | |
|---|---|
| wheel | zoom (6-40 px/m, around the cursor) |
| right / middle drag | pan |
| click | place the active prop (0.5 m snap), or select with `select` |
| drag | move the selection |

| Key | |
|---|---|
| `[` `]` | cycle the tool palette |
| `Q` `E` | rotate the selection 15 deg |
| `+` `-` | resize |
| `Del` | remove |
| `Ctrl+Z` | undo (32 deep) |
| `V` | verify with the winnability audit (~2 s, blocking) |
| `P` | play the level in place, `Esc` back to the editor |
| `S` | save to `custom/`, `O` copy the level as a share code |
| `Esc` | back to the level select |

Gamepad (any pad LÖVE recognises as a gamepad; hot-plug works): left stick or
`D-pad` to steer, `RT` forward, `LT` brake then reverse, `A` handbrake,
`Y` guide arc, `B` reset, `Start` pause. Rumble warns you as the articulation
approaches the jackknife angle. `F1` shows the detected pad and whether it
reports rumble support.

The two devices are live at the same time and merge per axis (strongest input
wins), and both feed the same rate-limited steering model — the pad only
supplies finer targets, never different physics.

Levels: the game starts on the level select — `W/S` (or stick/d-pad) choose,
`Enter` opens, `Esc` quits. Seven are shipped, in three series. `Tab` still
cycles levels inside a run, and `Esc` in a level goes back to the select.

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
| `lib/props.lua` | scenery vocabulary: kinds, footprints, palette (pure) |
| `lib/levelcheck.lua` | is a level legitimate? one implementation for the suite, the importer and the editor (pure) |
| `lib/levelfmt.lua` | level as portable text: encode/decode/hash (pure) |
| `lib/hash.lua` | canonical dump, sha256, build stamp |
| `lib/progress.lua` | best time, stars and ghosts, over an injected disk (pure) |
| `lib/menu.lua` | level select model: rows, cursor, marks (pure) |
| `lib/run.lua` | record / serialise / replay / verify a run (pure) |
| `lib/share.lua` | share bundles and `TY1:` codes (pure) |
| `lib/edit/doc.lua` | the editor's document and its edits (pure) |
| `lib/edit/undo.lua` | snapshot undo (pure) |
| `lib/codec.lua` | zlib + base64 over love.data, passed into the format |
| `lib/audit.lua` | level winnability probe, run with `love . --audit N` (pure) |
| `lib/draw.lua` | flat-colour renderer, HUD, result card, level select |
| `main.lua` | thin shell: callbacks, mode switch, camera, fixed-timestep loop |
| `tests/` | headless suite, run with `love tests` |
