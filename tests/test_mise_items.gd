extends "res://tests/harness.gd"

const FIXTURE := "res://content/m2_first_service.tres"
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceAnalysis := preload("res://sim/service_analysis.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func run(_tree: SceneTree) -> void:
	_test_mise_definitions()
	_test_mise_preparation()


func _fixture() -> Resource:
	return ResourceLoader.load(FIXTURE, "", ResourceLoader.CACHE_MODE_IGNORE)


func _ingredient(data: Resource, ingredient_id: String) -> Resource:
	return data.call("ingredient_for", ingredient_id)


## Typed exports ignore an untyped literal passed to set(), so fixtures assign through this.
static func _typed_inputs(values: Dictionary) -> Dictionary[String, int]:
	var typed: Dictionary[String, int] = {}
	typed.assign(values)
	return typed


func _test_mise_definitions() -> void:
	var data := _fixture()
	expect(data.call("validate").is_empty(), "the M2 fixture validates as one-item mise sets")
	expect(_ingredient(data, "prepped_salad").call("is_mise") and not _ingredient(data, "vegetable").call("is_mise"),
		"a non-purchasable ingredient with inputs is a mise item and a raw ingredient is not")
	var items: Array = data.call("mise_items")
	var item_ids: Array[String] = []
	for item: Resource in items:
		item_ids.append(item.get("id"))
	expect(item_ids == ["prepped_salad", "prepped_soup", "prepped_grill"], "mise_items keeps the ingredient array order")  # content/m2_first_service.tres:237
	expect(data.call("menu_count_for", "prepped_salad") == 1 and data.call("menu_count_for", "vegetable") == 0,
		"menu_count_for counts sale menus that reference the item")

	var wrong_cost := _fixture()
	_ingredient(wrong_cost, "prepped_soup").set("unit_cost", 351)
	expect(_has_error(wrong_cost, "mise cost must equal its raw input cost: prepped_soup"), "mise cost must equal the raw input cost")

	var raw_with_inputs := _fixture()
	_ingredient(raw_with_inputs, "vegetable").set("inputs", _typed_inputs({"grain": 1}))
	expect(_ingredient(raw_with_inputs, "vegetable").get("inputs") == _typed_inputs({"grain": 1}), "the typed set lands on the fixture")
	expect(_has_error(raw_with_inputs, "raw ingredients cannot have inputs or labor: vegetable"), "raw ingredients cannot carry inputs")

	var no_labor := _fixture()
	_ingredient(no_labor, "prepped_grill").set("labor_units", 0)
	expect(_has_error(no_labor, "mise items need inputs and labor: prepped_grill"), "a mise item needs positive labor")

	var unknown_item := _fixture()
	unknown_item.call("recipe_for", "salad").set("mise_ids", PackedStringArray(["prepped_salad", "missing"]))
	expect(_has_error(unknown_item, "invalid recipe mise item: salad"), "unknown mise references are rejected")

	var duplicate_item := _fixture()
	duplicate_item.call("recipe_for", "salad").set("mise_ids", PackedStringArray(["prepped_salad", "prepped_salad"]))
	expect(_has_error(duplicate_item, "invalid recipe mise item: salad"), "duplicate mise references are rejected")

	var mismatched_inputs := _fixture()
	mismatched_inputs.call("recipe_for", "soup").set("mise_ids", PackedStringArray(["prepped_salad"]))
	expect(_has_error(mismatched_inputs, "recipe ingredients must equal the raw inputs of its mise items: soup"),
		"the mise input sum must equal the recipe ingredients")

	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	expect(campaign.call("validate").is_empty(), "the campaign validates with one-item mise sets")
	var empty_menu: Resource = campaign.call("scenario_for", "first_shift")
	empty_menu.call("recipe_for", "salad").set("mise_ids", PackedStringArray())
	empty_menu.call("recipe_for", "salad").set("prepared_ingredient_id", "")
	empty_menu.call("recipe_for", "salad").set("prep_labor_units", 0)
	expect("campaign menu needs mise items: salad" in empty_menu.call("validate"), "a campaign menu without mise items is rejected")
	expect("unused mise item: prepped_salad" in empty_menu.call("validate"), "a mise item no sale menu uses is rejected")


func _has_error(data: Resource, message: String) -> bool:
	return message in data.call("validate")


func _command(plan: PreparationPlan, kind: String, target: String, value: Variant, sequence: int) -> Dictionary:
	return plan.apply_command({"kind": kind, "target_id": target, "value": value, "apply_tick": 0, "sequence": sequence})


func _test_mise_preparation() -> void:
	var plan := PreparationPlan.new(_fixture())
	expect(plan.snapshot().prep_quantities.keys() == ["prepped_salad", "prepped_soup", "prepped_grill"],
		"preparation quantities are keyed by mise item in ingredient order")  # content/m2_first_service.tres:237
	expect(not _command(plan, "set_prep", "salad", 1, 1).accepted, "set_prep no longer accepts a recipe ID")
	expect(not _command(plan, "set_prep", "vegetable", 1, 2).accepted, "set_prep rejects a raw ingredient")
	expect(_command(plan, "set_prep", "prepped_soup", 2, 3).accepted, "two soup mise items fit the labor budget")
	var snapshot := plan.snapshot()
	expect(snapshot.labor_used == 4 and snapshot.inventory.prepped_soup == 2 and snapshot.inventory.vegetable == 18
		and snapshot.inventory.grain == 6, "mise labor and raw inputs come from the item definition")
	expect(not _command(plan, "set_prep", "prepped_grill", 1, 4).accepted, "a seventh labor unit cannot be spent")
	var inventory := {"prepped_salad": 1, "prepped_soup": 0}
	expect(PreparationPlan.mise_ready(inventory, plan.display_definition().recipe_for("salad"))
		and not PreparationPlan.mise_ready(inventory, plan.display_definition().recipe_for("soup")),
		"mise_ready requires every item of the recipe")

	var started := _command(plan, "start", "", null, 5)
	expect(started.accepted, "the prepared fixture starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while not simulation.closed:
		simulation.step()
	var report: Dictionary = ServiceAnalysis.build(started.definitions, simulation.snapshot(), started.selection)
	expect(report.prep.keys() == ["prepped_salad", "prepped_soup", "prepped_grill"], "analysis prep rows are keyed by mise item")
	var soup_row: Dictionary = report.prep.prepped_soup
	expect(soup_row.planned == 2 and soup_row.labor_units == 2 and soup_row.menu_count == 1
		and soup_row.planned == soup_row.used + soup_row.remaining, "a prep row carries planned, used, remaining, labor and menu count")
	for recommendation: Dictionary in report.recommendations:
		if recommendation.category == "prep":
			expect(started.definitions.ingredient_for(recommendation.target_id) != null, "prep recommendations target a mise item")
