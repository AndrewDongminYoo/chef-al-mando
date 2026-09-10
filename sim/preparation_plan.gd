extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const DIRECTIONS := {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}
const ROTATION: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DUTIES: Array[String] = ["all", "cold", "hot", "off"]

var _source: Definitions
var _choices: Dictionary = {}
var _errors: Array[String] = []
var _sequence: int = 0
var _committed: bool = false


func _init(data: Definitions, selection: Dictionary = {}) -> void:
	_source = data
	_errors = data.validate(false)
	if not _errors.is_empty():
		return
	_choices = _defaults()
	if not selection.is_empty():
		if not _valid_selection_shape(selection):
			_errors.append("invalid_preparation")
			return
		_choices = selection.duplicate(true)
		if not _choices.has("menu_priorities"):
			_choices.menu_priorities = _defaults().menu_priorities
	var placement_reason := _placement_error(_choices)
	if not placement_reason.is_empty():
		_errors.append(placement_reason)
		return
	_errors = initial_state(_definition(_choices), _options(_choices), false).errors


func _defaults() -> Dictionary:
	var placements: Dictionary = {}
	var quantities: Dictionary[String, int] = {}
	var duties: Dictionary[String, String] = {}
	var priorities: Dictionary[String, int] = {}
	for recipe_id: String in _source.menu_ids:
		priorities[recipe_id] = 1
	for station: Definitions.StationDef in _source.stations:
		placements[station.id] = {"tile": _array(station.tile), "work_position": _array(station.work_position)}
	for recipe: Definitions.RecipeDef in _source.recipes:
		if not recipe.prepared_ingredient_id.is_empty():
			quantities[recipe.id] = 0
	for employee: Definitions.EmployeeDef in _source.employees:
		duties[employee.id] = "all"
	return {"purchases": _source.purchases.duplicate(), "prep_quantities": quantities, "placements": placements, "duties": duties, "menu_priorities": priorities}


func _valid_selection_shape(selection: Dictionary) -> bool:
	if selection.size() != (5 if selection.has("menu_priorities") else 4):
		return false
	if selection.has("menu_priorities") and not selection.menu_priorities is Dictionary:
		return false
	for field: String in ["purchases", "prep_quantities", "placements", "duties"]:
		if not selection.get(field) is Dictionary:
			return false
	for ingredient_id: Variant in selection.purchases:
		if not ingredient_id is String or not selection.purchases[ingredient_id] is int:
			return false
	if selection.placements.size() != _source.stations.size():
		return false
	for station: Definitions.StationDef in _source.stations:
		var placement: Variant = selection.placements.get(station.id)
		if not placement is Dictionary:
			return false
		for field: String in ["tile", "work_position"]:
			var coordinates: Variant = placement.get(field)
			if not coordinates is Array or coordinates.size() != 2 or not coordinates[0] is int or not coordinates[1] is int:
				return false
	return true


func _definition(selection: Dictionary) -> Definitions:
	var data := _source.duplicate() as Definitions
	data.purchases = {}
	data.purchases.assign(selection.purchases)
	data.stations = []
	for original: Definitions.StationDef in _source.stations:
		var station := original.duplicate() as Definitions.StationDef
		var placement: Dictionary = selection.placements[station.id]
		station.tile = _vector(placement.tile)
		station.work_position = _vector(placement.work_position)
		data.stations.append(station)
	return data


func display_definition() -> Definitions:
	return null if not _errors.is_empty() else _definition(_choices)


func _placement_error(selection: Dictionary) -> String:
	for station: Definitions.StationDef in _source.stations:
		if station.fixed:
			var placement: Dictionary = selection.placements[station.id]
			if _vector(placement.tile) != station.tile or _vector(placement.work_position) != station.work_position:
				return "fixed_station"
	return _definition(selection).placement_error()


static func _options(selection: Dictionary) -> Dictionary:
	return {"prep_quantities": selection.prep_quantities.duplicate(), "duties": selection.duties.duplicate(),
		"menu_priorities": selection.menu_priorities.duplicate()}


