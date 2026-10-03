# Vicky Racer — Design Document

A 2D top-down arcade racer for a young child, built in **Godot 4.7** (Forward+ renderer). The
player races three AI cars around tile-built circuits, earns coins by finishing, and spends them in
a garage on drift setups that change how the car handles. All art is generated locally with
ComfyUI from a single frozen recipe.

This document was written ahead of the code, with every system marked **(not implemented)** until
it landed. All of v1 is now built — the last markers came off with Phase 8 (effects, sound and the
balance pass) — and the document describes the game as it is. Mockups referenced here live in
[`mockups/`](mockups/); every generated image there is reproducible from
[`mockups/seeds.json`](mockups/seeds.json).

---

## 1. Design pillars

| Pillar | What it means in this build |
| --- | --- |
| **Forgiving by construction** | The car *cannot* spin out — steering rotates the car directly instead of applying torque. Walls slide you along rather than stopping you. Grass slows you but never ends your race. Nobody is ever told they lost. |
| **Drift is the fun** | Handling splits forward and sideways grip, so the car slides through corners and the handbrake kicks the tail out on demand. The garage is a menu of different answers to "how slidey?". |
| **Readable at a glance** | Bars instead of numbers, big position and lap readouts, a world-up camera that never rotates, four racers in four primary colours. A child who cannot read yet can still play. |
| **One good track before many** | A single hand-designed circuit, tuned until it is fun, before any second track is considered. |

## 2. Core loop

```
   ┌────────────────────────────────────────────────────────────────┐
   │                                                                │
   ▼                                                                │
 GARAGE ──► GRID ──► 3·2·1·GO ──► RACE 3 LAPS ──► RESULTS ──► COINS ─┘
 (buy /     (4 cars,  (cars       (drift, pass,    (order,     (paid by
  equip      player    frozen)     minimap,         best lap)   position,
  a drift    last-but-                position)                  generous
  setup)     one)                                                floor)
```

0. **Title.** The logo and PLAY / SETTINGS / QUIT over a live race of four AI cars.
1. **Garage.** Browse six drift-setup cards with a gamepad or keyboard. Buy what you can afford,
   equip what you own, press **RACE!**.
2. **Grid.** Four cars on a staggered two-wide grid behind the start/finish line.
3. **Countdown.** A big 3 · 2 · 1 · GO! Cars are frozen until GO.
4. **Race.** Three laps. A lap only counts if the mid-lap checkpoint was crossed.
5. **Results.** Always celebratory. The finishing order slides in, then the coin payout counts up.
6. **Back to the garage** — or straight into **RACE AGAIN**, focused by default.

## 3. Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Steer | ← → or A D | Left stick X (analog) |
| Accelerate | ↑ or W | RT or A |
| Brake / reverse | ↓ or S | LT or B |
| Handbrake (drift) | Space | X |
| Confirm (menus) | Enter | A |
| Back (menus) | Esc | B |
| Race from garage | R | Y |
| Pause (race) | Esc | Start |

Escape and B also go back from the garage to the title. In a race, Escape pauses instead of
leaving: one wrong button must never throw away a race (§10).

Both keyboard layouts are always live, so two hands can find the controls without being taught.
Steering reads `Input.get_axis`, which gives analog steering on a stick for free. Menu glyphs swap
between keyboard and gamepad depending on which was used last.

### 3.1 Assists

Two switches on the settings screen, both off by default, both applied live by
[`player_input.gd`](../actors/car/player_input.gd):

- **AUTO GO** — the car cruises at 65 % of its top speed with no pedal held, so a very young child
  only has to steer. Holding accelerate still gives full speed, and braking still brakes.
- **STEER HELP** — steers toward the road ahead: fully while the child is not steering, as a gentle
  nudge (30 %) on top of their steering when they are. It keeps whatever lane the child is in and
  only pulls toward the middle near the edge of the road.

Both on with no input at all, the car laps Track 01 without leaving the road or touching a wall,
and finishes **3rd** — the assists help, they do not race. At 80 % cruise it won outright, which
made it an autopilot; 65 % was chosen so that pressing the pedal still pays
([`tests/assist_test.gd`](../tests/assist_test.gd)).

## 4. Handling model

The car is a `CharacterBody2D` that points **+X**. Every physics frame:

```
forward = Vector2.RIGHT.rotated(rotation)
speed   = velocity.length()

# Steering is input-driven ROTATION, scaled by SIGNED forward speed.
# Because rotation comes from input and not from torque, the car cannot spin out;
# signed speed makes reversing steer the natural way round.
rotation += steer * max_steer_rate * clamp(forward_speed / steer_speed_ref, -1, 1) * delta

# Throttle acts along forward only. Braking below 40 px/s becomes reverse,
# at reverse_power_fraction of engine power, capped at max_reverse_speed.
velocity += forward * accel * delta

# Drift: split velocity and damp each part with its own coefficient.
# exp() is the exact form of per-frame damping and can never overshoot.
fwd_v = forward * velocity.dot(forward)
lat_v = velocity - fwd_v
grip  = (handbrake_lateral_grip if handbrake else lateral_grip) * surface.grip_mult
velocity = fwd_v * exp(-forward_drag * delta) + lat_v * exp(-grip * delta)

# Over the speed limit (e.g. just left the road) the car slows at 1500 px/s², not instantly.
move_and_slide()   # on a fresh wall hit: velocity *= (1 - wall_speed_scrub), keep the slide
```

