extends RefCounted

## (시나리오, 시드) → 주문 메뉴 순서의 순수 함수.
## 시드 0이거나 모든 메뉴의 slack 합이 0이면 작성된 순서를 그대로 돌려줍니다.
## 그 외에는 예보 범위 안에서 건수를 옮기되, 한 이동은 기증 메뉴가 든 슬롯 하나를 수신 메뉴로 바꾸는 것이고
## 슬롯을 섞지 않으므로 작성된 파동 구조가 유지됩니다.
## 시뮬레이션 상태, 시계, 저장 파일을 읽지 않습니다.

const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619
const MASK_32: int = 0xFFFFFFFF


static func stable_hash(text: String) -> int:
	var hash_value: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * FNV_PRIME) & MASK_32
	return hash_value


static func service_seed_for(scenario_id: String, attempt_index: int) -> int:
	if attempt_index <= 0:
		return 0
	var hash_value := stable_hash("%s:%d" % [scenario_id, attempt_index])
	return hash_value if hash_value != 0 else 1


static func recipe_ids(scenario: Resource, service_seed: int) -> PackedStringArray:
	var authored: PackedStringArray = scenario.order_recipe_ids
	var ranges: Dictionary = scenario.forecast_ranges()
	var counts: Dictionary[String, int] = {}
	var total_slack: int = 0
	for recipe_id: String in scenario.menu_ids:
		counts[recipe_id] = ranges[recipe_id]["baseline"]
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	if service_seed == 0 or total_slack == 0:
		return authored.duplicate()
	var result: PackedStringArray = authored.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = service_seed
	var moves: int = rng.randi_range(1, total_slack)
	for _move: int in moves:
		var donors: PackedStringArray = []
		for recipe_id: String in scenario.menu_ids:
			if counts[recipe_id] > ranges[recipe_id]["min"] and not _receivers(scenario, counts, ranges, recipe_id).is_empty():
				donors.append(recipe_id)
		if donors.is_empty():
			break
		var donor: String = donors[rng.randi_range(0, donors.size() - 1)]
		var receivers := _receivers(scenario, counts, ranges, donor)
		var receiver: String = receivers[rng.randi_range(0, receivers.size() - 1)]
		var slots: PackedInt32Array = []
		for index: int in result.size():
			if result[index] == donor:
				slots.append(index)
		result[slots[rng.randi_range(0, slots.size() - 1)]] = receiver
		counts[donor] -= 1
		counts[receiver] += 1
	return break_identity(result, authored)


## If no move is possible at all, the result equals the authored order. A seeded draw must differ
## from the authored order, so swap the first adjacent pair of different recipes; only a scenario
## whose every slot is the same recipe keeps the authored order.
static func break_identity(result: PackedStringArray, authored: PackedStringArray) -> PackedStringArray:
	if result != authored:
		return result
	var distinct := result.duplicate()
	for index: int in range(distinct.size() - 1):
		if distinct[index] != distinct[index + 1]:
			var held := distinct[index]
			distinct[index] = distinct[index + 1]
			distinct[index + 1] = held
			return distinct
	return distinct


static func _receivers(scenario: Resource, counts: Dictionary, ranges: Dictionary, donor: String) -> PackedStringArray:
	var receivers: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		if recipe_id != donor and counts[recipe_id] < ranges[recipe_id]["max"]:
			receivers.append(recipe_id)
	return receivers
