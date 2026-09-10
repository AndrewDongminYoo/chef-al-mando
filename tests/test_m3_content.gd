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
	var pressure_services: Array[String] = ["hot_queue", "shared_stock", "long_route", "split_duties", "rush_hour", "final_service"]
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
		if scenario.id in pressure_services:
			_test_pressure_service(scenario, schedule)
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
	invalid = campaign.duplicate(true)
	var changed_scenario: Resource = invalid.scenarios[2].duplicate(true)
	changed_scenario.order_arrival_ticks = PackedInt32Array([10])
	invalid.scenarios[2] = changed_scenario
	expect(not invalid.call("validate").is_empty(), "an explicit arrival schedule must match the order count")
	invalid = campaign.duplicate(true)
	changed_scenario = invalid.scenarios[2].duplicate(true)
	var backward_ticks: PackedInt32Array = changed_scenario.order_arrival_ticks.duplicate()
	backward_ticks[1] = backward_ticks[0] - 1
	changed_scenario.order_arrival_ticks = backward_ticks
	invalid.scenarios[2] = changed_scenario
	expect(not invalid.call("validate").is_empty(), "an explicit arrival schedule cannot move backward")
	changed_scenario = campaign.scenarios[2].duplicate(true)
	expect(changed_scenario.call("validate").is_empty(),
		"the closing-tick schedule fixture starts from a valid service")
	var closing_ticks: PackedInt32Array = changed_scenario.order_arrival_ticks.duplicate()
	closing_ticks[-1] = changed_scenario.closing_tick
	changed_scenario.order_arrival_ticks = closing_ticks
	expect("campaign arrival schedule must be ordered within service time" in changed_scenario.call("validate"),
		"an explicit arrival must occur before the closing tick")


func _test_pressure_service(scenario: Resource, schedule: Array) -> void:
	const RECOVERY_GAP_TICKS := 150
	var arrival_ticks: Variant = scenario.get("order_arrival_ticks")
	expect(arrival_ticks is PackedInt32Array and arrival_ticks.size() == scenario.order_count,
		"a pressure service defines every arrival tick: " + scenario.id)
	if not arrival_ticks is PackedInt32Array or arrival_ticks.size() != scenario.order_count:
		return
	var has_batch := false
	var has_recovery_gap := false
	for index: int in range(1, arrival_ticks.size()):
		has_batch = has_batch or arrival_ticks[index] == arrival_ticks[index - 1]
		has_recovery_gap = has_recovery_gap or arrival_ticks[index] - arrival_ticks[index - 1] >= RECOVERY_GAP_TICKS
	expect(has_batch and has_recovery_gap, "a pressure service has an order batch and a recovery gap: " + scenario.id)
	for index: int in arrival_ticks.size():
		expect(schedule[index].arrival_tick == arrival_ticks[index],
			"the service uses explicit arrival tick %d: %s" % [index, scenario.id])
	expect(scenario.space_rules, "a pressure service uses the kitchen space rules: " + scenario.id)
	var fixed_roles: Dictionary[String, bool] = {}
	for station: Resource in scenario.stations:
		if station.fixed:
			fixed_roles[station.role] = true
	expect(fixed_roles.has("storage") and fixed_roles.has("pass"),
		"a pressure service fixes storage and pass fixtures: " + scenario.id)