Implemented in [`actors/car/car.gd`](../actors/car/car.gd). The promises above are checked by
[`tests/handling_test.gd`](../tests/handling_test.gd) — it cannot spin out (even on Banana with
the handbrake), cannot turn on the spot, the handbrake at least doubles the slide, walls slide you
along, grass slows you gradually, and every setup resolves within the clamps:

```bash
Godot_v4.7.1-stable_win64_console.exe --path . --headless --fixed-fps 60 res://tests/handling_test.tscn
```

- **High `lateral_grip`** — the car goes where it points. **Low** — it keeps travelling sideways
  after it turns, which is the drift.
- The **handbrake** swaps in a much lower grip to kick the tail out on demand.
- **Speed-scaled steering** stops the car pirouetting on the spot and keeps it calm at speed.
- `CAR_drift_started` / `CAR_drift_ended` fire when `lat_v.length()` crosses a threshold; skid
  marks and the drift sound hang off those signals (§4.3).

### 4.1 `CarConfig` — the base car

One `Resource` holds the base values, editable in the inspector while the game runs. Starting point:

| Field | Value | Unit |
| --- | --- | --- |
| `engine_power` | 1400 | px/s² |
| `brake_power` | 2200 | px/s² |
| `max_speed` | 1100 | px/s |
| `max_steer_rate` | 3.2 | rad/s |
| `steer_speed_ref` | 350 | px/s — full steering authority from this speed up |
| `forward_drag` | 0.6 | 1/s |
| `lateral_grip` | 9.0 | 1/s |
| `handbrake_lateral_grip` | 1.8 | 1/s |
| `wall_speed_scrub` | 0.15 | fraction of speed lost per wall hit |

### 4.2 `DriftSetup` — what the garage sells

A `DriftSetup` is a `Resource` of **multipliers over** `CarConfig`, never replacement values. Because
they multiply a sane base and the results are clamped, no setup can produce nonsense physics, and
none is a strict upgrade — each is a different trade.

| Setup | Grip × | Handbrake grip × | Engine × | Top speed × | Steer × | Bars G / S / S | Price |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Starter** | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 0.7 / 0.4 / 0.5 | owned |
| **Grippy** | 1.5 | 1.6 | 0.95 | 0.95 | 1.05 | 0.95 / 0.15 / 0.45 | 100 |
| **Slider** | 0.55 | 0.6 | 1.0 | 1.0 | 1.15 | 0.3 / 0.9 / 0.5 | 250 |
| **Rocket** | 0.9 | 1.0 | 1.25 | 1.2 | 0.8 | 0.55 / 0.45 / 0.9 | 250 |
| **Kart** | 1.2 | 1.0 | 1.1 | 0.85 | 1.35 | 0.8 / 0.35 / 0.35 | 250 |
| **Banana** | 0.45 | 0.5 | 1.3 | 1.25 | 1.0 | 0.2 / 1.0 / 1.0 | 600 |

Resolved values are clamped — `lateral_grip` never below 3.0, `max_speed` never above 1500 px/s — so
even Banana stays drivable.

**A setup also changes how the car looks:** in the race the player drives the car from its garage
card — knobbly tyres for Grippy, light-blue swirls for Slider, boosters for Rocket, the go-kart, the
banana car ([`screenshots/setup_cars.png`](screenshots/setup_cars.png)). Setups were first
handling-only, which left a child who bought Banana still driving the plain red car. Because the
player's car can now share a colour with an opponent (Banana and Yellow), a small white arrow
always floats above the player's car. The three **bar values** are authored, not computed: they describe how
the setup *feels*, which is what the garage needs to communicate.

### 4.3 Feedback: marks, puffs, shake and sound

Drift is the fun, so a drift has to be *seen and heard* — the payoff for buying a slippery setup.

![Skid marks, tyre smoke and grass dust](screenshots/drift_effects.png)

