# Tow Yard — Enjoyment Roadmap

**Goal:** turn a working mechanic (a caravan reverse that is hard but learnable) into a game
that is worth replaying, by adding a **decision layer** on top of the execution layer.

**Architecture:** everything below stays inside the existing shape — pure logic in `lib/`,
rules and rig variants as data in `lib/levels.lua`, `main.lua` stays a thin shell. No new
dependency, no engine change.

**Tech stack:** LÖVE 11.5 / LuaJIT, headless tests via `love tests`, render smoke via
`love . --smoke` under `xvfb-run`.

Read `.hermes/plans/tow-yard.md` first for the physics, controls and tuning numbers this
plan builds on.

---

## §0 — Decisions locked with the user (do not re-litigate)

| Decision | Choice |
|---|---|
| Identity | A **precision reversing game** — a game about the trailer, not a driving game with trailers in it |
| What makes it a game, not a toy | A decision layer: authored constraints that must be solved, not only executed |
| Direction order | 1) constraint rules, 2) ghost replay, 3) rig variety, 4) sound/juice, 5) meta layer |
| Excluded, permanently | open world / delivery map, deeper physics sim (suspension, tyre slip), procedural levels, multiplayer-first |
| Rule violation model | **Hard fail** the attempt with a stated reason + instant retry (not a silent grade penalty) |
| Rules live in data | `level.rules` in `lib/levels.lua`; `lib/rules.lua` only *evaluates* them |
| Par times | Always from playtests, never computed. A rule change invalidates existing pars |
| Determinism | The fixed 1/120 step is a contract; ghost replay depends on it and it must not regress |
| TBD | Should a level ever be **unauthorable in a single attempt** (you cannot see the trap until you have failed into it)? If yes, retry cadence and level intro change shape. Gate: decide after 4 levels exist with rules, by playtesting both an informed and an uninformed variant |

---

## §1 — Schema: level rules and rig variants

One source of truth, in `lib/levels.lua`. Every field is optional; a level with no `rules`
behaves exactly as today.

```lua
{
    name = "One shot",
    hint = "You get one gear change. Set the angle up before you use it.",

    -- existing fields: bounds, spawn, bay, walls, cones, par, apron

    rules = {
        max_shifts = 1,                    -- gear changes (D<->R) allowed after the clock starts
        time_limit = 20,                   -- hard deadline in seconds, distinct from par
        cones_must_stand = true,           -- any cone contact fails the attempt
        gate = { x = 34, y = 20, r = 3 },  -- must reach this disc before reverse may engage
        no_wall_contact = true,            -- any wall contact fails the attempt
    },

    rig = {                               -- optional override of lib/rig.lua defaults
        drawbar = 5.2,                    -- longer caravan: larger tau, calmer reverse
        length = 6.4,
        twins = false,                    -- twin axle: resists rotation (see Task C2)
    },
}
```

### Schema invariants (tests enforce these)

1. Every `rules` field is either absent or a positive number / boolean of the declared type.
2. `rules.time_limit`, when present, is ≤ `par` is **not** required — `par` is for stars,
   `time_limit` is a wall. But `time_limit > 0`.
3. `gate`, when present, lies inside `bounds` and does not overlap a wall or the bay apron.
4. `rig`, when present, keeps `drawbar > car wheelbase / 2` (a trailer shorter than that
   self-jackknifes at rest) and `length >= drawbar`.
5. A level with `cones_must_stand = true` must have at least one cone, or the rule is inert
   and the fixture is lying about its own difficulty.
6. Every rule present in a level must be *surfaced* — see §4. A silent rule is a bug.

---

## §2 — Semantics: the pure rule functions

New module `lib/rules.lua`, pure, no `love.*`.

```lua
-- nil = attempt still legal; a string = the reason the attempt is failed
function M.check(s) end

-- The list of active rules for the HUD, in display order.
function M.active(level) end

-- One-line status per rule for the HUD, e.g. { "shifts 1/1", "time 12.4/20" }.
function M.status(s) end
```

**Contract:**

