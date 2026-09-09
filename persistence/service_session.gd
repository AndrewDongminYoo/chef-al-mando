extends RefCounted

const CampaignDef := preload("res://content/campaign_def.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const MAX_SAFE_INTEGER: float = 9007199254740991.0
const MAX_SAFE_INTEGER_INT: int = 9007199254740991
const TICK_US: int = 100000


static func capture(scenario_id: String, selection: Dictionary, simulation: ServiceSim, speed: int = 1,
	accumulator_us: int = 0) -> Dictionary:
	return {"scenario_id": scenario_id, "preparation": selection.duplicate(true),
		"simulation": simulation.export_state(), "speed": speed, "accumulator_us": accumulator_us}


static func restore(campaign: CampaignDef, session: Dictionary, records: Dictionary) -> Dictionary:
	if campaign == null or not campaign.validate().is_empty():
		return _failure("invalid_campaign")
	var normalized := _normalize_json(session)
	if not normalized.accepted:
		return _failure("invalid_session")
	var saved: Dictionary = normalized.value
	if saved.size() != 5:
		return _failure("invalid_session")
	for field: String in ["scenario_id", "preparation", "simulation", "speed", "accumulator_us"]:
		if not saved.has(field):
			return _failure("invalid_session")
	if not saved.scenario_id is String or not saved.preparation is Dictionary or not saved.simulation is Dictionary:
		return _failure("invalid_session")
	if not saved.speed is int or saved.speed not in [1, 2, 4]:
		return _failure("invalid_speed")
	if not saved.accumulator_us is int or saved.accumulator_us < 0 or saved.accumulator_us >= TICK_US:
		return _failure("invalid_accumulator")
	var progress := CampaignProgress.new(campaign, records)
	if not progress.errors.is_empty():
		return _failure("invalid_records")
	if not progress.is_unlocked(saved.scenario_id):
		return _failure("locked_service")
	var scenario = campaign.scenario_for(saved.scenario_id)
	if scenario == null:
		return _failure("unknown_service")
	if not _exact_preparation(scenario, saved.preparation):
		return _failure("invalid_preparation")
	var preparation := PreparationPlan.new(scenario, saved.preparation)
	var started := preparation.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	if not started.accepted:
		return _failure("invalid_preparation")
	var restored := ServiceSim.restore(started.definitions, saved.simulation, started.options)
	if not restored.accepted:
		return _failure(restored.reason)
	return {"accepted": true, "reason": "", "simulation": restored.simulation,
		"definitions": started.definitions, "selection": started.selection.duplicate(true),
		"scenario_id": saved.scenario_id, "speed": saved.speed, "accumulator_us": saved.accumulator_us}


static func _normalize_json(value: Variant) -> Dictionary:
	if value is float:
		if not is_finite(value) or value != floor(value) or absf(value) > MAX_SAFE_INTEGER:
			return {"accepted": false}
		return {"accepted": true, "value": int(value)}
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value:
			var normalized_item := _normalize_json(item)
			if not normalized_item.accepted:
				return {"accepted": false}
			normalized_array.append(normalized_item.value)
		return {"accepted": true, "value": normalized_array}
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key: Variant in value:
			if not key is String:
				return {"accepted": false}
			var normalized_item := _normalize_json(value[key])
			if not normalized_item.accepted:
				return {"accepted": false}
			normalized_dictionary[key] = normalized_item.value
		return {"accepted": true, "value": normalized_dictionary}
	if value is int:
		if value < -MAX_SAFE_INTEGER_INT or value > MAX_SAFE_INTEGER_INT:
			return {"accepted": false}
		return {"accepted": true, "value": value}
	if value == null or value is bool or value is String:
		return {"accepted": true, "value": value}
	return {"accepted": false}


static func _exact_preparation(scenario: Resource, selection: Dictionary) -> bool:
	var fields: Array[String] = ["purchases", "prep_quantities", "placements", "duties"]
	if not _exact_fields(selection, fields):
		return false
	var defaults: Variant = PreparationPlan.new(scenario).snapshot().get("selection")
	if not defaults is Dictionary:
		return false
	for field: String in fields:
		if not selection[field] is Dictionary or not _same_keys(selection[field], defaults[field]):
			return false
	var placement_fields: Array[String] = ["tile", "work_position"]
	for placement: Variant in selection.placements.values():
		if not _exact_fields(placement, placement_fields):
			return false
	return true


static func _same_keys(candidate: Dictionary, expected: Dictionary) -> bool:
	if candidate.size() != expected.size():
		return false
	for key: Variant in expected:
		if not candidate.has(key):
			return false
	return true


static func _exact_fields(value: Variant, fields: Array[String]) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
