extends Control
class_name SunburstRays
## Simple radial "shining" background behind the champion reveal card --
## alternating triangular rays drawn once from the control's own center, then
## just rotated by the parent (ChampionReveal._process()) rather than
## redrawn every frame -- Godot re-renders an already-drawn CanvasItem's
## content under its updated transform for free, no per-frame draw_polygon()
## calls needed for the spin itself.

const RAY_COUNT := 24
const RAY_COLOR := Color(1.0, 0.85, 0.35, 0.10)

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = size.length() * 0.6
	var angle_step: float = TAU / float(RAY_COUNT)
	for i in range(RAY_COUNT):
		if i % 2 != 0:
			continue
		var a0: float = angle_step * i
		var a1: float = angle_step * (i + 1)
		var p1: Vector2 = center + Vector2(cos(a0), sin(a0)) * radius
		var p2: Vector2 = center + Vector2(cos(a1), sin(a1)) * radius
		draw_polygon(PackedVector2Array([center, p1, p2]), PackedColorArray([RAY_COLOR]))