| Effect | Trigger | Built in |
| --- | --- | --- |
| **Skid marks** — two dark lines from the rear wheels, fading out 6 s after the drift, at most 80 kept | `CAR_drift_started` / `_ended`, any car | [`actors/effects/skid_marks.gd`](../actors/effects/skid_marks.gd), one node per race between the track and the cars, so marks lie under every car |
| **Tyre smoke** — white puffs while drifting on the road | the car's drift state | [`actors/car/car_effects.gd`](../actors/car/car_effects.gd) |
| **Dust** — earth-coloured on grass (green would vanish against it), sand-coloured on sand | `CAR_surface_changed` | same; the puff texture is a generated soft disc, no art file |
| **Wall shake** — the view jolts by up to 9 px and settles within a second; a bump to feel, not a jolt to frighten | `CAR_wall_hit` for the camera's own car | [`actors/car/chase_camera.gd`](../actors/car/chase_camera.gd), added to the rig's position so physics interpolation still smooths it |
| **Engine** — one steady loop, pitch from 0.6× at rest to 1.5× at top speed, a touch higher under throttle | every frame | [`actors/car/car_audio.gd`](../actors/car/car_audio.gd), positional: opponents are heard near the camera and fade with distance |
| **Tyre squeal** — a loop that fades in with sideways speed | the car's drift state | same |
| **Bump** — a soft thump, louder for harder hits | `CAR_wall_hit` | same |
| **Beeps** — three low beeps and a high GO | `RAC_countdown_tick` | [`game/managers/sound_manager.gd`](../game/managers/sound_manager.gd), in the main shell |
| **Fanfare**, **coin chime**, **menu click** | `RAC_race_finished`; `PRO_setup_purchased` and the results count-up; menu focus moving | same, and [`ui/results/results_screen.gd`](../ui/results/results_screen.gd) |

[`tests/effects_test.gd`](../tests/effects_test.gd) checks the visual effects headlessly. Sounds
are skipped under the dummy audio driver of headless runs: it never mixes, so a played sound would
never finish and be reported as leaked at exit. Where the sounds come from: §11.2.

## 5. Scale

| Thing | Size | Why |
| --- | --- | --- |
| Tile | 128 px | Large enough that generated textures keep their character; a 48 × 28 map stays manageable in the editor |
| Road | 3 tiles (384 px) | Room for two cars side by side plus a mistake |
| Car sprite | 128 × 72 px, facing +X | Godot 2D's zero rotation; reads clearly against a 384 px road |
| Car collision | 110 × 60 px rectangle | Slightly inside the sprite so contact looks fair |
| Viewport | 1920 × 1080, `canvas_items` / `expand` | Already set in `project.godot` |
| Camera zoom | 0.92, fixed | About 16 × 9 tiles visible. Close enough to match the chosen style frame, where cars read at ~130–160 px; the camera's 260 px lead toward the direction of travel shows about a second of road ahead at top speed. A speed-dependent zoom-out was dropped: changing zoom while driving defeats physics interpolation and made the view judder (see below) |

### 5.1 Smooth motion on fast monitors

Physics runs at 60 Hz, but monitors refresh at 100–165 Hz. Without help the car and camera only
move on physics ticks, so on a 100 Hz screen the view moves on three frames in five and stands
still on the other two — a judder that reads as flicker. The fix is Godot's **physics
interpolation** (`project.godot`), which draws everything between ticks. It only smooths node
*positions*, so the chase camera ([`actors/car/chase_camera.gd`](../actors/car/chase_camera.gd))
is built from positions alone: a rig node holds the lead, the Camera2D has no smoothing, and the
zoom is fixed. Anything teleported (a reset, the start grid) calls
`reset_physics_interpolation()` so it does not glide.

[`tools/dev/motion_check.py`](../tools/dev/motion_check.py) measures this on rendered frames
(100 fps against 60 Hz physics, tracking a hay bale): frame-to-frame wobble of the view went from
**17.8 px** without interpolation to **0.57 px** with it — the same as running physics at 100 Hz.

### 5.2 Performance

[`tests/perf_probe.gd`](../tests/perf_probe.gd) measures a full race with every car on
autopilot. Headless at a fixed 60 fps (`-- --autopilot --bench`), wall time per frame is the
whole CPU cost of simulating the race; with a window it reports frame rate, draw calls and
objects.

| Measure (RTX 5070 Ti machine) | Before the pass | After |
| --- | --- | --- |
| CPU per simulated frame (scripts + physics) | 415 µs | **234 µs** — 1.4 % of a 60 Hz frame |
| Windowed, vsync off | 1,940 fps | 2,190 fps |
| Draw calls / objects | ~40 / stable | unchanged |
| Race load (track, road, cars) | — | 18 ms |

Three changes, each measured on its own:

1. **Racing line baked at 20 px**, not Godot's default 5. Every closest-point search walks
   every baked point; a quarter of the points made each search ~11 → 3 µs. On Track 01's
   tightest bend the chord error is under a quarter pixel, and the balance table did not move.
2. **Each car measured once per frame.** The track (physics priority −2, before anyone
   else) searches the line once per car and caches progress and distance; the race, the AI and
   steering help read `Track.progress_of()` / `distance_of()` instead of searching again.
