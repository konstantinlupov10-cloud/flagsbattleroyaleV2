extends Node2D
## Root scene. Only job at this milestone is the explicit, non-auto-run start
## call -- the arena/physics bridge and UI get wired in starting milestone 3.

func _ready() -> void:
	GameManager.start_game()
