extends "res://content/definitions.gd"

@export var display_name: String = ""
@export_multiline var briefing: String = ""
@export var operation_problem: String = ""
@export var minimum_served: int = 1
@export var minimum_profit: int = 0
@export var order_recipe_ids: PackedStringArray = PackedStringArray()


func validate(require_stock: bool = true) -> Array[String]:
	var errors := super.validate(require_stock)
	if display_name.is_empty() or briefing.is_empty() or operation_problem.is_empty():
		errors.append("campaign service needs a title, briefing, and operating problem")
	if closing_tick != 3000 or employees.size() > 4 or stations.size() > 6 or ingredients.size() > 12:
		errors.append("campaign service exceeds the supported limits")
	if minimum_served <= 0 or minimum_served > order_count or minimum_profit < -starting_budget:
		errors.append("invalid campaign target")
	if order_recipe_ids.size() != order_count:
		errors.append("campaign order sequence must match the order count")
	var seen: Dictionary = {}
	for recipe_id: String in menu_ids:
		if seen.has(recipe_id):
			errors.append("duplicate campaign menu: " + recipe_id)
		seen[recipe_id] = true
	for recipe_id: String in order_recipe_ids:
		var recipe := recipe_for(recipe_id)
		if recipe == null or recipe_id not in menu_ids:
			errors.append("campaign order is outside its menu: " + recipe_id)
	if errors.is_empty() and minimum_profit > maximum_profit(order_count):
		errors.append("campaign profit target exceeds revenue after required ingredient cost")
	return errors


func order_schedule() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in order_recipe_ids.size():
		var recipe := recipe_for(order_recipe_ids[index])
		if recipe == null:
			return []
		var arrival_tick := first_arrival_tick + arrival_interval_ticks * index
		result.append({"id": "order_%02d" % (index + 1), "arrival_tick": arrival_tick,
			"recipe_id": recipe.id, "deadline_tick": arrival_tick + recipe.patience_ticks})
	return result


func maximum_profit(served_limit: int) -> int:
	var margins: Array[int] = []
	for recipe_id: String in order_recipe_ids:
		var recipe := recipe_for(recipe_id)
		if recipe == null:
			continue
		var margin: int = recipe.revenue
		for ingredient_id: String in recipe.ingredients:
			var ingredient := ingredient_for(ingredient_id)
			if ingredient != null:
				margin -= ingredient.unit_cost * recipe.ingredients[ingredient_id]
		margins.append(margin)
	margins.sort()
	margins.reverse()
	var upper_bound: int = -labor_cost
	for index: int in mini(maxi(served_limit, 0), margins.size()):
		upper_bound += maxi(margins[index], 0)
	return upper_bound