| Rule | Violated when | Failure reason |
|---|---|---|
| `max_shifts` | `s.shifts > max_shifts` | `"too many gear changes"` |
| `time_limit` | `s.t > time_limit` | `"out of time"` |
| `cones_must_stand` | `s.bump_kinds.cone > 0` | `"hit a cone"` |
| `no_wall_contact` | `s.bump_kinds.wall > 0` or jackknife | `"touched the fence"` / `"jackknifed"` |
| `gate` | never violated — it *gates* reverse instead | `reverse refused while gate closed` |

`gate` is not a failure rule; it forbids the reverse pedal until the rig's rear axle has
entered the disc, which turns "drive up, then back in" into a real two-phase plan.

```lua
-- lib/rules.lua
local M = {}

function M.gate_open(s)
    local g = s.level.rules and s.level.rules.gate
    if not g then return true end
    if s.gate_open then return true end
    local d = (s.rig.x - g.x) ^ 2 + (s.rig.y - g.y) ^ 2
    if d <= g.r * g.r then
        s.gate_open = true
    end
    return s.gate_open
end

function M.check(s)
    local r = s.level.rules or {}
    if r.time_limit and s.t > r.time_limit then return "out of time" end
    if r.max_shifts and s.shifts > r.max_shifts then return "too many gear changes" end
    if r.cones_must_stand and s.bump_kinds.cone > 0 then return "hit a cone" end
    if r.no_wall_contact then
        if s.bump_kinds.jackknife > 0 then return "jackknifed" end
        if s.bump_kinds.wall > 0 then return "touched the fence" end
    end
    return nil
end

return M
```

Shift counting is a session concern, not a rule concern. In `lib/session.lua`:

```lua
-- count a shift when the committed direction actually flips, not when a key is
-- tapped: a player who brakes to a stop and drives on has not shifted gears
local g = M.gear(s)                      -- "D" | "R" | "N"
if g ~= "N" and s.last_gear ~= "N" and g ~= s.last_gear then
    s.shifts = s.shifts + 1
end
if g ~= "N" then s.last_gear = g end
```

---

## §3 — Contracts

**Determinism.** Ghost replay is only valid if the same input sequence always produces the
same state. Already true (fixed 1/120 step, no RNG in the sim) and pinned by
`tests/test_rig.lua:fixed_step_determinism`. Any future procedural or random element must
be a *seeded, recorded* input to the sim, never a call inside it. Restated as a rule:
**nothing in `lib/rig.lua` or `lib/session.lua` may call `love.math.random`, `os.time` or
`os.clock`.**

**Failure is an event, not a state.** A failed attempt freezes the sim exactly like a park
does, records `s.failed = { reason = ..., time = ... }`, and waits for `R`. Retry is
sub-second. Never animate the failure out of existence — the player must see why.

**A rule may not change the physics.** Rules gate inputs and grade outcomes; they never
touch `rig.step`. If a rule needs new physics (e.g. "you may not stop"), that is a
different feature, not a rule.

**Ghosts are keyed to level content.** Store the ghost under `index .. ":" .. hash(level)`.
Editing a level invalidates its ghost rather than replaying a run that no longer exists.

---

## §4 — Presentation contract (every rule must be visible)

Per state, what the player sees. Nothing here may be hidden behind the debug overlay.

- **Level with no rules** — unchanged from today: hint line only.
- **Level with rules** — a rules strip under the title, one token per active rule, in
  `lib/rules.lua` order. Each token is neutral while legal, amber in the last 25% of its
  budget (time running out, last gear change used), and red for the step that fails.
- **Gate rule** — a disc drawn on the ground, ring-red while closed with the label "reverse
  locked", solid green once entered. Reverse pedal input while closed must produce visible
  refusal (the gear readout flashes "R LOCKED"), never silence.
- **Attempt failed** — the result card is reused with the same shape: title "FAILED",
  the reason string, elapsed time, and "R retry / Tab next".
- **Attempt parked with a rule set** — the card shows the rules that were *spent*
  ("1/1 shifts used", "0 cones hit") so the grading feels earned.
- **Ghost present** — the best run is drawn as a 35% alpha rig with no wheels or details;
  it must never be mistakable for the player's rig. Toggle with `H`.

