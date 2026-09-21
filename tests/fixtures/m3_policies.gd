extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const TickDriver := preload("res://presentation/tick_driver.gd")

## §4.3 영업별 지렛대(pressure-rebalance.md). 무지렛대 정책은 정책에서 이 종류의 명령만 뺀 것이고,
## "priorities"는 priorities 사전을 비웁니다. 시나리오 .tres의 operation_problem은 표시용이며 게이트는 이 표를 읽습니다.
const LEVER_KINDS: Dictionary = {
	"hot_queue": ["priorities"],
	"shared_stock": ["set_purchase"],
	"long_route": ["move_station", "rotate_station"],
	"split_duties": ["set_duty"],
	"rush_hour": ["set_prep", "priorities"],
}


static func reference_policy(scenario_id: String) -> Dictionary:
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	match scenario_id:
		"lunch_prep":
			_add(policy, "set_prep", "prepped_grain", 4)
			_add(policy, "set_prep", "soup_base", 4)
			_add(policy, "set_prep", "prepped_vegetable", 1)
		"hot_queue":
			_add(policy, "set_prep", "marinated_protein", 1)
			_add(policy, "set_prep", "prepped_vegetable", 3)
			policy.priorities = {"grill": 2}
		"shared_stock":
			_add(policy, "set_purchase", "vegetable", 31)
			_add(policy, "set_prep", "prepped_grain", 5)
			_add(policy, "set_prep", "soup_base", 6)
		"long_route":
			_add(policy, "set_prep", "marinated_protein", 4)
			_moves(policy, "cold_01", "up", 1)
			_moves(policy, "cold_01", "left", 3)
			_moves(policy, "hot_01", "up", 1)
			_moves(policy, "hot_01", "left", 5)
			_add(policy, "rotate_station", "hot_02", null)
			_moves(policy, "hot_02", "up", 2)
		"split_duties":
			_add(policy, "set_duty", "employee_02", "cold")
			_add(policy, "set_duty", "employee_03", "hot")
			_add(policy, "set_duty", "employee_04", "hot")
			_add(policy, "set_prep", "prepped_vegetable", 6)
			_add(policy, "set_prep", "prepped_grain", 3)
			_add(policy, "set_prep", "prepped_mushroom", 4)
			_add(policy, "set_prep", "thawed_protein", 2)
		"rush_hour":
			_add(policy, "set_prep", "prepped_vegetable", 4)
			_add(policy, "set_prep", "prepped_grain", 3)
			_add(policy, "set_prep", "prepped_mushroom", 3)
			policy.priorities = {"grill": 2, "protein_bowl": 2}
		"final_service":
			_add(policy, "set_prep", "marinated_protein", 5)
			_add(policy, "set_prep", "prepped_grain", 3)
	return policy


## 정책에서 주어진 명령 종류만 뺀 사본. "priorities"는 priorities 사전을 비웁니다.
static func without_kinds(policy: Dictionary, kinds: Array) -> Dictionary:
	var stripped: Dictionary = {"preparation": [], "priorities": {}}
	for command: Dictionary in policy.get("preparation", []):
		if command.kind not in kinds:
			stripped.preparation.append(command.duplicate(true))
	if "priorities" not in kinds:
		stripped.priorities = policy.get("priorities", {}).duplicate(true)
	return stripped


## 기준 정책에서 지렛대 종류를 뺀 정책. kinds를 비우면 LEVER_KINDS의 그 영업 항목 전부를 뺍니다.
static func without_lever_policy(scenario_id: String, kinds: Array = []) -> Dictionary:
	var stripped_kinds: Array = kinds if not kinds.is_empty() else LEVER_KINDS.get(scenario_id, [])
	return without_kinds(reference_policy(scenario_id), stripped_kinds)


