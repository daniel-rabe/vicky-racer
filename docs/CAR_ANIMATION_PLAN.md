# Vicky Racer — Plan: animated cars

Status: **Phase 20a (rolling tread) and 20b (steering front wheels) are built**, and so is the
body lean from §5 — §3, §4 and §5 now describe what was built. The other extras in §5 are still
proposals. Nothing here changes handling; it is all
drawing.

## 1. What we have today

**The art.** Every car is one flat PNG, 128 × 72 px, seen from straight above, facing +X:
12 originals in `art/cars/setups/<car>.png` and 60 recolours in
`art/cars/paint/<car>_<colour>.png` (12 cars × blue, green, pink, purple, yellow), plus the four
old `art/cars/car_<colour>.png`. The wheels are **baked into the body**: four dark tyres poking out
above and below the body, front pair on the right. The rocket's exhaust flames are baked in too.

Two facts about the art decide the approach:

- **The wheels are seen from above.** A top-down tyre does not visibly turn round its axle the way
  a side-view wheel does. What reads as "rolling" from above is the **tread sliding past**, plus
  the **front wheels turning** when steering. Rotating a wheel sprite round its centre would look
  like steering, not rolling.
- **The recolours are not pixel-identical.** The paints are Kontext edits of the original, and
  their silhouettes differ by a few pixels (alpha masks of `kart_blue` vs `kart_pink` differ inside
  a box of about 80 × 70 px). So wheel positions must be found **per image** — 76 images, not 12.

**The rendering.** All drivable cars are `actors/car/car.tscn`: a `CharacterBody2D` (`car.gd`)
with one `Sprite2D` child named `Body`, whose texture comes from `Car.body_texture`, set from the
setup (`DriftSetup.body`) or from `Paint.body(setup, colour)`. That one scene is used by the race
(`game/managers/racer_spawner.gd`), the town and its traffic (`game/screens/town.gd`), the title
screen (`ui/title/title_screen.gd`) and the tests. Ghosts are separate: `actors/ghost/ghost_car.gd`
is a plain `Sprite2D` replaying a recorded lap. The garage, podium and standings show static
pictures and need no animation. Effects (`car_effects.gd`) already generate their textures in code
and already flash `Body.self_modulate` for the car wash; skid marks and tyre smoke use a hard-coded
rear axle at `Vector2(-40, 0)`.

## 2. The options

| Approach | How it works | Art cost | Verdict |
| --- | --- | --- | --- |
| **A. Frame animation** | 3–4 frames per car with the tread shifted, swapped by speed (`AnimatedSprite2D` or an atlas) | 76 × 4 = 304 images; Kontext/FLUX will not keep frames consistent, so they would flicker | **No.** Too much generated art for the effect, and a nightmare to keep in sync with paints. |
| **B. Separate wheel sprites** | Cut the tyres out of each body, draw them as child `Sprite2D`s; rotate the front pair for steering, scroll/swap them for rolling | A tool pass over all 76 bodies (erase the tyres, export wheel PNGs) plus a small hand fix per car | **Later, for steering only.** It is the only way to turn the front wheels convincingly, but it touches every body image. |
| **C. Shader on the baked wheels** | A `canvas_item` shader on `Body` draws moving tread lines over the tyre pixels, inside four wheel rectangles per texture; the car feeds it how far it has rolled | No new art. One generated data file of wheel rectangles, checked once by eye | **Yes — do this first.** Cheap, works with every existing paint, and new cars only need their rectangles. |
| **D. Node rotation / transforms** | Rotate, squash or tilt the `Body` sprite itself | None | **Yes, as extras** (lean and bounce, §5) — not for wheels. |

**Recommendation: C now, B only if steering front wheels turn out to be wanted, D as small
extras.** The plan below is phased so each phase ships on its own.

## 3. Phase 20a — Rolling tread (shader)

### 3.1 Wheel rectangles

`tools/comfy/wheel_rects.py` finds the four tyres in every car body and writes them into a
generated script, `game/configs/car_wheels.gd` (a script rather than JSON, so the export takes it
along with no extra filter):

```gdscript
const BODIES := {
	"setups/kart.png": [Rect2i(32, 3, 23, 9), Rect2i(81, 4, 23, 16), Rect2i(32, 60, 23, 9), Rect2i(81, 53, 23, 15)],
	...
}
```

