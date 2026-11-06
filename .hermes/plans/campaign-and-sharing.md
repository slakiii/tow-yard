# Tow Yard — Campaign, Level Select, Ghosts, Sharing and Editor

**Goal:** turn six hand-authored levels into a game with a campaign structure, persistent
progress, shareable runs and levels, and an authoring tool — without a server, a UI toolkit
or a second physics.

**Architecture:** everything goes through one new idea — **a level and a run are portable
data**. `lib/levelfmt.lua` (level text format, canonical hash), `lib/run.lua` (input
recording, replay, verification), `lib/share.lua` (bundles and codes) are pure modules
under `lib/`; `main.lua` gets the first explicit scene machine it has ever had and stays a
thin shell. Ghosts are nearly free because the sim is already a deterministic fixed 1/120
step; the cost is the format, the verification and the UI, in that order.

**Tech stack:** LÖVE 11.5 / LuaJIT. Headless suite `love tests`, render smoke
`xvfb-run -a -s "-screen 0 1280x720x24" love . --smoke`, winnability audit `love . --audit N`.
Verified present in the installed `love-11.5` binary: `sha256`, `zlib`, `base64`,
`filedropped`, `getClipboardText`.

Read `.hermes/plans/tow-yard.md` first (physics, controls, tuning numbers) and
`.hermes/plans/enjoyment-roadmap.md` §A/§C/§D, which this plan does **not** touch.

---

## §0 — Decisions locked with the user (do not re-litigate)

| Decision | Choice |
|---|---|
| Campaign structure | Levels carry `series` + `order`; the menu shows one row per series |
| Progression gating | **None.** Every level is open from the start; stars and best times are the only progression |
| Training series | Easy levels with a hint line, taught by geometry. **No** scripted prompts, no gated inputs, no tutorial subsystem |
| "Completed" | A parked attempt, any grade. Stars stay `session.grade` (3 clean+par, 2 one of them, 1 parked); best time is the minimum |
| Transport | **Offline first**: a share code on the clipboard and a `.towyard` file, imported by paste or drag-and-drop. A hosted paste/leaderboard may come later **behind the same seam** — no accounts, no upload in v1 |
| Editor timing | **Dev tool first** (`love . --edit`), player-facing second. The format and the loader ship before the editor UI |
| Custom levels | A separate **Custom levels** tab, never mixed into the campaign list |
| Shared files | Data-only text, parsed by hand. **Never `loadstring`/`load` on imported content.** Strict keys, hard caps |
| Run honesty | A shared run is verified by replaying it through the shipped sim on load. A claimed time is never trusted; the recomputed one is what is shown |
| Identity | Stable `id` for progress, `content_hash` for time/ghost validity — two keys, not one |
| Determinism | Inputs are **quantised at the boundary**, so live play and replay consume the identical numbers |
| Consequence of an edit | Completion is a memory, times and ghosts are content-bound: an edited level shows "completed (level changed), set a new time" |
| Supersedes | `enjoyment-roadmap.md` §0's "no hosted leaderboard" line (now: optional later), and its §B (ghost replay) and §E1/E2/E4 (level select, next-level flow, ghost export) are folded into this plan |
| Untouched | Roadmap Milestone C (rig variants) and D (sound) |
| Rules live in level data | **Decided with the user:** `level.rules` is part of the level document, so it sits inside `content_hash` — changing a rule invalidates times and ghosts exactly like moving a wall does |

---

## §1 — Data schema

Four text documents, one line-oriented grammar, one parser per document. Text and not JSON
because LÖVE ships no JSON parser, and not Lua because a shared file must never be
executable. Canonical re-encoding must reproduce identical bytes for identical data — the
hash depends on it.

### 1.1 Level document

```
TOWYARD LEVEL 1
id straight-back
name "Straight back"
hint "Reverse straight back into the bay. The caravan will not stay straight on its own."
series training
order 1
bounds 0 0 60 40
spawn 46 20 0
bay 22 20 9 4 0 6
par 22
apron 2.0
wall hedge 29 14 46 0.6 0
wall building 8 33
cone cone 33 17.2 0.35
cone firepit 40 15.8
surface gravel 30 20 60 14 0
```

Grammar notes (all angles in **degrees** in the file, radians in memory):

- `wall <kind> <x> <y> [w] [h] [angle]` — a size omitted means "take the kind's default".
- `cone <kind> <x> <y> [r]`.
- `surface <kind> <x> <y> <w> <h> [angle]`.
- `bay <x> <y> <w> <h> <angle> <tol>` — `tol` is the angle tolerance in degrees.
- `#` starts a comment line; comments are ignored and never influence the hash.
- Strings are double-quoted with exactly three escapes: `\"`, `\\`, `\n`.
- No other key may appear on any line. Unknown key = rejected document.

### 1.2 Run document

```
TOWYARD RUN 1
level straight-back
content 3f1c9a0e7b2d4c68a5e9f0b1c2d3e4f5
build 91ab77c0e21d4f38a6b5c4d3e2f10987
time 13.21
bumps 0
frames 1585
data eJytVk1v2zAM...
```

- `data` is `base64(zlib(4 bytes per frame × frames))`, one byte each:
  `steer` (int8 offset by +127 ⇒ 0..254), `throttle` (0..255), `brake` (0..255),
  `flags` (bit 0 = handbrake).
- One frame per **physics step** from the moment the level loads. Pausing records nothing,
  because pausing stops the accumulator — a property worth a test.
- `time` and `bumps` are **informational**. On import they are recomputed and the
  recomputed values are the ones displayed, so a hand-edited header buys nothing.
- `content` is the level's `content_hash`; `build` is the physics/rule-constants hash.

### 1.3 Share document (one paste carries what it needs)

```
TOWYARD SHARE 1
author "user"
--- level
TOWYARD LEVEL 1
...level lines...
--- run
TOWYARD RUN 1
...run lines...
```

The `--- level` and `--- run` section markers split the payload into sub-documents, each
handed to its own parser. Either section may be absent (a level with no run, a run on a
shipped level). The clipboard form is `TY1:` ++ `base64(zlib(the whole share text))` on one
line; the file form is the text itself as `<name>.towyard`. The reader sniffs the prefix, so
one code path accepts both.