## tests/sweep_policies.gd --without <지렛대> --best 가 시드 0에서 찾은 가장 강한 무지렛대 정책(best_any).
## 게이트는 이 정책이 한 목표 이상에 미달해야 통과하며, 값의 근거는 docs/notes/kitchen-pressure-verification.md의
## 재조율 절입니다. 아직 스윕하지 않은 영업은 지렛대를 뺀 기준 정책이 그 자리를 채웁니다.
static func lever_free_policy(scenario_id: String) -> Dictionary:
	var policy: Dictionary = without_lever_policy(scenario_id)
	match scenario_id:
		## sweep: --scenario shared_stock --attempt 0 --without set_purchase --best → passed 0, best_any {"prepped_grain": 6, "soup_base": 5} · 15 · 3,700
		"shared_stock":
			policy = {"preparation": [], "priorities": {}}
			_add(policy, "set_prep", "prepped_grain", 6)
			_add(policy, "set_prep", "soup_base", 5)
	return policy


## §4.2의 "추첨 인지 기준 정책": 시드 0 기준 정책 앞에, 원재료마다 작성 발주(기준 정책에 set_purchase가 있으면
## 그 값)와 그 시드의 구성이 필요로 하는 양 가운데 큰 값을 set_purchase로 맞춥니다. 시드 0에서는 기준 정책의 발주와 같습니다.
static func draw_aware_policy(scenario: Definitions, seed_value: int) -> Dictionary:
	var seeded: Definitions = scenario if seed_value == 0 else scenario.with_service_seed(seed_value)
	var needs: Dictionary[String, int] = {}
	for arrival: Dictionary in seeded.order_schedule():
		var recipe := scenario.recipe_for(arrival.recipe_id)
		for ingredient_id: String in recipe.ingredients:
			needs[ingredient_id] = needs.get(ingredient_id, 0) + recipe.ingredients[ingredient_id]
	var reference := reference_policy(scenario.id)
	var authored: Dictionary = scenario.purchases.duplicate()
	for command: Dictionary in reference.preparation:
		if command.kind == "set_purchase":
			authored[command.target_id] = command.value
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	for ingredient: Definitions.IngredientDef in scenario.ingredients:
		if not ingredient.purchasable:
			continue
		var quantity: int = maxi(authored.get(ingredient.id, 0), needs.get(ingredient.id, 0))
		if quantity > 0:
			_add(policy, "set_purchase", ingredient.id, quantity)
	policy.preparation.append_array(without_kinds(reference, ["set_purchase"]).preparation)
	policy.priorities = reference.priorities.duplicate(true)
	return policy


static func passes_targets(scenario: Definitions, run: Dictionary) -> bool:
	return run.accepted and run.snapshot.accounting.served >= scenario.minimum_served \
		and run.snapshot.accounting.profit >= scenario.minimum_profit


static func alternative_policies(scenario_id: String) -> Array[Dictionary]:
	var alternatives: Array[Dictionary] = []
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	match scenario_id:
		"first_shift":
			_add(policy, "set_prep", "prepped_vegetable", 2)
		"lunch_prep":
			_add(policy, "set_prep", "prepped_vegetable", 6)
		"hot_queue":
			_add(policy, "set_prep", "marinated_protein", 1)
			_add(policy, "set_prep", "prepped_grain", 1)
			_add(policy, "set_prep", "soup_base", 1)
			_add(policy, "set_prep", "prepped_vegetable", 1)
			policy.priorities = {"grill": 2, "soup": 0}
		"shared_stock":
			_add(policy, "set_purchase", "vegetable", 29)
			_add(policy, "set_prep", "prepped_grain", 4)
			_add(policy, "set_prep", "soup_base", 4)
		"long_route":
			_add(policy, "set_prep", "marinated_protein", 4)
			_moves(policy, "cold_01", "up", 1)
			_moves(policy, "cold_01", "left", 3)
			_moves(policy, "hot_01", "up", 1)
			_moves(policy, "hot_01", "left", 4)
			_add(policy, "rotate_station", "hot_02", null)
			_moves(policy, "hot_02", "up", 2)
		"split_duties":
			_add(policy, "set_prep", "prepped_vegetable", 3)
			_add(policy, "set_prep", "prepped_grain", 4)
			_add(policy, "set_prep", "thawed_protein", 1)
			_add(policy, "set_prep", "prepped_mushroom", 5)
		"rush_hour":
			_add(policy, "set_prep", "marinated_protein", 1)
			_add(policy, "set_prep", "prepped_vegetable", 5)
			_add(policy, "set_prep", "prepped_grain", 3)
			_add(policy, "set_prep", "thawed_protein", 1)
			_add(policy, "set_prep", "prepped_mushroom", 3)
		"final_service":
			_add(policy, "set_prep", "marinated_protein", 6)
			_moves(policy, "hot_02", "right", 1)
	if not policy.preparation.is_empty() or not policy.priorities.is_empty():
		alternatives.append(policy)
	policy = {"preparation": [], "priorities": {}}
	match scenario_id:
		"first_shift":
			_add(policy, "set_purchase", "vegetable", 11)
		"lunch_prep":
			_add(policy, "set_purchase", "vegetable", 19)
		"hot_queue":
			policy = reference_policy(scenario_id)
			_add(policy, "set_purchase", "protein", 5)
		"shared_stock":
			_add(policy, "set_purchase", "vegetable", 31)
			policy.priorities = {"soup": 2}
		"long_route":
			policy = reference_policy(scenario_id)
			_add(policy, "set_duty", "employee_03", "hot")
		"split_duties":
			_add(policy, "set_prep", "prepped_vegetable", 6)
			_add(policy, "set_prep", "prepped_mushroom", 4)
		"rush_hour":
			policy.priorities = {"mushroom_soup": 0}
		"final_service":
			policy = reference_policy(scenario_id)
			_add(policy, "set_purchase", "protein", 6)
	if not policy.preparation.is_empty() or not policy.priorities.is_empty():
		alternatives.append(policy)
	return alternatives


