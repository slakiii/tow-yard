# Tow Yard — design plan

Status: playable skeleton (1 of 3 levels verified end-to-end, 39 headless tests,
render smoke). Next step is a human playtest before any more levels are authored.

## 1. The pitch

> You are towing a caravan, and every level ends with a reverse maneuver you have
> to set up before you arrive.

The driving is travel. The **reversing is the game**. Every design decision below
follows from that one sentence — if a proposal makes the forward driving more
interesting and the reverse less, it is the wrong proposal.

## 2. Why the mechanic works

A caravan on a drawbar is a first-order trailer. Forward motion is a stable
equilibrium, reverse motion is an unstable one — same math, opposite sign. The
player does not have to be told the rule; they feel it within ten seconds and
then spend the game mastering it.

Counter-steer falls out of the model: **steering the wheel LEFT while reversing
throws the caravan's tail RIGHT** (measured: 8° of lock held for 2 s at 1.2 m/s
moves the tail ~0.6 m). The wheel points opposite to where the caravan goes.
That is the one non-obvious thing a real driver has to learn, and it is a gift
from the physics rather than a mechanic to invent.

Verified numbers for a 4.2 m car + 4.6 m caravan (2.5 m wheelbase, 30° lock,
3.6 m drawbar), all from the model in `lib/rig.lua`:

| Quantity | Value | Design consequence |
|---|---|---|
| Min turn radius (car) | 4.33 m | Corners need ≥ 5 m clearance |
| Swept corridor, 90° bend | 4.8–5.2 m | Anything tighter is a hard level |
| Caravan wheels cut inside the car's path | ~1.9 m at full lock | Inner corners are the hazard |
| Steady articulation, full lock forward | 56° | Holding full lock is already dangerous |
| Jackknife (bodies touch) | 66–72° | ~10° of margin from full-lock cornering |
| Reverse divergence constant τ | drawbar / \|v\| = 2.4 s at 1.5 m/s | Reverse speed IS the difficulty dial |
| 2° error → 20° / 45° hands-off | 5.5 s / 7.6 s | ~5 s reaction budget |

Two levers fall straight out of the table: **reverse speed cap** (reaction time)
and **drawbar length** (τ) — a longer caravan is *easier* to reverse, which is a
counterintuitive and useful progression knob.

## 3. Model

```
thd = v * tan(steer) / wheelbase                        -- car heading rate
phd = (v / drawbar) * sin(th - ph)                      -- trailer follows
    + (coupling / drawbar) * thd * cos(th - ph)         -- hitch-offset offtracking
```

- `coupling = -1.15` (0.35 m behind the rear bumper). Putting it on the rear axle
  is geometrically impossible at large articulation — the coupling ends up
  inside the car body — and it shifts the jackknife angle by tens of degrees.
- Caravan collision shape is a **tapered polygon** (narrow drawbar → full-width
  box). A full-width rectangle from the coupling reports a collision at ~25°,
  which makes the game unplayable. Guarded by a test.
- Fixed timestep 1/120 with an accumulator; `dt` clamped at 1/30.
- One pedal axis (`-1..1`), not separate throttle/brake: the direction decides
  whether it accelerates or brakes, which keeps the rig from ever being in two
  gears at once.

## 4. Controls

One normalised input (`steer`, `throttle`, `brake`, `handbrake`) written by
`lib/input.lua`; both devices go through the same rate-limited steering model,
so the pad only supplies finer targets, not different physics.

| Gamepad | Keyboard | Action |
|---|---|---|
| Left stick X | `A`/`D`, arrows | steering target (deadzone 0.12, expo 1.4) |
| `RT` | `W`/`↑` | forward |
| `LT` | `S`/`↓` | brake, then reverse after a 0.2 s dwell at a standstill |
| `A` | `Space` | handbrake |
| `B` | `R` | reset level |
| `Y` | `G` | toggle guide arc |
| `Start` | `Esc` | pause / quit |

Deliberate choices:

- **Rate-limited steering** (0.26 s to full lock at speed, ~0.58 s from rest)
  gives the wheels weight and turns a 50 ms key tap into ~3° of lock.
- **Steering rate scales with speed**, which is the single thing that makes
  keyboard reversing viable.
- **Gear dwell** prevents "I meant to brake and now I'm reversing into a fence".
- **Rumble reports articulation** from 45° to the 72° limit. Real drivers feel
  the trailer through the seat; this is the only channel that approximates it,
  and it is the strongest reason to play with a pad.
- **The guide arc** (predicted caravan path, 10 s horizon) is the assist switch.
  On = learnable, off = hard mode.

## 5. Level design rules

- Fixed camera, whole yard visible (~60×40 m). A follow-cam makes reversing
  unreadable.
- A bay has a position tolerance (all caravan corners inside) and an **angle
  tolerance** (5–7°); angle is what makes it a parking game.
- Parking requires the rig to be **stopped** for 0.25 s — no drive-by wins.
- Corridors ≥ 5 m unless the level is meant to be tight; put obstacles on the
  *inside* of corners, where the caravan's wheels cut.
- `apron` (default 2 m) is the clearance a level must leave around its bay; a
  test rejects data that violates it, so "unwinnable by typo" cannot ship.

## 6. Levels shipped

1. **Straight back** — reverse 20 m down a lane. Verified end-to-end by a
   scripted replay test: 39 tests pass, the level parks itself when driven.
2. **Angled bay** — a 90° bay; forces an approach angle.
3. **Tight alley** — 6.8 m alley, lower apron, tighter angle tolerance.

Levels 2 and 3 are geometry placeholders: the data invariants pass and the spawn
is clear, but **no scripted replay proves them yet**. Per-level replays are the
next test to write, and par times must come from playtests, not arithmetic.

## 7. Roadmap

**Now (playtest this first)**
- Feel check: is the crawl-speed steering governor (0.58 s from rest) sluggish?
  If so, floor the scale at ~0.7 → 0.37 s.
- Check the guide arc reads as "where the caravan will go", not decoration.
- Check whether the handbrake is exploitable as a free halt.

**Next**
- Scripted replay per level (the winnability harness) + par times from playtests.
- 5 more levels: S-curve gates, parallel park between caravans, forced 3-point
  turn, long-caravan/short-car variant, time attack on the parallel park.
- Level select screen, best times persisted to `love.filesystem`.
- Sound: engine, reverse beeper, cone hit, park chime.

**Later**
- Caravan sway/tipping: a cheap scalar driven by lateral acceleration × speed.
  It is fake physics bolted onto real physics — only worth adding once the core
  feels good.
- Unhitching at the end (park the caravan, then the car) as a second mechanic.
- Remappable controls UI (the mapping is already data in `lib/input.lua`).

## 8. Open questions

1. Core loop: reversing puzzle (current) vs. delivery drive across a map?
2. Does the caravan ever detach? One extra step, one whole extra mechanic.
3. Guide arc default: on for everyone, or only in an easy mode?
4. Target: local LÖVE build now, itch.io web later? love.js rules out FFI and
   shared-library modules but this project uses neither.

## 9. Verification status

- `love tests` → 39 passed, exit 0.
- `love . --smoke` under xvfb → renders scene, result card and debug overlay,
  prints `SMOKE OK`, exit 0; screenshots in the LÖVE save directory
  (`~/.local/share/love/tow-yard/`).
- Physical numbers cross-checked against an independent float64 integration of
  the same equations before any of it was written to Lua.
- **Not** verified: actual driving feel. That needs a human at the keyboard.
