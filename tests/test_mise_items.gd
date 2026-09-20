extends "res://tests/harness.gd"

const FIXTURE := "res://content/m2_first_service.tres"
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceAnalysis := preload("res://sim/service_analysis.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const CAMPAIGN_MISE := {
	"prepped_vegetable": {"name": "손질 토마토", "inputs": {"vegetable": 1}, "labor": 1, "cost": 100, "menus": 4},
	"prepped_grain": {"name": "불린 현미", "inputs": {"grain": 1}, "labor": 1, "cost": 150, "menus": 4},
	"prepped_mushroom": {"name": "손질 양송이", "inputs": {"mushroom": 1}, "labor": 1, "cost": 200, "menus": 3},
	"soup_base": {"name": "토마토 베이스", "inputs": {"vegetable": 2}, "labor": 1, "cost": 200, "menus": 2},
	"thawed_protein": {"name": "해동 연어", "inputs": {"protein": 1}, "labor": 1, "cost": 400, "menus": 1},
	"marinated_protein": {"name": "재운 연어", "inputs": {"protein": 1}, "labor": 3, "cost": 400, "menus": 1},
}
const CAMPAIGN_NAMES := {"protein": "연어", "vegetable": "토마토", "grain": "현미", "mushroom": "양송이",
	"grill": "연어 구이", "protein_bowl": "연어 덮밥", "salad": "토마토 샐러드", "grain_salad": "현미 샐러드",
	"mushroom_salad": "양송이 샐러드", "soup": "토마토 수프", "mushroom_soup": "양송이 수프", "grain_grill": "현미 볶음밥"}


func run(_tree: SceneTree) -> void:
	_test_mise_definitions()
	_test_mise_preparation()
	_test_mise_set_consumption()
	_test_campaign_mise_content()
	_test_shared_mise_stock()


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

	var negative_labor := _fixture()
	_ingredient(negative_labor, "prepped_grill").set("labor_units", -1)
	expect(_has_error(negative_labor, "mise items need inputs and labor: prepped_grill"), "a mise item rejects negative labor")

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
	expect("campaign menu needs mise items: salad" in empty_menu.call("validate"), "a campaign menu without mise items is rejected")
	expect("unused mise item: prepped_vegetable" in empty_menu.call("validate"), "a mise item no sale menu uses is rejected")


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


func _split_soup_fixture() -> Resource:
	var data := _fixture()
	var grain_item: Resource = _ingredient(data, "prepped_soup").duplicate()
	grain_item.set("id", "prepped_soup_grain")
	grain_item.set("unit_cost", 150)
	grain_item.set("inputs", _typed_inputs({"grain": 1}))
	grain_item.set("labor_units", 1)
	var vegetable_item: Resource = _ingredient(data, "prepped_soup").duplicate()
	vegetable_item.set("id", "prepped_soup_vegetable")
	vegetable_item.set("unit_cost", 200)
	vegetable_item.set("inputs", _typed_inputs({"vegetable": 2}))
	vegetable_item.set("labor_units", 1)
	var items: Array = data.get("ingredients").duplicate()
	items.append(grain_item)
	items.append(vegetable_item)
	data.set("ingredients", items)
	data.call("recipe_for", "soup").set("mise_ids", PackedStringArray(["prepped_soup_grain", "prepped_soup_vegetable"]))
	data.set("menu_ids", PackedStringArray(["soup"]))
	data.set("order_count", 1)
	data.set("first_arrival_tick", 1)
	return data