### 1.4 Progress document (local, in the LÖVE save directory)

```
TOWYARD PROGRESS 1
level straight-back 3 13.21 1 3f1c9a0e7b2d4c68a5e9f0b1c2d3e4f5
```

`id stars best_time has_ghost content_hash`. Ghost bytes live in
`ghosts/<content_hash>.tyrun`, so the index stays small and one corrupt ghost cannot take
the whole progress file with it. Custom levels are **not** indexed — they are discovered by
scanning `custom/*.tylevel`, so there is no second list to desync.

### 1.5 Schema invariants (tests enforce these)

1. Every shipped level has a unique `id` matching `^[a-z0-9][a-z0-9-]{0,31}$`, a `series`
   string and a positive integer `order`.
2. A level document round-trips: `decode(encode(L))` deep-equals `L` for every shipped level
   (after `resolve()`), and `encode(decode(encode(L))) == encode(L)` byte for byte.
3. Caps, rejected on import: bounds each side 4..500 m; `par` 1..600 s; `tol` 0.5..30°;
   `apron` 0..10 m; ≤ 2000 walls, ≤ 2000 cones, ≤ 500 surfaces, name ≤ 60 chars, hint ≤ 200
   chars, run ≤ 36 000 frames (5 min).
4. Non-finite numbers (`nan`, `inf`), unknown keys, unknown prop kinds, unknown surface
   kinds and a wrong header version are all rejected with a one-line reason.
5. `content_hash` covers the **resolved** level, including `rules` and `rig` when present,
   so a change to a prop's default footprint in `lib/props.lua` invalidates hashes.
6. A progress entry whose `content_hash` no longer matches keeps `completed`, and loses
   `best`, `stars` and the ghost.
7. A run's `level` and `content` must both match the level it is offered to; `build` must
   match the running build.

---

## §2 — Semantics (module APIs and contract tables)

### 2.1 `lib/hash.lua`

```lua
function M.sha256(s)            -- hex digest via love.data.hash("sha256", s)
function M.short(hex, n)        -- n hex chars, default 8
function M.canonical(v)         -- stable text dump: sorted keys, %.6f numbers, %q strings
function M.build_hash()         -- canonical(rig + session constants + DT + quantisation)
```

`M.build_hash` reads `rig.TUNE`, `rig.CAR`, `rig.CARAVAN`, `session.DWELL`,
`session.PARK_SPEED`, `session.PARK_HOLD`, `session.STEER_STEPS`, `session.PEDAL_STEPS`,
plus `DT` — the numbers that decide whether an input stream parks. Testable by passing a
mutated copy of the constant table.

### 2.2 `lib/levelcheck.lua`

```lua
function M.errors(level)  -- list of strings; empty when the level is legitimate
```

Moves the space invariants out of `tests/test_levels.lua`, which currently owns them:
spawn clear of walls (both bodies), bay inside bounds, apron clear, discrete props disjoint
(linear props exempt in pairs), props and paint inside bounds, bay on painted ground, unique
name, valid `id`/`series`/`order`. One implementation, called by the test **and** by the
editor's save gate and the importer.

### 2.3 `lib/levelfmt.lua`

```lua
function M.encode(level)        -- text document, authored fields only
function M.decode(text)         -- level|nil, reason
function M.resolve(level)       -- defaults filled from props.footprint (moved here from
                                -- levels.lua's local, so the importer and the editor share it)
function M.to_lua(level)        -- a RAW-shaped Lua literal, for pasting into lib/levels.lua
function M.content_hash(level)  -- hex of canonical(resolved(level))
```

`encode` writes a size only when it differs from the kind's default, so the file stays
readable and the hash is computed on the resolved form. `to_lua` exists because the editor
must be able to feed the campaign: the dev exports a block and pastes it into
`lib/levels.lua`, whose RAW entry shape is the same table.

### 2.4 `lib/run.lua`

```lua
function M.new(level)                     -- { level_id, frames = {} }
function M.record(run, input)             -- one physics step's worth, quantised input
function M.encode(run)                    -- text document
function M.decode(text)                   -- run|nil, reason
function M.replay(level, run)             -- a fresh session advanced to the end
function M.verify(level, run, build)      -- ok, "reason" | final{time,bumps,angle_err}
```

| Call | Contract |
|---|---|
| `record` | Appends one frame; refuses beyond `MAX_FRAMES` (returns unchanged, no raise) |
| `replay` | Stops early once `s.parked`; feeds every frame through `session.update` at `DT` |
| `verify` | Rejects on id/content/build mismatch **before** replaying; then rejects unless the replay ends `parked`; returns the recomputed `final`, never the header's |

### 2.5 `lib/share.lua`

```lua
function M.bundle(level, run, author)     -- share text
function M.code(text)                     -- "TY1:..." one-liner
function M.unpack(text_or_code)           -- { level = ..., run = ..., author = ... }|nil, reason
```

Transport is deliberately not this module's business: `main.lua` decides that the string
goes to the clipboard, a file, or (later) an HTTP call. That is the seam the optional
hosted version plugs into.

### 2.6 `lib/progress.lua` (pure over an injected filesystem)

```lua
function M.open(io)                 -- io = { read(name), write(name, data), remove(name) }
function M.entry(self, id)
function M.record(self, level, s)   -- a parked session: best, stars, ghost flag, hash
function M.save(self)
```

A corrupt or missing index yields an empty store plus a warning — never a raise. The test
suite drives it with an in-memory fake `io`, so corruption, staleness and merges are all
headless.

### 2.7 `lib/menu.lua` (pure model)

```lua
function M.new(shipped, custom, progress)
function M.rows(self)               -- display order: series in data order, then order
function M.move(self, d)            -- wraps
function M.confirm(self)            -- the selected level, or nil on a header row
function M.mark(self, id)           -- { completed, stars, best, ghost, stale }
```

### 2.8 `lib/edit/doc.lua` (pure document + undo)

```lua
function M.new(level)
function M.add(self, kind, x, y)      -- wall/cone/surface by the kind's shape
function M.pick(self, x, y, tol)      -- topmost prop under the cursor
function M.move(self, dx, dy)
function M.rotate(self, ddeg)
function M.resize(self, dw, dh)
function M.remove(self)
function M.set_bay(self, bend)
function M.set_spawn(self, bend)
function M.level(self)                -- resolved copy, safe to hand to a session
```

