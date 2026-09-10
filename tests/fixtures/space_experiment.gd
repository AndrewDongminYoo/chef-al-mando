extends RefCounted

const ScenarioDef := preload("res://content/scenario_def.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")
const SCENARIOS: Array[String] = ["hot_queue", "long_route"]
const LAYOUTS: Array[String] = ["original", "clustered", "legacy"]
const DUTIES: Array[String] = ["all", "dedicated"]


static func scenario(scenario_id: String, constrained: bool = true) -> ScenarioDef:
	if scenario_id not in SCENARIOS:
		return null
	var data := load("res://content/campaign/scenarios/" + scenario_id + ".tres").duplicate(true) as ScenarioDef
	data.space_rules = constrained
	for station: Resource in data.stations:
		station.fixed = constrained and station.fixed
	return data


static func policy(scenario_id: String, layout: String = "original", duties: String = "all") -> Dictionary:
	assert(scenario_id in SCENARIOS and layout in LAYOUTS and duties in DUTIES)
	var result: Dictionary = {"preparation": [], "priorities": {}}
	_add(result, "set_prep", "grill", 4)
	if scenario_id == "hot_queue":
		_add(result, "set_menu_priority", "grill", 2)
	if layout == "legacy":
		for choice: Dictionary in Policies.reference_policy(scenario_id).preparation:
			if choice.kind in ["move_station", "rotate_station"]:
				result.preparation.append(choice.duplicate(true))
		_moves(result, "pass_01", "up", 1)
	elif layout == "clustered":
		if scenario_id == "hot_queue":
			_moves(result, "cold_01", "left", 2)
			_moves(result, "hot_01", "left", 3)
		else:
			_moves(result, "cold_01", "up", 1)
			_moves(result, "cold_01", "left", 3)
			_moves(result, "hot_01", "up", 1)
			_moves(result, "hot_01", "left", 5)
			_add(result, "rotate_station", "hot_02", null)
			_moves(result, "hot_02", "up", 2)
	if duties == "dedicated":
		_add(result, "set_duty", "employee_01", "cold")
		_add(result, "set_duty", "employee_02", "hot")
		if scenario_id == "long_route":
			_add(result, "set_duty", "employee_03", "hot")
	return result


static func _add(result: Dictionary, kind: String, target: String, value: Variant) -> void:
	result.preparation.append({"kind": kind, "target_id": target, "value": value})


static func _moves(result: Dictionary, target: String, direction: String, count: int) -> void:
	for _index: int in count:
		_add(result, "move_station", target, direction)