3. **Minimap line cached in map space**, rebuilt only on resize. Converting all 200 points every
   frame was the most expensive script in the race (71 µs).

The game is far inside its budget even on this fast machine; the margins are for the slower
laptop a child is likely to play on.

## 6. Architecture

### 6.1 Event bus

As in Vicky's Game, systems never hold references to each other. `game/event_system.gd` is the
single autoload (`EventSystem`) and declares every cross-system signal. Managers `connect` in
`_enter_tree()`; emitters call `EventSystem.<SIGNAL>.emit(...)`.

| Prefix | Domain | Signals |
| --- | --- | --- |
| `RAC_` | Race | `countdown_tick(n)`, `race_started()`, `lap_completed(racer, lap, lap_time)`, `positions_updated(order)`, `race_finished(results, track_id)` |
| `CAR_` | Car | `drift_started(car)`, `drift_ended(car, duration)`, `surface_changed(car, surface)`, `wall_hit(car, impact_speed)` |
| `PRO_` | Progression | `state_requested()`, `state_changed(state)`, `buy_requested(id)`, `equip_requested(id)`, `coins_changed(total)`, `coins_awarded(amount, breakdown)`, `setup_purchased(id)`, `setup_equipped(id)`, `purchase_refused(id, reason)` |
| `UI_` | Screens | `show_message(text, duration)`, `screen_requested(name)`, `settings_requested()`, `settings_changed(settings)`, `setting_change_requested(key, value)` |

Screens never reach into managers. Following Vicky's Game's inventory pattern, a screen emits
`PRO_state_requested` and `GarageManager` answers synchronously with `PRO_state_changed`, carrying
the whole garage state: coins, owned and equipped setups, best laps and the last race. Buying and
equipping are requests (`PRO_buy_requested`, `PRO_equip_requested`); the manager decides.

Each `RAC_race_finished` result is a Dictionary: `name`, `body` (car sprite path), `is_player`,
`position`, `time`, `best_lap`.

### 6.2 Scenes and managers

```
main.tscn  (persistent shell — never unloaded)
├── GarageManager        wallet, ownership, equipped setup, last race; pays out on RAC_race_finished
├── SettingsManager      volume, fullscreen, assists, difficulty; applies and saves every change
├── SoundManager         beeps, fanfare, coin, menu clicks (runs while paused)
└── ScreenSlot           swaps on UI_screen_requested(&"title" | &"garage" | &"race" | &"results"):
    ├── title_screen.tscn     logo + menu over a live attract-mode race; SettingsPanel
    ├── garage_screen.tscn
    ├── race.tscn
    │   ├── Track (track_01.tscn)
    │   ├── SkidMarks
    │   ├── RacerSpawner      places 4 cars on the grid
    │   ├── RaceManager       countdown, laps, positions, rubber-banding, finish
    │   ├── RaceHUD + Minimap
    │   └── PauseMenu         pauses the tree; RESUME / RESTART / SETTINGS / GARAGE
    └── results_screen.tscn
```

The managers live in the shell rather than becoming more autoloads, keeping to the one-autoload
rule while still surviving every screen swap. Changing screen always unpauses the tree.

### 6.3 Drivers

`car.gd` exposes three plain fields — `steer_input`, `throttle_input`, `handbrake` — and knows
nothing about who sets them. `player_input.gd` and `ai_driver.gd` are interchangeable children that
write into those fields. The same car scene is used for all four racers.

## 7. Track

### 7.1 Track 01

![Track 01 layout](mockups/track_01_layout.png)

- **48 × 28 tiles** (6144 × 3584 px), lap ≈ **107 tiles / 13,600 px**, about **19 s** at a 700 px/s
  average — roughly a minute for three laps, about right for a young child's attention.
- Six corners: a sweeping T1, a hairpin at T2, the T3/T4 S-bend, the long T5 and T6 back onto the
  start straight. Sand traps on the outside of T1 and T2, where mistakes happen.
- The circuit is defined **once**, as control points in
  [`tools/layouts/track_layout.py`](../tools/layouts/track_layout.py). That script writes both this
  diagram and [`mockups/track_01_points.json`](mockups/track_01_points.json), which the game reads
  to build the racing line — so the reviewed layout and the driven track cannot drift apart.

### 7.2 Building the track: spline road over a tile map

Decided after [`mockups/road_compare.png`](mockups/road_compare.png): tile terrain turns the hairpin
into a jagged octagon, while a road drawn from the spline keeps frame 04's smooth sweep. So the
track is two layers:

- **Ground — a `TileMapLayer`.** Grass, sand traps and decoration, painted by hand in Godot's
  TileMap editor. The fills are the flat procedural textures (§11.1); the grass↔sand edge pieces
  are composited by script from those fills, so every edge matches.
