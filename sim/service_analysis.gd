extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")


static func build(data: Definitions, view: Dictionary, selection: Dictionary) -> Dictionary:
	var prep: Dictionary = {}
	var priorities: Dictionary = {}
	var ingredients: Dictionary = {}
	var prep_quantities: Dictionary = selection.get("prep_quantities", {})
	var menu_priorities: Dictionary = selection.get("menu_priorities", {})
	var labor_used := 0
	for recipe_id: String in data.menu_ids:
		var recipe := data.recipe_for(recipe_id)
		var planned: int = prep_quantities.get(recipe_id, 0)
		labor_used += planned * recipe.prep_labor_units
		var remaining: int = view.inventory.get(recipe.prepared_ingredient_id, 0)
		var prep_row := {"planned": planned, "used": maxi(0, planned - remaining),
			"remaining": remaining, "raw_orders": 0, "served": 0, "expired": 0,
			"shortage_ticks": 0, "pressure_ticks": 0, "prep_labor_units": recipe.prep_labor_units}
		var priority_row := {"default_priority": menu_priorities.get(recipe_id, 1),
			"served": 0, "expired": 0, "pressure_ticks": 0, "shortage_ticks": 0,
			"employee_busy_ticks": 0, "station_ticks": 0, "moving_ticks": 0,
			"revenue": recipe.revenue}
		for order: Dictionary in view.orders:
			if order.recipe_id != recipe_id:
				continue
			if order.raw_consumed:
				prep_row.raw_orders += 1
			if order.state == "served":
				prep_row.served += 1
				priority_row.served += 1
			elif order.state == "expired":
				prep_row.expired += 1
				priority_row.expired += 1
			var pressure: int = order.metrics.station_in_use + order.metrics.responsible_employee_busy
			prep_row.shortage_ticks += order.metrics.missing_ingredients
			prep_row.pressure_ticks += pressure
			priority_row.shortage_ticks += order.metrics.missing_ingredients
			priority_row.pressure_ticks += pressure
			priority_row.employee_busy_ticks += order.metrics.responsible_employee_busy
			priority_row.station_ticks += order.metrics.station_in_use
			priority_row.moving_ticks += order.metrics.moving
		prep[recipe_id] = prep_row
		priorities[recipe_id] = priority_row
	for ingredient: Definitions.IngredientDef in data.ingredients:
		if not ingredient.purchasable:
			continue
		var purchased: int = selection.get("purchases", data.purchases).get(ingredient.id, 0)
		var remaining: int = view.inventory.get(ingredient.id, 0)
		var related_shortage_ticks := 0
		for order: Dictionary in view.orders:
			var recipe := data.recipe_for(order.recipe_id)
			if recipe.ingredients.has(ingredient.id):
				related_shortage_ticks += order.metrics.missing_ingredients
		ingredients[ingredient.id] = {"purchased": purchased, "used": maxi(0, purchased - remaining),
			"remaining": remaining, "related_shortage_ticks": related_shortage_ticks,
			"unit_cost": ingredient.unit_cost}
	var recommendations: Array[Dictionary] = []
	var prep_recommendation := _prep_recommendation(data, prep, labor_used)
	if not prep_recommendation.is_empty():
		recommendations.append(prep_recommendation)
	var ingredient_recommendation := _ingredient_recommendation(ingredients, data, selection)
	if not ingredient_recommendation.is_empty():
		recommendations.append(ingredient_recommendation)
	var priority_recommendation := _priority_recommendation(priorities)
	if not priority_recommendation.is_empty():
		recommendations.append(priority_recommendation)
	recommendations = _cap_notices_last(recommendations)
	return {"prep": prep, "ingredients": ingredients, "priorities": priorities,
		"labor_used": labor_used, "labor_capacity": data.prep_labor_capacity,
		"recommendations": recommendations.slice(0, 3)}


