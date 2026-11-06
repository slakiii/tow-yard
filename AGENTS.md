# AGENTS.md - Tow Yard

Guidelines for agents working on this codebase.

## Project Overview

- **Type**: LÖVE 2D game (Lua / LuaJIT, LÖVE 11.5)
- **Purpose**: reverse a towed caravan into a parking bay as quickly as possible
- **Entry point**: `main.lua`

## Build & Run Commands

```bash
love .                                   # play (starts on the level select)
love tests                               # headless suite, exit 0 = green
love . --smoke                           # render every screen once, print SMOKE OK, exit 0
xvfb-run -a -s "-screen 0 1280x720x24" timeout 30 love . --smoke   # same, headless box
love . --audit 4                         # can level 4 be parked? exit 0 = a line exists
love . --audit all                       # every level (~25 s each, full grid only)
love . --edit                            # the level editor (dev tool, see README)
timeout 4 love .                         # legacy boot smoke (exit 124 = survived)
```

## Testing

`tests/main.lua` is the runner; modules return `{ order = {...}, test_name = function }`.
Pure logic (`rig`, `session`, `levels`, `geom`, `props`, `input`) is covered headlessly;
`main.lua` and `lib/draw.lua` are verified by `--smoke` plus human playtest.

**Level winnability is auditable, not assumed.** `lib/audit.lua` searches staging
poses, reverses in with a bounded controller, and replays the best line through a
fresh session — a park it reports is a park the shipped physics actually produces.
Run it for any level you author or move: `love . --audit N` (exit 1 = no line
found, do not ship). Its time is a **par floor**, never the par itself. It cannot
do a three-point turn, so a spawn that faces a wall (level 3, Angled bay) reports
NO LINE — that verdict means "needs a playtest", not "unwinnable".

**The full grid is the gate; `--quick` is not.** `--quick` tries 18 poses and
misses off-axis levels completely: Fire side and Long way back both report NO
LINE under `--quick` and find a clean line in the full 360-pose grid. Use it to
smoke-check the instrument, never to clear a level.

Always gate a commit on the runner's exit code, not on grepped output:

```bash
love tests > /tmp/t.log 2>&1; echo "exit=$?"   # commit only when exit=0
```

`--smoke` is the real render check: it draws a scene frame, a parked-result
frame and a debug frame, writes screenshots to the LÖVE save directory, then
quits 0. A `timeout` exit of 124 only proves the process did not crash.

## Architecture: pure core, thin shell

- `lib/rig.lua` and `lib/session.lua` must not call `love.*` at all — not just
  at module level. That is what makes the physics testable and forces one
  physics for both input devices.
- `lib/input.lua` is the only module that reads devices; it writes into
  `{ steer, throttle, brake, handbrake }` and nothing else. `steer` is a
  **target** wheel position in [-1, 1], not a rate: the ramp lives in `rig.step`.
- `main.lua` owns the love callbacks, the camera and the fixed-timestep loop,
  and contains no rules. It also owns the **mode switch** (`menu` / `play`):
  each mode has its own update/draw/keypressed, and one dispatch block at the
  bottom is the only place that knows more than one screen exists.
- A run is what makes a ghost honest: `lib/run.lua` records one quantised frame
  per physics step, serialises it to four bytes per frame, replays it through a
  fresh session, and `verify` refuses a run from other geometry or another build
  **before** it is drawn. Never trust a header's claimed time; the replay is the
  answer. `lib/share.lua` bundles a level and a run for one paste, and
  `lib/codec.lua` is the only place zlib/base64 is touched.
- Content is data, identity is a hash: `lib/levelfmt.lua` encodes/decodes a
  level as portable text and hashes its *content* (geometry, props, par — not
  `id`/`series`/`order`), `lib/levelcheck.lua` says whether a level is
  legitimate (used by the suite and, later, the importer and editor),
  `lib/progress.lua` stores best time/stars/ghost over an injected disk, and
  `lib/menu.lua` is the level select's model, and `lib/edit/doc.lua` +
  `lib/edit/undo.lua` are the editor's document and its snapshot stack. The
  editor's view draws AUTHORED data, not the resolved level: the file is what
  you are editing, so what it says is what you should see.

## Code Style

- 4 spaces, no tabs; `snake_case` names; `UPPER_SNAKE_CASE` constants;
  modules export a single table (`local M = {}`).
- Comments explain *why* (a physical constant, a regression, a tuning reason),
  never what the line does.

## Model Notes (do not "simplify" these)

- The trailer is a first-order kinematic model with a hitch offset:
  `phd = (v/drawbar)*sin(th-ph) + (coupling/drawbar)*thd*cos(th-ph)`.
  Drop the offset term and the caravan stops cutting the corner; get its sign
  wrong and reversing behaves backwards.
- `coupling` is negative on purpose (behind the rear axle, at the bumper).
  Putting the coupling on the rear axle is geometrically impossible at large
  articulation and its 0.35 m overhang moves the jackknife angle by tens of
  degrees.
- The caravan body is a **tapered polygon**. A full-width rectangle from the
  coupling reports a collision at ~25 deg, which makes the game unplayable.
  `tests/test_rig.lua:bodies_touch_near_jackknife_not_earlier` guards this.
- Fixed `dt` (1/120). The reverse is unstable, so a variable step makes the
  handling depend on frame rate and the tests stop describing the game.
- Steering rate scales down with speed (`0.45 + 0.55*min(1,|v|/6)`). That is
  what makes keyboard reversing possible; it also means full lock takes 0.26 s
  at speed and ~0.58 s from rest. Both numbers are asserted in tests.

## Level Authoring

A level is data only: `id`, `name`, `hint`, `series`, `order`, `spawn`, `bay`
(position, size, angle, tolerance), `walls` (boxes), `cones` (circles), `par`,
and `apron` (clearance required around the bay, default 2 m — tight levels lower
it). `tests/test_levels.lua` rejects a level whose spawn overlaps a wall, whose
bay apron is intruded on, or whose bay falls outside the bounds; `lib/levelcheck.lua`
holds the rules and also requires the catalogue to be consistent: unique `id`s,
one contiguous run per `series`, `order` values 1..n inside a series. The menu,
`Tab` and the audit all walk the same list, so a split series makes them
disagree. Never hand-tune par times: playtest them.