- **Road — built from the spline.** A `Path2D` holds the racing line, defined by the control
  points in `tools/layouts/track_layout.py`. From it the track scene builds, in `_ready()` and as
  an editor tool so it is visible while editing:
  - the asphalt as a `Polygon2D` (the curve offset ±192 px, textured with the asphalt fill);
  - the kerbs as `Line2D`s along both road edges, textured with the kerb strip in tile mode, so
    the red/cream blocks follow every bend at an even spacing — only where the bend is tight;
  - the lane dashes and the chequered start/finish line.

  Moving a control point moves the road, the kerbs, the racing line and the surface detection
  together. Nothing about the road is painted by hand, so it can never disagree with the AI's line.
  Kerbs are continuous strips: gaps under 160 px between tight stretches are bridged and pieces
  under 320 px dropped, so gentle bends at the threshold do not fragment.

**Built:** [`screenshots/track_overview.png`](screenshots/track_overview.png),
[`screenshots/track_grid.png`](screenshots/track_grid.png).

| Piece | File |
| --- | --- |
| Ground tileset: 16 corner tiles, Grass/Sand terrain in Match Corners mode | [`tools/layouts/build_tileset.py`](../tools/layouts/build_tileset.py) → `art/tiles/ground_atlas.png`, `track/ground_tiles.tres` |
| Track logic and road drawing (`@tool`, so the road also shows in the editor) | [`track/track.gd`](../track/track.gd) |
| Scene builder: layout points → `track_01.tscn` (curve, painted sand traps, grid, gates, walls, trees, tyre stacks) | [`track/build/build_track.gd`](../track/build/build_track.gd) |
| Checks: surfaces, progress, grid, gates | [`tests/track_test.gd`](../tests/track_test.gd) |

Inside a ground tile, sand is where the bilinear blend of its four corners exceeds 0.5. The tiles
are drawn with that rule and `Track.surface_at()` tests with it, so what you see is what you drive
on. Neighbouring tiles share corners, so edges continue across tile borders without a seam.

To change Track 01: edit `CONTROL_POINTS` and friends in `tools/layouts/track_layout.py`, run it,
then rebuild the scene (this overwrites hand edits to `track_01.tscn`):

```bash
python tools/layouts/track_layout.py
Godot_v4.7.1-stable_win64_console.exe --path . --headless res://track/build/build_track.tscn
```

Image generation makes none of this geometry — it is exactly what diffusion does worst. Generated
art is limited to the cars, props and UI illustrations.

### 7.3 Surfaces

The car checks what it is on every physics frame:

1. **On the road?** Distance from the car to the racing line (`Curve2D.get_closest_point`) is under
   the road's half-width → asphalt. Kerbs count as asphalt.

The track, not the car, does this: each physics frame it sets the surface multipliers of every
node in the `cars` group and emits `CAR_surface_changed` when a car's surface changes. Cars stay
unaware of tracks.
2. **Otherwise**, the ground tile beneath it, read from the TileSet's custom data layer `surface`.

| Surface | `speed_mult` | `lateral_grip` × | Feel |
| --- | --- | --- | --- |
| Asphalt / kerb | 1.0 | 1.0 | Normal |
| Grass | 0.55 | 0.7 | Slow and a bit loose — get back on |
| Sand | 0.4 | 0.6 | Sticky and slow, but you drive out |

The map edge is a tyre wall: solid, but it slides you along it.

### 7.4 Progress and laps

- **Progress** is distance along the racing line: `progress = laps × lap_length +
  curve.get_closest_offset(position)`. One number per car, sorted every frame for live positions.
- **Lap validation** uses two `Area2D`s: the mid-lap checkpoint must be crossed before the
  start/finish line counts. This blocks reverse driving and cutting across the infield.

## 8. AI and the race

### 8.1 AI drivers

Each AI car runs [`actors/car/ai_driver.gd`](../actors/car/ai_driver.gd), writing the same three
inputs a player would:

1. **Steer** at a point on the racing line 150 px + 0.3 s of speed ahead, shifted sideways into
   its own lane (−70 / 0 / +70 px), so the pack does not drive in single file.
2. **Read the road ahead** — the sharpest bend in the next 250 / 500 / 800 px sets a target speed
   between its straight pace (0.80 + 0.15 × skill of its top speed) and corner pace (0.45 + 0.15 ×
   skill of the *base* car's top speed, times its setup's steering multiplier); it lifts or brakes
   to meet it. Corner speed follows how fast the car turns, not how fast it goes: a Kart carries
   more speed through a bend, a Rocket must lift more. Opponents drive the base car, so for them
   nothing changes; it matters when the player's car is on autopilot for the balance pass (§8.3).
3. **Avoid** — a car close in front pushes it into the other half of the road until clear.
4. **Never strand** — stuck (slow with the throttle down) for 1.2 s, it backs out steering the
   other way; after three back-outs, or 900 px off the line, it is put back on the line. The race
   test expects no rescues in a normal race, and sees none.
