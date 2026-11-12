# Tow Yard — review findings: bugs and errors

A read-only review of the whole codebase (11.5k lines of Lua: `main.lua`, `lib/`,
`lib/edit/`, `tests/`), done on 2026-11-12 against commit `ebee817`.

**Every finding below was reproduced by execution on this machine.** Where a claim
could only be established by reading, it says so. Nothing in the repository was
modified to produce this document.

Baseline at the time of review:

| Gate | Result |
|---|---|
| `love tests` | 209 passed, 0 failed, exit 0 |
| `love . --smoke` (under `xvfb-run`) | `SMOKE OK`, exit 0, save directory byte-identical except the PNGs |
| `love . --audit all` | exit 1 (level 3 reports NO LINE — see B2) |
| `git status --porcelain` | empty |

Severity is about what a **player** experiences, not about how hard the fix is.

| | Count |
|---|---|
| Critical | 5 |
| Major | 10 |
| Minor | 12 |

---

## Critical

### B1 — The ghost desynchronises from the player whenever the run has a pre-roll

> **FIXED** in `1839e4d` — `run.clock_start` / `run.advance_aligned` rebase the
> ghost onto its own pre-roll; measured lag 5.4 m -> 0.000 m, pinned by
> `the_ghost_stays_level_with_a_pre_roll`.

**`lib/session.lua:204` · `lib/run.lua:52` · `main.lua:1009`**

