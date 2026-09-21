extends "res://tests/harness.gd"

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const SeedGate := preload("res://tests/fixtures/seed_gate.gd")
const ATTEMPTS: Array[int] = [1, 2, 3, 4, 5]


func run(_tree: SceneTree) -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_test_draw_aware_policy(campaign)
	_test_synthetic_failures(campaign)
	_test_campaign_gate(campaign)


## 시드 0의 추첨은 작성된 순서이므로 추첨 인지 발주는 작성된 purchases와 같아야 하고, 시드가 있으면 그
## 시드의 구성이 필요로 하는 양이어야 합니다.
func _test_draw_aware_policy(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		var policy: Dictionary = Policies.draw_aware_policy(scenario, 0)
		var purchases: Dictionary = {}
		for command: Dictionary in policy.preparation:
			if command.kind == "set_purchase":
				purchases[command.target_id] = command.value
		var reference: Dictionary = Policies.reference_policy(scenario.id)
		var expected: Dictionary = scenario.purchases.duplicate()
		for command: Dictionary in reference.preparation:
			if command.kind == "set_purchase":
				expected[command.target_id] = command.value
		expect(purchases == expected, "seed 0 draw-aware purchases equal the authored purchases overlaid by the reference purchase commands: " + scenario.id)
		var behind: Dictionary = Policies.without_kinds(reference, ["set_purchase"])
		expect(policy.preparation.slice(purchases.size()) == behind.preparation and policy.priorities == reference.priorities,
			"the draw-aware policy is the reference policy behind its purchases: " + scenario.id)
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	var seed_value: int = ScheduleGenerator.service_seed_for("hot_queue", 1)
	var drawn: Dictionary = {}
	for arrival: Dictionary in slacked.with_service_seed(seed_value).order_schedule():
		var recipe: Resource = slacked.recipe_for(arrival.recipe_id)
		for ingredient_id: String in recipe.ingredients:
			drawn[ingredient_id] = drawn.get(ingredient_id, 0) + recipe.ingredients[ingredient_id]
	var expected_purchases: Dictionary = {}
	for ingredient_id: String in hot_queue.purchases:
		expected_purchases[ingredient_id] = maxi(hot_queue.purchases[ingredient_id], drawn.get(ingredient_id, 0))
	for ingredient_id: String in drawn:
		if not expected_purchases.has(ingredient_id):
			expected_purchases[ingredient_id] = drawn[ingredient_id]
	var seeded_policy: Dictionary = Policies.draw_aware_policy(slacked, seed_value)
	var seeded_purchases: Dictionary = {}
	for command: Dictionary in seeded_policy.preparation:
		if command.kind == "set_purchase":
			seeded_purchases[command.target_id] = command.value
	var seeded_ids: PackedStringArray = []
	for arrival: Dictionary in slacked.with_service_seed(seed_value).order_schedule():
		seeded_ids.append(arrival.recipe_id)
	expect(seeded_ids != hot_queue.order_recipe_ids, "the seeded fixture draws a different order than the authored one")
	expect(seeded_purchases == expected_purchases,
		"a seeded draw-aware policy raises each purchase to what the drawn composition needs and keeps the authored surplus")
	var run: Dictionary = Policies.run_policy(slacked, seeded_policy, 1, seed_value)
	expect(run.accepted and run.snapshot.orders.size() == slacked.order_count, "run_policy executes a seeded schedule")
	var repeat: Dictionary = Policies.run_policy(slacked, seeded_policy, 1, seed_value)
	expect(repeat.accepted and repeat.hash == run.hash, "a seeded run repeats its final state hash")


## 게이트는 풀리지 않는 fixture에서 실패해야 합니다(§10). 첫째: 손익 목표를 예보 상한의 최대 손익과 같게
## 두면 어떤 실제 영업도 닿지 못합니다. 둘째: 목표가 없다시피 하면 무계획이 통과해 게이트가 실패합니다.
func _test_synthetic_failures(campaign: Resource) -> void:
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var unsolvable: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	unsolvable.forecast_slack = slack
	unsolvable.minimum_profit = unsolvable.maximum_profit(unsolvable.order_count)
	expect(unsolvable.validate().is_empty(), "the unsolvable fixture is still valid content")
	var verdict: Dictionary = SeedGate.evaluate(campaign, unsolvable, ATTEMPTS)
	expect(not verdict.passed and verdict.failures.size() == ATTEMPTS.size()
		and verdict.failures[0].begins_with("attempt 1:") and verdict.failures[0].contains("misses the targets"),
		"a profit target equal to the forecast maximum fails the gate on every attempt")
	var trivial: Resource = hot_queue.duplicate()
	trivial.forecast_slack = slack
	trivial.minimum_served = 1
	trivial.minimum_profit = -trivial.starting_budget
	verdict = SeedGate.evaluate(campaign, trivial, ATTEMPTS)
	expect(not verdict.passed and verdict.failures.size() == ATTEMPTS.size()
		and verdict.failures[0].contains("no plan misses by less than"),
		"targets the no-plan service reaches fail the gate on every attempt")
	var narrow: Resource = hot_queue.duplicate()
	var no_plan: Dictionary = Policies.run_policy(hot_queue)
	narrow.minimum_served = no_plan.snapshot.accounting.served + 1
	narrow.minimum_profit = no_plan.snapshot.accounting.profit
	expect(narrow.validate().is_empty(), "the narrow fixture is still valid content")
	var seed_zero: Array[int] = [0]
	verdict = SeedGate.evaluate(campaign, narrow, seed_zero)
	expect(not verdict.passed and verdict.failures.size() == 1
		and verdict.failures[0].begins_with("attempt 0:") and verdict.failures[0].contains("no plan misses by less than"),
		"targets the no-plan service misses by one order fail the widened gate")


func _test_campaign_gate(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		var verdict: Dictionary = SeedGate.evaluate(campaign, scenario, ATTEMPTS)
		expect(verdict.passed, "attempts 1-5 are solvable and pressured: %s %s" % [scenario.id, ", ".join(verdict.failures)])
		for attempt: int in ATTEMPTS:
			var seed_value: int = ScheduleGenerator.service_seed_for(scenario.id, attempt)
			if scenario.forecast_slack.is_empty():
				expect(ScheduleGenerator.recipe_ids(scenario, seed_value) == scenario.order_recipe_ids,
					"an empty forecast slack reproduces the authored order on attempt %d: %s" % [attempt, scenario.id])
		for row: Dictionary in verdict.rows:
			print("SEED_GATE ", scenario.id, " ", JSON.stringify(row, "", true))
