extends Node
## The one autoload. Every cross-system signal lives here so systems never hold
## references to each other: emitters call EventSystem.<SIGNAL>.emit(...), listeners
## connect in _enter_tree(). Prefixes group signals by domain (see docs/DESIGN.md §6.1).

# Race
signal RAC_countdown_tick(seconds_left: int)
signal RAC_race_started
signal RAC_lap_completed(racer: Node, lap: int, lap_time: float)
## The player has just started the last lap (never in a one-lap race).
signal RAC_final_lap_started
signal RAC_positions_updated(order: Array)
## results: one Dictionary per racer, in finishing order — name, colour, is_player,
## position, time, best_lap. GarageManager pays out on it.
signal RAC_race_finished(results: Array, track_id: StringName)
## A time trial is over (instead of RAC_race_finished: nobody else raced, nothing is paid).
## lap_times in order; ghost: the session's best lap, recorded (GarageManager keeps it if it
## is a new record for the track).
signal RAC_time_trial_finished(track_id: StringName, setup_id: StringName, lap_times: Array, ghost: GhostLap)

# Car
signal CAR_drift_started(car: Node)
signal CAR_drift_ended(car: Node, duration: float)
signal CAR_surface_changed(car: Node, surface: StringName)
signal CAR_wall_hit(car: Node, impact_speed: float)
signal CAR_horn(car: Node)
signal CAR_boosted(car: Node)
## Driven through the car wash in Free Drive: foam, then the car sparkles for a while.
signal CAR_washed(car: Node)
## A boat flew off a ramp, and came down again (docs/DESIGN.md §20.2): whoosh, then splash.
signal CAR_jumped(car: Node)
signal CAR_landed(car: Node)
## A comet brushed a ship and pushed it sideways (docs/DESIGN.md §24.2): sparkles and a chime.
signal CAR_comet_nudged(car: Node)

# Space (docs/DESIGN.md §24.2)
## A comet's path has started to glow: it comes in COMET_WARNING seconds.
signal SPC_comet_warned(comet: Node)
## The comet itself is flying along its path now.
signal SPC_comet_passing(comet: Node)

# Progression. Screens never touch GarageManager directly: they emit a *_requested
# signal and listen for PRO_state_changed, which carries the whole garage state.
signal PRO_state_requested
signal PRO_state_changed(state: Dictionary)
signal PRO_buy_requested(setup_id: StringName)
signal PRO_equip_requested(setup_id: StringName)
signal PRO_paint_requested(setup_id: StringName)
signal PRO_track_select_requested(track_id: StringName)
## &"race" or &"time_trial": what the next race on the selected track is (PICK A RACE's switch).
signal PRO_race_mode_requested(mode: StringName)
## &"car", &"boat" or &"ship": which the garage, PICK A RACE and the race show (the title's CARS /
## BOATS / SPACE).
signal PRO_vehicle_kind_requested(kind: StringName)
signal PRO_track_locked(track_id: StringName)
signal PRO_coins_changed(total: int)
signal PRO_coins_awarded(amount: int, breakdown: Dictionary)
## Coins picked up in Free Drive's town (docs/DESIGN.md §19): GarageManager banks them at once.
signal PRO_coins_found(amount: int)
signal PRO_setup_purchased(setup_id: StringName)
signal PRO_setup_equipped(setup_id: StringName)
signal PRO_setup_painted(setup_id: StringName, colour: StringName)
signal PRO_purchase_refused(setup_id: StringName, reason: StringName)
## A new sticker for the book (StickerManager decides, GarageManager saves it). Never twice.
signal PRO_sticker_earned(sticker_id: StringName)

# Cups. Screens ask with CUP_state_requested and get the whole cup state back (as with
# PRO_). CupManager owns the logic; GarageManager stores progress and pays the trophy.
signal CUP_state_requested
signal CUP_state_changed(state: Dictionary)
signal CUP_start_requested(cup_id: StringName)
signal CUP_continue_requested
## progress: what must survive closing the game mid-cup ({} = no cup running).
signal CUP_progress_changed(progress: Dictionary)
## trophy: &"gold", &"silver", &"bronze" or &"ribbon".
signal CUP_finished(cup_id: StringName, standings: Array, trophy: StringName)

# Players: one or two (PlayersManager). Ask with PLY_state_requested, get the whole state
## ({two_player, players, opponents}) on PLY_state_changed.
signal PLY_state_requested
signal PLY_state_changed(state: Dictionary)
## Start a two-player game with nobody joined yet (the title's 2 PLAYERS).
signal PLY_two_player_requested
## device: {"kind": &"keys_left" | &"keys_right" | &"pad", "pad": id}; the next free player takes it.
signal PLY_join_requested(device: Dictionary, setup_id: StringName)
signal PLY_car_requested(player_index: int, setup_id: StringName)
signal PLY_opponents_requested(on: bool)

# Screens
signal UI_show_message(text: String, duration: float)
signal UI_screen_requested(screen_name: StringName)
## Settings follow the same request/answer pattern as the garage: ask with
## UI_settings_requested, get the whole set (Settings.to_dict()) on UI_settings_changed.
signal UI_settings_requested
signal UI_settings_changed(settings: Dictionary)
signal UI_setting_change_requested(key: StringName, value: Variant)
## A screen whose music is not fixed by its name (the race: its track's theme) asks for it.
signal UI_music_requested(piece: MusicPiece)