func apply_command(command: Dictionary) -> Dictionary:
	if _committed:
		return _rejected("service_started")
	if not _errors.is_empty():
		return _rejected("invalid_content")
	for field: String in ["kind", "target_id", "value", "apply_tick", "sequence"]:
		if not command.has(field):
			return _rejected("invalid_command")
	if not command.kind is String or not command.target_id is String or not command.apply_tick is int or not command.sequence is int:
		return _rejected("invalid_command")
	if command.apply_tick != 0 or command.sequence <= _sequence:
		return _rejected("invalid_command_order")
	var candidate := _choices.duplicate(true)
	var target: String = command.target_id
	match command.kind:
		"set_purchase":
			var ingredient := _source.ingredient_for(target)
			if ingredient == null or not ingredient.purchasable or not command.value is int or command.value < 0:
				return _rejected("invalid_purchase")
			candidate.purchases[target] = command.value
		"set_prep":
			var recipe := _source.recipe_for(target)
			if recipe == null or recipe.prepared_ingredient_id.is_empty() or not command.value is int or command.value < 0:
				return _rejected("invalid_preparation")
			candidate.prep_quantities[target] = command.value
		"set_duty":
			if not candidate.duties.has(target) or not command.value is String or command.value not in DUTIES:
				return _rejected("invalid_duty")
			candidate.duties[target] = command.value
		"set_menu_priority":
			if not candidate.menu_priorities.has(target) or not command.value is int or command.value < 0 or command.value > 2:
				return _rejected("invalid_priority")
			candidate.menu_priorities[target] = command.value
		"move_station", "rotate_station":
			if not candidate.placements.has(target):
				return _rejected("unknown_station")
			var placement: Dictionary = candidate.placements[target]
			var tile := _vector(placement.tile)
			var work := _vector(placement.work_position)
			if command.kind == "move_station":
				if not command.value is String or not DIRECTIONS.has(command.value):
					return _rejected("invalid_direction")
				placement.tile = _array(tile + DIRECTIONS[command.value])
				placement.work_position = _array(work + DIRECTIONS[command.value])
			else:
				if command.value != null:
					return _rejected("invalid_command")
				placement.work_position = _array(tile + ROTATION[(ROTATION.find(work - tile) + 1) % 4])
			var placement_reason := _placement_error(candidate)
			if not placement_reason.is_empty():
				return _rejected(placement_reason)
		"reset":
			candidate = _defaults()
		"start":
			pass
		_:
			return _rejected("unknown_command")
	var data := _definition(candidate)
	var resolved := initial_state(data, _options(candidate), command.kind == "start")
	if not resolved.errors.is_empty():
		return _rejected(resolved.errors[0])
	_choices = candidate
	_sequence = command.sequence
	if command.kind == "start":
		_committed = true
		return {"accepted": true, "reason": "", "definitions": data, "options": _options(candidate),
			"inventory": resolved.inventory.duplicate(), "selection": candidate.duplicate(true)}
	return {"accepted": true, "reason": ""}


func snapshot() -> Dictionary:
	if not _errors.is_empty():
		return {"can_start": false, "errors": _errors.duplicate(), "committed": _committed,
			"sequence": _sequence, "inventory": {}, "stations": [], "duties": {}}
	var data := _definition(_choices)
	var resolved := initial_state(data, _options(_choices))
	var stations: Array[Dictionary] = []
	for station: Definitions.StationDef in data.stations:
		stations.append({"id": station.id, "name": station.display_name,
			"tile": _array(station.tile), "work_position": _array(station.work_position),
			"fixed": station.fixed, "placement_options": _placement_options(station) if data.space_rules else {}})
	return {"can_start": resolved.errors.is_empty() and not _committed, "errors": resolved.errors.duplicate(),
		"space_rules": data.space_rules,
		"committed": _committed, "sequence": _sequence, "purchases": _choices.purchases.duplicate(),
		"prep_quantities": _choices.prep_quantities.duplicate(), "inventory": resolved.inventory.duplicate(),
		"menu_priorities": _choices.menu_priorities.duplicate(),
		"labor_used": resolved.labor_used, "labor_capacity": data.prep_labor_capacity,
		"purchased_cost": data.purchased_cost(), "budget_remaining": data.starting_budget - data.labor_cost - data.purchased_cost(),
		"stations": stations, "duties": _choices.duties.duplicate(), "selection": _choices.duplicate(true)}


func _placement_options(station: Definitions.StationDef) -> Dictionary:
	var options: Dictionary = {}
	for direction: String in ["up", "left", "down", "right", "rotate"]:
		if station.fixed:
			options[direction] = "fixed_station"
			continue
		var candidate := _choices.duplicate(true)
		var placement: Dictionary = candidate.placements[station.id]
		if direction == "rotate":
			var offset := station.work_position - station.tile
			placement.work_position = _array(station.tile + ROTATION[(ROTATION.find(offset) + 1) % 4])
		else:
			placement.tile = _array(station.tile + DIRECTIONS[direction])
			placement.work_position = _array(station.work_position + DIRECTIONS[direction])
		options[direction] = _placement_error(candidate)
	return options