Undo is **snapshot** based: `snapshot()` returns the encoded document text, the stack keeps
the last 32 (byte-budgeted). Levels are a few KB, so snapshots cost nothing and eliminate a
class of command-pattern bugs. Say it out loud in the module header so nobody "optimises"
it into a command stack later without a reason.

---

## §3 — Contracts

**Purity.** `lib/hash.lua` (the one place that calls `love.data.hash`), `lib/levelfmt.lua`,
`lib/run.lua`, `lib/share.lua`, `lib/progress.lua`, `lib/menu.lua` and `lib/edit/*` contain
no `love.*` call other than that hash call, and no `os.time`/`os.clock`. `lib/rig.lua` and
`lib/session.lua` keep their existing absolute ban — which means the **quantiser lives in
`session`**, not in the recorder.

**Quantisation is structural.** `session.quantise(input)` snaps `steer` to 1/127 and
`throttle`/`brake` to 1/255; `session.update` applies it defensively at the top (it is
idempotent), and `main.lua` records the quantised table it passed in. Live play and replay
therefore consume byte-identical numbers, and "replay matches exactly" stops being a
property you have to defend when someone touches the steering ramp.

**Verification, not cryptography.** The hash prevents *accidental* mismatch (an edited
level, a re-export). It is not a signature: a determined person can forge a level whose
hash they also write into a run file. They gain nothing, because the run is still replayed
through the shipped physics and must actually park. Never describe the hash as anti-cheat
in the UI or the docs.

**No code from outside.** Imported text is parsed by the four hand-written parsers and
validated against the caps in §1.5. Nothing imported is ever `load`ed or `loadstring`ed.
`to_lua` output is the single exception, it is generated by our own encoder, and the only
`load` on it is inside a test.

**Lockstep ghosts.** The ghost advances one step per player step, not on wall-clock time, so
pausing cannot desync it. It replays into its own session object and never touches the
player's.

**Retry is a keypress.** A park or a failure keeps the existing freeze; `R` reloads in one
frame. The menu is one `Esc` away and returns to the same level.

**Invalidation matrix** (what an edit costs the player):

| What changed | Completion | Best time | Stars | Ghost |
|---|---|---|---|---|
| Nothing | kept | kept | kept | kept |
| Level geometry / props / bay / par | kept | dropped | dropped | dropped |
| `lib/rig.lua` or `session` constants | kept | dropped | dropped | dropped (`build` mismatch) |
| Menu `series`/`order` only | kept | kept | kept | kept (not in the hash) |

---

## §4 — Layout contract (per screen, per state)

**Menu (`game.mode == "menu"`), the title screen — there is no separate main menu.**

- Header: `TOW YARD`, and the tab row `Campaign | Custom levels`.
- Campaign: one block per series (`Training`, `Basics`, `Tricky`, …) in data order; each
  block is a grid of cards. A card shows the level name, three star outlines filled by the
  stored grade, and the best time (`--:--` when none). Completed cards carry a tick; a
  selected card is drawn with the bay's green outline.
- Stale cards (level changed) show `completed — level changed` in place of the time, no
  stars, no ghost mark.
- Custom tab: imported levels as cards with a `CUSTOM` tag, plus `Import a code…` as the
  last card when the list is empty. Delete is `X` on a selected card with a confirm row.
- Footer: `Enter open · H ghost · Y import · Esc quit`, device-aware (`A`, `Y`, `B` on a pad).
- Navigation is fully pad-navigable: stick/d-pad moves, `A`/`Enter` opens, `B`/`Esc` backs
  out or quits. A mouse click opens a card, but no interaction requires a mouse.

**Play, in addition to today's HUD:**

- Ghost legend, top-right, only while a ghost is drawn: a 12 px line in the ghost colour,
  the label `BEST 13.21`, and `H` when a second (rival) ghost is loaded.
- Result card gains: `NEW BEST` when the run beat the stored time, the delta
  (`-1.42`), and a footer line naming what is now stored: `ghost saved · Y copy share code`.
- A ghost that failed verification never draws. The card that would offer it says
  `this run was recorded on a different version` and offers `Y` to re-import.

**Editor (`game.mode == "editor"`), dev-first:**

- Left rail: tool list (`Select`, `Solid`, `Knockable`, `Paint`, `Spawn`, `Bay`, `Bounds`),
  the active kind below it, and the numeric fields of the current selection.
- Bottom rail: `grid 0.5 m`, `snap ✓`, the live error list (first three, red), and
  `V verify · P play · S save · O export · Esc menu`.
- Camera: wheel zooms 8..40 px/m around the cursor, middle-drag or space-drag pans. This is
  the first screen in the game with a movable camera; the play camera stays fixed.
- Verify: a `verifying…` panel, then `a line exists (13.4 s, audit floor)` or
  `no line found — this level may need a playtest` in amber, never red: the audit's verdict
  is not a bug report.
- Dirty state: the document title shows `*` in the header; leaving with unsaved changes asks
  once.
- Every error state is text, in the rail, and never a modal.

---

## §5 — Files

```
lib/
  hash.lua          CREATE  sha256 + canonical dump + build hash (one love.data call)
  levelfmt.lua      CREATE  level encode/decode/to_lua + content_hash
  levelcheck.lua    CREATE  space invariants, moved out of the test
  run.lua           CREATE  record / encode / decode / replay / verify
  share.lua         CREATE  bundle + TY1 code + unpack (transport-agnostic)
  progress.lua      CREATE  best/stars/ghost store over an injected io
  menu.lua          CREATE  pure menu model (rows, cursor, marks)
  levels.lua        MODIFY  id/series/order on every level; two new training levels
  session.lua       MODIFY  quantise() + call at the top of update; expose steps
  draw.lua          MODIFY  D.menu, D.ghost, D.editor, result-card additions
  edit/
    doc.lua         CREATE  editable document ops (pure)
    undo.lua        CREATE  snapshot stack (pure)
main.lua            MODIFY  scene machine, menu/editor wiring, run recording, ghost step,
                            clipboard + drag-drop import, --edit flag
tests/
  test_hash.lua     CREATE
  test_levelfmt.lua CREATE
  test_run.lua      CREATE
  test_share.lua    CREATE
  test_progress.lua CREATE
  test_menu.lua     CREATE
  test_edit_doc.lua CREATE
  test_levels.lua   MODIFY  delegate to lib/levelcheck.lua; series/order invariants
  fixtures.lua      MODIFY  deep_copy() for hash tests
  main.lua          MODIFY  add every new module (a new module not listed here runs zero
                            tests and the suite still looks green)
README.md           MODIFY  new commands and the sharing flow
AGENTS.md           MODIFY  format rules, purity exception, "levels are data, runs are proof"
```

