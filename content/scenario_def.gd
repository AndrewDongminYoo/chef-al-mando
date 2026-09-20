extends "res://content/definitions.gd"

const ScheduleGenerator := preload("res://content/schedule_generator.gd")

@export var display_name: String = ""
@export_multiline var briefing: String = ""
@export var operation_problem: String = ""
@export var minimum_served: int = 1
@export var minimum_profit: int = 0
@export var order_recipe_ids: PackedStringArray = PackedStringArray()
@export var order_arrival_ticks: PackedInt32Array = PackedInt32Array()
## 메뉴별 예보 폭. 기준 건수 ± 폭이 브리핑에 보이는 범위이며, 비어 있으면 모든 메뉴가 폭 0입니다.
@export var forecast_slack: Dictionary[String, int] = {}
## 이번 영업이 쓰는 추첨. 작성된 .tres에서는 항상 0이며 with_service_seed()로만 바뀝니다.
## export여야 PreparationPlan의 duplicate()가 값을 함께 복사합니다.
@export var service_seed: int = 0


func validate(require_stock: bool = true) -> Array[String]:
	var errors := super.validate(require_stock)
	if display_name.is_empty() or briefing.is_empty() or operation_problem.is_empty():
		errors.append("campaign service needs a title, briefing, and operating problem")
	if closing_tick != 3000 or employees.size() > 4 or stations.size() > 6 or ingredients.size() > 12:
		errors.append("campaign service exceeds the supported limits")
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe != null and recipe.mise_ids.is_empty():
			errors.append("campaign menu needs mise items: " + recipe_id)
	for ingredient: IngredientDef in ingredients:
		if ingredient == null or not ingredient.is_mise():
			continue
		if menu_count_for(ingredient.id) == 0:
			errors.append("unused mise item: " + ingredient.id)
	if minimum_served <= 0 or minimum_served > order_count or minimum_profit < -starting_budget:
		errors.append("invalid campaign target")
	if order_recipe_ids.size() != order_count:
		errors.append("campaign order sequence must match the order count")
	for recipe_id: String in forecast_slack:
		if recipe_id not in menu_ids or forecast_slack[recipe_id] < 0:
			errors.append("invalid forecast slack: " + recipe_id)
	if service_seed < 0:
		errors.append("invalid service seed")
	if not order_arrival_ticks.is_empty():
		if order_arrival_ticks.size() != order_count:
			errors.append("campaign arrival schedule must match the order count")
		else:
			for index: int in order_arrival_ticks.size():
				var arrival_tick := order_arrival_ticks[index]
				if arrival_tick <= 0 or arrival_tick >= closing_tick or (index > 0 and arrival_tick < order_arrival_ticks[index - 1]):
					errors.append("campaign arrival schedule must be ordered within service time")
					break
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


func baseline_counts() -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for recipe_id: String in menu_ids:
		counts[recipe_id] = 0
	for recipe_id: String in order_recipe_ids:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	return counts


func forecast_ranges() -> Dictionary:
	var ranges: Dictionary = {}
	var counts := baseline_counts()
	for recipe_id: String in menu_ids:
		var slack: int = forecast_slack.get(recipe_id, 0)
		ranges[recipe_id] = {"baseline": counts[recipe_id], "min": maxi(counts[recipe_id] - slack, 0), "max": counts[recipe_id] + slack}
	return ranges


func with_service_seed(seed_value: int) -> Resource:
	var seeded := duplicate() as Resource
	seeded.service_seed = seed_value
	return seeded


func order_schedule() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipe_ids := ScheduleGenerator.recipe_ids(self, service_seed)
	for index: int in recipe_ids.size():
		var recipe := recipe_for(recipe_ids[index])
		if recipe == null:
			return []
		var arrival_tick := order_arrival_ticks[index] if not order_arrival_ticks.is_empty() else first_arrival_tick + arrival_interval_ticks * index
		result.append({"id": "order_%02d" % (index + 1), "arrival_tick": arrival_tick,
			"recipe_id": recipe.id, "deadline_tick": arrival_tick + recipe.patience_ticks})
	return result


func maximum_profit(served_limit: int) -> int:
	var margins: Array[int] = []
	var ranges := forecast_ranges()
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe == null:
			continue
		var margin: int = recipe.revenue
		for ingredient_id: String in recipe.ingredients:
			var ingredient := ingredient_for(ingredient_id)
			if ingredient != null:
				margin -= ingredient.unit_cost * recipe.ingredients[ingredient_id]
		for _index: int in ranges[recipe_id]["max"]:
			margins.append(margin)
	margins.sort()
	margins.reverse()
	var upper_bound: int = -labor_cost
	for index: int in mini(maxi(served_limit, 0), margins.size()):
		upper_bound += maxi(margins[index], 0)
	return upper_bound