Per body: rear left, front left, rear right, front right, in texture pixels; "left" is the top
of the image (the car's left when it faces +X). `CarWheels.of(texture)` looks a body up.

Detection: tyre pixels are opaque, dark and grey. The tyres are the outermost dark things above
and below the body, so their columns come from the rows nearest the top and bottom edges (moving
inwards until two tyres are found: the Dragon's wings keep its tyres a few rows in), with gaps
of a hubcap's width bridged; each rectangle then grows inwards while its rows are mostly tyre,
and the two tyres of an axle share one width. A first, naive pass (bands instead of edge rows)
missed tyres like these:

![First pass of the wheel detection](screenshots/wheel_detection.png)

The tool compares each paint with its original and reports rectangles that moved, takes hand
fixes from `wheel_overrides` in `tools/comfy/asset_manifest.json`, and draws every rectangle on
`docs/mockups/wheel_rects.png` for a check by eye. 70 of the 76 bodies are listed; the six
Bubble Car bodies are overridden to "none" — their tyres only peek out at the corners. Re-run
the tool after building new cars or paints.

The tyre **mask** inside a rectangle is computed in the shader from the same dark-and-grey rule,
so hubcaps, suspension arms and body paint overlapping the rectangle are left alone.

### 3.2 The shader

`actors/car/rolling_tread.gdshader`, a `canvas_item` shader:

- uniforms `vec4 wheels[4]` (rectangles in UV), `float roll_front`, `float roll_rear` (distance
  rolled, px), `float blur` (0..1);
- inside a wheel rectangle and on a tyre-coloured pixel, darken stripes across the tyre:
  `step(fract((x + roll) / TREAD_PERIOD), TREAD_WIDTH)`, with a period of about 4 px of texture
  (≈ 3 tread bars visible on a tyre), stripes perpendicular to the car's heading;
- `blur` fades the stripes' contrast towards a flat even darkening at speed, so fast wheels look
  smeared instead of strobing backwards (wagon-wheel effect);
- everywhere else the texture is drawn untouched, so `modulate` / `self_modulate` (wash shine,
  ghost tint) keep working.

### 3.3 Driving it

`actors/car/rolling_tread.gd` (`RollingTread`), on a `Tread` node in `car.tscn` (keeping
`car.gd` about handling only, as its header says):

- looks the body's texture up in `CarWheels` whenever it changes (paint change, title screen,
  town). No entry → no material: the car just looks as it does today;
- gives `Body` its own `ShaderMaterial` per car (`duplicate()`; the rectangles differ per paint);
- each physics tick: `roll += car.forward_speed() * delta * ROLL_SCALE` — signed, so reversing
  rolls backwards. `ROLL_SCALE` (0.15) slows the tread down: at the true rate it would strobe
  from walking pace up, and a slower one still reads as rolling;
  rear wheels stop (`roll_rear` frozen) while `car.handbrake` is held, which looks like locked
  wheels in a handbrake drift; frozen cars (countdown) do not roll;
- `blur = smoothstep(BLUR_FROM, BLUR_TO, abs(speed))`, both constants in px/s, tuned by eye.

`ghost_car.gd` adds a `RollingTread` of its own and feeds it the distance between recorded
samples, so ghosts roll too.

### 3.4 Files

| File | What |
| --- | --- |
| `tools/comfy/wheel_rects.py` | detect, compare with originals, apply overrides, contact sheet, write the script |
| `tools/comfy/asset_manifest.json` | `wheel_overrides` (the Bubble Car: none) |
| `game/configs/car_wheels.gd` | generated: `CarWheels`, the tyre rectangles of every body |
| `docs/mockups/wheel_rects.png` | generated: every body with its rectangles drawn on |
| `actors/car/rolling_tread.gdshader` | the tread |
| `actors/car/rolling_tread.gd` + `car.tscn` | `RollingTread`, feeding the shader |
| `actors/ghost/ghost_car.gd` | ghosts roll too |
| `tests/effects_test.gd` | rolls with speed, backwards in reverse, rear locked on the handbrake, still while frozen, smeared at top speed, follows a paint change, none on the Bubble Car; every body in every paint has its tyres listed |

## 4. Phase 20b — Steering front wheels

The plan was to cut the front tyres out of every body (approach B) and draw them as sprites.
That would have meant 76 touched-up images; the shader of 20a turned out to be able to do it
with no new art at all:

1. `rolling_tread.gd` turns the front wheels towards `steer_input × MAX_STEER` (20°), smoothed
   (`STEER_RATE`), and hands the angle to the shader as `steer`. They turn on the grid during
   the countdown too, as something to do. Ghosts do not steer.
2. While turned, the shader takes the **rubber** of each front tyre out of the body (the tyre
   rule, widened by `SHINE` to the grey shine on the rubber; lights and hubs stay) and draws
   the tyre again, turned round its middle, **behind** the body, as a rounded block in the
   tyre's own colours with the tread sliding along it.
3. Only the outer part of most tyres shows. A whole tyre is taken to be at least `TYRE_WIDTH`
   (13 px) wide, the rest hidden under the body; turned, that part peeks out in plain rubber.
4. The picture is drawn `PAD` (6 px) taller above and below, so a turned tyre at the edge of
   the texture is not cut off.
5. Straight ahead the shader does just what it did in 20a, so no car looks any different.

Checked by eye on every car with `tools/dev/steer_sheet.tscn` (every body in its original and
pink paint, turned left, straight, right) and `tools/dev/steer_clip.tscn` (frames of a short
drive with drifts). On the Kart, whose thin dark suspension arms count as rubber, the arms are
hidden while the wheels are turned. `tests/effects_test.gd` checks that the wheels turn each
way, come back straight, turn on the grid, and that a drift leans the body outwards and lets
it settle.

## 5. Extras that fall out of the same work (optional, small)

- **Body lean ✅ built** — `actors/car/body_lean.gd` (`BodyLean`, the `Lean` node in
  `car.tscn`): sliding sideways faster than `FROM` (120 px/s), the body shifts towards the
  outside of the drift (up to 3 px) and swings its tail further out (up to 5°), in full from
  `FULL` (450 px/s). Only `Body` moves (its driver and roof load with it); `Body.scale` stays
  free for the town's ramp hop. Still open: a tiny squash when hitting a wall (`CAR_wall_hit`).
- **Idle shake** — a sub-pixel engine wobble at standstill during the countdown.
- **Rocket flames** — the rocket's baked flames could flicker with the same shader (a flame mask
  rectangle instead of wheels) and grow with throttle/boost.
- **Exact skid marks** — `skid_marks.gd` and `car_effects.gd` could use the real rear-wheel
  positions from `CarWheels` instead of the fixed `Vector2(-40, 0)`.

## 6. Done when

- Every car in every paint shows tread rolling at its speed, backwards in reverse, locked rear
  wheels on the handbrake, a smooth blur at top speed, in races, town, title screen and ghosts.
- No car without wheel data looks any different from today.
- Tests pass headless; the perf probe shows no measurable frame-time change.