static func _cap_notices_last(values: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for value: Dictionary in values:
		if value.action not in ["prep_at_capacity", "priority_at_max"]:
			ordered.append(value)
	for value: Dictionary in values:
		if value.action in ["prep_at_capacity", "priority_at_max"]:
			ordered.append(value)
	return ordered


static func _prep_recommendation(data: Definitions, prep: Dictionary, labor_used: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for recipe_id: String in data.menu_ids:
		var row: Dictionary = prep[recipe_id]
		var action := ""
		var amount := 0
		if row.remaining > 0:
			action = "reduce_prep"
			amount = 1
		elif row.raw_orders > 0:
			var available_labor: int = data.prep_labor_capacity - labor_used
			if available_labor >= row.prep_labor_units:
				action = "increase_prep"
				amount = 1
			else:
				action = "prep_at_capacity"
		var score: int = (10000 if row.planned > 0 else 0) + row.raw_orders * 100 + row.remaining * 10
		if not action.is_empty() and score > best_score:
			best_score = score
			best = {"category": "prep", "action": action, "target_id": recipe_id, "amount": amount}
	return best


static func _ingredient_recommendation(ingredients: Dictionary, data: Definitions = null, selection: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for ingredient_id: String in ingredients:
		var row: Dictionary = ingredients[ingredient_id]
		var action := ""
		var amount := 0
		var score := 0
		if row.remaining == 0 and row.related_shortage_ticks > 0:
			action = "increase_purchase"
			amount = 1
			score = 100000 + row.related_shortage_ticks
		elif row.remaining > 0:
			action = "reduce_purchase"
			amount = 1
			score = 50000 + row.remaining * row.unit_cost
		elif row.purchased > 0:
			action = "purchase_consumed"
			score = row.purchased * row.unit_cost
		if action in ["increase_purchase", "reduce_purchase"]:
			var quantity: int = row.purchased + (1 if action == "increase_purchase" else -1)
			if not _valid_purchase_change(data, selection, ingredient_id, quantity):
				continue
		if not action.is_empty() and score > best_score:
			best_score = score
			best = {"category": "ingredient", "action": action, "target_id": ingredient_id, "amount": amount}
	return best


static func _valid_purchase_change(data: Definitions, selection: Dictionary, ingredient_id: String, quantity: int) -> bool:
	if data == null or selection.is_empty():
		return true
	var purchases: Dictionary = selection.get("purchases", data.purchases).duplicate()
	purchases[ingredient_id] = quantity
	var candidate := data.duplicate() as Definitions
	candidate.purchases = {}
	candidate.purchases.assign(purchases)
	var options := {"prep_quantities": selection.get("prep_quantities", {}).duplicate(),
		"duties": selection.get("duties", {}).duplicate(),
		"menu_priorities": selection.get("menu_priorities", {}).duplicate()}
	return PreparationPlan.initial_state(candidate, options, true).errors.is_empty()


static func _priority_recommendation(priorities: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for recipe_id: String in priorities:
		var row: Dictionary = priorities[recipe_id]
		if row.expired == 0:
			continue
		var action := ""
		if row.default_priority < 2 and row.pressure_ticks > 0:
			action = "raise_priority"
		elif row.default_priority == 2 and (row.pressure_ticks > 0 or row.moving_ticks > 0):
			action = "priority_at_max"
		var score: int = row.expired * row.revenue
		if not action.is_empty() and score > best_score:
			best_score = score
			best = {"category": "priority", "action": action, "target_id": recipe_id, "amount": 1}
			if action == "priority_at_max":
				best.merge(_largest_bottleneck(row))
	return best


static func _largest_bottleneck(row: Dictionary) -> Dictionary:
	var bottleneck := "movement"
	var bottleneck_ticks: int = row.moving_ticks
	if row.employee_busy_ticks > bottleneck_ticks:
		bottleneck = "employee_busy"
		bottleneck_ticks = row.employee_busy_ticks
	if row.station_ticks > bottleneck_ticks:
		bottleneck = "station"
		bottleneck_ticks = row.station_ticks
	return {"bottleneck": bottleneck, "bottleneck_ticks": bottleneck_ticks}