---

## §6 — Tasks

Phases 0–2 are specified to executable detail; 3–4 to objective/files/acceptance and get
their own breakdown when reached, because the editor's shape depends on how the format
behaves under real content.

Gate every commit on the runner's own exit code, never on grepped output:

```bash
love tests >/tmp/t.log 2>&1; ec=$?; tail -3 /tmp/t.log; echo "exit=$ec"
```

A new test module must be added to `tests/main.lua` **in the same commit** as its file, and
the passing count must grow by the number of tests written.

### Phase 0 — the format (pure, invisible, no UI change)

#### Task 1: Hashing and the build stamp

**Objective:** one canonical hash function and one build fingerprint, both testable.

**Files:** Create `lib/hash.lua`, `tests/test_hash.lua`; Modify `tests/main.lua`.

**Step 1: failing test**

```lua
local M = { order = { "sha256_matches_a_known_vector", "canonical_is_order_independent",
                      "build_hash_changes_with_a_constant" } }

function M.sha256_matches_a_known_vector()
    H.expect(hash.sha256("abc") ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "sha256 of 'abc' must match the standard vector")
end

function M.canonical_is_order_independent()
    H.expect(hash.canonical({ b = 1, a = { 2, x = 3 } }) ==
             hash.canonical({ a = { x = 3, 2 }, b = 1 }),
             "table construction order must not change the canonical dump")
end

function M.build_hash_changes_with_a_constant()
    local base = hash.build_hash()
    local mutated = hash.build_hash({ session = { PARK_SPEED = 0.06 } })
    H.expect(base ~= mutated, "changing a parking constant must change the build hash")
end
```

**Step 2: run, expect RED** — `MODULE LOAD FAILED: tests.test_hash`.

**Step 3: implement** — `M.sha256 = function(s) return love.data.hash("sha256", s) end`.
`canonical` walks tables with sorted keys, `%.6f` for numbers and `%q` for strings so two
equal levels cannot hash differently. `build_hash(override)` merges `override` over the live
constant tables, dumps them and hashes.

**Step 4: GREEN**, count +3. **Step 5: commit** `feat: content hashing and a build stamp`.

> If `love.data.hash` ever moves, the vector test is what tells you — do not replace it with
> a hand-rolled hash "to be safe": the vectors are the only reason to trust either.

#### Task 2: Level invariants become a library

**Objective:** the editor, the importer and the test suite must ask the same question.

**Files:** Create `lib/levelcheck.lua`; Modify `tests/test_levels.lua` (each spatial test
becomes one line delegating to `levelcheck.errors`).

**Step 1: failing test** — add to `test_levels.lua`:

```lua
function M.levelcheck_rejects_a_bad_level()
    local lvl = levels.get(1)
    local broken = { name = lvl.name, id = lvl.id, series = lvl.series, order = lvl.order,
                     bounds = lvl.bounds, spawn = lvl.spawn, bay = lvl.bay,
                     walls = { { x = lvl.spawn.x, y = lvl.spawn.y, w = 4, h = 4, kind = "car" } },
                     cones = {}, surfaces = {}, par = 10 }
    H.expect(#levelcheck.errors(broken) > 0, "a prop on the spawn must be an error")
end
```

**Step 2: RED** — `levelcheck` is nil.

**Step 3: implement** — move the bodies of `spawn_is_clear`, `bay_apron_is_clear`,
`bay_inside_bounds`, `props_stay_inside_bounds`, `discrete_props_do_not_intersect`,
`paint_stays_inside_bounds`, `the_bay_sits_on_a_painted_surface` and `levels_have_unique_names`
into `M.errors(level)`; each returns a reason string instead of asserting. The tests then
assert `#errors == 0` and keep their existing non-emptiness checks (a level with no props
must still fail — see the vacuous-pass pitfall in AGENTS).

**Step 4: GREEN**, count unchanged except +1. **Step 5: commit** `refactor: level invariants are a library, not a test`.

#### Task 3: Encode a level

**Objective:** every shipped level produces a document that reads like the source data.

**Files:** Create `lib/levelfmt.lua`, `tests/test_levelfmt.lua`; Modify `tests/main.lua`.

**Step 1: failing test**

```lua
function M.every_shipped_level_round_trips()
    for _, lvl in ipairs(levels.ALL) do
        local text = levelfmt.encode(lvl)
        local back, err = levelfmt.decode(text)
        H.expect(back ~= nil, lvl.name .. ": " .. tostring(err))
        H.expect(levelfmt.encode(back) == text, lvl.name .. ": not byte-stable")
    end
end
```

