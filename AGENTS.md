# AGENTS.md - Tow Yard

Guidelines for agents working on this codebase.

## Project Overview

- **Type**: LÖVE 2D game (Lua / LuaJIT, LÖVE 11.5)
- **Purpose**: reverse a towed caravan into a parking bay as quickly as possible
- **Entry point**: `main.lua`

## Build & Run Commands

```bash
love .                                   # play
love tests                               # headless suite, exit 0 = green
love . --smoke                           # render every screen once, print SMOKE OK, exit 0
xvfb-run -a -s "-screen 0 1280x720x24" timeout 30 love . --smoke   # same, headless box
timeout 4 love .                         # legacy boot smoke (exit 124 = survived)
```

## Testing

`tests/main.lua` is the runner; modules return `{ order = {...}, test_name = function }`.
Pure logic (`rig`, `session`, `levels`, `geom`, `input`) is covered headlessly;
`main.lua` and `lib/draw.lua` are verified by `--smoke` plus human playtest.

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
  and contains no rules.

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

A level is data only: `spawn`, `bay` (position, size, angle, tolerance), `walls`
(boxes), `cones` (circles), `par`, and `apron` (clearance required around the
bay, default 2 m — tight levels lower it). `tests/test_levels.lua` rejects a
level whose spawn overlaps a wall, whose bay apron is intruded on, or whose bay
falls outside the bounds. Never hand-tune par times: playtest them.
