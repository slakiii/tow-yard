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

Level select: `W`/`S` choose, `Enter` open, `Tab` switch tab (Campaign /
Custom levels), `N` new level, `E` open the selected level in the editor,
`X` delete a custom level, `I` paste a share code, `Esc` quit.

Custom levels live in `custom/` inside the LÖVE save directory (the empty tab
prints the exact path). They are a separate tab from the campaign, they carry
their own best times and ghosts, and deleting one asks once and removes the file
and its index entry together.

Editor: `love . --edit`, or `E` on a level in the select.

Editing the built-in tracks: `E` on a campaign level opens it; `L` produces the
`lib/levels.lua` entry for it (clipboard and `drafts/`); paste that over the entry
with the same `id`, then `love tests` and `love . --audit N` before committing.
`S` is for custom levels -- it saves a copy and leaves the shipped level alone.

| Mouse | |
|---|---|
| click the rail | pick a tool (the name in the rail is the level's; `F2` renames it) |
| wheel | zoom (6-40 px/m, around the cursor) |
| right / middle drag | pan |
| click | place the active prop (0.5 m snap), or select with `select` |
| — | with a tool picked, a faint preview follows the cursor; clicking puts it down |
| drag | move the selection (props, the bay and the spawn alike) |

| Key | |
|---|---|
| `[` `]` | cycle the tool palette (`bay` and `spawn` place the goal and the start) |
| `Q` `E` | rotate the selection 15 deg |
| `+` `-` | resize |
| `Del` | remove |
| `Ctrl+Z` | undo (32 deep) |
| `G` | snapping on/off (0.5 m, or free placement) |
| `F2` | rename the level |
| `V` | verify with the winnability audit (~2 s, blocking) |
| `P` | play the level in place, `Esc` back to the editor |
| `S` | save to `custom/` (a shipped level's id becomes `<id>-copy`) |
| `L` | copy a `lib/levels.lua` entry to the clipboard, and write it to `<save dir>/drafts/<id>.lua` |
| `O` | copy the level as a share code |
| `Esc` | back to the level select |

Gamepad (any pad LÖVE recognises as a gamepad; hot-plug works): left stick or
`D-pad` to steer, `RT` forward, `LT` brake then reverse, `A` handbrake,
`Y` guide arc, `B` reset, `Start` pause. Rumble warns you as the articulation
approaches the jackknife angle. `F1` shows the detected pad and whether it
reports rumble support.

In the menus the pad is `D-pad`/left stick to move, `A` confirm, `B` cancel
(`Tab`/`L1`-style tab switching is keyboard-only for now).

The two devices are live at the same time and merge per axis (strongest input
wins), and both feed the same rate-limited steering model — the pad only
supplies finer targets, never different physics.

Button names come from `input.BUTTONS`/`input.AXES`, never from literals:
`love.joystick.isGamepadDown` raises on a name LÖVE does not have, so a typo is a
crash the moment a controller is plugged in. `tests/test_input_pad.lua` drives a
fake pad that rejects any name outside that vocabulary.

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