**Step 2: RED**. **Step 3: implement** `encode` (header, `id`/`name`/`hint`/`series`/`order`,
scalars, then props in list order; omit a size equal to `props.footprint`'s default) and a
minimal `decode` sufficient to round-trip. **Step 4: GREEN**. **Step 5: commit**
`feat: levels encode to a portable text document`.

#### Task 4: Decode strictly

**Objective:** nothing a stranger wrote can crash or poison the game.

**Files:** Modify `lib/levelfmt.lua`, `tests/test_levelfmt.lua`.

**Step 1: failing tests** — one per rejection: wrong header (`TOWYARD LEVEL 9`), unknown key
(`wallz`), a level with no `id`, `nan` as a coordinate, 2001 walls, an unknown prop kind, a
`tol` of 0°, an unbalanced quote, a hint over 200 chars. Each asserts `nil` plus a non-empty
reason.

**Step 2: RED**. **Step 3: implement** the field table (key → parser returning a value or
`nil, reason`), the caps, and `footprint`-based kind validation. Numbers are parsed with
`tonumber` and then checked `v == v` and `math.abs(v) < 1e9` — `tonumber("nan")` returns
`nan` in LuaJIT and would otherwise reach `geom` and make every overlap test false.

**Step 4: GREEN**. **Step 5: commit** `feat: strict, capped level parser`.

#### Task 5: Identity and content hash

**Objective:** progress keyed to a stable id, times and ghosts keyed to the content.

**Files:** Modify `lib/levelfmt.lua`, `lib/levels.lua`, `tests/test_levelfmt.lua`,
`tests/test_levels.lua`, `tests/fixtures.lua` (add `F.deep_copy(t)` — a recursive copy;
the fixture file currently has only `field()`, and a shallow copy would mutate the shipped
level under the hash).

**Step 1: failing tests**

```lua
function M.hash_covers_resolved_defaults()
    local lvl = levels.get(1)
    local before = levelfmt.content_hash(lvl)
    local copy = fixtures.deep_copy(lvl)
    copy.walls[1].h = lvl.walls[1].h + 0.01     -- a geometry change
    H.expect(levelfmt.content_hash(copy) ~= before, "a size change must change the hash")

    local same = fixtures.deep_copy(lvl)
    same.series, same.order = "moved", 99        -- menu-only fields
    H.expect(levelfmt.content_hash(same) == before, "re-sorting a level must not invalidate a ghost")
end
```

**Step 2: RED**. **Step 3: implement** `M.content_hash` over `canonical(resolved(level))`
with `series` and `order` stripped first, and add `id`/`series`/`order` to all six levels in
`lib/levels.lua` (training: `straight-back 1`, `angled-bay 2`; basics: `tight-alley 1`,
`fire-side 2`; tricky: `round-the-back 1`, `clean-line 2`).

**Step 4: GREEN**. **Step 5: commit** `feat: stable ids and content hashes for levels`.

#### Task 6: Export a level as a Lua block

**Objective:** the editor must be able to feed the campaign, not just custom levels.

**Files:** Modify `lib/levelfmt.lua`, `tests/test_levelfmt.lua`.

**Step 1: failing test**

```lua
function M.to_lua_produces_a_loadable_table()
    local lvl = levels.get(1)
    local fn = assert(load("return " .. levelfmt.to_lua(lvl)))
    local t = fn()
    H.expect(t.name == lvl.name and #t.walls == #lvl.walls, "exported block must describe the level")
    H.expect(levelfmt.content_hash(levelfmt.resolve(t)) == levelfmt.content_hash(lvl),
             "the block must resolve to the same content")
end
```

**Step 2: RED**. **Step 3: implement** `to_lua` as a RAW-shaped literal (sizes omitted when
default, radians as degrees for readability, `par`/`apron`/`bounds`/`spawn`/`bay` inline).
The `load` here is on our own generated text in a test — imported content is still never
loaded.

**Step 4: GREEN**. **Step 5: commit** `feat: export a level as a pasteable Lua block`.

### Phase 1 — scene machine, menu, progress

#### Task 7: An explicit mode switch

**Objective:** `main.lua` gains `menu`/`play`/`editor` without changing what it does today.

**Files:** Modify `main.lua`.

**Step 1: no test** — mechanical. The gate is the suite plus `--smoke` unchanged.

**Step 2: implement** `game.mode = "play"`; `love.update`/`love.draw`/`love.keypressed`
dispatch on it; play branches are today's bodies moved verbatim into `update_play` /
`draw_play`; `Esc` in play opens the menu instead of quitting (quit lives in the menu).

**Step 3: verify** — `love tests` exit 0 with the same count, `xvfb-run … --smoke` prints
`SMOKE OK`, and the four screenshots are unchanged. **Step 4: commit**
`refactor: main.lua gets an explicit mode switch`.

#### Task 8: The progress store

**Objective:** best time, stars and ghost presence survive a restart, and a corrupt file is
survivable.

**Files:** Create `lib/progress.lua`, `tests/test_progress.lua`; Modify `tests/main.lua`.

**Step 1: failing tests** — four cases, each with the same fake io:

```lua
local function fake_io(files)
    local io = { files = files or {} }
    function io.read(n) return io.files[n] end
    function io.write(n, d) io.files[n] = d end
    function io.remove(n) io.files[n] = nil end
    return io
end

function M.fresh_store_is_empty()      -- no file on disk
function M.corrupt_store_does_not_raise()
    local p = progress.open(fake_io({ ["progress.txt"] = "\0\0garbage" }))
    H.expect(p.entries and next(p.entries) == nil, "garbage must read as an empty store")
end
function M.best_time_only_improves()   -- 13.2 then 14.0 keeps 13.2; stars take the max
function M.edited_level_keeps_completion_loses_time()
    -- record on a level, change its walls, reopen: completed true, best nil, ghost false
end
```

**Step 2: RED**. **Step 3: implement** the parse/serialise of §1.4 and the merge rules of
§1.5.6; `record` writes only when something changed.

**Step 4: GREEN**, count +4. **Step 5: commit** `feat: progress store survives corruption and edits`.

#### Task 9: Wire progress to the filesystem

**Objective:** the store is live, and a park writes it.

**Files:** Modify `main.lua` (a `save_io` table wrapping `love.filesystem`), `tests/test_smoke.lua`.

**Step 1: test** — extend the smoke test's fake io assertion: `save_io.read` returns nil for
a missing file instead of raising, and `write` creates the parent-less path
`love.filesystem.write("progress.txt", …)` succeeds.

**Step 2: implement** — load on `love.load`; in `main.lua`, the frame where `game.s.parked`
first becomes true calls `progress.record(game.progress, game.level, game.s)` and
`progress.save()`. `session` stays unaware of the store (it is the pure core, and `parked`
is a fact, not a side effect). `F5` in play re-reads the store for debugging.

**Step 3: verify** — play level 1, park it, quit, relaunch: the value is still there. This is
the one task that ends with a human check, because `love.filesystem` is the boundary no test
crosses. **Step 4: commit** `feat: park a level and the result is kept`.

#### Task 10: The menu model

**Objective:** rows, cursor and marks, with no graphics in sight.

**Files:** Create `lib/menu.lua`, `tests/test_menu.lua`; Modify `tests/main.lua`.

**Step 1: failing tests** — series order follows data (`Training` before `Basics` before
`Tricky`); moving down from the last row wraps to the first; `move` skips header rows only in
the sense that a header is never *selected* (headers are decoration, so the model returns
levels only); `confirm` returns the level under the cursor; a stale entry's mark is
`{ completed = true, stale = true }`.

**Step 2: RED**. **Step 3: implement** the model over `(shipped, custom, progress)`.
**Step 4: GREEN**, count +5. **Step 5: commit** `feat: menu model with series rows and marks`.

#### Task 11: Series in the data

**Files:** Modify `lib/levels.lua` (already done in Task 5), `tests/test_levels.lua`.

**Step 1: failing test** — every level has `series` and `order`; within a series `order`
values are unique and start at 1; a series' levels are contiguous in `ALL` (the audit and
`Tab` both walk `ALL`, so a scattered series would make "next level" lie).

