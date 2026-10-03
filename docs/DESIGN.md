# Vicky Racer — Design Document

A 2D top-down arcade racer for a young child, built in **Godot 4.7** (Forward+ renderer). The
player races three AI cars around tile-built circuits, earns coins by finishing, and spends them in
a garage on drift setups that change how the car handles. All art is generated locally with
ComfyUI from a single frozen recipe.

This document is written ahead of the code. Every system is marked **(not implemented)** until it
lands, and the markers come off as it does. Mockups referenced here live in
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

Both keyboard layouts are always live, so two hands can find the controls without being taught.
Steering reads `Input.get_axis`, which gives analog steering on a stick for free. Menu glyphs swap
between keyboard and gamepad depending on which was used last.

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
  marks and the drift sound hang off those signals.

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
even Banana stays drivable. The three **bar values** are authored, not computed: they describe how
the setup *feels*, which is what the garage needs to communicate.

## 5. Scale

| Thing | Size | Why |
| --- | --- | --- |
| Tile | 128 px | Large enough that generated textures keep their character; a 48 × 28 map stays manageable in the editor |
| Road | 3 tiles (384 px) | Room for two cars side by side plus a mistake |
| Car sprite | 128 × 72 px, facing +X | Godot 2D's zero rotation; reads clearly against a 384 px road |
| Car collision | 110 × 60 px rectangle | Slightly inside the sprite so contact looks fair |
| Viewport | 1920 × 1080, `canvas_items` / `expand` | Already set in `project.godot` |
| Camera zoom | 1.0, easing to 0.85 at top speed | About 15 × 8 tiles visible. Matches the chosen style frame, where cars read at ~130–160 px on screen; 0.75 made them feel distant. The camera leads toward the direction of travel and zooms out with speed, which gives back the lookahead |

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
| `UI_` | Screens | `show_message(text, duration)`, `screen_requested(name)` |

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
└── ScreenSlot           swaps on UI_screen_requested(&"garage" | &"race" | &"results"):
    ├── garage_screen.tscn
    ├── race.tscn
    │   ├── Track (track_01.tscn)
    │   ├── RacerSpawner      places 4 cars on the grid
    │   ├── RaceManager       countdown, laps, positions, rubber-banding, finish
    │   └── RaceHUD + Minimap
    └── results_screen.tscn
```

`GarageManager` lives in the shell rather than becoming a second autoload, keeping to the one-
autoload rule while still surviving every screen swap.

### 6.3 Drivers

`car.gd` exposes three plain fields — `steer_input`, `throttle_input`, `handbrake` — and knows
nothing about who sets them. `player_input.gd` and `ai_driver.gd` are interchangeable children that
write into those fields. The same car scene is used for all four racers.

## 7. Track **(not implemented)**

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

Image generation makes none of this geometry — it is exactly what diffusion does worst. Generated
art is limited to the cars, props and UI illustrations.

### 7.3 Surfaces

The car checks what it is on every physics frame:

1. **On the road?** Distance from the car to the racing line (`Curve2D.get_closest_point`) is under
   the road's half-width → asphalt. Kerbs count as asphalt.
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

## 8. AI **(not implemented)**

Each AI car runs `ai_driver.gd`, writing the same three inputs a player would:

1. **Steer** toward a point on the racing line, a speed-scaled distance ahead.
2. **Read the road ahead** — sample the curve further on, measure how sharply it turns, lift and
   brake into tight corners, full throttle on straights.
3. **Spread out** — each car has its own `line_offset` so the pack does not drive in single file; a
   short forward ray nudges that offset sideways to avoid rear-ending.
4. **Skill** — `skill` 0–1 scales top speed, lookahead and line accuracy. Default spread for track
   01: 0.55 / 0.7 / 0.85.
5. **Rubber-banding** — `RaceManager` gives each AI a speed multiplier from its gap to the player:
   cars far ahead ease off, cars far behind push. The pack stays in sight; the player can still win.

## 9. Garage and economy

### 9.1 Earning

| Finish | Coins |
| --- | --- |
| 1st | 100 |
| 2nd | 75 |
| 3rd | 60 |
| 4th | 50 |
| First time finishing a track | +100 once |

The floor is deliberately generous: a child finishing last every time still affords **Grippy**
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
| Race HUD **(not implemented)** | [`mockups/hud_layout.png`](mockups/hud_layout.png) — position, lap, timers, speed bar, minimap, countdown |
| Garage | [`mockups/garage_layout.png`](mockups/garage_layout.png) — balance, 3 × 2 setup cards, preview with Grip / Slide / Speed bars. Built: [`screenshots/garage.png`](screenshots/garage.png) |
| Results | [`mockups/results_layout.png`](mockups/results_layout.png) — finishing order, payout count-up, Race Again. Built: [`screenshots/results.png`](screenshots/results.png) |

Pink annotations on each spec give anchors, sizes and animation timings; they are meant to be
built verbatim with `Control` anchors. All menus are fully navigable with a gamepad alone.

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

## 12. Out of scope for v1

- More than one track
- Car body selection (setups change handling, not the car)
- Engine and tyre sounds (stretch goal — a local SFX model is installed)
- Lap ghosts, time-trial mode, split-screen
- Touch controls
