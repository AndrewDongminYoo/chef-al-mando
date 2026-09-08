extends Resource

const IngredientDef := preload("res://content/ingredient_def.gd")
const RecipeDef := preload("res://content/recipe_def.gd")
const StationDef := preload("res://content/station_def.gd")
const EmployeeDef := preload("res://content/employee_def.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")

@export var id: String = ""
@export var seed: int = 0
@export var closing_tick: int = 0
@export var starting_budget: int = 0
@export var labor_cost: int = 0
@export var grid_size: Vector2i = Vector2i.ZERO
@export var extra_obstacles: Array[Vector2i] = []
@export var ingredients: Array[IngredientDef] = []
@export var recipes: Array[RecipeDef] = []
@export var stations: Array[StationDef] = []
@export var employees: Array[EmployeeDef] = []
@export var purchases: Dictionary[String, int] = {}
@export var menu_ids: PackedStringArray = PackedStringArray()
@export var order_count: int = 0
@export var first_arrival_tick: int = 0
@export var arrival_interval_ticks: int = 0
@export var prep_labor_capacity: int = 0


func validate(require_stock: bool = true) -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty() or closing_tick <= 0 or starting_budget < 0 or labor_cost < 0 or prep_labor_capacity < 0:
		errors.append("invalid scenario values")
	if order_count <= 0 or first_arrival_tick <= 0 or arrival_interval_ticks <= 0:
		errors.append("invalid arrival schedule")
	elif first_arrival_tick + arrival_interval_ticks * (order_count - 1) > closing_tick:
		errors.append("orders must arrive no later than closing")
	_check_ids(ingredients, "ingredient", errors)
	_check_ids(recipes, "recipe", errors)
	_check_ids(stations, "station", errors)
	_check_ids(employees, "employee", errors)
	var ingredient_ids: Dictionary[String, bool] = {}
	for ingredient: IngredientDef in ingredients:
		if ingredient == null:
			continue
		ingredient_ids[ingredient.id] = true
		if ingredient.unit_cost < 0:
			errors.append("negative ingredient cost: " + ingredient.id)
	for ingredient_id: String in purchases:
		if not ingredient_ids.has(ingredient_id) or purchases[ingredient_id] < 0:
			errors.append("invalid purchase: " + ingredient_id)
		elif not ingredient_for(ingredient_id).purchasable:
			errors.append("prepared ingredients cannot be purchased: " + ingredient_id)
	var roles: Dictionary[String, bool] = {}
	for station: StationDef in stations:
		if station != null:
			if station.role not in ["storage", "cold", "hot", "pass"]:
				errors.append("invalid station role: " + station.id)
			else:
				roles[station.role] = true
	var prepared_ids: Dictionary[String, bool] = {}
	for recipe: RecipeDef in recipes:
		if recipe == null:
			continue
		if recipe.revenue < 0 or recipe.patience_ticks <= 0 or recipe.cook_role not in ["cold", "hot"] or not roles.has(recipe.cook_role):
			errors.append("invalid recipe values: " + recipe.id)
		for ingredient_id: String in recipe.ingredients:
			if not ingredient_ids.has(ingredient_id) or recipe.ingredients[ingredient_id] < 0:
				errors.append("invalid recipe ingredient: " + ingredient_id)
		var has_preparation := not recipe.prepared_ingredient_id.is_empty()
		if has_preparation:
			var prepared := ingredient_for(recipe.prepared_ingredient_id)
			if prepared == null or prepared.purchasable or prepared_ids.has(recipe.prepared_ingredient_id):
				errors.append("invalid prepared ingredient: " + recipe.id)
			prepared_ids[recipe.prepared_ingredient_id] = true
			if recipe.prep_labor_units <= 0 or recipe.ingredients.is_empty():
				errors.append("invalid preparation inputs or labor: " + recipe.id)
			var input_cost: int = 0
			for ingredient_id: String in recipe.ingredients:
				var ingredient := ingredient_for(ingredient_id)
				if ingredient == null or not ingredient.purchasable or recipe.ingredients[ingredient_id] <= 0:
					errors.append("preparation requires raw ingredients: " + recipe.id)
				else:
					input_cost += ingredient.unit_cost * recipe.ingredients[ingredient_id]
			if prepared != null and prepared.unit_cost != input_cost:
				errors.append("prepared ingredient cost must equal its raw input cost: " + recipe.id)
		elif recipe.prep_labor_units != 0:
			errors.append("preparation labor requires a prepared ingredient: " + recipe.id)
		_check_ids(recipe.processes, "process", errors)
		var ordered_processes := recipe.ordered_processes()
		if ordered_processes.is_empty():
			errors.append("processes must form one complete linear chain: " + recipe.id)
		else:
			var process_ids: Array[String] = []
			for process: RecipeDef.ProcessDef in ordered_processes:
				process_ids.append(process.id)
			var required_phases: Array[String] = ["pickup", "cook", "serve"]
			if has_preparation:
				required_phases.insert(1, "prep")
			if process_ids != required_phases:
				errors.append("processes must follow the supported recipe phases: " + recipe.id)
		var phase_roles := {"pickup": "storage", "cook": recipe.cook_role, "serve": "pass"}
		if has_preparation:
			phase_roles["prep"] = "cold"
		for process: RecipeDef.ProcessDef in recipe.processes:
			if process == null:
				continue
			if process.duration_ticks <= 0 or not roles.has(process.station_role):
				errors.append("invalid process duration or station role: " + process.id)
			if phase_roles.has(process.id) and process.station_role != phase_roles[process.id]:
				errors.append("incorrect station role for M1 process: " + process.id)
	if menu_ids.is_empty():
		errors.append("scenario menus must not be empty")
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe == null:
			errors.append("unknown scenario menu: " + recipe_id)
			continue
		if require_stock:
			for ingredient_id: String in recipe.ingredients:
				if purchases.get(ingredient_id, 0) < recipe.ingredients[ingredient_id]:
					errors.append("scenario cannot sell menu: " + recipe_id)
	if grid_size.x < 3 or grid_size.y < 3:
		errors.append("invalid kitchen grid size")
		return errors
	var routes := GridRoutes.new(grid_size, blocked_tiles())
	for employee: EmployeeDef in employees:
		if employee != null and not routes.is_walkable(employee.starting_tile):
			errors.append("invalid employee starting tile: " + employee.id)
	var reference_station: StationDef = null
	for station: StationDef in stations:
		if station == null:
			continue
		if not Rect2i(Vector2i.ZERO, grid_size).has_point(station.tile):
			errors.append("station tile is outside the kitchen: " + station.id)
		if reference_station == null:
			reference_station = station
		elif routes.path_between(reference_station.work_position, station.work_position).is_empty():
			errors.append("station is disconnected from the kitchen: " + station.id)
		var reachable: bool = false
		for employee: EmployeeDef in employees:
			if employee != null and not routes.path_between(employee.starting_tile, station.work_position).is_empty():
				reachable = true
		if not reachable:
			errors.append("unreachable station: " + station.id)
	if supports_preparation():
		var placement_reason := placement_error()
		if not placement_reason.is_empty():
			errors.append(placement_reason)
	return errors


