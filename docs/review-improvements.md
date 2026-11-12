# Tow Yard — review findings: improvement ideas

A read-only review of the whole codebase on 2026-11-12 against commit `ebee817`.

**Every number below was measured on this machine**, not estimated — camera scale,
response times, par ratios, window fill, prop counts. Where a claim is a judgement
rather than a measurement, it says so.

This document is the *design* half of the review. The *defect* half is
[`review-bugs.md`](review-bugs.md), and several items here depend on fixes there —
those are marked **[blocked by]**.

The house style is the existing `love2d-games` skill's ordering: **decision layer
first, then ghost replay, then variety along existing constants, then sound and
juice, then the meta layer.** The game's own plan
(`.hermes/plans/enjoyment-roadmap.md`) already locks this direction, so this
document is mostly about *sequencing* it against the bugs and about the presentation
work, which the roadmap does not cover.

---

## The diagnosis in one paragraph

Tow Yard is **execution-only**: geometry → manoeuvre → time. Every level asks the
same question ("can you reverse a trailer into this slot?") and the answer is always
"yes, eventually, if you are patient". There is no decision to make *before* you
touch the controls, and no reason to replay a level other than "I was faster". The
mechanic is genuinely good — reversing a trailer is a hard, learnable control
problem — but it is a **skill ceiling with no floor to raise**. The retention lever
the skill names ("ghost replay from the deterministic sim") is *already implemented*
and barely used; the ghost is the best thing in the game and the HUD barely mentions
it.

---

## Tier 1 — Feel and readability

Cheap, high-impact, no new systems. Do these before anything else.

### I1 — Cap the forward speed

**`lib/rig.lua:40` — `vmax = 11.0` m/s = 40 km/h.**

