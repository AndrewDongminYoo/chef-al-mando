extends "res://tests/harness.gd"

const ScheduleGenerator := preload("res://content/schedule_generator.gd")


func run(_tree: SceneTree) -> void:
	expect(ScheduleGenerator.stable_hash("a") == 3826002220, "FNV-1a 32-bit hash of a known input")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 0) == 0, "attempt 0 always uses seed 0")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 1) == 104076537, "attempt 1 seed is pinned")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 2) == 53743680, "attempt 2 seed is pinned")
	expect(ScheduleGenerator.service_seed_for("first_shift", 1) == 2225007163, "seeds differ per scenario")
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	expect(ScheduleGenerator.recipe_ids(hot_queue, 0) == hot_queue.order_recipe_ids, "seed 0 returns the authored order")
	expect(ScheduleGenerator.recipe_ids(hot_queue, 104076537) == hot_queue.order_recipe_ids, "zero slack returns the authored order for any seed")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	expect(ScheduleGenerator.recipe_ids(slacked, 0) == hot_queue.order_recipe_ids, "seed 0 ignores slack")
	var drawn := ScheduleGenerator.recipe_ids(slacked, 104076537)
	expect(drawn == ScheduleGenerator.recipe_ids(slacked, 104076537), "the same seed draws the same order")
	expect(drawn.size() == hot_queue.order_count, "the draw keeps the order count")
	var counts: Dictionary = {}
	for recipe_id: String in drawn:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	var ranges: Dictionary = slacked.forecast_ranges()
	for recipe_id: String in slacked.menu_ids:
		expect(counts.get(recipe_id, 0) >= ranges[recipe_id]["min"] and counts.get(recipe_id, 0) <= ranges[recipe_id]["max"], "drawn count stays inside the forecast range: " + recipe_id)
	expect(_differs(counts, slacked.baseline_counts()), "a seed with available slack moves at least one order")
	expect(drawn != ScheduleGenerator.recipe_ids(slacked, 53743680), "different seeds draw different orders")
	var identical: int = 0
	for sweep_seed: int in range(1, 51):
		if ScheduleGenerator.recipe_ids(slacked, sweep_seed) == hot_queue.order_recipe_ids:
			identical += 1
	expect(identical == 0, "no seed in 1..50 reproduces the authored order on a slacked scenario (found %d)" % identical)
	var one_sided: Resource = hot_queue.duplicate()
	var one_slack: Dictionary[String, int] = {"grill": 2}
	one_sided.forecast_slack = one_slack
	var one_sided_drawn := ScheduleGenerator.recipe_ids(one_sided, 104076537)
	var one_sided_counts: Dictionary = {}
	for recipe_id: String in one_sided_drawn:
		one_sided_counts[recipe_id] = one_sided_counts.get(recipe_id, 0) + 1
	var one_sided_baseline: Dictionary = one_sided.baseline_counts()
	for recipe_id: String in one_sided.menu_ids:
		expect(one_sided_counts.get(recipe_id, 0) == one_sided_baseline.get(recipe_id, 0),
			"slack on a single menu cannot move anything because no other menu can give or take: " + recipe_id)
	var schedule: Array = slacked.with_service_seed(104076537).order_schedule()
	expect(schedule.size() == hot_queue.order_count, "the seeded scenario schedules every order")
	for index: int in schedule.size():
		expect(schedule[index].recipe_id == drawn[index], "order_schedule uses the drawn recipe per slot")
		expect(schedule[index].arrival_tick == hot_queue.order_arrival_ticks[index], "arrival ticks never change")
	var interval: Resource = campaign.scenario_for("lunch_prep").with_service_seed(104076537)
	var interval_schedule: Array = interval.order_schedule()
	expect(interval_schedule[3].arrival_tick == interval.first_arrival_tick + interval.arrival_interval_ticks * 3, "interval arrivals stay on the formula under a seed")


func _differs(actual: Dictionary, expected: Dictionary) -> bool:
	for recipe_id: String in expected:
		if actual.get(recipe_id, 0) != expected[recipe_id]:
			return true
	return false
