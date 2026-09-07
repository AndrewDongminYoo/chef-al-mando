extends "res://tests/harness.gd"

const Definitions := preload("res://content/definitions.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func fresh() -> Definitions:
	return ResourceLoader.load("res://content/m2_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func run(_tree: SceneTree) -> void:
	expect(fresh().validate().is_empty(), "the production M2 content passes strict content validation")
	for defect: String in ["missing_prepared", "prepared_purchase", "duplicate_prepared", "zero_labor", "negative_labor", "zero_duration", "wrong_role", "cycle", "skip", "prepared_input", "empty_input", "zero_input", "wrong_cost"]:
		var data := fresh()
		var recipe := data.recipe_for("salad")
		match defect:
			"missing_prepared": recipe.prepared_ingredient_id = "unknown"
			"prepared_purchase": data.purchases.prepped_salad = 1
			"duplicate_prepared": data.recipe_for("soup").prepared_ingredient_id = "prepped_salad"
			"zero_labor": recipe.prep_labor_units = 0
			"negative_labor": recipe.prep_labor_units = -1
			"zero_duration": recipe.processes[1].duration_ticks = 0
			"wrong_role": recipe.processes[1].station_role = "hot"
			"cycle": recipe.processes[1].next_id = "pickup"
			"skip": recipe.processes[0].next_id = "cook"
			"prepared_input": recipe.ingredients = {"prepped_soup": 1}
			"empty_input": recipe.ingredients = {}
			"zero_input": recipe.ingredients.vegetable = 0
			"wrong_cost": data.ingredient_for("prepped_salad").unit_cost = 101
		expect(not data.validate().is_empty(), "M2 content rejects " + defect)
		var sim := ServiceSim.new(data)
		expect(sim.closed and not sim.errors.is_empty(), "invalid content cannot run: " + defect)
	var extra := ResourceLoader.load("res://tests/fixtures/m2_extra_menu.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions
	expect(extra != null and extra.validate().is_empty(), "the fourth menu loads as data without a simulation branch")
	var plan := PreparationPlan.new(extra)
	expect(plan.apply_command({"kind": "set_prep", "target_id": "grain_salad", "value": 1, "apply_tick": 0, "sequence": 1}).accepted, "the data-only fourth menu can be prepared")
	var committed := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 2})
	var sim := ServiceSim.new(committed.definitions, null, committed.options)
	while sim.tick < 200:
		sim.step()
	var first: Dictionary = sim.snapshot().orders[0]
	expect(first.recipe_id == "grain_salad" and first.name == "곡물 샐러드" and first.uses_prepared and first.state == "served", "the actual fourth-menu order consumes preparation and serves its data-defined name")
	extra.menu_ids[0] = "missing_menu"
	expect("unknown scenario menu: missing_menu" in extra.validate(), "a broken fourth-menu reference fails with its expected content error")