static func run_policy(scenario: Definitions, policy: Dictionary = {}, speed: int = 1, seed_value: int = 0) -> Dictionary:
	var seeded: Definitions = scenario if seed_value == 0 else scenario.with_service_seed(seed_value)
	var plan := PreparationPlan.new(seeded)
	var sequence: int = 0
	for choice: Dictionary in policy.get("preparation", []):
		sequence += 1
		var command := choice.duplicate(true)
		command.apply_tick = 0
		command.sequence = sequence
		var result := plan.apply_command(command)
		if not result.accepted:
			return {"accepted": false, "reason": "preparation: " + str(command) + " " + result.reason}
	var committed := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": sequence + 1})
	if not committed.accepted:
		return {"accepted": false, "reason": "start: " + committed.reason}
	var sim := ServiceSim.new(committed.definitions, null, committed.options)
	var driver := TickDriver.new(sim)
	driver.set_speed(speed)
	driver.set_paused(false)
	sequence = 0
	for arrival: Dictionary in seeded.order_schedule():
		_drive_to(driver, sim, arrival.arrival_tick, speed)
		if policy.get("priorities", {}).has(arrival.recipe_id):
			sequence += 1
			var result := sim.enqueue_command({"kind": "set_priority", "target_id": arrival.id,
				"value": policy.priorities[arrival.recipe_id], "apply_tick": sim.tick + 1, "sequence": sequence})
			if not result.accepted:
				return {"accepted": false, "reason": "priority: " + result.reason}
	_drive_to(driver, sim, scenario.closing_tick, speed)
	return {"accepted": true, "snapshot": sim.snapshot(), "hash": sim.state_hash(), "selection": committed.selection}


static func _drive_to(driver: TickDriver, sim: ServiceSim, target_tick: int, speed: int) -> void:
	var frames: Array[int] = [16667, 5001, 33001]
	if speed == 4:
		frames.assign([99991, 333, 70001])
	var frame: int = 0
	while sim.tick < target_tick and not sim.closed:
		var remaining: int = (target_tick - sim.tick) * 100000 - driver.accumulator_us
		driver.advance_microseconds(mini(frames[frame % frames.size()], remaining / speed))
		driver.take_events()
		frame += 1


static func _add(policy: Dictionary, kind: String, target: String, value: Variant) -> void:
	policy.preparation.append({"kind": kind, "target_id": target, "value": value})


static func _moves(policy: Dictionary, target: String, direction: String, count: int) -> void:
	for _index: int in count:
		_add(policy, "move_station", target, direction)