**Step 2: RED** if Task 5's fields are not yet complete. **Step 3: implement** any missing
fields, reorder `RAW` so series are contiguous. **Step 4: GREEN**. **Step 5: commit**
`data: levels carry a series and an order`.

#### Task 12: Draw the menu

**Files:** Modify `lib/draw.lua` (`D.menu`), `main.lua` (input, mode wiring),
`tests/test_draw.lua` (palette/contract only), `main.lua`'s smoke block.

**Step 1: implement** `D.menu(menu, progress)` per §4: tab row, series blocks, cards with
stars as three outlined triangles, best time in the small font, tick for completed, green
outline for the cursor. Keyboard `W/S/A/D` + `Enter`; pad `dpad`/`A`/`B` through
`input.poll_actions` (add `confirm`, `cancel` edge actions).

**Step 2: smoke frame** — add a frame that switches to `menu` mode and captures
`smoke-menu.png`, and one with a completed card and a stale card: `smoke-menu-progress.png`.

**Step 3: look at the PNGs.** A menu is verified when you have read the pixels: the
selected card is the only green outline, stars fill from the left, no text overlaps a card
border, `--:--` appears on unplayed cards. Then `SMOKE OK`.

**Step 4: commit** `feat: the level select is the title screen`.

#### Task 13: The training series

**Objective:** three levels that teach the mechanic by geometry, per the user's decision.

**Files:** Modify `lib/levels.lua`; Modify `tests/test_levels.lua` if a new invariant is
needed.

**Levels:** `straight-back` (exists) → a new `pull-up` (a 12 m wide, 6 m deep bay off a 20 m
straight, so the lesson is "drive past, stop, reverse in") → `angled-bay` (exists). Hints
state the one idea, not the solution.

**Step 1:** author each as data; **Step 2:** `love . --audit <n>` must exit 0 (a level no line
parks does not ship); **Step 3:** `love tests` invariants pass; **Step 4:** par is written as
audit time × 1.5 and the comment says so, then replaced after a playtest — never scaled;
**Step 5: commit** `data: a training series that teaches by geometry`.

### Phase 2 — runs, ghosts and sharing

#### Task 14: Quantise at the boundary

**Objective:** the number the player's run was recorded with is the number the replay feeds.

**Files:** Modify `lib/session.lua` (`M.STEER_STEPS`, `M.PEDAL_STEPS`, `M.quantise`,
call at the top of `M.update`), `tests/test_session.lua`.

**Step 1: failing tests**

```lua
function M.quantise_is_idempotent()
    local once = session.quantise({ steer = 0.37, throttle = 0.61, brake = 0, handbrake = false })
    local twice = session.quantise(once)
    H.expect(once.steer == twice.steer and once.throttle == twice.throttle,
             "quantising must be idempotent or replay cannot be exact")
end

function M.quantised_input_still_parks_level_1()   -- the existing straight-reverse script,
                                                    -- fed as quantised values, still parks
```

**Step 2: RED**. **Step 3: implement**; keep `input.last_device` through the copy so the HUD
glyph does not flicker.

**Step 4: GREEN**, and `tests/test_rig.lua:fixed_step_determinism` still passes unchanged.
**Step 5: commit** `feat: inputs are quantised where they enter the sim`.

#### Task 15: Record a run

**Files:** Create `lib/run.lua`, `tests/test_run.lua`; Modify `tests/main.lua`, `main.lua`.

**Step 1: failing tests** — recording 300 steps yields 300 frames; a frame holds the
quantised values; `record` beyond `MAX_FRAMES` returns the run unchanged; replaying a run
whose frames were appended after the park stops at the park (the early return in `replay` is
what keeps a paused or post-park frame out of the ghost).

**Step 2: RED**. **Step 3: implement** `M.new`/`M.record`, and in `main.lua`'s step loop:
`run.record(game.run, game.input)` immediately before `session.update`, with
`game.run = run.new(game.level)` in `load_level`.

**Step 4: GREEN**. **Step 5: commit** `feat: record the input stream of an attempt`.

#### Task 16: Serialise a run

**Files:** Modify `lib/run.lua`, `lib/hash.lua`, `tests/test_run.lua`, `main.lua` (the
`love.data` codec pair passed in).

**Step 1: failing tests** — a 3-frame run encodes/decodes to the same quantised values;
truncated `data` is rejected; a header claiming 99 999 frames is rejected by the cap; a
base64 body of the wrong length is rejected; `encode` is byte-stable.

**Step 2: RED**. **Step 3: implement** the 4-byte frame packing with
`love.data.compress`/`love.data.encode` injected as `codec = { compress, decompress, encode,
decode }` so `lib/run.lua` stays pure and the test can pass an identity codec.

**Step 4: GREEN**. **Step 5: commit** `feat: runs serialise to a few kilobytes`.

#### Task 17: Replay is exact

**Objective:** the property everything else rests on, asserted to zero.

**Files:** Modify `lib/run.lua`, `tests/test_run.lua`.

**Step 1: failing test**