The rig is 10 m long (car 3.4 m + drawbar 1.15 m + caravan 4.6 m), so at full speed
it covers its own length in **0.9 s**. The narrowest corridor in the game is
**5.6 m** (level 6's gate). Forward motion is meant to be the "stable, easy" half of
the game — the half where the caravan straightens itself — and at 40 km/h it is a
hair-trigger that punishes you for the thing you are supposed to be doing well.

**Recommendation: drop `vmax` to 4–5 m/s.** This costs nothing in the physics, does
not touch the reverse (which is where the game lives), and removes a whole class of
"I clipped a cone because the thing lurched".

The skill's warning applies here: *"Never answer 'too slow' by raising a speed cap
that is also the difficulty dial."* Lowering `vmax` does not shorten the reverse
manoeuvre at all — it only makes the *forward* half calmer.

### I2 — Frame the world, or crop the camera to it

The yard is **60×40 m (3:2)** and the window is **1280×720 (16:9)**, so the world
fills only **71% of the window width** — 184 px of dead black on each side, plus
56 px top and bottom:

```
scale 15.20 px/m -> world 912 x 608 px in a 1280 x 720 window
black bars: left 184 px, right 184 px, top 56, bottom 56
```

Right now that black reads as an unfinished viewport rather than a deliberate frame.
Two options:

- **Letterbox deliberately** — draw a panel border and a subtle vignette around the
  world rectangle, so the black reads as a frame. Cheap, and it keeps the whole yard
  visible.
- **Crop** — zoom in so the yard fills more of the window, and let the camera follow
  the rig when it is near an edge. Better looking, but it needs the camera work that
  B3 (the escape bug) also needs, so do them together.

Either way, the current state is the worst of the two.

### I3 — Straighten the HUD's right edge

The timer, the gear line and the par line all end at different x positions, so the
top-right corner never resolves:

```
timer   "0:00.00"    ends at x=1262
gear    "N 0 km/h"   ends at x=1194
par     "par 22s  bumps 0"  ends at x=1250
```

Right-align all three to one column (`lib/draw.lua:581`, `:587`, `:589` currently use
three different hardcoded offsets: `W - 24 - width`, `W - 24 - 130`, `W - 24 - 150`).

### I4 — Tell the player the tolerance in metres, not degrees

The card prints `angle 1.2 deg` and the HUD prints `articulation 0 deg`. Neither
tells the player what they need to know: **how far off the centre they are.**

A 6° bay tolerance on a 4.6 m caravan is **0.48 m of lateral error**; a 5° tolerance
on level 7 is 0.40 m. These are the numbers a player can act on.

**Recommendation:** the result card should say `off centre: 0.4 m` rather than
`angle 1.2 deg`, and the bay marker could draw the tolerance as a visible band
around the slot.

### I5 — Make the guide arc's discoverability real

The arc ships **off**, which is the right call (it hands the manoeuvre away). But the
only mention of it is a `G guide off` token in the hint line. The player has to
guess that `G` is a thing worth pressing.

The skill's rule: *"a toggle nobody has a reason to press is a feature nobody
finds."* **Recommendation:** on the very first level, show the hint `G — show where
the caravan will go` in the level's `hint` line, then retire it once the player has
toggled it once. This is one field of data, not a system.

### I6 — Make the `H` ghost-mode cycle discoverable

`H` cycles rig / trail / off (`main.lua:1626`) and is **not in the on-screen hint
line** (`lib/draw.lua:630`). The same rule applies as I5: a feature nobody can find
is not shipped. Add it to the hint.

---

## Tier 2 — The decision layer (the big one)

**This is the single highest-payoff change in the document.** The game is a
precision reversing game whose whole identity is "a game about the trailer, not a
driving game with trailers in it" (the roadmap's own §0). A precision game earns
replayability through *precision targets*, not through more time trials.

The roadmap already specifies this in detail: `lib/rules.lua`, `level.rules` in
`lib/levels.lua`, hard-fail with a stated reason, at most two rules per level early,
and the presentation contract in §4. **That plan is sound and this review does not
change it.** What this review adds is the *sequencing* and three specific
observations the plan does not cover.

### I7 — Ship the decision layer only after the audit can certify a level

**[blocked by B2]**

The roadmap's Task A7 says *"Author six levels around the rules"*, with par set
*"after a playtest, never guessed"*. But the audit — the only cheap evidence that a
level is winnable — **cannot see any level whose bay is off-axis** (B2), and it
reports "NO LINE" for levels that are trivially parkable. A rule level is *more*
likely to need a non-trivial approach than a plain one, so the blind spot bites
harder exactly where the plan needs it.

**Recommendation:** land B2 (the goal-pose audit) before Task A7, and treat the
audit's verdict on any new rule level as meaningful only after it passes.

### I8 — The rule that would pay off most is the one the game already half-has

The cone penalty is a **time** penalty (+2 s). The wall/jackknife penalty is a
**void**. There is no rule that says *"on this level, nothing may be touched"* —
the thing the skill calls *"a hard fail with a stated reason"*, and the thing a
"Clean line" level would actually want.

The shipped level named "Clean line" has no clean-line rule; it has five knockables
and a hint asking you to thread them. A rule makes that a puzzle instead of a
request.

**Recommendation:** `cones_must_stand` and `no_wall_contact` (the roadmap's A4) are
the highest-value first rules, because the store already has the machinery to detect
both events and price them.

### I9 — Make the rules visible *before* the first input, and make failure legible

The skill is emphatic: *"A rule the player cannot see is a bug, not a challenge"*
and *"Prefer hard fail with a stated reason and instant retry over a silent grade
penalty."* The roadmap's §4 already specifies a rules strip and a failure card
reusing the result card's shape. **Add to that:** the failure reason should name the
*rule* and the *budget* ("too many gear changes — 2 of 1 used"), not just the rule.
A player who loses to a rule they had not internalised needs the reason and the
number on screen, immediately, with a sub-second retry.

### I10 — Separate the star axes (cleanliness from speed)

**[blocked by B13]**

Today the star rating has one axis with an `or` in it: a bump only ever costs the
third star, and a clean but slow run gets the same two stars as a fast dirty one
(B13). Once the two axes are separate, the star rule can state what it means:
"3 pips = clean and inside par · 2 = clean or quick · 1 = parked". The README
already promises this shape; the code does not deliver it.

### I11 — The ghost is implemented and underused

The ghost is the biggest retention lever the skill names, and it is **already
built**: recording, quantised serialisation, replay, content-hash verification, a
trail mode and a rig mode. But:

- It is invisible on the first level a player sees (no stored ghost).
- Its mode toggle is undocumented (I6).
- The result card shows a delta (`+1.30 s`) but never *where* the ghost was faster.
- **[blocked by B1]** a ghost with a pre-roll is misaligned by up to 3.6 m, which
  makes it look broken rather than informative.

**Recommendation:** once B1 is fixed, add the ghost's position delta to the card —
"you were 4 m behind at the gate" — which is the thing that turns a time delta into
a lesson. The trail mode (`H`) already computes the line; it needs one more number.

---

## Tier 3 — Content and variety

### I12 — Seven levels of the same geography

Every shipped level is **60×40 m**, every spawn is on the right edge facing −x, and
every bay is on the left:

```
spawn x,y : 46,20 | 52,20 | 49,10 | 50,20 | 50,20 | 52,20 | 52,20
bay x,y   : 22,20 | 16,22 | 23,24 | 14,20 | 18,22 | 12,20 | 14,20
bounds    : 60x40 × 7
```

The player learns one layout and plays it seven times with different scenery. The
variety axis the skill recommends — *"the same model, different constants"* — is
currently **unused**: the only thing that varies is the distance from spawn to bay
(24–40 m) and the hedge geometry.

**Recommendation: four new levels that change the *geometry*, not the dressing.**
The skill's warning is the design rule here: *"Props-first authoring yields pretty
levels that play exactly like the bare ones."* So author from manoeuvre archetypes:

1. **A bay you must approach from the far side** — the rig must pass the bay and
   reverse back to it. This is a different *plan*, not a longer one.
2. **A spawn already past the gate** — the rig starts committed, and the first move
   is a recovery.
3. **A bay you reverse *through*** — the slot's far end is open, so the rig can
   overshoot and come back.
4. **A narrow yard** — the same geometry at 45 m wide instead of 60, so the same
   manoeuvre has a smaller margin.

### I13 — Close the yard with real edges

**[blocked by B3]**

The bounds rectangle is a camera frame, not a fence, so every level has an open edge
the player can drive off (B3). Whatever the new levels are, they need the same
treatment: a hedge run, a building line, or a water edge that reads as "the site
ends here". This also improves I2 — a yard with visible edges has a visible frame.

### I14 — One level that needs a three-point turn

**[blocked by B2]**

"Round the back" already gestures at this (a 5.6 m gate the rig must line up for).
A level that *requires* a three-point turn would be the clearest expression of the
game's identity — but the audit's controller cannot do one, so it would report
NO LINE forever. This is the sharpest example of why B2 is a content blocker and not
just a tooling annoyance.

---

## Tier 4 — Presentation

### I15 — Unify the vehicle art

The screen currently has **three visual languages**:

| Thing | How it is drawn |
|---|---|
| The player's rig | rounded vector car, a window, tyres, headlights |
| Parked props (`car`, `rv`, `caravan`) | flat blocks with speckled wheel dots |
| Trailers (`rv`, `caravan`) | grey bars with darker end caps |

A parked motorhome and the player's rig do not look like the same world. The skill's
rule — *"Make the theme recede so the mechanic stays legible"* — cuts the other way
here: the *theme* is fine, but the player's own vehicle should be the only thing
drawn in the "real" style, and the props should share **one** simplified language
with each other.

**Recommendation:** pick one prop language (say: a body, a darker roof, two wheels,
no outline) and apply it to every prop kind. The player's rig keeps its detail.

### I16 — Give hazards a silhouette, not just a colour

At the game's real scale of **15.20 px/m**:

| Prop | Radius | Pixels |
|---|---|---|
| traffic cone | 0.35 m | ~5 px |
| camp chair | 0.50 m | ~8 px |
| fire pit | 0.55 m | ~8 px |
| beach umbrella | 1.10 m | ~17 px |

A 5 px cone is at the edge of legibility, and the skill says outright: *"Small
knockables stay ambiguous at scale no matter how they are drawn."* The current
treatment relies on colour alone (`props.lua`'s `loud` flag), which works for the
fire pit but not for the cone.

**Recommendation:** give each hazard a distinct *shape* that survives at 5 px — a
triangle for a cone, a ring for a fire pit, a square for a chair — plus a bright
rim. The colour stays; the silhouette is what makes it findable at 15 px/m.

### I17 — The result card: add par, drop the duplicate, speak in metres

The card currently shows the time, the delta, the cones, the angle and the record.
The **par is missing**, and the time is printed twice (HUD and card).

**Recommendation:**
- Add `par 0:26.00` to the card, so the delta has something to be a delta *from*.
- Replace `angle 1.2 deg` with `off centre 0.4 m` (I4).
- Report the star rule in words next to the pips — three pips with no legend is the
  least readable element on the screen.

### I18 — The `N` / `D` / `R` gear glyph is ambiguous

The HUD prints `N 0 km/h`. `N` reads as a compass heading, and the rig is drawn
horizontally, so "N" is nonsense — it means *neutral*. A player who takes it for a
compass gets a second, wrong idea about which way they are facing.

**Recommendation:** `—` / `D` / `R`, or label it `gear N`.

### I19 — Level naming and hints do not promise a difficulty curve

The three series are `training` / `basics` / `tricky`, but the par times are
scattered (22, 30, 30, 26, 30, 32, 30) and the difficulty does not track the series:
"Tight alley" (basics) has the *tightest* par-to-audit ratio in the game (1.25 — it
gives away 3 stars for a machine line), while "Straight back" (training) has the
loosest (1.66).

**Recommendation:** once B2 is fixed and every par is recomputed from the audit
(B12), order the campaign so the par *ratio* is monotonic. A player should feel the
series tighten.

---

## What not to do

The roadmap's §9 fence is correct and this review does not argue with it. In
particular, none of these ideas require: an open world, a delivery map, traffic, a
deeper physics sim (suspension, tyre slip, weight transfer), procedural levels,
multiplayer, or mobile/web export.

The one thing to resist is **adding levels before the audit can certify them**
(I7, I14). Four new levels authored against a broken instrument is four levels that
need re-auditing, not four levels that need playing.

---

## Sequencing

| # | Item | Depends on | Why here |
|---|---|---|---|
| 1 | B1 ghost desync | — | The ghost is the retention hook; a 3.6 m desync makes it look broken |
| 2 | B2 audit goal-pose | — | Unblocks level 3, the in-app Verify, and every new level |
| 3 | B3 bounds as collision | — | A player can drive into the void |
| 4 | B4 damaged-park completion | — | The player parked and the game says they didn't |
| 5 | B5 gamepad overrides keyboard | — | A drifting pad steers the car on its own |
| 6 | I1 forward speed cap | — | One constant, the biggest single feel win |
| 7 | B6–B15 the remaining bugs | B2 | Cheap once the audit is trustworthy |
| 8 | I2–I6 feel and readability | — | Cheap, no new systems |
| 9 | I15–I18 presentation | — | No dependencies; can run in parallel |
| 10 | **Decision layer** (roadmap Milestone A) | B2, B7 | The big retention lever |
| 11 | **Ghost replay polish** (I11) | B1 | Already built; needs surfacing, not building |
| 12 | I12–I14 new levels | B2, B3 | Only after the audit can certify them |
| 13 | Rig variety, sound, meta layer | roadmap Milestones C–E | Last; each shifts every par |

**Do not** start the decision layer's content work (roadmap Task A7) before B2
lands. The rules are what make a level interesting, and a level the audit cannot
certify is a level whose fairness is a guess.