func supports_preparation() -> bool:
	for recipe: RecipeDef in recipes:
		if recipe != null and not recipe.prepared_ingredient_id.is_empty():
			return true
	return false


# cspell:ignore absi
func placement_error() -> String:
	if grid_size.x < 3 or grid_size.y < 3 or stations.is_empty() or employees.is_empty():
		return "invalid_layout"
	var interior := Rect2i(Vector2i.ONE, grid_size - Vector2i(2, 2))
	var occupied: Array[Vector2i] = []
	for station: StationDef in stations:
		if station == null:
			return "invalid_layout"
		if not interior.has_point(station.tile):
			return "outside_kitchen"
		if station.tile in occupied or station.tile in extra_obstacles:
			return "station_overlap"
		occupied.append(station.tile)
		var offset := station.work_position - station.tile
		if absi(offset.x) + absi(offset.y) != 1:
			return "invalid_work_position"
	var routes := GridRoutes.new(grid_size, blocked_tiles())
	for station: StationDef in stations:
		if not routes.is_walkable(station.work_position):
			return "blocked_work_position"
		if routes.path_between(stations[0].work_position, station.work_position).is_empty():
			return "no_route"
	for employee: EmployeeDef in employees:
		if employee == null or not routes.is_walkable(employee.starting_tile):
			return "employee_start_blocked"
		if routes.path_between(employee.starting_tile, stations[0].work_position).is_empty():
			return "no_route"
	return ""


func _check_ids(items: Array, kind: String, errors: Array[String]) -> void:
	var seen: Dictionary[String, bool] = {}
	if items.is_empty():
		errors.append("empty definitions: " + kind)
	for item: Resource in items:
		if item == null:
			errors.append("missing definition: " + kind)
			continue
		var item_id: String = item.get("id")
		if item_id.is_empty() or seen.has(item_id):
			errors.append("empty or duplicate ID: " + kind)
		seen[item_id] = true


func blocked_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in grid_size.y:
		for x: int in grid_size.x:
			if x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1:
				result.append(Vector2i(x, y))
	for station: StationDef in stations:
		if station != null:
			result.append(station.tile)
	result.append_array(extra_obstacles)
	return result


func purchased_cost() -> int:
	var total: int = 0
	for ingredient: IngredientDef in ingredients:
		total += ingredient.unit_cost * purchases.get(ingredient.id, 0)
	return total


func recipe_for(recipe_id: String) -> RecipeDef:
	for recipe: RecipeDef in recipes:
		if recipe != null and recipe.id == recipe_id:
			return recipe
	return null


func ingredient_for(ingredient_id: String) -> IngredientDef:
	for ingredient: IngredientDef in ingredients:
		if ingredient != null and ingredient.id == ingredient_id:
			return ingredient
	return null


func order_schedule() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in order_count:
		var recipe := recipe_for(menu_ids[posmod(index + seed, menu_ids.size())])
		var arrival_tick := first_arrival_tick + arrival_interval_ticks * index
		result.append({
			"id": "order_%02d" % (index + 1),
			"arrival_tick": arrival_tick,
			"recipe_id": recipe.id,
			"deadline_tick": arrival_tick + recipe.patience_ticks,
		})
	return result
