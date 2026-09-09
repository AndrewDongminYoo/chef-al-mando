extends Control

const Definitions := preload("res://content/definitions.gd")
const STATION_NAMES := {"storage": "재료", "cold": "냉식", "hot": "화구", "pass": "제공"}
const STATION_COLORS := {"storage": Color("91734e"), "cold": Color("447e9b"), "hot": Color("b96547"), "pass": Color("638457")}
const STATION_TEXTURES := {"storage": preload("res://assets/m2/storage.svg"), "cold": preload("res://assets/m2/cold.svg"),
	"hot": preload("res://assets/m2/hot.svg"), "pass": preload("res://assets/m2/pass.svg")}
const EMPLOYEE_TEXTURE := preload("res://assets/m2/employee.svg")
var definitions: Definitions
var view: Dictionary = {}
var selected_station_id: String = ""
var text_scale: float = 1.0


func show_state(data: Definitions, snapshot: Dictionary) -> void:
	definitions = data
	view = snapshot
	queue_redraw()


func _draw() -> void:
	if definitions == null:
		return
	var cell := minf((size.x - 16.0) / definitions.grid_size.x, (size.y - 16.0) / definitions.grid_size.y)
	if cell <= 0:
		return
	var origin := (size - Vector2(definitions.grid_size) * cell) / 2.0
	var obstacles := definitions.blocked_tiles()
	for y: int in definitions.grid_size.y:
		for x: int in definitions.grid_size.x:
			var tile := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(tile) * cell, Vector2.ONE * cell)
			draw_rect(rect.grow(-1), Color("273839") if tile in obstacles else Color("51605b"))
	var font := get_theme_default_font()
	var font_size := clampi(int(cell * 0.42 * text_scale), 14, roundi(24 * text_scale))
	var illustrated := definitions.supports_preparation()
	for station: Definitions.StationDef in definitions.stations:
		var rect := Rect2(origin + Vector2(station.tile) * cell, Vector2.ONE * cell)
		if illustrated:
			var facing := Vector2(station.work_position - station.tile).angle() - PI / 2.0
			draw_set_transform(rect.get_center(), facing)
			draw_texture_rect(STATION_TEXTURES[station.role], Rect2(-rect.size * 0.5, rect.size), false)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_rect(rect.grow(-2), STATION_COLORS[station.role])
			draw_string(font, rect.position + Vector2(2, cell * 0.65), tr(STATION_NAMES[station.role]), HORIZONTAL_ALIGNMENT_CENTER, cell - 4, font_size)
		if station.id == selected_station_id:
			draw_rect(rect.grow(-1), Color("f2dba0"), false, 3)
		var work_center := origin + (Vector2(station.work_position) + Vector2.ONE * 0.5) * cell
		draw_arc(work_center, cell * 0.3, 0, TAU, 20, Color("b7c7b6"), 2)
	for index: int in view.get("employees", []).size():
		var employee: Dictionary = view.employees[index]
		var tile := Vector2(employee.tile[0], employee.tile[1])
		var next := Vector2(employee.next_tile[0], employee.next_tile[1])
		var center := origin + (tile.lerp(next, employee.progress / 5.0) + Vector2.ONE * 0.5) * cell
		if illustrated:
			draw_set_transform(center + Vector2(0, cell * 0.26), 0, Vector2(1, 0.35))
			draw_circle(Vector2.ZERO, cell * 0.28, Color(0.08, 0.14, 0.12, 0.5))
			draw_set_transform(Vector2.ZERO)
			var tint := Color("#fff0c6") if index == 0 else Color("#b8dfec")
			draw_texture_rect(EMPLOYEE_TEXTURE, Rect2(center - Vector2.ONE * cell * 0.42, Vector2.ONE * cell * 0.84), false, tint)
			if tile != next:
				draw_line(center + (next - tile) * cell * 0.3, center + (next - tile) * cell * 0.43, tint, 3)
			for order: Dictionary in view.get("orders", []):
				if order.id == employee.order_id and order.state == "working":
					draw_arc(center, cell * 0.44, -PI * 0.9, -PI * 0.1, 10, Color("f1c56f"), 3)
			draw_string(font, center + Vector2(-cell * 0.2, cell * 0.31), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, cell * 0.4, maxi(12, int(cell * 0.3)), Color("182728"))
		else:
			draw_circle(center, cell * 0.29, Color("f2dba0") if index == 0 else Color("b1d3e6"))
			draw_string(font, center + Vector2(-cell * 0.25, font_size * 0.35), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, cell * 0.5, font_size, Color("182728"))
