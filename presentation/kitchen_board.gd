extends Control

const Definitions := preload("res://content/definitions.gd")
const STATION_NAMES := {"storage": "재료", "cold": "냉식", "hot": "화구", "pass": "제공"}
const STATION_COLORS := {"storage": Color("91734e"), "cold": Color("447e9b"), "hot": Color("b96547"), "pass": Color("638457")}
const STATION_TEXTURES := {"storage": preload("res://assets/m2/storage.svg"), "cold": preload("res://assets/m2/cold.svg"),
	"hot": preload("res://assets/m2/hot.svg"), "pass": preload("res://assets/m2/pass.svg")}
const EMPLOYEE_TEXTURES := {"north": preload("res://assets/m2/employee_north.svg"), "east": preload("res://assets/m2/employee_east.svg"),
	"south": preload("res://assets/m2/employee_south.svg"), "west": preload("res://assets/m2/employee_west.svg")}
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
	var kitchen_rect := Rect2(origin, Vector2(definitions.grid_size) * cell)
	draw_rect(Rect2(kitchen_rect.position + Vector2(0, 3), kitchen_rect.size).grow(5), Color("142425"))
	draw_rect(kitchen_rect.grow(3), Color("a9825b"))
	var obstacles := definitions.blocked_tiles()
	for y: int in definitions.grid_size.y:
		for x: int in definitions.grid_size.x:
			var tile := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(tile) * cell, Vector2.ONE * cell)
			var floor_color := Color("6d8474") if (x + y) % 2 == 0 else Color("748b7a")
			draw_rect(rect, Color("243c3b") if tile in obstacles else floor_color)
			if tile in obstacles:
				draw_line(rect.position + Vector2(1, 1), rect.position + Vector2(cell - 1, 1), Color("3f5650"), 2)
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
			draw_rect(rect.grow(-1), Color("ffe0a3"), false, 3)
		var work_center := origin + (Vector2(station.work_position) + Vector2.ONE * 0.5) * cell
		draw_arc(work_center, cell * 0.3, 0, TAU, 20, Color("d4debe"), 2)
	for index: int in view.get("employees", []).size():
		var employee: Dictionary = view.employees[index]
		var tile := Vector2(employee.tile[0], employee.tile[1])
		var next := Vector2(employee.next_tile[0], employee.next_tile[1])
		var center := origin + (tile.lerp(next, employee.progress / 5.0) + Vector2.ONE * 0.5) * cell
		draw_set_transform(center + Vector2(0, cell * 0.26), 0, Vector2(1, 0.35))
		draw_circle(Vector2.ZERO, cell * 0.28, Color(0.08, 0.14, 0.12, 0.5))
		draw_set_transform(Vector2.ZERO)
		var tint := Color("#fff0c6") if index == 0 else Color("#b8dfec")
		var direction := _employee_direction(employee)
		var texture: Texture2D = EMPLOYEE_TEXTURES[direction]
		draw_texture_rect(texture, Rect2(center - Vector2.ONE * cell * 0.42, Vector2.ONE * cell * 0.84), false, tint)
		if tile != next:
			draw_line(center + (next - tile) * cell * 0.3, center + (next - tile) * cell * 0.43, tint, 3)
		for order: Dictionary in view.get("orders", []):
			if order.id == employee.order_id and order.state == "working":
				draw_arc(center, cell * 0.44, -PI * 0.9, -PI * 0.1, 10, Color("f1c56f"), 3)
		draw_string(font, center + Vector2(-cell * 0.2, cell * 0.31), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, cell * 0.4, roundi(maxi(12, int(cell * 0.3)) * text_scale), Color("182728"))


func _employee_direction(employee: Dictionary) -> String:
	var tile := Vector2i(employee.tile[0], employee.tile[1])
	var next := Vector2i(employee.next_tile[0], employee.next_tile[1])
	if tile != next:
		return _direction_between(tile, next)
	if not employee.order_id.is_empty():
		for task: Dictionary in view.get("tasks", []):
			if task.employee_id != employee.id:
				continue
			for station: Definitions.StationDef in definitions.stations:
				if station.id == task.station_id:
					return _direction_between(tile, station.tile)
	return "south"


func _direction_between(from: Vector2i, to: Vector2i) -> String:
	var offset := to - from
	if abs(offset.x) >= abs(offset.y):
		return "east" if offset.x > 0 else "west"
	return "south" if offset.y > 0 else "north"