---

## §5 — Files

```
lib/
  rules.lua        CREATE  pure rule evaluation + gate
  session.lua      MODIFY  shift counting, failure state, gate wiring, bump_kinds
  levels.lua       MODIFY  rules + rig data for shipped levels; new levels
  rig.lua          MODIFY  accept a per-level rig override (Task C1), twin axle (C2)
  ghost.lua        CREATE  record / serialise / replay a run (pure)
  draw.lua         MODIFY  rules strip, gate disc, failure card skin, ghost rig, level select
  audio.lua        CREATE  engine pitch, reverse beeper, cone, park chime (D)
  progress.lua     CREATE  best time / stars / ghost per level, love.filesystem (E)
main.lua           MODIFY  pause already exists; add ghost toggle, level select flow
tests/
  test_rules.lua   CREATE  every rule branch + gate math
  test_ghost.lua   CREATE  record/replay round trip, corruption rejection
  test_rig_variants.lua CREATE  tau scaling, twin-axle claims
  test_levels.lua  MODIFY  schema invariants §1
  test_session.lua MODIFY  shift counting, failure freeze
```

---

## §6 — Tasks

Milestones A and B are specified to executable detail: they are the next two weeks of work.
C–E are specified to objective / files / acceptance test and get their own task breakdown
when reached, because their shape depends on playtest results from A and B.

### Milestone A — the decision layer (rules)

#### Task A1: Rule module skeleton + time limit

**Objective:** the smallest rule that proves the plumbing end to end.

**Files:** Create `lib/rules.lua`, `tests/test_rules.lua`; Modify `check_park` call site in
`lib/session.lua`, `tests/main.lua` (add `tests.test_rules`).

**Step 1: Write failing test**

```lua
-- tests/test_rules.lua
local H = require("tests.helper")
local session = require("lib.session")
local fixtures = require("tests.fixtures")

local M = { order = { "time_limit_fails_the_attempt" } }

function M.time_limit_fails_the_attempt()
    local lvl = fixtures.field()
    lvl.rules = { time_limit = 2 }
    local s = session.new(lvl)
    local go = { steer = 0, throttle = 1, brake = 0, handbrake = false }
    for _ = 1, 120 * 3 do session.update(s, go, 1 / 120) end
    H.expect(s.failed ~= nil, "overrunning the time limit must fail the attempt")
    H.expect(s.failed.reason == "out of time", "reason should be out of time")
    H.expect(not s.parked, "a failed attempt is not a park")
end

return M
```

**Step 2: Run, expect RED** — `love tests` → `MODULE LOAD FAILED: tests.test_rules`
(module missing) or `s.failed` nil. Both are legitimate reds; a syntax error is not.

**Step 3: Implement** — `lib/rules.lua` as in §2, plus in `session.update` after
`M.check_park`:

```lua
local reason = rules.check(s)
if reason then
    s.failed = { reason = reason, time = s.t }
    s.rig.v = 0
    return s
end
```

and at the top of `update`: `if s.parked or s.failed then return s end`.

**Step 4: Run, expect GREEN** — `love tests` → `45 passed, 0 failed`.

**Step 5: Commit** — `git add -A && git commit -m "feat: rule evaluation with a time limit"`

#### Task A2: Shift counting

**Objective:** count direction changes, not key presses.

**Files:** Modify `lib/session.lua`, `tests/test_session.lua`.

Test: drive forward, brake to a stop, keep holding brake (reverse), assert `shifts == 1`;
then release, throttle forward, assert `shifts == 2`; and assert that stopping without
reversing adds none. Implement the `last_gear` block from §2. Expect `46 passed`.

#### Task A3: Bump accounting by kind

**Objective:** `bump_kinds = { wall = 0, cone = 0, jackknife = 0 }` so rules can grade by
kind without re-deriving from `last_bump`.

**Files:** Modify `lib/session.lua` (`revert`, cone hit), `tests/test_session.lua`.

Test: one wall hit then one cone → `bump_kinds.wall == 1`, `bump_kinds.cone == 1`,
`bumps == 2`. Expect `47 passed`.