5. **Skill** — 0.85 / 0.70 / 0.55 for Blue / Yellow / Green on Track 01
   ([`game/configs/tracks/track_01.tres`](../game/configs/tracks/track_01.tres)).

### 8.2 Race flow

[`RaceManager`](../game/managers/race_manager.gd) holds the cars still through 3-2-1-GO, then:

- **Laps** count on the finish line only after the mid-lap checkpoint. The grid is behind the
  line, so the first crossing *starts* lap 1. Lap 1 is timed from GO.
- **Positions** sort finished cars by finish time, the rest by progress (laps × lap length + distance
  past the line; negative on the grid).
- **The race ends when the player finishes** (after a 2.5 s FINISH! moment). Opponents still racing
  get a time from their average pace carried over the distance left, so a child never waits on a
  race that is over for them. Results go out on `RAC_race_finished`; `GarageManager` pays out.
- The player starts **3rd of 4** — something to chase, nobody to lap.

### 8.3 Rubber-banding and the balance pass

Each AI's pace is scaled by how far it is from **where it wants to be**: 1,500 px ahead of that
spot it eases to **60 %**, the same distance behind it pushes to **112 %**, and may then pass its
own top speed by as much (`Car.catch_up_mult`), so a player on a faster setup cannot simply drive
away. Where it wants to be: level with the player for Blue, the best driver; the others hang back
5,000 px per point of skill below 0.85, so Yellow 750 px and Green 1,500 px. The best opponent
always makes the player work for a win, and the weaker two leave room on the podium for a child who
is still learning ([`race_manager.gd`](../game/managers/race_manager.gd)).

These numbers are **Normal**. The settings screen's OPPONENTS switch picks one of three
[`DifficultyConfig`](../game/configs/difficulty_config.gd) resources, which shift every
opponent's skill and retune the band:

| Difficulty | Skill | Ease off / push | Hang back per skill point | Struggling child (0.7) | Clean driving |
| --- | --- | --- | --- | --- | --- |
| Easy | −0.10 | 55 % / 110 % | 6,000 px | 2nd by a few tenths with Starter, wins with the faster setups | wins by ~2 s |
| Normal | — | 60 % / 112 % | 5,000 px | 3rd | wins by ~1 s |
| Fast | +0.10 | 75 % / 115 % | 2,500 px | 4th, 2–6 s back | a close fight for 1st |

Tuned with [`tools/dev/balance_report.py`](../tools/dev/balance_report.py) (`--difficulty`), which races every setup
with the player's car on autopilot at three paces: 1.0 = clean driving, 0.85 = a decent child,
0.7 = a struggling one. Each cell is the player's place and the gap to the winner (negative = the
winning margin). Runs are deterministic, so before and after compare directly.

Before Phase 8 (70 % / 1,800 px, every AI banded level with the player, capped at its own top
speed):

| Setup | 1.0 | 0.85 | 0.7 |
| --- | --- | --- | --- |
| Starter | 2nd +0.2 s | 4th +1.0 s | 4th +2.8 s |
| Grippy | 2nd +0.3 s | 4th +1.4 s | 4th +4.1 s |
| Slider | 2nd +0.1 s | 4th +1.2 s | 4th +3.0 s |
| Rocket | 1st −4.3 s | 1st −0.6 s | 4th +1.1 s |
| Kart | 4th +0.6 s | 4th +2.2 s | 4th +7.1 s |
| Banana | 1st −4.5 s | 1st −0.8 s | 3rd +0.8 s |

Three problems: a decent child came last on every setup but the two fastest; Rocket and Banana won
by over 4 s, because nothing could catch them on the straights; and Kart looked strictly worse, only
because the autopilot ignored its sharper steering. Shipped:

| Setup | 1.0 | 0.85 | 0.7 |
| --- | --- | --- | --- |
| Starter | 1st −0.8 s | 2nd +0.4 s | 3rd +1.4 s |
| Grippy | 1st −0.6 s | 2nd +0.6 s | 3rd +1.5 s |
| Slider | 1st −1.0 s | 3rd +1.0 s | 3rd +1.5 s |
| Rocket | 1st −1.7 s | 1st −0.1 s | 3rd +1.0 s |
| Kart | 1st −0.8 s | 2nd +0.6 s | 3rd +1.3 s |
| Banana | 1st −3.0 s | 1st −0.5 s | 2nd +0.6 s |

Clean driving wins narrowly on anything; a decent child fights for 2nd and 3rd; a struggling child
reaches the podium. Setups are worth buying without trivialising the race. The autopilot never
uses the handbrake, so the table cannot show what a slippery setup costs a child in control:
Banana's margin is deliberately the largest because it is also the hardest car to keep on the road.

## 9. Garage and economy

### 9.1 Earning

| Finish | Coins |
| --- | --- |
| 1st | 100 |
| 2nd | 75 |
| 3rd | 60 |
| 4th | 50 |
| First time finishing a track | +100 once |