```lua
function M.replay_reproduces_the_run_exactly()
    local lvl = levels.get(1)
    local s, run = session.new(lvl), run.new(lvl)
    local script = scripted_drive(s)         -- 900 steps: reverse, steer, straighten, stop
    for i = 1, 900 do
        local inp = session.quantise(script(i))
        run.record(run, inp)
        session.update(s, inp, 1 / 120)
    end
    local again = run.replay(lvl, run.decode(run.encode(run)))
    H.expect(again.rig.x == s.rig.x and again.rig.y == s.rig.y, "x/y must match exactly")
    H.expect(again.rig.th == s.rig.th and again.rig.ph == s.rig.ph, "headings must match exactly")
    H.expect(again.t == s.t, "the clock must match exactly")
end
```

**Step 2: RED**. **Step 3: implement** `M.replay` per §2.4.

**Step 4: GREEN.** If this fails, the quantiser is too coarse or something in the sim
consults state outside the session — **raise the resolution or find the leak; never loosen
the assertion to a tolerance.**

**Step 5: commit** `feat: a recorded run replays bit-identically`.

#### Task 18: Verify a run on import

**Files:** Modify `lib/run.lua`, `tests/test_run.lua`.

**Step 1: failing tests** — a valid run verifies and returns the recomputed `final`; a run
whose `content` does not match is rejected *before* replaying (assert the reason string); a
run that does not park is rejected; a run whose header claims `time 9.00` while the sim
produces 13.21 returns 13.21 (the header is a comment, not a claim).

**Step 2: RED**. **Step 3: implement** `M.verify` per §2.4. **Step 4: GREEN**.
**Step 5: commit** `feat: a shared run is verified by replaying it`.

#### Task 19: Draw the ghost

**Files:** Modify `lib/draw.lua` (`D.ghost`), `main.lua` (a lockstep ghost session, `H`
toggle), `main.lua`'s smoke block.

**Step 1: implement** — default cue is the **trail**: the caravan's rear-corner polyline for
the last 4 s, plus a small dot at the tail, drawn at 60 % alpha in `guide` blue; `H` cycles
`off → trail → rig`. The full ghost rig is a 35 % alpha silhouette only in that third state.
The rival ghost, when one is loaded, draws its trail in a second colour (magenta,
`0.75, 0.45, 0.85`) — the only new palette entry in this plan.

**Step 2: smoke frames** — `smoke-ghost-trail.png` (trail only) and `smoke-ghost-rig.png`
(both ghosts, one in each mode). **Look at them**: the trail must be readable in the 6.8 m
alley and the player's rig must remain the loudest thing on the ground.

**Step 3: commit** `feat: a ghost trail you can follow without confusing it for your rig`.

#### Task 20: Bundles and codes

**Files:** Create `lib/share.lua`, `tests/test_share.lua`; Modify `tests/main.lua`.

**Step 1: failing tests** — a bundle with both sections unpacks to a level and a run whose
hashes agree; a bundle with only a level unpacks with `run == nil`; a `TY1:` code unpacks to
the same table as its text form; a share text with an unknown section marker is rejected; a
code with a bad prefix is rejected with a readable reason.

**Step 2: RED**. **Step 3: implement** `M.bundle`, `M.code` (injected codec again),
`M.unpack`. **Step 4: GREEN**, count +5. **Step 5: commit**
`feat: one paste carries a level and its run`.

#### Task 21: Import and export for real

**Files:** Modify `main.lua` (`love.filedropped`, `love.system.getClipboardText`,
`love.system.setClipboardText`, `love.system.openURL` for the save folder), `lib/levelfmt.lua`
(`save_custom` / `scan_custom` over an injected io), `tests/test_levelfmt.lua`.

**Step 1: failing test** — `scan_custom` over a fake io with one good and one garbage
`.tylevel` returns one level and one warning; saving a level twice overwrites by content
hash, never by name.

**Step 2: implement** — `Y` in the menu / result card copies the bundle code; `Shift+Y`
opens the save folder; a dropped `.towyard` file or a pasted `TY1:` code parses, validates
(`levelcheck` + `props.check`) and lands in `custom/`. Import shows a one-line result card:
`imported "One shot" · 2 runs · verified` or the reason.

**Step 3: human check** — copy a code in level 1's result card, restart the game, paste it
into the menu, play the ghost. That round trip is the whole feature; do it before the
commit. **Step 4: commit** `feat: share a run by code or file and import it back`.

#### Task 22: Best run and ghost on level start

**Files:** Modify `lib/progress.lua` (ghost blob read/write), `main.lua` (load ghost in
`load_level`, save on park, draw `NEW BEST`/delta on the result card), `lib/draw.lua`.

**Step 1: test** — `progress.ghost(level)` returns nil for a stale hash and the decoded run
for a matching one; `record` stores the blob under `ghosts/<content_hash>.tyrun`.

**Step 2: implement** — on park: verify the live run (it is the live sim, so trust it),
store it if `s.t` beats the stored time, reload the ghost. Result card gets the delta line
per §4.

**Step 3: smoke frame** for the result card with `NEW BEST` and a delta, and **look at it**
(a card that shows a delta the clock disagrees with reads as a bug — force the state).
**Step 4: commit** `feat: your best run is your ghost`.

### Phase 3 — the editor, internal

**Objective:** `love . --edit` opens a document editor on level 1 that can produce a level
the audit accepts and the game can play.

**Files:** Create `lib/edit/doc.lua`, `lib/edit/undo.lua`, `tests/test_edit_doc.lua`; Modify
`lib/draw.lua` (`D.editor`), `main.lua` (`--edit`, mouse/wheel/middle-drag, snap).

1. **Task 23** — document ops (`add`, `pick`, `move`, `rotate`, `resize`, `remove`,
   `set_bay`, `set_spawn`, `level`), each driven by a headless test; selection is
   `(list, index)` so a wall and a cone cannot be confused. Acceptance: 12 tests, exit 0.
2. **Task 24** — snapshot undo: `undo.push(doc)` before every mutating op, `undo.back()`
   restores, 32-deep, byte-budgeted; test that 40 edits leave the boundary state restorable
   and that `undo` past the start is a no-op.
3. **Task 25** — `D.editor`: left rail tools, bottom rail with the live `levelcheck` errors,
   camera zoom around the cursor, grid at 0.5 m with a snap toggle, drag to move, `[`/`]` to
   rotate, `+`/`-` to resize. Smoke frame `smoke-editor.png`, looked at.