static func initial_state(data: Definitions, options: Dictionary = {}, require_stock: bool = true) -> Dictionary:
	var errors := data.validate(false)
	var inventory: Dictionary[String, int] = {}
	var duties: Dictionary[String, String] = {}
	var priorities: Dictionary[String, int] = {}
	var result := {"errors": errors, "inventory": inventory, "duties": duties, "menu_priorities": priorities, "labor_used": 0}
	if not errors.is_empty():
		return result
	for ingredient: Definitions.IngredientDef in data.ingredients:
		inventory[ingredient.id] = data.purchases.get(ingredient.id, 0)
	for employee: Definitions.EmployeeDef in data.employees:
		duties[employee.id] = "all"
	var remaining_budget := data.starting_budget - data.labor_cost
	if remaining_budget < 0:
		errors.append("insufficient_budget")
		return result
	for ingredient: Definitions.IngredientDef in data.ingredients:
		var quantity: int = data.purchases.get(ingredient.id, 0)
		if ingredient.unit_cost > 0 and quantity > remaining_budget / ingredient.unit_cost:
			errors.append("insufficient_budget")
			return result
		remaining_budget -= quantity * ingredient.unit_cost
	for field: Variant in options:
		if field not in ["prep_quantities", "duties", "menu_priorities"] or not options[field] is Dictionary:
			errors.append("invalid_preparation")
			return result
	for recipe_id: String in data.menu_ids:
		priorities[recipe_id] = 1
	if options.has("menu_priorities"):
		if options.menu_priorities.size() != priorities.size():
			errors.append("invalid_priority")
			return result
		for recipe_id: Variant in options.menu_priorities:
			var priority: Variant = options.menu_priorities[recipe_id]
			if not recipe_id is String or not priorities.has(recipe_id) or not priority is int or priority < 0 or priority > 2:
				errors.append("invalid_priority")
				return result
			priorities[recipe_id] = priority
	var quantities: Dictionary = options.get("prep_quantities", {})
	var required: Dictionary[String, int] = {}
	var labor_used: int = 0
	var ordered_ids: Array = quantities.keys()
	ordered_ids.sort()
	for recipe_id: Variant in ordered_ids:
		if not recipe_id is String or not quantities[recipe_id] is int or quantities[recipe_id] < 0:
			errors.append("invalid_preparation")
			return result
		var recipe := data.recipe_for(recipe_id)
		if recipe == null or recipe.prepared_ingredient_id.is_empty():
			errors.append("invalid_preparation")
			return result
		var quantity: int = quantities[recipe_id]
		if quantity > (data.prep_labor_capacity - labor_used) / recipe.prep_labor_units:
			errors.append("insufficient_labor")
			return result
		labor_used += quantity * recipe.prep_labor_units
		for ingredient_id: String in recipe.ingredients:
			if quantity > (inventory[ingredient_id] - required.get(ingredient_id, 0)) / recipe.ingredients[ingredient_id]:
				errors.append("missing_ingredients")
				return result
			required[ingredient_id] = required.get(ingredient_id, 0) + quantity * recipe.ingredients[ingredient_id]
	for ingredient_id: String in required:
		inventory[ingredient_id] -= required[ingredient_id]
	for recipe_id: String in ordered_ids:
		inventory[data.recipe_for(recipe_id).prepared_ingredient_id] += quantities[recipe_id]
	result.labor_used = labor_used
	for employee_id: Variant in options.get("duties", {}):
		var duty: Variant = options.duties[employee_id]
		if not employee_id is String or not duties.has(employee_id) or not duty is String or duty not in DUTIES:
			errors.append("invalid_duty")
			return result
		duties[employee_id] = duty
	if require_stock:
		var available := inventory.duplicate()
		for recipe_id: String in data.menu_ids:
			var recipe := data.recipe_for(recipe_id)
			if inventory.get(recipe.prepared_ingredient_id, 0) > 0:
				continue
			for ingredient_id: String in recipe.ingredients:
				if available[ingredient_id] < recipe.ingredients[ingredient_id]:
					errors.append("menu_missing_ingredients")
					return result
				available[ingredient_id] -= recipe.ingredients[ingredient_id]
	return result


static func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}


static func _array(tile: Vector2i) -> Array[int]:
	return [tile.x, tile.y]


static func _vector(coordinates: Array) -> Vector2i:
	return Vector2i(coordinates[0], coordinates[1])
