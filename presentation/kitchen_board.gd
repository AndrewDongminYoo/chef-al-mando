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
var employee_badges: Dictionary = {}
var chatter: Dictionary = {}
var chatter_rect := Rect2()


func show_state(data: Definitions, snapshot: Dictionary) -> void:
	definitions = data
	view = snapshot
	employee_badges.clear()
	for employee: Dictionary in view.get("employees", []):
		for order: Dictionary in view.get("orders", []):
			if order.id == employee.order_id:
				employee_badges[employee.id] = {"phase": order.phase_id, "recipe_id": order.recipe_id}
				break
	queue_redraw()


func show_chatter(value: Dictionary) -> void:
	chatter = value.duplicate(true)
	if chatter.is_empty():
		chatter_rect = Rect2()
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
		if employee_badges.has(employee.id):
			_draw_employee_badge(center, cell, employee_badges[employee.id], font, font_size)
		draw_string(font, center + Vector2(-cell * 0.2, cell * 0.31), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, cell * 0.4, roundi(maxi(12, int(cell * 0.3)) * text_scale), Color("182728"))
	if not chatter.is_empty():
		_draw_chatter(kitchen_rect, origin, cell, font, font_size)


func _draw_employee_badge(center: Vector2, cell: float, badge: Dictionary, font: Font, font_size: int) -> void:
	var recipe := definitions.recipe_for(badge.recipe_id)
	var icon_size := cell * 0.32
	if recipe != null and recipe.icon != null:
		draw_texture_rect(recipe.icon, Rect2(center + Vector2(cell * 0.14, -cell * 0.47), Vector2.ONE * icon_size), false)
	var phase_mark := _phase_mark(badge.phase)
	var badge_center := center + Vector2(-cell * 0.28, -cell * 0.32)
	draw_circle(badge_center, cell * 0.17, Color("182728"))
	draw_string(font, badge_center + Vector2(-cell * 0.14, cell * 0.1), phase_mark,
		HORIZONTAL_ALIGNMENT_CENTER, cell * 0.28, mini(font_size, roundi(cell * 0.24)), Color("fff0c6"))


func _phase_mark(phase: String) -> String:
	return tr({"pickup": "재", "prep": "손", "cook": "조", "serve": "출"}.get(phase, ""))


func _draw_chatter(kitchen_rect: Rect2, origin: Vector2, cell: float, font: Font, font_size: int) -> void:
	var anchor := kitchen_rect.get_center()
	for employee: Dictionary in view.get("employees", []):
		if employee.id == chatter.get("employee_id", ""):
			var tile := Vector2(employee.tile[0], employee.tile[1])
			var next := Vector2(employee.next_tile[0], employee.next_tile[1])
			anchor = origin + (tile.lerp(next, employee.progress / 5.0) + Vector2.ONE * 0.5) * cell
			break
	var bubble_font_size := mini(roundi(18 * text_scale), font_size)
	var text_value: String = chatter.get("text", "")
	var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, bubble_font_size)
	var bubble_size := Vector2(minf(text_size.x + 20.0, kitchen_rect.size.x - 12.0), text_size.y + 14.0)
	chatter_rect = _place_chatter(kitchen_rect, origin, cell, anchor, bubble_size)
	draw_rect(chatter_rect, Color("fff5d6"))
	draw_rect(chatter_rect, Color("5b3b2d"), false, 2.0)
	draw_string(font, chatter_rect.position + Vector2(10.0, bubble_size.y - 8.0), text_value,
		HORIZONTAL_ALIGNMENT_CENTER, bubble_size.x - 20.0, bubble_font_size, Color("35251f"))


func _place_chatter(kitchen_rect: Rect2, origin: Vector2, cell: float, anchor: Vector2, bubble_size: Vector2) -> Rect2:
	var candidates: Array[Vector2] = [
		anchor + Vector2(-bubble_size.x * 0.5, -cell * 0.55 - bubble_size.y),
		anchor + Vector2(-bubble_size.x * 0.5, cell * 0.55),
		anchor + Vector2(-cell * 0.55 - bubble_size.x, -bubble_size.y * 0.5),
		anchor + Vector2(cell * 0.55, -bubble_size.y * 0.5),
	]
	var step := maxi(4, roundi(cell * 0.5))
	for y: int in range(roundi(kitchen_rect.position.y + 6.0), roundi(kitchen_rect.end.y - bubble_size.y - 5.0), step):
		for x: int in range(roundi(kitchen_rect.position.x + 6.0), roundi(kitchen_rect.end.x - bubble_size.x - 5.0), step):
			candidates.append(Vector2(x, y))
	var best := Rect2(_clamp_chatter_position(candidates[0], kitchen_rect, bubble_size), bubble_size)
	var best_overlap := _chatter_overlap_area(best, origin, cell)
	var best_distance := best.get_center().distance_squared_to(anchor)
	for candidate_position: Vector2 in candidates:
		var candidate := Rect2(_clamp_chatter_position(candidate_position, kitchen_rect, bubble_size), bubble_size)
		var overlap := _chatter_overlap_area(candidate, origin, cell)
		var distance := candidate.get_center().distance_squared_to(anchor)
		if overlap < best_overlap or (is_equal_approx(overlap, best_overlap) and distance < best_distance):
			best = candidate
			best_overlap = overlap
			best_distance = distance
	return best


func _clamp_chatter_position(position: Vector2, kitchen_rect: Rect2, bubble_size: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, kitchen_rect.position.x + 6.0, kitchen_rect.end.x - bubble_size.x - 6.0),
		clampf(position.y, kitchen_rect.position.y + 6.0, kitchen_rect.end.y - bubble_size.y - 6.0))


func _chatter_overlap_area(rect: Rect2, origin: Vector2, cell: float) -> float:
	var overlap := 0.0
	for station: Definitions.StationDef in definitions.stations:
		overlap += rect.intersection(Rect2(origin + Vector2(station.tile) * cell, Vector2.ONE * cell)).get_area()
	for employee: Dictionary in view.get("employees", []):
		var tile := Vector2(employee.tile[0], employee.tile[1])
		var next := Vector2(employee.next_tile[0], employee.next_tile[1])
		var center := origin + (tile.lerp(next, employee.progress / 5.0) + Vector2.ONE * 0.5) * cell
		overlap += rect.intersection(Rect2(center - Vector2.ONE * cell * 0.42, Vector2.ONE * cell * 0.84)).get_area()
	return overlap


func chatter_obscures_content() -> bool:
	if definitions == null or chatter_rect.size == Vector2.ZERO:
		return false
	var cell := minf((size.x - 16.0) / definitions.grid_size.x, (size.y - 16.0) / definitions.grid_size.y)
	var origin := (size - Vector2(definitions.grid_size) * cell) / 2.0
	return _chatter_overlap_area(chatter_rect, origin, cell) > 0.0


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
