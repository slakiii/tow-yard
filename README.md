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
`R` reset, `P` pause, `H` ghost (rig / trail / off), `Y` copy a share code,
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

The editor **autosaves** as you work, to `drafts/<id>.autosave.tylevel` in the
save directory (Linux `~/.local/share/love/tow-yard/`, Windows
`%APPDATA%\LOVE\tow-yard\`, macOS `~/Library/Application Support/LOVE/tow-yard/`).
Reopening that level offers the unsaved work back; `S` or `L` clears it. `L` also
writes `drafts/<id>.lua`, the `lib/levels.lua` entry. So a crash, a forgotten
keypress or a closed window no longer costs a level -- and if the game will not
start, the autosave is a plain text file you can open in an editor.

### Authoring the built-in tracks

The campaign lives in `lib/levels.lua`. The editor writes data, never source, so
there is one deliberate step between them:

1. `love .` → pick a campaign level → `E`. (`love . --edit` opens level 1.)
2. Edit: pick a tool in the rail, click the yard; drag to move, drag a handle to
   resize, `Q`/`E` to turn, `Ctrl+Z` to undo, `F2` to rename. It autosaves as you
   go, so nothing is lost by closing the window.
3. `V` checks the level is winnable (quick audit, ~2 s), `P` plays it in place and
   `Esc` comes back. The audit's time is a floor, never a par.
4. `L` writes `drafts/<id>.lua` -- the `lib/levels.lua` entry for this level --
   and puts the same text on the clipboard.
5. `python3 tools/apply-level.py <id>` splices that draft into `lib/levels.lua`
   (brace-matched, id-checked) and runs `love tests`.
6. `love . --audit <n>` -- `n` is the level's row in the catalogue, or its id:
   `--audit 3` and `--audit angled-bay` are the same level. Full grid, then
   playtest it and set par from what you actually drive.
7. Commit.

**Read the diff before committing.** Applying a draft replaces the entry
wholesale, so that one entry is normalised to the generated style -- `math.pi / 2`
becomes `math.rad(90)`, default sizes become explicit -- and **any comments inside
it are lost**; the tool says so when that happens. The rest of the file is
untouched, so a diff that reaches two levels means something went wrong.

**`--audit` answers "is there a line at all?"** on the full grid, and `NO LINE`
means the probe could not find one -- it cannot do a three-point turn, so a spawn
that faces a wall reports it -- not that the level is unwinnable. Playtest before
believing either verdict, and measure par from the playtest rather than scaling
the old number.

**Users cannot change the shipped tracks.** The editor writes only into the save
directory, and `S` on a shipped level saves a copy as `<id>-copy`: `S` is for
custom levels, `lib/levels.lua` is only ever edited by you, through the tool
above. For a build that ships with no editor at all, set `EDITOR_ENABLED = false`
in `main.lua` -- `E`, `N` and `--edit` stop working (and `--smoke` draws the
editor, so its editor frames need removing in that build).

Only structural things stretch: buildings, tents, pools, decking, gravel, grass,
water, the bay, and hedges (length only). A car, a motorhome, a chair, a cone, a
fire pit, a picnic table, a beach umbrella and the spawn have one real size and
offer no handles -- stretching them is not authoring, it is distorting.

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
| drag a handle | resize (corner handles both ways, a hedge only along its length) |
| `Del` | remove |
| `Ctrl+Z` | undo (32 deep) |
| `G` | snapping on/off (0.5 m, or free placement) |
| `F2` | rename the level |
| `V` | verify with the winnability audit (~2 s, blocking) |
| `P` | play the level in place, `Esc` back to the editor |
| `S` | save to `custom/` (a shipped level's id becomes `<id>-copy`) |
| `L` | copy a `lib/levels.lua` entry to the clipboard, and write it to `<save dir>/drafts/<id>.lua` |
| `O` | copy the level as a share code |
| `Esc` | back to the level select (asks first if there are unsaved changes) |

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