`game.steps` counts only frames **after** the session `started`. But `run.recording`
also records frames **before** `started` — steering at a standstill is captured
deliberately ("the wheel position is physics state, and dropping those frames would
make the replay diverge"). So a run can hold *N* frames while the player's counter
holds *M*, and `advance_ghost()` advances the ghost to the player's `M` — landing it
*N* frames inside its own pre-roll.

Verified with a 2 s standstill steer, which is exactly what the game itself teaches
("Set the angle up before you commit to the reverse"):

```
run holds 840 frames, player clock counts 600 steps
ghost advanced to 600 -> ghost x = 41.343, player x = 37.743   (3.6 m apart)
```

The ghost visibly drives the wrong part of its line while you race it. The lag is
exactly the length of the pre-roll: 60 frames of setup → 60 frames behind, 360 frames
→ 360 frames behind.

**Fix.** Advance the ghost to *its own* clock start plus the player's step count, not
to the player's step count:

```lua
-- the ghost's own pre-roll is not the player's
local target = (ghost.clock_start - 1) + game.steps
run.advance(game.ghost, target)
```

Measured after the fix: lag **3.600 m → 0.000 m**.

**Note.** `run.trim()` cannot fix this. `idle_frame()` (`lib/run.lua:59`) treats a
steer-only frame as *non*-idle, so the prefix survives the trim — which is correct,
because the wheel angle is real physics state. The two counters are simply in
different time bases.

---

### B2 — The audit cannot see any level whose bay is off-axis, and reports "unwinnable"

> **PARTLY FIXED** in `a1e7327` — a two-segment arc search now certifies bays up
> to 60 deg off-axis, and a NO LINE past that prints "UNPROVEN, not unwinnable"
> instead of implying the level is broken. A three-point turn is still beyond the
> instrument; level 3 therefore still needs a hand-staged playtest to certify.

**`lib/audit.lua:86`**

```lua
local target_th = reversing and geom.wrap(bearing + math.pi) or bearing
```

`approach()` derives the target heading from the **bearing to the pose**, never from
the pose's own heading. The rig can therefore only ever arrive pointing *along the
bearing*, while the arrival test demands `|th - tth| < 14°` — a heading the
controller structurally cannot produce once the bay axis differs from the
spawn→bay bearing.

Decisive proof: take shipped level 1 and rotate **only** its bay, on an empty,
trivially parkable yard with no walls and no cones.

```
bay at  0 deg off-axis: WINNABLE        (reached 16, parked 12)
bay at 15 deg off-axis: WINNABLE        (reached 16, parked 4)
bay at 30 deg off-axis: NO LINE FOUND   (reached 8,  parked 0)
bay at 45 deg off-axis: NO LINE FOUND   (reached 0,  parked 0)
bay at 90 deg off-axis: NO LINE FOUND   (reached 0,  parked 0)
```

An empty field with a 30°-rotated bay is not "unwinnable" — the instrument is
failing. This is exactly level 3 "Angled bay" (a 270° bay), the one level the
full-grid audit reports as **NO LINE**, and AGENTS.md currently excuses it as *"the
spawn faces a wall (level 3, Angled bay) reports NO LINE — that verdict means 'needs
a playtest', not 'unwinnable'".*

**It does not need a playtest.** From the correct staging pose the game's own
reverse-in parks level 3 in 0.2 s with zero bumps:

```
pose (23,20) facing 270 -> PARKED (t=0.2 s, bumps=0, ph=270 deg)
pose (23,18) facing 270 -> PARKED (t=1.4 s, bumps=0, ph=270 deg)
pose (23,16) facing 270 -> PARKED (t=2.8 s, bumps=0, ph=270 deg)
pose (23,14) facing 270 -> PARKED (t=3.9 s, bumps=0, ph=269 deg)
```

The staging grid is wrong for a non-horizontal axis too: poses are placed *past* the
bay along `+axis`, which for a 270° bay puts them **south** of it — the wrong side to
reverse from.

**Fix.** Make the approach a goal-pose controller that converges to position *and*
heading, and place staging poses on the side the rig reverses *from*. Until then, no
level whose bay is off-axis can be certified, which blocks authoring anything new.

---

### B3 — The rig can drive straight out of the yard, and the camera stops following

> **FIXED** in `6b20ccf` — the bounds rectangle is now collision, reported as a
> wall contact; all seven levels contain a 30 s straight run, pinned by
> `the_yard_edge_is_a_wall` (mutation-checked).

**`lib/levels.lua` (every `bounds`) · `main.lua:78`**

`bounds` sizes the camera. It is not collision. Every shipped level lets the rig
escape:

```
Straight back ESCAPED the bounds (60.1,20.0) at t=3.1 s
Long way back    ESCAPED the bounds (60.0,20.0) at t=2.3 s
Angled bay       ESCAPED the bounds (-0.0,10.0) at t=6.2 s
Tight alley      ESCAPED the bounds (60.0,20.0) at t=2.6 s
Fire side        ESCAPED the bounds (60.0,20.0) at t=2.6 s
Round the back   ESCAPED the bounds (60.0,20.0) at t=2.3 s
Clean line       ESCAPED the bounds (60.0,20.0) at t=2.3 s
```

While building probes for this review, two rigs reached **x = 209 m** and
**y = −57 m**. The camera is recomputed only on load and resize (`main.lua:109`,
`main.lua:1650`) — it never follows the rig. Drive off the right edge and the rig
leaves the screen entirely, with no wall, no bump and no way back.

**Fix.** Close the yard with a hedge run **in the data** (the bounds rectangle is a
camera frame, not a fence) and add a bounds check that reverts the step. A level
whose open edge lets the player drive into the void is a shipped bug.

---

### B4 — A damaged park loses the level's "completed" mark on reload

> **FIXED** in `9545902` — `parse_line` now accepts `best == 0` (the value
> `serialise` already writes for "no time") and maps it back to `nil`, so the
> level reads as completed with no phantom `0.00` best. `0` cannot collide with
> a real time: `PARK_HOLD` is 0.25 s. Pinned by
> `a_damaged_park_survives_a_restart`.

**`lib/progress.lua:88` (writer) vs `lib/progress.lua:41` (reader)**

```lua
-- writer
out[#out + 1] = string.format("level %s %d %.2f %d %s",
    e.id, e.stars or 0, e.best or 0, e.ghost and 1 or 0, e.content or ...)

-- reader
if best ~= best or best <= 0 then return nil end
```

A damaged attempt has no time, so `e.best` is `nil`, the serialiser writes `0.00`,
and the reader **rejects the whole line**. The player's park is lost:

```
the file on disk:
  level straight-back 0 0.00 0 84fbacab...
reload: warnings: skipped a line: level straight-back 0 0.00 0 ...
progress.mark() -> completed = false   stars = nil   best = nil
```

The player *did* park the caravan — `session.check_park` counts a damaged rig's park
("the park still completes") — but the level shows as never completed, forever. A
clean park round-trips fine (`completed = true, best = 20`).

**Fix.** Let `parse_line` accept `best == 0` as "completed, no time", or write a
distinct marker. The two halves of one file format must agree on what "no time" means.

---

### B5 — A gamepad stick drift silently overrides the keyboard

> **FIXED** in `61ef03c` — the steer merge compares magnitudes like throttle and
> brake already did; measured keyboard-held + drift 0.2 now yields steer `+1.0000`
> / `keyboard` (was `-0.0348` / `gamepad`), pinned by
> `a_drifting_pad_does_not_override_a_held_key`.

**`lib/input.lua:87-95`**

The module header claims *"The stronger of the two devices wins per axis, so the pad
and the keyboard can be held at the same time"*, and the README repeats it ("merge per
axis (strongest input wins)"). But `merge_pad` **overwrites** the keyboard value
whenever the stick is past the deadzone:

```lua
local steer = M.steer_from_stick(pad.leftx or 0)
if steer == 0 then
    steer = (pad.dpleft and 1 or 0) - (pad.dpright and 1 or 0)
end
if steer ~= 0 then
    input.steer = steer          -- overwrites, does not compare
    input.last_device = "gamepad"
end
```

Verified:

```
keyboard LEFT (1), pad resting (0)      -> steer = +1.0000  last_device=nil
keyboard LEFT (1), pad drift (0.2)     -> steer = -0.0348  last_device=gamepad
no keyboard,        pad drift (0.2)    -> steer = -0.0348  last_device=gamepad
no keyboard,        pad inside dz(0.05) -> steer = +0.0000  last_device=nil
```

A pad resting just past the deadzone (0.12) steers the car by itself **and steals the
HUD glyph**. That is exactly the failure the skill's "a resting pad must change
nothing" rule forbids, and `tests/test_input_pad.lua` only checks the resting-stick
case for the **menu**, never for driving.

**Fix.**

```lua
if math.abs(steer) > math.abs(input.steer or 0) then
    input.steer = steer
    input.last_device = "gamepad"
end
```

Add a test case: keyboard held + pad drift.

---

## Major

### B6 — `bay_inside_bounds` ignores the bay's angle: false rejects *and* false accepts

**`lib/levelcheck.lua:109`**

```lua
if b.x - b.w / 2 < bd.x0 or b.x + b.w / 2 > bd.x1 then
```

It compares `w/2` on the X axis even when the bay is rotated. Both failure directions
confirmed:

| case | reality | rule says |
|---|---|---|
| 9×4 bay at (56,20), rotated 90° | x extent 54.00–58.00, **inside** bounds | ❌ "bay x outside bounds" |
| 8×16 bay at (55,20), rotated 90° | x extent 47.00–63.00, **escapes** bounds | ❌ nothing |

The first locks an author out of a legal 90° bay; the second lets the editor save a
bay whose corner is 3 m outside the yard.

**Fix.** Build the rotated bay polygon and test its four corners against the bounds
rectangle.

---

### B7 — A failed write is reported as success, and the best time is silently lost

> **FIXED** in `cf24471` — `save`/`put_ghost` check the write, keep `dirty` set on
> failure so the next park retries, and return `false, reason`; the three
> `main.lua` sites go through `save_progress()`, which toasts the reason.
> Mutation-checked (both write checks reverted fails exactly the two new tests).

**`lib/progress.lua:202` (`save`) and `:186` (`put_ghost`)**

```lua
self.disk.write(ghost_name(level), text)
return true          -- write() may have returned nil, err

self.disk.write(M.FILE, serialise(self))
self.dirty = false   -- cleared even though nothing was written
```

`love.filesystem.write` returns `nil, err` on failure. Verified with a disk whose
`write` fails:

```
progress.save() returned true
store.dirty after save = false     <-- it will NEVER retry
progress.txt actually written? false
```

The player's best time is gone and can never be saved again, because `dirty` was
cleared by a write that did not happen. `lib/edit/autosave.lua:42` *does* check its
return value — the two writers in one codebase disagree.

**Fix.** Capture the return, keep `dirty = true` on failure, and return the error.
Same for `put_ghost`.

---

### B8 — The importer and the editor's Save skip every geometric rule

> **FIXED** in `9f88d20` — the importer now runs `levelcheck.errors` and refuses
> an illegal level before storing it; the editor still saves (the rail already
> names the problem, and the work is the player's) but its toast now says "saved
> X with N problems: …" instead of a clean "saved". Pinned by the
> `IMPORT REFUSES AN ILLEGAL LEVEL` smoke frame, mutation-checked.

**`main.lua:187` (`import_text`) · `main.lua:449` (`editor_save`)**

`levelcheck.errors()` is called by the test suite and by the editor's *error
display* — but **not** by the import path and **not** by the save path.
`catalog_errors` is likewise only ever called from `tests/`, despite the module
header claiming it is "used by the suite and, later, the importer and editor".

A level with a spawn inside a wall and a bay outside the bounds round-trips through
the format layer without complaint:

```
levelcheck.errors() says:
  - spawn overlaps wall 1 (hedge)
  - bay x outside bounds
encode+decode: ACCEPTED
```

An imported level is then stored, listed in the menu and playable with a broken spawn.
(Unknown *kinds* are caught — the format layer rejects those — but no geometric rule
is.)

**Fix.** Run `levelcheck.errors()` in `import_text` and in `editor_save`, and refuse
with the reasons listed.

---

### B9 — The editor's Verify button uses the grid AGENTS.md says is not a gate

**`main.lua:433`**

```lua
local res = audit.solve(lvl, { grid = audit.QUICK_GRID })
```

`QUICK_GRID` is 18 poses against the full grid's 360, and AGENTS.md states: *"Fire
side and Long way back both report NO LINE under `--quick` and find a clean line in
the full 360-pose grid."* Verified — the in-app button tells an author their good
level is broken:

```
level 2 Long way back    quick = NO LINE FOUND   (full grid: winnable)
level 3 Angled bay       quick = NO LINE FOUND   (full grid: also NO LINE — see B2)
level 5 Fire side        quick = NO LINE FOUND   (full grid: winnable)
```

**Fix.** Use the full grid, or add a middle tier between quick and full and label the
button with the tier it actually ran. The full grid takes ~29 s per level, so it
cannot simply block the UI — but a two-second quick check that lies is worse than no
check.

---

### B10 — The editor never draws its own toasts

**`lib/draw.lua` — the toast is rendered only in `D.hud` (638) and `D.menu` (791);
`D.editor_ui` (1243–1442) has no toast renderer at all.**

The skill's standing pitfall, verbatim: *"a `say()`/toast renderer that lives only in
the play HUD leaves every 'saved', 'renamed', 'copied' on a second screen permanently
invisible, so a screen that reuses the channel must draw it."*

The editor calls `say()` on 14 distinct events — *"saved X"*, *"renamed to X"*, *"a
line exists: N s by machine"*, *"no line found"*, *"undo"*, *"level code copied"*, the
"pick a tool, then click the yard" hint — and **none of them are ever visible**. The
editor's entire feedback loop is silent. `main.lua:1263` even contains
`game.toast = nil -- keep the capture unchanged`, which implies the author expected
the editor frame to show it.

**Fix.** Draw the toast in `D.editor_ui` (and `D.editor_prompt`), reading `game.toast`
through the same `love.timer.getTime() < game.toast.expires` guard the other two
screens use.

---

### B11 — The smoke writes into the player's real save directory

**`main.lua:1461` → `import_text` → `levelfmt.save_custom(disk, ...)`,** where `disk`
(`main.lua:30-35`) is the real `love.filesystem`. The cleanup is at
`main.lua:1465-1468`, *after* the import.

If the smoke dies in between, the player is left with a bogus `smoke-import` custom
level in their level select, permanently. AGENTS.md documents this exact hazard: *"one
real failure then poisons every run after it."*

The autosave path has the same exposure and is guarded only by a **frame fixture**,
not by a rule: `main.lua:294` guards `editor_autosave_now()`, but `editor_edit`
(`310`), `editor_mousemoved` (`664`, `695`) and `editor_autosave` (`271`) have no
`smoke.enabled` guard. The only thing stopping them is
`e.autosave_state = { at = math.huge }` at `main.lua:1252` and `1518` — a line of
test fixture, which any future editor gesture added to a smoke frame will bypass.

**Fix.** Give the smoke its own disk, the way it already has one for progress
(`smoke_progress()`, `main.lua:805`), and route `save_custom` / `delete_custom`
through it under `smoke.enabled`. Put the `smoke.enabled` guard inside
`editor_autosave` so the guarantee lives in the shell rather than in a frame.

---

### B12 — Par times are not comparable between levels

**`lib/levels.lua` · `lib/session.lua:319`**

The stated policy (in `lib/levels.lua`) is "audit time × ~1.5". The actual ratios
run from 1.25 to 1.66:

```
Straight back    par 22  audit 13.22  ratio 1.66
Long way back    par 30  audit 19.48  ratio 1.54
Tight alley      par 26  audit 20.78  ratio 1.25   <-- a perfect machine run earns 3 stars
Fire side        par 30  audit 18.07  ratio 1.66
Round the back   par 32  audit 22.10  ratio 1.45
Clean line       par 30  audit 20.99  ratio 1.43
```

"Tight alley" hands out 3 stars for a flawless machine drive; no other level does. A
star rating is supposed to be a shared currency — right now it means something
different per level.

**Fix.** Recompute every par as `audit × 1.5` once B2 is fixed (the audit times
change), and re-measure after any physics change. The skill's rule stands: *"Never
hand-tune par times: playtest them"* — and never scale an old one.

---

### B13 — One clipped cone costs exactly the same two stars as a perfect run

> **FIXED** in `2232a89` — the two qualities are defined independently
> (`clean = bumps == 0`, `quick = time <= par`) and each is priced at every tier,
> so a cone costs a star in both the fast and the slow case. The `1.5x` band is
> gone. Pinned by `the_grade_prices_both_cleanliness_and_speed`, which walks all
> four corners and isolates the one that distinguishes the two rules.

**`lib/session.lua:325` (`session.grade`)**

```lua
if f.bumps == 0 and f.time <= s.level.par then return 3 end
if f.bumps == 0 or f.time <= s.level.par * 1.5 then return 2 end
```

Because the second rule is an `or`, **any** zero-bump run gets 2 stars regardless of
time, and a bump only ever costs the third star:

```
par 30:  clean 20s -> 3    clean 40s -> 2    1 cone 20s -> 2    1 cone 40s -> 2
```

The cone's 2 s penalty is invisible in the star rating — the number the player
actually reads. The README says "Three pips are for a clean run inside par; two for
clean-or-quick", which is literally what the code does, but it is not what the player
expects from a game whose only scoring currency is time.

**Fix.** Make the second rule a conjunction with the par band, so cleanliness and
speed are separate axes:

```lua
if (f.bumps == 0 and f.time <= s.level.par * 1.5)
   or (f.bumps > 0 and f.time <= s.level.par) then return 2 end
```

---

### B14 — A run-only share import is verified against the last-played level, not the highlighted row

**`main.lua:201`**

```lua
local ok, final = run.verify(game.level, got.run)
```

Reached from the level select at `main.lua:1601-1603` (`menu_keypressed` "i"), where
`game.level` is still whatever was last loaded (`main.lua:946` loads level 1 at boot)
rather than `menu.current(game.menu)`.

A player on "Tight alley" who pastes a rival ghost for Tight Alley gets *"that run
does not fit this level"* unless Tight Alley happens to be the last level played; a
run that *does* verify is stored as the ghost for the wrong level id
(`main.lua:203-205`).

**Fix.** In the menu path, bind the import to `menu.current(game.menu)`; fall back to
`game.level` only in play mode.

---

### B15 — `progress.adopt()` accepts a void run that `record()` refuses

**`lib/progress.lua:143`**

`adopt` never checks `final.damaged`:

```lua
if not entry.best or final.time < entry.best then entry.best = final.time end
entry.ghost = true
```

The two writers disagree about the **same** void park:

```
progress.record(void park) -> best=nil ghost=false stars=0
progress.adopt(void final) -> best=0    ghost=true  stars=0
```

`adopt` is exactly what the import path calls (`main.lua:189`, `main.lua:203`).
`check_park` never consults `s.damaged` (verified: a damaged rig placed in the bay
still parks, with `final.damaged = true`), so a void `final` can reach `adopt`.

**Reachability caveat.** I could not construct a void run that survives
`run.verify`'s replay-and-park check — every detour I spliced in either repaired
itself (`revert()` restores the previous pose) or prevented the park. The
inconsistency between the two writers is **verified**; the exploit path is
**plausible but unproven**. Treat it as a correctness bug in the store, not as a
confirmed live exploit.

**Fix.** Make `adopt` refuse a damaged final, matching `record`.

---

## Minor

### B16 — `--audit` returns before the smoke error handler is installed

**`main.lua:907` vs `main.lua:913`.** `love . --audit N --smoke` therefore runs under
LÖVE's **interactive** error screen, so a crash reports as a timeout (124) instead of
a failure with a traceback. Move the handler install above the `want_audit` early
return.

### B17 — `love.resize` indexes `game.level` with no nil guard

**`main.lua:1650`** → `camera(game.level)` → `lvl.bounds`. On the `--audit` path
`game.level` is nil, because `love.load` returns at `main.lua:907` before
`load_level(1)` at `main.lua:946`. Guard it.

### B18 — `game.paused` survives a level reload and a mode switch

**`main.lua:98-137`** (`load_level_object`) resets acc/steps/record/delta/input but
**not** `paused`; `open_menu` (`main.lua:238-245`) does not either. Pause, press Esc,
pick a level → you return to a still-paused game.

### B19 — `game.toast` is never cleared on a mode change

`game.toast = nil` appears only at `main.lua:1263` and `1495`, both smoke fixtures. A
menu message (*"deleted X"*) can still be drawn by the HUD, and the editor's messages
persist into the play screen. Clear it in `open_menu` / `load_level_object`.

### B20 — The editor reads two different pointers

The rail hover uses the injected pointer (`draw.set_pointer` → `mouse_pos()`,
`lib/draw.lua:66-69`, `1276`), but `editor_wheelmoved` (`main.lua:716`) calls
`love.mouse.getPosition()` directly, so zoom anchors on the real cursor instead of the
injected one. Route the wheel zoom through the same seam.

### B21 — Dead locals that look alive

**`main.lua:832` and `:847`** both declare `WINDOW_MARGIN_X, WINDOW_MARGIN_Y` (the
first is shadowed), and `main.lua:863` declares `resize_guard, last_clamp`, which are
never read. The skill flags exactly this class: *"a window-floor clamp added as a
second `love.resize` near the window helpers never ran."*

### B22 — `clone_cones` hardcodes the traffic-cone radius

**`lib/session.lua:51`** — `r = c.r or 0.35`. Harmless today only because
`levelfmt.resolve` always fills `r`; any cone reaching the session unresolved gets the
traffic-cone radius regardless of kind (a fire pit would be 0.35 m, not 0.55 m). Use
`props.footprint(c).r`.

### B23 — `TUNE.jackknife` is never read by the sim

**`lib/rig.lua:42`.** The jackknife is detected geometrically (`lib/session.lua:240`,
`geom.overlap(car, van)`); the constant only labels the HUD tick (`lib/draw.lua:602`)
and a debug line (`:1569`). Changing it changes no behaviour, yet the HUD presents 72°
as the danger line — and the real limit (66–72°) varies with geometry.

### B24 — `hash.short()` is dead code

**`lib/hash.lua:31`** — zero references anywhere in `lib/`, `main.lua`, `tests/` or
`tools/`.

### B25 — `doc.list()` is only used by a test

**`lib/edit/doc.lua:80`** — called only from `tests/test_edit_doc.lua:44`.

### B26 — Encoding an *unresolved* level writes `w 0 h 0`

**`lib/levelfmt.lua:100-104`.** `default_size = def and def.w == w.w and def.h == w.h`
is false when the entry has no explicit `w`/`h` (the authored form), and `num(nil)`
returns `"0"`:

```
encoded:   wall hedge 30 14 0 0
decoded:   REFUSED: wall sizes must be positive
```

**Not reachable today** — every current caller passes a resolved level, and
`doc.add` (`lib/edit/doc.lua:149-156`) carries the kind's sizes explicitly — but it
is a live trap for the first caller that forgets `resolve()`.

### B27 — `M.KEYS.backward` is both brake and reverse, and the precedence is undocumented

**`lib/input.lua:135-138` · `lib/session.lua:114`.** `if throttle > 0 and brake <= 0`
means a held brake key silently cancels the throttle. Not proven to be a
player-visible defect; flagged because the precedence is undocumented.

### B28 — `delete_custom` ignores its index write's return value

**`lib/levelfmt.lua:549-558`** — same shape as B7: the file is deleted and the index
rewritten with no check that the write succeeded. By inspection; the delete path was
not exercised.

### B29 — `editor_autosave`'s failure check is asymmetric with `progress.save()`

**`lib/edit/autosave.lua:43`** — `if ok == false or (ok == nil and err)`: a disk
adapter returning `nil` with no error message reports success. Same shape in
`lib/progress.lua`. By inspection.

---

## Claims that were checked and refuted

Recording these so they are not re-investigated.

| Claim | Verdict |
|---|---|
| `love.filedropped`'s `file:read()` reads one line | **Refuted.** LÖVE's `File:read()` reads the **whole** file (56 of 56 bytes). Plain Lua `io` differs; the game's drop path is correct. |
| `run.trim()` drops a steer-only prefix | **Refuted.** `idle_frame()` treats a non-zero steer as non-idle; the trim dropped 0 frames. |
| Level 3 has no `par` field (would crash the HUD) | **Refuted.** Level 3 has `par = 30`. |
| `progress.adopt()` is exploitable end-to-end via a share import | **Unproven.** The writer inconsistency is real (B15); no void run was found that survives `run.verify`. |
| The rig can leave the yard on every level | **Confirmed** (B3), and worse than expected — probes reached x = 209 m. |

## Also ruled out

- **No duplicate `love.*` callbacks** — all 15 definitions appear exactly once.
- **No `love.*` calls in `lib/` or `lib/edit/`** — verified by grep across every pure
  module.
- **No rad/deg confusion** — `levelfmt` converts at the file boundary only.
- **No division by zero** — `session.lua:287` guards `|v| < PARK_SPEED` before
  `check_park`; `sfx.lua:56` divides by a non-zero constant; `geom.lua:96` guards
  `len2 > 0`.
- **No off-by-one in the quantisation grid** — `session.lua:25-30` and
  `run.lua:199-223` agree at 127/255.
- **The fixed-timestep loop cannot spiral** — `dt` is clamped to 0.1 s and
  `MAX_STEPS * DT` is exactly 0.1 s.
- **Restart / next-level navigation** — `reload_level` reloads the *level object*, and
  `next_campaign_level` resolves by **id** via `levels.find`. No stale catalogue index
  survives.
- **The result card's arithmetic** — `game.record` / `game.delta` come from the sim's
  `final.time` (= driven + penalties), and the HUD clock shows the same sum. A damaged
  attempt is refused a time, a star and a ghost.