#### Task A4: `cones_must_stand` and `no_wall_contact`

**Objective:** the two "clean line" rules.

**Files:** Modify `lib/rules.lua`, `tests/test_rules.lua`.

Test both branches: knock a cone with the rule on → failed with "hit a cone"; the same
manoeuvre with the rule off → parks. Same for a wall, including the jackknife reason.
Expect `49 passed`.

#### Task A5: The gate

**Objective:** forbid reverse until the rig reaches a marker.

**Files:** Modify `lib/rules.lua` (`gate_open`), `lib/session.lua` (call it in `derive`
before granting reverse), `tests/test_rules.lua`.

Test: with a gate 10 m ahead, holding brake from the spawn must not move the rig backwards
for 2 s; after driving forward through the disc, the same input reverses normally. Expect
`50 passed`.

#### Task A6: Rules in the HUD

**Objective:** the surface from §4, so no rule is silent.

**Files:** Modify `lib/draw.lua` (`D.hud`), `lib/session.lua` (`M.status`), `main.lua`
(smoke frames).

Verification: extend `--smoke` with a rules-level frame, then **look at the screenshot**:
each active rule has a token, the gate disc is drawn, and the failure card names a reason.
No numeric assertion substitutes for this.

#### Task A7: Author six levels around the rules

**Objective:** the actual content. Each level teaches one idea:

1. **One shot** — `max_shifts = 1`: you must commit to the approach angle.
2. **Gate** — `gate`: drive past the bay, then reverse back to it.
3. **Clean line** — `cones_must_stand` down a cone-lined alley.
4. **Deadline** — `time_limit` tight enough that a second correction loses.
5. **Long rig** — `drawbar = 5.2`: the same bay is suddenly easier to reverse and harder to
   corner (this is where rig variants and rules meet).
6. **Exam** — two rules at once, par from playtest only.

Every level: invariants from §1 pass, `apron` still holds, and par is set *after* a
playtest, never guessed. Expect `56 passed`.

### Milestone B — ghost replay

#### Task B1: Record a run

**Files:** Create `lib/ghost.lua`, `tests/test_ghost.lua`.

```lua
-- lib/ghost.lua (pure)
local M = {}

function M.new()
    return { frames = {} }
end

function M.record(g, input)
    g.frames[#g.frames + 1] = {
        steer = input.steer or 0,
        throttle = input.throttle or 0,
        brake = input.brake or 0,
        handbrake = input.handbrake and 1 or 0,
    }
end

return M
```

Test: recording 120 frames produces 120 entries with clamped values.

#### Task B2: Serialise and reparse

**Files:** Modify `lib/ghost.lua`.

Format: a header line `"TYG1 <frames> <levelHash>"` then one line per frame with four
fixed-point integers (`steer*127`, `throttle*255`, ...). Test: encode → decode → every
frame equal within 1/127; a truncated body or a bad header returns `nil, "corrupt"` rather
than raising.

#### Task B3: Playback is bit-identical

**Objective:** the property the whole feature rests on.

**Files:** Modify `lib/ghost.lua` (`M.replay(level, ghost)` returning a session-like state
per step), `tests/test_ghost.lua`.

Test: drive level 1 with a scripted input for 300 steps while recording; replay the record
through a fresh session; assert the final `x, y, th, ph` match to 0 (not `1e-6`). If this
fails, the input quantisation is too coarse — raise it rather than loosening the assertion.

#### Task B4: Store the best run

**Files:** Create `lib/progress.lua`; Modify `main.lua`.

`progress.lua` writes `love.filesystem.write("progress.lua", serialised)` and reads it back
with `loadstring`-free parsing. Key: `levelIndex .. ":" .. hash(level)`. Test the hash
changes when any level field changes.

#### Task B5: Draw the ghost

**Files:** Modify `lib/draw.lua`, `main.lua` (advance the ghost at the same elapsed time,
toggle with `H`).

Verification: smoke frame with a ghost present; the ghost must be visibly a ghost.

### Milestone C — rig variety

