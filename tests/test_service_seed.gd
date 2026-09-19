extends "res://tests/harness.gd"

const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	_test_scenario_fields(campaign)


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


func _margin(scenario: Resource, recipe_id: String) -> int:
	var recipe: Resource = scenario.recipe_for(recipe_id)
	var margin: int = recipe.revenue
	for ingredient_id: String in recipe.ingredients:
		margin -= scenario.ingredient_for(ingredient_id).unit_cost * recipe.ingredients[ingredient_id]
	return margin
