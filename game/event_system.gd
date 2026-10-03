extends Node
## The one autoload. Every cross-system signal lives here so systems never hold
## references to each other: emitters call EventSystem.<SIGNAL>.emit(...), listeners
## connect in _enter_tree(). Prefixes group signals by domain (see docs/DESIGN.md §6.1).

# Race
signal RAC_countdown_tick(seconds_left: int)
signal RAC_race_started
signal RAC_lap_completed(racer: Node, lap: int, lap_time: float)
signal RAC_positions_updated(order: Array)
signal RAC_race_finished(results: Array)

# Car
signal CAR_drift_started(car: Node)
signal CAR_drift_ended(car: Node, duration: float)
signal CAR_surface_changed(car: Node, surface: StringName)
signal CAR_wall_hit(car: Node, impact_speed: float)

# Progression
signal PRO_coins_changed(total: int)
signal PRO_coins_awarded(amount: int, breakdown: Dictionary)
signal PRO_setup_purchased(setup_id: StringName)
signal PRO_setup_equipped(setup_id: StringName)
signal PRO_purchase_refused(setup_id: StringName, reason: StringName)

# Screens
signal UI_show_message(text: String, duration: float)
signal UI_screen_requested(screen_name: StringName)
