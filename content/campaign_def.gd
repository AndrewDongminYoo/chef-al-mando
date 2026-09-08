extends Resource

const ScenarioDef := preload("res://content/scenario_def.gd")
const SERVICE_IDS: Array[String] = ["first_shift", "lunch_prep", "hot_queue", "shared_stock", "long_route", "split_duties", "rush_hour", "final_service"]

@export var id: String = ""
@export var scenarios: Array[ScenarioDef] = []


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty() or scenarios.size() != 8:
		errors.append("campaign must define its ID and eight services")
	var actual_ids: Array[String] = []
	for scenario: ScenarioDef in scenarios:
		actual_ids.append(scenario.id if scenario != null else "")
	if actual_ids != SERVICE_IDS:
		errors.append("campaign services must follow the fixed order")
	var seen: Dictionary = {}
	var ingredients: Dictionary = {}
	var recipes: Dictionary = {}
	for scenario: ScenarioDef in scenarios:
		if scenario == null:
			errors.append("campaign contains a missing service")
			continue
		if seen.has(scenario.id):
			errors.append("duplicate campaign service: " + scenario.id)
		seen[scenario.id] = true
		errors.append_array(scenario.validate())
		for ingredient: ScenarioDef.IngredientDef in scenario.ingredients:
			if ingredient == null:
				continue
			var signature: Array = [ingredient.display_name, ingredient.unit_cost, ingredient.purchasable]
			if ingredients.has(ingredient.id) and ingredients[ingredient.id] != signature:
				errors.append("inconsistent campaign ingredient: " + ingredient.id)
			ingredients[ingredient.id] = signature
		for recipe: ScenarioDef.RecipeDef in scenario.recipes:
			if recipe == null:
				continue
			var processes: Array = []
			for process: ScenarioDef.RecipeDef.ProcessDef in recipe.processes:
				if process != null:
					processes.append([process.id, process.station_role, process.duration_ticks, process.next_id])
			var signature: Array = [recipe.display_name, recipe.ingredients, recipe.cook_role, recipe.revenue,
				recipe.patience_ticks, recipe.prepared_ingredient_id, recipe.prep_labor_units, recipe.first_process_id, processes]
			if recipes.has(recipe.id) and recipes[recipe.id] != signature:
				errors.append("inconsistent campaign recipe: " + recipe.id)
			recipes[recipe.id] = signature
	if ingredients.size() > 12 or recipes.size() != 8:
		errors.append("campaign requires eight menus and at most twelve ingredients")
	return errors


func scenario_for(scenario_id: String) -> ScenarioDef:
	for scenario: ScenarioDef in scenarios:
		if scenario != null and scenario.id == scenario_id:
			return scenario
	return null