func _run_until_consumed(simulation: ServiceSim, limit: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _step: int in limit:
		simulation.step()
		events.append_array(simulation.events())
		if simulation.snapshot().orders.size() > 0 and simulation.snapshot().orders[0].input_consumed:
			break
	return events


func _test_mise_set_consumption() -> void:
	var data := _split_soup_fixture()
	expect(_ingredient(data, "prepped_soup_grain").get("inputs") == _typed_inputs({"grain": 1}), "the split fixture keeps its typed inputs")
	expect(data.call("validate").is_empty(), "a two-item mise set whose inputs sum to the recipe validates")
	var partial := ServiceSim.new(data, null, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(partial.errors.is_empty(), "one of two mise items can be prepared")
	_run_until_consumed(partial, 40)
	var view: Dictionary = partial.snapshot()
	expect(view.orders[0].raw_consumed and not view.orders[0].uses_prepared and view.inventory.prepped_soup_grain == 1,
		"a recipe with one missing mise item takes the raw path and leaves the stocked item")
	expect(view.orders[0].missing_mise_ids == ["prepped_soup_grain", "prepped_soup_vegetable"],
		"a raw-path order records every mise item of its recipe as missing")
	var full := ServiceSim.new(data, null, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	var events := _run_until_consumed(full, 40)
	view = full.snapshot()
	expect(view.orders[0].missing_mise_ids == [], "a fully prepared order records no missing mise item")
	expect(view.orders[0].uses_prepared and view.inventory.prepped_soup_grain == 0 and view.inventory.prepped_soup_vegetable == 0
		and view.orders[0].consumed_cost == 350, "a complete mise set is consumed item by item at its combined cost")
	var depleted_ids: Array[String] = []
	for event: Dictionary in events:
		if event.kind == "prepared_stock_depleted":
			depleted_ids.append(event.ingredient_id)
	expect(depleted_ids == ["prepped_soup_grain", "prepped_soup_vegetable"],
		"each mise item that reaches zero emits its own depletion event")
	var saved: Dictionary = full.export_state()
	var restored := ServiceSim.restore(data, saved, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	expect(restored.accepted and restored.simulation.state_hash() == full.state_hash(),
		"a snapshot with a consumed mise set restores to the same hash")
	var raw_state: Dictionary = partial.export_state()
	var reordered: Dictionary = raw_state.duplicate(true)
	reordered.orders[0].missing_mise_ids = ["prepped_soup_vegetable", "prepped_soup_grain"]
	var reordered_restore := ServiceSim.restore(data, reordered, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(not reordered_restore.accepted and reordered_restore.reason == "invalid_consumption",
		"restore rejects missing mise IDs that are not in recipe order")
	var unknown: Dictionary = raw_state.duplicate(true)
	unknown.orders[0].missing_mise_ids = ["prepped_soup_grain", "missing"]
	expect(not ServiceSim.restore(data, unknown, {"prep_quantities": {"prepped_soup_grain": 1}}).accepted,
		"restore rejects a missing mise ID the recipe does not use")
	var understated: Dictionary = raw_state.duplicate(true)
	understated.orders[0].missing_mise_ids = ["prepped_soup_grain"]
	var understated_restore := ServiceSim.restore(data, understated, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(not understated_restore.accepted and understated_restore.reason == "invalid_inventory",
		"restore rejects a missing list that does not explain the consumed inventory")
	var contradictory: Dictionary = full.export_state()
	contradictory.orders[0].missing_mise_ids = ["prepped_soup_grain", "prepped_soup_vegetable"]
	var contradictory_restore := ServiceSim.restore(data, contradictory, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	expect(not contradictory_restore.accepted and contradictory_restore.reason == "invalid_consumption",
		"restore rejects uses_prepared with a non-empty missing list")


func _test_campaign_mise_content() -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	expect(campaign.call("validate").is_empty(), "the restructured campaign validates")
	var final_service: Resource = campaign.call("scenario_for", "final_service")
	expect(final_service.get("ingredients").size() == 10, "the final service lists four raw ingredients and six mise items")
	for mise_id: String in CAMPAIGN_MISE:
		var expected: Dictionary = CAMPAIGN_MISE[mise_id]
		var item: Resource = final_service.call("ingredient_for", mise_id)
		expect(item != null and item.get("display_name") == expected.name and item.get("inputs") == _typed_inputs(expected.inputs)
			and item.get("labor_units") == expected.labor and item.get("unit_cost") == expected.cost,
			"campaign mise item matches the approved table: " + mise_id)
		expect(item != null and final_service.call("menu_count_for", mise_id) == expected.menus,
			"campaign mise item is shared by the approved number of menus: " + mise_id)
	for id: String in CAMPAIGN_NAMES:
		var definition: Resource = final_service.call("ingredient_for", id)
		if definition == null:
			definition = final_service.call("recipe_for", id)
		expect(definition != null and definition.get("display_name") == CAMPAIGN_NAMES[id], "campaign display name is a real food: " + id)
	expect(final_service.call("recipe_for", "grain_grill").get("mise_ids") == PackedStringArray(["prepped_grain", "prepped_mushroom"]),
		"the rice stir-fry uses grain and mushroom mise, not protein")
	TranslationServer.set_locale("en")
	expect(TranslationServer.translate("재운 연어") == "Marinated salmon", "the English translation covers the new mise names")
	TranslationServer.set_locale("ko")


## lunch_prep's salad/soup/grain_salad share prepped_vegetable and prepped_grain across menus, so the
## require_stock check must decrement a working copy of inventory as it credits each menu, not read the
## static inventory for every menu independently.
func _test_shared_mise_stock() -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var scenario: Resource = campaign.call("scenario_for", "lunch_prep")

	# One unit of each: salad and grain_salad both need the single prepped_vegetable, and soup and
	# grain_salad both need the single prepped_grain, so at most two of the three menus can actually be
	# served from this stock even though the raw purchases (vegetable 3, grain 1) were fully spent
	# preparing it.
	var short_plan := PreparationPlan.new(scenario)
	expect(_command(short_plan, "set_purchase", "vegetable", 3, 1).accepted, "lunch_prep accepts a vegetable purchase of 3")
	expect(_command(short_plan, "set_purchase", "grain", 1, 2).accepted, "lunch_prep accepts a grain purchase of 1")
	expect(_command(short_plan, "set_prep", "prepped_vegetable", 1, 3).accepted, "one prepped_vegetable fits the labor budget")
	expect(_command(short_plan, "set_prep", "prepped_grain", 1, 4).accepted, "one prepped_grain fits the labor budget")
	expect(_command(short_plan, "set_prep", "soup_base", 1, 5).accepted, "one soup_base fits the labor budget")
	var short_snapshot: Dictionary = short_plan.snapshot()
	expect(not short_snapshot.can_start and "menu_missing_ingredients" in short_snapshot.errors,
		"a single unit of each shared mise item cannot cover all three lunch_prep menus at once")

	# Two of each shared item: salad(prepped_vegetable) + soup(prepped_grain, soup_base) +
	# grain_salad(prepped_vegetable, prepped_grain) need prepped_vegetable twice and prepped_grain twice
	# across the three menus, so doubling those two (and the raw purchases that feed them: vegetable
	# 2*1 + 1*2 = 4, grain 2*1 = 2) is the smallest stock where every menu is served from the prepared
	# path rather than falling back to raw ingredients, which is what exercises the fixed decrement.
	var full_plan := PreparationPlan.new(scenario)
	expect(_command(full_plan, "set_purchase", "vegetable", 4, 1).accepted, "lunch_prep accepts a vegetable purchase of 4")
	expect(_command(full_plan, "set_purchase", "grain", 2, 2).accepted, "lunch_prep accepts a grain purchase of 2")
	expect(_command(full_plan, "set_prep", "prepped_vegetable", 2, 3).accepted, "two prepped_vegetable fit the labor budget")
	expect(_command(full_plan, "set_prep", "prepped_grain", 2, 4).accepted, "two prepped_grain fit the labor budget")
	expect(_command(full_plan, "set_prep", "soup_base", 1, 5).accepted, "one soup_base fits the labor budget")
	var full_snapshot: Dictionary = full_plan.snapshot()
	expect(full_snapshot.can_start and full_snapshot.errors.is_empty(),
		"one prepared unit per menu's own share of prepped_vegetable and prepped_grain lets lunch_prep start")
