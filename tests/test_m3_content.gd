extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists("res://content/campaign/campaign.tres"):
		expect(false, "the eight-service campaign resource must exist")
		return
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	expect(campaign.call("validate").is_empty(), "the complete campaign content is valid")
	var scenarios: Array = campaign.get("scenarios")
	expect(scenarios.size() == 8, "the campaign contains eight services")
	var menus: Dictionary = {}
	var ingredients: Dictionary = {}
	var layouts: Dictionary = {}
	for scenario: Resource in scenarios:
		expect(scenario.call("validate").is_empty(), "service content validates: " + scenario.id)
		var plan := PreparationPlan.new(scenario)
		expect(plan.snapshot().can_start, "default preparation can start: " + scenario.id)
		var committed := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
		expect(committed.accepted, "default preparation commits atomically: " + scenario.id)
		var schedule: Array = scenario.call("order_schedule")
		expect(schedule.size() == scenario.order_count and schedule[-1].arrival_tick < 3000, "all configured orders arrive before closing: " + scenario.id)
		for order: Dictionary in schedule:
			expect(order.recipe_id in scenario.menu_ids, "every scheduled order belongs to the service menu")
		for recipe: Resource in scenario.recipes:
			menus[recipe.id] = true
		for ingredient: Resource in scenario.ingredients:
			ingredients[ingredient.id] = true
		var positions: Array = []
		for station: Resource in scenario.stations:
			positions.append([station.tile, station.work_position])
		layouts[str([scenario.grid_size, scenario.extra_obstacles, positions])] = true
		expect(scenario.employees.size() <= 4 and scenario.stations.size() <= 6, "service stays within mobile resource caps")
	expect(menus.size() == 8 and ingredients.size() <= 12, "campaign has eight menus and at most twelve ingredient definitions")
	expect(layouts.size() == 3, "campaign uses three actual kitchen layouts")
	var invalid: Resource = campaign.duplicate(true)
	var first: Resource = invalid.scenarios[0]
	invalid.scenarios[0] = invalid.scenarios[1]
	invalid.scenarios[1] = first
	expect(not invalid.validate().is_empty(), "the fixed campaign service order cannot be swapped")
	invalid = campaign.duplicate(true)
	invalid.scenarios[0].minimum_profit = 4000
	expect(not invalid.validate().is_empty(), "a target cannot exceed revenue after required ingredient cost")
	invalid = campaign.duplicate(true)
	invalid.scenarios[1].id = invalid.scenarios[0].id
	expect(not invalid.call("validate").is_empty(), "duplicate scenario IDs are rejected")
	invalid = campaign.duplicate(true)
	invalid.scenarios[0].order_recipe_ids[0] = "missing_recipe"
	expect(not invalid.call("validate").is_empty(), "orders referencing missing menus are rejected")
	invalid = campaign.duplicate(true)
	invalid.scenarios[0].minimum_served = invalid.scenarios[0].order_count + 1
	expect(not invalid.call("validate").is_empty(), "impossible served targets are rejected")
	invalid = campaign.duplicate(true)
	invalid.scenarios[0].employees.append(invalid.scenarios[0].employees[0].duplicate())
	invalid.scenarios[0].employees[-1].id = "employee_extra"
	invalid.scenarios[0].employees.append(invalid.scenarios[0].employees[-1].duplicate())
	invalid.scenarios[0].employees[-1].id = "employee_other"
	invalid.scenarios[0].employees.append(invalid.scenarios[0].employees[-1].duplicate())
	invalid.scenarios[0].employees[-1].id = "employee_fifth"
	expect(not invalid.call("validate").is_empty(), "more than four employees are rejected")