- **C1** `rig.new(x, y, th, override)` merges `level.rig` over the defaults; everything that
  reads `M.CAR`/`M.CARAVAN` becomes instance state. Test: a 5.2 m drawbar diverges slower
  than 3.6 m at the same reverse speed (the τ claim, measured not assumed).
- **C2** Twin axle: a second trailer axle behind the first resists rotation. Cheapest
  honest model is a rotation damping term proportional to lateral velocity at the rear
  axle — needs its own plan and a falsification test before it touches the game.
- **C3** Three levels per rig variant; par re-measured for all of them.

### Milestone D — sound and juice

- **D1** Reverse beeper, pitched to `|v|`, starts when gear is R. It is also the clearest
  possible feedback that the dwell completed.
- **D2** Engine note pitched to `v`, tyre crunch on cone contact, sawtooth scrape on wall.
- **D3** Park chime + 120 ms camera pulse; failure thud with no pulse (failures must not
  feel like rewards).
- **D4** Surface flag per level (asphalt/gravel) changing the crunch sound only — not grip.
  Grip changes belong to Milestone C's physics, not to a sound task.

### Milestone E — the meta layer

- **E1** Level select: grid of levels, stars, best time, ghost present.
- **E2** Next-level flow after a park (`Space`), restart (`R`).
- **E3** Per-level star thresholds stored in level data, not computed.
- **E4** Optional: export a ghost as a shareable string.

---

## §7 — Validation checklist

- [ ] `love tests` exits 0, and the count matches the number of tests written.
- [ ] `xvfb-run -a -s "-screen 0 1280x720x24" love . --smoke` prints `SMOKE OK` and the
      screenshots for rules, gate, failure card and ghost have each been looked at.
- [ ] Every level with a rule has that rule visible in the HUD before the player moves.
- [ ] `lib/rules.lua`, `lib/ghost.lua`, `lib/progress.lua` contain no `love.*` call at all.
- [ ] `lib/rig.lua` and `lib/session.lua` contain no RNG, `os.time` or `os.clock`.
- [ ] A failed attempt freezes and names its reason; `R` retries in under 200 ms.
- [ ] Ghost replay of a recorded run reproduces the final pose exactly.
- [ ] Editing a level invalidates its stored ghost and best time.
- [ ] No par time in any level was written without a playtest behind it.

---

## §8 — Risks and trade-offs

**Hard failure punishes information the player did not have.** A player who drives 15 s and
then exceeds a shift budget has lost to a rule they may not have internalised. Mitigation:
the rules strip is visible from the first frame, the token that is about to be spent goes
amber, and retry is instant. Decide by playtest whether hard fail should become a star cap
instead — the same `rules.check` supports both, it is a card-and-freeze difference only.

**Rules multiply until the level is a checklist.** Six tokens above the bay turns a driving
game into a form to fill in. Mitigation: at most two rules per level for the first eight
levels, and every rule must be the *reason the level is interesting* — if a level is winnable
with the rule off and no different, cut the rule.

**Ghost replay silently rots if determinism breaks.** The whole feature rests on one
property. Mitigation: `bodies_touch_near_jackknife_not_earlier` and `fixed_step_determinism`
already exist; Task B3 adds an exact-equality round trip, and any change to `rig.step`
should be treated as breaking until that test says otherwise.

**Rig variants turn tuning into a 2-D matrix.** Speed cap, steering rate, bay tolerance and
par all shift with drawbar length. Mitigation: one variant per level, no mixed variants in
one campaign section, and re-measure par per variant rather than scaling it.

**Scope creep is the real risk.** The prototype is 1,700 lines and complete; a delivery map
or a physics upgrade would double it and add nothing the mechanic needs. §9 is the fence.

---

## §9 — Explicitly out of scope

- An open world, a town, traffic, or a delivery map with navigation.
- Suspension, tyre slip, weight transfer, or any physics beyond the kinematic trailer.
- Procedural or generated levels.
- Online multiplayer, accounts, or a hosted leaderboard (a local best-time board only).
- Unhitching the caravan as a mechanic (revisit only if §0's facing question reopens).
- Caravans that tip over, weather, time of day, or a day/night cycle.
- Mobile or web export (love.js) — the game targets desktop LÖVE.
