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
	expect(
		ScheduleGenerator.recipe_ids(hot_queue, 0) == hot_queue.order_recipe_ids, "seed 0 returns the authored order"
	)
	var fixed: Resource = hot_queue.duplicate()
	var no_slack: Dictionary[String, int] = {}
	fixed.forecast_slack = no_slack
	expect(
		ScheduleGenerator.recipe_ids(fixed, 104076537) == hot_queue.order_recipe_ids,
		"zero slack returns the authored order for any seed"
	)
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
		expect(
			(
				counts.get(recipe_id, 0) >= ranges[recipe_id]["min"]
				and counts.get(recipe_id, 0) <= ranges[recipe_id]["max"]
			),
			"drawn count stays inside the forecast range: " + recipe_id
		)
	expect(_differs(counts, slacked.baseline_counts()), "a seed with available slack moves at least one order")
	expect(drawn != ScheduleGenerator.recipe_ids(slacked, 53743680), "different seeds draw different orders")
	var changed: int = 0
	for index: int in drawn.size():
		if drawn[index] != hot_queue.order_recipe_ids[index]:
			changed += 1
	var total_slack: int = 0
	for recipe_id: String in slacked.menu_ids:
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	expect(
		changed >= 1 and changed <= total_slack,
		"a seeded draw changes between one slot and the total slack (changed %d of %d)" % [changed, total_slack]
	)
	var authored_runs: Dictionary = _longest_runs(hot_queue.order_recipe_ids)
	var drawn_runs: Dictionary = _longest_runs(drawn)
	# 2026-09-22 재조율 뒤의 작성 순서(salad·grill 묶음 → soup → grill → salad, 네 묶음)는 묶음 경계에서만 샐러드가 두 번 이어집니다.
	expect(
		authored_runs.get("soup", 0) == 1 and authored_runs.get("grill", 0) == 1 and authored_runs.get("salad", 0) == 2,
		"the authored hot_queue order repeats a menu only where a wave's last salad meets the next wave's first"
	)
	expect(
		drawn_runs.get("soup", 0) == 1 and drawn_runs.get("grill", 0) == 1 and drawn_runs.get("salad", 0) == 3,
		"seed 104076537 raises salad's longest run from 2 to 3 and leaves the others at 1"
	)
	var identical: int = 0
	for sweep_seed: int in range(1, 51):
		if ScheduleGenerator.recipe_ids(slacked, sweep_seed) == hot_queue.order_recipe_ids:
			identical += 1
	expect(
		identical == 0, "no seed in 1..50 reproduces the authored order on a slacked scenario (found %d)" % identical
	)
	var authored_pattern := PackedStringArray(["grill", "grill", "soup", "salad"])
	var broken := ScheduleGenerator.break_identity(authored_pattern.duplicate(), authored_pattern)
	expect(broken != authored_pattern, "a shuffle that lands on the authored order is broken deterministically")
	expect(
		broken == PackedStringArray(["grill", "soup", "grill", "salad"]),
		"the fallback swaps the first adjacent pair of different recipes"
	)
	var sorted_broken := Array(broken)
	sorted_broken.sort()
	var sorted_authored := Array(authored_pattern)
	sorted_authored.sort()
	expect(sorted_broken == sorted_authored, "the fallback keeps the drawn counts")
	var already_different := PackedStringArray(["soup", "grill", "grill", "salad"])
	expect(
		ScheduleGenerator.break_identity(already_different.duplicate(), authored_pattern) == already_different,
		"a result that already differs is returned unchanged"
	)
	var single_menu := PackedStringArray(["salad", "salad", "salad"])
	expect(
		ScheduleGenerator.break_identity(single_menu.duplicate(), single_menu) == single_menu,
		"a single-menu order has no distinguishable permutation and stays authored"
	)
	var one_sided: Resource = hot_queue.duplicate()
	var one_slack: Dictionary[String, int] = {"grill": 2}
	one_sided.forecast_slack = one_slack
	var one_sided_drawn := ScheduleGenerator.recipe_ids(one_sided, 104076537)
	var one_sided_counts: Dictionary = {}
	for recipe_id: String in one_sided_drawn:
		one_sided_counts[recipe_id] = one_sided_counts.get(recipe_id, 0) + 1
	var one_sided_baseline: Dictionary = one_sided.baseline_counts()
	for recipe_id: String in one_sided.menu_ids:
		expect(
			one_sided_counts.get(recipe_id, 0) == one_sided_baseline.get(recipe_id, 0),
			"slack on a single menu cannot move anything because no other menu can give or take: " + recipe_id
		)
	expect(
		one_sided_drawn == hot_queue.order_recipe_ids,
		"a slack that allows no move returns the authored order, so changed slots never exceed the total slack"
	)
	var schedule: Array = slacked.with_service_seed(104076537).order_schedule()
	expect(schedule.size() == hot_queue.order_count, "the seeded scenario schedules every order")
	for index: int in schedule.size():
		expect(schedule[index].recipe_id == drawn[index], "order_schedule uses the drawn recipe per slot")
		expect(schedule[index].arrival_tick == hot_queue.order_arrival_ticks[index], "arrival ticks never change")
	var interval: Resource = campaign.scenario_for("lunch_prep").with_service_seed(104076537)
	var interval_schedule: Array = interval.order_schedule()
	expect(
		interval_schedule[3].arrival_tick == interval.first_arrival_tick + interval.arrival_interval_ticks * 3,
		"interval arrivals stay on the formula under a seed"
	)


func _differs(actual: Dictionary, expected: Dictionary) -> bool:
	for recipe_id: String in expected:
		if actual.get(recipe_id, 0) != expected[recipe_id]:
			return true
	return false


func _longest_runs(recipe_ids: PackedStringArray) -> Dictionary:
	var longest: Dictionary = {}
	var current: String = ""
	var length: int = 0
	for recipe_id: String in recipe_ids:
		length = length + 1 if recipe_id == current else 1
		current = recipe_id
		longest[recipe_id] = maxi(longest.get(recipe_id, 0), length)
	return longest
