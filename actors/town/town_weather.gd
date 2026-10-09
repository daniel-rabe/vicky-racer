class_name TownWeather
extends Weather
## Rain in Free Drive (docs/DESIGN.md §23): the town's puddles, on Weather's town schedule
## (the first shower after a few minutes, then now and then).

var town: Town:
	set(value):
		town = value
		ground = value
