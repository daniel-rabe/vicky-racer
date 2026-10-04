class_name EconomyConfig
extends Resource
## Every coin number in one place (docs/DESIGN.md §9.1). The floor is deliberately
## generous: a child finishing last every race still affords the cheapest setup after
## two races. Winning just gets there faster.

## Coins by finishing position: index 0 = 1st place.
@export var place_payouts: Array[int] = [100, 75, 60, 50]
## Paid once per track, the first time the player finishes it.
@export var first_finish_bonus := 100
## Paid at the end of a cup, by the trophy won (docs/DESIGN.md §12). Finishing at all earns
## the ribbon's coins: nobody is ever told they lost.
@export var cup_bonus := {&"gold": 300, &"silver": 200, &"bronze": 150, &"ribbon": 100}
## Coins in a brand-new save.
@export var starting_coins := 0


## Coins for one finish, itemised so the results screen can show each line.
func payout(position: int, first_finish: bool) -> Dictionary:
	var place := place_payouts[clampi(position - 1, 0, place_payouts.size() - 1)]
	var breakdown := {"place": place}
	if first_finish:
		breakdown["first_finish"] = first_finish_bonus
	return breakdown