4. **Task 26** — the loop: `V` verify (`audit.solve(level, { grid = audit.QUICK_GRID })`,
   ~1.7 s; draw a panel and call `love.graphics.present()` before the blocking call so the
   panel is actually on screen), `P` play the document (a session on `doc:level()`, `Esc`
   returns with the document intact), `S` save to `custom/dev-<hash>.tylevel`, `O` export the
   Lua block to the clipboard and to `export/<id>.lua`.

**Acceptance for Phase 3:** author one new level entirely in the editor, export it, paste the
block into `lib/levels.lua`, run `love tests` and `love . --audit N`, and playtest it. If
that loop is painful, the editor is not finished — the loop is the product.

### Phase 4 — the editor, player-facing

**Objective:** a player with no shell can make, verify, play, export and import a level.

- **Task 27** — the Custom tab per §4: browse, open, delete with confirm, share, import.
- **Task 28** — polish: tool palette labels, an inline error list capped at three, snapping
  toggle, pad navigation for the menus only (the editor is mouse+keyboard and says so on
  screen), and a first-run hint that custom levels live in the save folder.
- **Task 29** — docs: README (new commands, the sharing flow as three lines a player can
  follow), AGENTS.md (the format rules, the purity exception for `love.data.hash`, "levels
  are data and runs are proof"), and a cross-reference from `enjoyment-roadmap.md` §B/E to
  this plan.

**Phase 4 acceptance:** someone who has never seen the code imports a code a friend sent,
plays the ghost, makes their own level, verifies it, exports it, and the friend imports it.
That is the feature; anything short of it is a demo.

---

## §7 — Validation checklist

- [ ] `love tests` exits 0 and the count equals the number of tests written (not "looks green").
- [ ] `xvfb-run -a -s "-screen 0 1280x720x24" love . --smoke` prints `SMOKE OK`, and these
      PNGs have each been looked at: menu, menu with progress, ghost trail, ghost rig,
      result card with `NEW BEST`, editor.
- [ ] Every shipped level has a unique `id`, a `series` and an `order`, and each series is
      contiguous in `levels.ALL`.
- [ ] `decode(encode(L))` round-trips for every shipped level and `encode` is byte-stable.
- [ ] A level document with an unknown key, an unknown kind, a `nan`, or 2001 props is
      rejected with a reason, not a crash.
- [ ] No imported string is ever passed to `load` or `loadstring` outside `tests/`.
- [ ] `session.quantise` is idempotent, and a run recorded live replays to an **exactly**
      equal pose and clock (`==`, not `1e-6`).
- [ ] A run with a different `content` or `build` is rejected before it is drawn.
- [ ] A run that does not park on this build is never drawn as a ghost, and says why.
- [ ] A corrupted `progress.txt` reads as an empty store; the game still starts.
- [ ] Editing a level's geometry drops its time, stars and ghost but keeps "completed".
- [ ] Re-sorting a level into another series keeps its time and ghost.
- [ ] Every new level (shipped or custom, promoted to the campaign) has an `--audit` line.
- [ ] `lib/rig.lua` and `lib/session.lua` contain no `love.` call, no RNG, no `os.time`.
- [ ] Every module this plan creates, except `lib/hash.lua`, is `love.*`-free; `hash.lua`
      contains exactly one `love.data.hash` call.

---

## §8 — Risks and trade-offs

**The editor is the other half of the program.** Everything else here is a thin layer on a
deterministic sim and pure data; the editor needs a document model, gestures, snapping, undo,
a movable camera (the first in the game) and validation UI, on top of 600 lines of
immediate-mode drawing with no widget toolkit. Mitigation: it is Phase 3 and it is a dev
tool first, so a half-built editor costs the player nothing. The Phase 3 acceptance test is
the loop (author → export → tests → audit → play), not a screenshot.

**A file format is forever.** Level documents and run documents will outlive the code that
made them, and a shared file outlives the build it was recorded on. Mitigation: version
numbers in every header, a strict reader per version, and `build` in the run header so a
stale ghost is *explained* rather than silently wrong. Do not add a field to v1 — bump to
v2 and accept both.

**Run verification costs the only thing that cannot be faked, and it can still lie about
effort.** A replay proves the line parks; it does not prove a human drove it (a bot could
generate the input stream). That is fine for a game with no leaderboard; if a hosted board
ever arrives, it inherits this limitation and needs a server-side replay, not a signature.

**Progress invalidation will annoy someone.** A player who 3-starred a level you then fixed
loses the stars. Mitigation: the "changed" card explains itself in one line, and stars are
never silently preserved against new geometry (a stale 3-star is a lie the menu would tell
forever). Re-audit after any level edit; a fixed level's par is a new number.

**Snapshots instead of a command stack.** Undo by encoded-document snapshots is memory
wasteful and cannot be undone "smartly" (no coalescing of a drag). At a few KB per level and
32 steps it is under 200 KB; the alternative is a command pattern whose bugs cost more than
the memory. If the editor ever needs coalescing, add it on top of snapshots.

**Sharing is a clipboard, not a store.** A code sent in a chat is lost the moment the chat
scrolls. Mitigation: import writes a file into `custom/` immediately, so the level persists
even if the code doesn't; the "open save folder" button makes the files findable.

**Scope creep, again.** The fence is §9. The failure mode here is not a wrong feature but a
right one built twice: two progress stores, two level loaders, two ghosts (the roadmap's
`lib/ghost.lua` and this plan's `lib/run.lua`). This plan supersedes roadmap §B and §E, and
the first commit of Phase 0 should say so in the roadmap file.

---

## §9 — Explicitly out of scope

- Any server, account, upload, matchmaking or hosted leaderboard in v1 (the transport seam
  in `lib/share.lua` is the only accommodation made).
- Scripted tutorials: gated inputs, step detection, checkpoints, voice-over style prompts.
- Procedurally generated levels.
- Multiplayer in any form; asynchronous ghosts are the social feature.
- Editing the physics from the editor (rig variants stay authored data).
- A curated browser of other people's levels — importing is by code or file, deliberately.
- Web export via love.js; this stays a desktop LÖVE game.
- Level thumbnails/renders in the menu; the cards are text and stars.