The Phase 8 balance pass left these numbers alone: with the retuned rubber-banding a decent child
finishes 2nd or 3rd (60–75 coins), which keeps the pacing below. The floor is deliberately generous: a child finishing last every time still affords **Grippy**
after two races and a 250-coin setup after about five. Winning just gets there faster. Owning
everything costs 1,450 coins — roughly 15 races for a strong player, 25 for a struggling one. All of
these numbers live in one `EconomyConfig` resource.

### 9.2 Save file

A `ConfigFile` at `user://vicky_racer.cfg`:

```ini
[profile]
schema_version=1
coins=240
owned_setups=PackedStringArray("starter", "slider")
equipped_setup="slider"
completed_tracks=PackedStringArray("track_01")

[best_laps]
track_01=38.90
```

`completed_tracks` records which tracks have paid their one-off first-finish bonus.

Loading is defensive: a missing, unreadable or unknown-version file yields a fresh profile instead
of an error, and an unreadable file is kept as `vicky_racer.cfg.bak` rather than overwritten.
Values are sanitised on load — negative coins become 0, Starter is always owned, and an equipped
setup the player does not own falls back to Starter. A broken save must never stand between a
child and the game.

A purchase equips the setup straight away: a child who just bought something wants to drive it.

Implemented in [`game/save_game.gd`](../game/save_game.gd) and
[`game/managers/garage_manager.gd`](../game/managers/garage_manager.gd); checked by
[`tests/economy_test.gd`](../tests/economy_test.gd), which also proves the design promise that two
last places afford Grippy.

## 10. Screens

| Screen | Spec |
| --- | --- |
| Title | [`mockups/title_layout.png`](mockups/title_layout.png) — logo, PLAY / SETTINGS / QUIT over a live attract-mode race (four AI cars on Track 01, no HUD, no engine sounds). Built: [`screenshots/title.png`](screenshots/title.png) |
| Pause | [`mockups/pause_settings_layout.png`](mockups/pause_settings_layout.png) — Esc / Start or the window losing focus pauses the whole tree. RESUME is focused, so pausing twice resumes; B resumes too; RESTART and GARAGE ask SURE? with NO focused. Built: [`screenshots/pause.png`](screenshots/pause.png) |
| Settings | Same spec — SOUND, FULLSCREEN, AUTO GO, STEER HELP, OPPONENTS; one focusable row each, ← → change it. Over the title and over the pause menu. Built: [`screenshots/settings.png`](screenshots/settings.png) |
| Race HUD | [`mockups/hud_layout.png`](mockups/hud_layout.png) — position, lap, timers, speed bar, minimap, countdown. Built: [`screenshots/race.png`](screenshots/race.png), [`screenshots/race_countdown.png`](screenshots/race_countdown.png). The countdown sits above screen centre rather than on it, so it never hides the player's own car |
| Garage | [`mockups/garage_layout.png`](mockups/garage_layout.png) — balance, 3 × 2 setup cards, preview with Grip / Slide / Speed bars. Built: [`screenshots/garage.png`](screenshots/garage.png) |
| Results | [`mockups/results_layout.png`](mockups/results_layout.png) — finishing order, payout count-up, Race Again. Built: [`screenshots/results.png`](screenshots/results.png) |

Pink annotations on each spec give anchors, sizes and animation timings; they are meant to be
built verbatim with `Control` anchors. All menus are fully navigable with a gamepad alone.

### 10.1 Settings file

`user://vicky_settings.cfg`, separate from the save game: settings belong to the computer and
the person at it, progress belongs to the child, and neither should be able to break the other.
[`Settings`](../game/settings.gd) validates every value on load and on change (volume clamped and
snapped to 10 % steps, unknown keys and mistyped values ignored), so a hand-edited file falls back
to defaults rather than failing. [`SettingsManager`](../game/managers/settings_manager.gd) applies
and saves each change at once. Sound goes through an `SFX` bus (`default_bus_layout.tres`; a
`Music` bus waits for Phase 13). Checked by [`tests/front_end_test.gd`](../tests/front_end_test.gd).

The HUD takes race state from the `RAC_` signals. The speed bar and the minimap are the exception:
the race screen hands them the cars, because they need positions every frame and no signal should
carry that 60 times a second.

## 11. Art direction and asset pipeline

**Style anchor: frame 04, "picture book".**

![Style anchor](mockups/style_anchor.png)

Soft, rounded, friendly shapes in warm bright colours; no hard black outlines; a near-overhead
camera, which suits top-down sprites. Generated by FLUX.1-dev at 1344 × 768, seed **202**, guidance
3.5, 20 steps, euler / beta, with the prompt:

> top-down view from directly above of a winding race track for a children's racing video game:
> grey asphalt road with red and white kerbs, green grass, a few round trees, tyre stacks and hay
> bales, four small colourful race cars (red, blue, yellow, green) driving around a bend, 2D video
> game screenshot, soft flat children's picture book illustration, rounded friendly shapes, warm
> bright flat colours, no outlines

