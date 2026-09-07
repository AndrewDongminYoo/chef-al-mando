extends RefCounted

var grid := AStarGrid2D.new()


func _init(size: Vector2i, obstacles: Array[Vector2i]) -> void:
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for tile: Vector2i in obstacles:
		if grid.region.has_point(tile):
			grid.set_point_solid(tile)


func is_walkable(tile: Vector2i) -> bool:
	return grid.region.has_point(tile) and not grid.is_point_solid(tile)


func path_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(from) or not is_walkable(to):
		return []
	return grid.get_id_path(from, to)
