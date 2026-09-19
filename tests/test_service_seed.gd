extends "res://tests/harness.gd"

const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	_test_scenario_fields(campaign)
	_test_session_seed(campaign)


func _test_scenario_fields(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		expect(scenario.forecast_slack.is_empty(), "authored slack is empty in this PR: " + scenario.id)
		expect(scenario.service_seed == 0, "authored service seed is zero: " + scenario.id)
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var counts: Dictionary = hot_queue.baseline_counts()
	expect(counts.get("grill") == 10 and counts.get("soup") == 5 and counts.get("salad") == 5, "baseline counts come from the authored order")
	var ranges: Dictionary = hot_queue.forecast_ranges()
	expect(ranges.grill == {"baseline": 10, "min": 10, "max": 10}, "zero slack collapses the range to the baseline")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	expect(slacked.validate().is_empty(), "slack on menu items validates")
	ranges = slacked.forecast_ranges()
	expect(ranges.grill == {"baseline": 10, "min": 8, "max": 12} and ranges.soup == {"baseline": 5, "min": 4, "max": 6}, "slack widens the range around the baseline")
	var wide: Resource = hot_queue.duplicate()
	var wide_slack: Dictionary[String, int] = {"soup": 9}
	wide.forecast_slack = wide_slack
	expect(wide.forecast_ranges().soup["min"] == 0, "the lower bound never goes below zero")
	var invalid: Resource = hot_queue.duplicate()
	var bad_key: Dictionary[String, int] = {"grain_salad": 1}
	invalid.forecast_slack = bad_key
	expect(not invalid.validate().is_empty(), "slack for a menu outside the service is rejected")
	invalid = hot_queue.duplicate()
	var bad_value: Dictionary[String, int] = {"grill": -1}
	invalid.forecast_slack = bad_value
	expect(not invalid.validate().is_empty(), "negative slack is rejected")
	invalid = hot_queue.duplicate()
	invalid.service_seed = -1
	expect(not invalid.validate().is_empty(), "a negative service seed is rejected")
	var seeded: Resource = hot_queue.with_service_seed(7)
	expect(seeded.service_seed == 7 and hot_queue.service_seed == 0, "with_service_seed returns a seeded copy and leaves the source untouched")
	expect(seeded.id == hot_queue.id and seeded.order_recipe_ids == hot_queue.order_recipe_ids, "the seeded copy keeps the authored content")
	expect(slacked.maximum_profit(20) == hot_queue.maximum_profit(20) + 2 * _margin(hot_queue, "grill") + _margin(hot_queue, "soup") - 3 * _margin(hot_queue, "salad"), "maximum profit uses the forecast upper bounds")


func _test_session_seed(campaign: Resource) -> void:
	var records: Dictionary = {}
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var unlocked: Dictionary = {}
	for scenario: Resource in campaign.scenarios:
		if scenario.id == "hot_queue":
			break
		unlocked[scenario.id] = {"completed": true, "best_served": scenario.minimum_served, "best_profit": scenario.minimum_profit}
	records = unlocked
	var seeded: Resource = hot_queue.with_service_seed(104076537)
	var plan := PreparationPlan.new(seeded)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(started.accepted, "seeded preparation starts")
	expect(started.definitions.service_seed == 104076537, "the started definition carries the service seed through duplicate()")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	expect(simulation.errors.is_empty(), "seeded simulation builds")
	var session := ServiceSession.capture("hot_queue", started.selection, simulation, 1, 0, 104076537)
	expect(session.size() == 6 and session.service_seed == 104076537, "capture stores the service seed as the sixth field")
	var restored := ServiceSession.restore(campaign, session, records)
	expect(restored.accepted and restored.service_seed == 104076537, "restore returns the service seed")
	expect(restored.definitions.order_schedule()[0].recipe_id == seeded.order_schedule()[0].recipe_id, "restore rebuilds the seeded schedule")
	var legacy := session.duplicate(true)
	legacy.erase("service_seed")
	var legacy_restored := ServiceSession.restore(campaign, legacy, records)
	expect(legacy_restored.accepted and legacy_restored.service_seed == 0, "a five-field session restores with seed 0")
	var forged := session.duplicate(true)
	forged.service_seed = "7"
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a non-integer seed is rejected")
	forged = session.duplicate(true)
	forged.service_seed = -1
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a negative seed is rejected")
	var modified: Resource = campaign.duplicate(true)
	var slacked: Resource = modified.scenario_for("hot_queue")
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	var drawn_scenario: Resource = slacked.with_service_seed(104076537)
	var drawn_plan := PreparationPlan.new(drawn_scenario)
	var drawn_started := drawn_plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(drawn_started.accepted, "a slack-bearing seeded preparation starts")
	var drawn_sim := ServiceSim.new(drawn_started.definitions, null, drawn_started.options)
	while not drawn_sim.closed:
		drawn_sim.step()
	var drawn_session := ServiceSession.capture("hot_queue", drawn_started.selection, drawn_sim, 1, 0, 104076537)
	expect(ServiceSession.restore(modified, drawn_session, records).accepted, "a closed session restores under the seed that produced it")
	var wrong_seed := drawn_session.duplicate(true)
	wrong_seed.service_seed = 0
	var rejected := ServiceSession.restore(modified, wrong_seed, records)
	expect(not rejected.accepted and rejected.reason == "invalid_schedule", "the same orders cannot restore under a seed whose draw differs")


func _margin(scenario: Resource, recipe_id: String) -> int:
	var recipe: Resource = scenario.recipe_for(recipe_id)
	var margin: int = recipe.revenue
	for ingredient_id: String in recipe.ingredients:
		margin -= scenario.ingredient_for(ingredient_id).unit_cost * recipe.ingredients[ingredient_id]
	return margin