What the frame gets right, and production assets must keep: rounded cartoon proportions, warm
saturated greens and greys, chunky red/white kerbs, props as soft simple blocks. What it gets wrong
and Phase 2 must correct: the soft 3D shading and drop shadows (FLUX's house style — the prompt
asked for flat), and the slight perspective on some cars. This image is the reference fed to
`ReduxAdvanced` when style-locking every asset.

Assets come from local ComfyUI through `tools/comfy/`:

| Asset | Count | Approach |
| --- | --- | --- |
| Player car | 1 | **Chosen: the sports car** (`mockups/raw/car_sports.png`, seed 11). Generated top-down, cut out with BiRefNet, rotated from its nose-down source to +X, fitted to 128 × 72 |
| Opponent cars | 3 | The player car repainted blue, yellow and green with FLUX Kontext — identical silhouette, proven in [`mockups/car_palette.png`](mockups/car_palette.png) |
| Ground fills | 3 | Asphalt, grass, sand — **procedural flat colour** sampled from the style anchor (the bake-off showed generated fills cannot tile) |
| Edge / corner tiles | ~16 per surface pair | Composited by script from the fills (§7.2) |
| Kerbs, finish line | 2 | Drawn — red/cream kerb strip and a chequer, both tileable |
| Props | 4 | Straw ring, hay bale, tree, tyre stack — generated + cut out, style-locked to the style board. The tyre stack's hole is punched out in post so the ground shows through |
| UI | 7 | Coin, and one card illustration per drift setup |

### 11.0 Production (Phase 3)

Every asset, its subject or edit instruction, pinned seed, facing, size and output path is in
[`tools/comfy/asset_manifest.json`](../tools/comfy/asset_manifest.json). Picks were made from four
candidates each ([`mockups/candidates/`](mockups/candidates/)); the whole set is shown together in
[`mockups/asset_overview.png`](mockups/asset_overview.png). To rebuild:

```bash
python tools/comfy/generate_assets.py build            # reuse cached masters
python tools/comfy/generate_assets.py build --force    # re-render everything from seeds
```

### 11.1 The frozen recipe (Phase 2)

Five bake-off rounds ([`mockups/bakeoff/`](mockups/bakeoff/)) settled the recipe in
[`tools/comfy/pipeline.json`](../tools/comfy/pipeline.json):

| Setting | Value | Why |
| --- | --- | --- |
| Model | FLUX.1-dev, fp8 weights | SD3.5 was faster but gritty and realistic. bf16 was not reproducible at 1536 px |
| Size | 1536 px, downscaled to sprite size | The softest, most anchor-like finish of any setting |
| Style lock | Redux on the **style board**, factor 4.5 / weight 0.75 | The full style frame leaked its track into every asset; the board is frame 04's objects only |
| Steps | 20 | 30 steps added nothing visible |
| Cut-out | BiRefNet-general | `toonout` kept shadows, filled the straw ring's hole and kept a dirt rim on trees |
| Picking | 4 candidates per asset, best one pinned | Quality over speed |

The recipe is **verified reproducible**: an identical request regenerates pixel-identically, so a
pinned seed fully defines an asset. Prompt lessons — how to get props truly top-down, and that car
facing is unreliable and must be recorded per asset — are kept in `pipeline.json` itself.

### 11.2 Sound (Phase 8)

Six sounds are generated with **Stable Audio 3** through the same ComfyUI client, declared with
prompts and pinned seeds in [`tools/comfy/sfx_manifest.json`](../tools/comfy/sfx_manifest.json) and
built by [`tools/comfy/generate_sfx.py`](../tools/comfy/generate_sfx.py) into `art/sfx/` as mono
16-bit WAVs. Recipe: `stable_audio_3_medium_base`, 50 steps, cfg 7. A bake-off on a tyre-squeal
probe found it gave the cleanest tonal squeal; `small_sfx` is distilled (cfg 1 only) and noisier.
Four candidates per sound were picked from spectrogram sheets in [`mockups/sfx/`](mockups/sfx/).
One-shots are trimmed and faded; the two loops (engine, squeal) are cut from the steadiest stretch
of their clip and cross-faded so they repeat without a click, and imported with looping on. The
countdown beeps are synthesised: a pure tone is what they need.

```bash
python tools/comfy/generate_sfx.py candidates [--only coin]   # render candidates + review sheet
python tools/comfy/generate_sfx.py pick coin 104              # pin a seed
python tools/comfy/generate_sfx.py build                      # write art/sfx/*.wav
```

## 12. Out of scope for v1

More tracks, more cars, tournaments, music, split screen, time trial and ghosts are planned as
Phases 9–17 in [`ROADMAP.md`](ROADMAP.md). Touch controls remain out of scope.
