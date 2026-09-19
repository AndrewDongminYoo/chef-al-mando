extends RefCounted

## (시나리오, 시드) → 주문 메뉴 순서의 순수 함수.
## 시드 0은 작성된 순서를 그대로 돌려주고, 그 외 시드는 예보 범위 안에서 건수를 옮긴 뒤 슬롯을 섞습니다.
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
	if service_seed == 0:
		return authored.duplicate()
	var ranges: Dictionary = scenario.forecast_ranges()
	var counts: Dictionary[String, int] = {}
	var total_slack: int = 0
	for recipe_id: String in scenario.menu_ids:
		counts[recipe_id] = ranges[recipe_id]["baseline"]
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	var rng := RandomNumberGenerator.new()
	rng.seed = service_seed
	var moves: int = rng.randi_range(1, maxi(total_slack, 1))
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
		counts[donor] -= 1
		counts[receiver] += 1
	if counts == scenario.baseline_counts():
		return authored.duplicate()
	var result: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		for _index: int in counts[recipe_id]:
			result.append(recipe_id)
	for index: int in range(result.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := result[index]
		result[index] = result[swap_index]
		result[swap_index] = held
	return result


static func _receivers(scenario: Resource, counts: Dictionary, ranges: Dictionary, donor: String) -> PackedStringArray:
	var receivers: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		if recipe_id != donor and counts[recipe_id] < ranges[recipe_id]["max"]:
			receivers.append(recipe_id)
	return receivers
