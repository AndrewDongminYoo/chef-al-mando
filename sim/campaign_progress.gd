extends RefCounted

const CampaignDef := preload("res://content/campaign_def.gd")

var errors: Array[String] = []
var _campaign: CampaignDef
var _records: Dictionary = {}


func _init(campaign: CampaignDef, records: Dictionary = {}) -> void:
	_campaign = campaign
	errors = campaign.validate()
	errors.append_array(validate_records(campaign, records))
	if errors.is_empty():
		_records = records.duplicate(true)


static func validate_records(campaign: CampaignDef, records: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for scenario_id: Variant in records:
		if not scenario_id is String or campaign.scenario_for(scenario_id) == null:
			problems.append("record contains an unknown service")
			continue
		var scenario := campaign.scenario_for(scenario_id)
		var record: Variant = records[scenario_id]
		var has_legacy_completion: bool = record is Dictionary and record.get("legacy_completed") == true
		if not record is Dictionary or (record.size() != 3 and not (record.size() == 4 and has_legacy_completion)):
			problems.append("invalid record fields")
			continue
		if not record.get("completed") is bool or not record.get("best_served") is int or not record.get("best_profit") is int:
			problems.append("invalid record value types")
			continue
		if record.best_served < 0 or record.best_served > scenario.order_count or record.best_profit < -scenario.starting_budget or record.best_profit > scenario.maximum_profit(record.best_served):
			problems.append("record value is outside the service limits")
		if has_legacy_completion and not record.completed:
			problems.append("legacy completion marker requires a completed record")
		if record.completed and not has_legacy_completion \
			and (record.best_served < scenario.minimum_served or record.best_profit < scenario.minimum_profit):
			problems.append("completed record does not meet its targets")
	if not problems.is_empty():
		return problems
	var previous_complete := true
	for scenario: CampaignDef.ScenarioDef in campaign.scenarios:
		if scenario == null:
			continue
		if records.has(scenario.id) and not previous_complete:
			problems.append("record skips an incomplete earlier service")
		previous_complete = previous_complete and records.get(scenario.id, {}).get("completed", false)
	return problems


func is_unlocked(scenario_id: String) -> bool:
	if not errors.is_empty():
		return false
	for scenario: CampaignDef.ScenarioDef in _campaign.scenarios:
		if scenario.id == scenario_id:
			return true
		if not _records.get(scenario.id, {}).get("completed", false):
			return false
	return false


func record_result(scenario_id: String, result: Dictionary) -> Dictionary:
	if not is_unlocked(scenario_id):
		return {"accepted": false, "reason": "locked_service"}
	var scenario := _campaign.scenario_for(scenario_id)
	if result.get("closed") != true or result.get("tick") != scenario.closing_tick or result.get("errors", ["missing"]) != []:
		return {"accepted": false, "reason": "service_not_closed"}
	var accounting: Variant = result.get("accounting")
	if not accounting is Dictionary or not accounting.get("served") is int or not accounting.get("profit") is int:
		return {"accepted": false, "reason": "invalid_result"}
	if accounting.served < 0 or accounting.served > scenario.order_count or accounting.profit < -scenario.starting_budget or accounting.profit > scenario.maximum_profit(accounting.served):
		return {"accepted": false, "reason": "invalid_result"}
	var passed: bool = accounting.served >= scenario.minimum_served and accounting.profit >= scenario.minimum_profit
	var previous: Dictionary = _records.get(scenario_id, {})
	var record := {"completed": passed or previous.get("completed", false),
		"best_served": maxi(accounting.served, previous.get("best_served", accounting.served)),
		"best_profit": maxi(accounting.profit, previous.get("best_profit", accounting.profit))}
	if previous.get("legacy_completed") == true and not passed:
		record.legacy_completed = true
	var candidate := _records.duplicate(true)
	candidate[scenario_id] = record
	if not validate_records(_campaign, candidate).is_empty():
		return {"accepted": false, "reason": "invalid_result"}
	var changed := candidate != _records
	_records = candidate
	return {"accepted": true, "passed": passed, "changed": changed,
		"served": accounting.served, "profit": accounting.profit,
		"minimum_served": scenario.minimum_served, "minimum_profit": scenario.minimum_profit}


func snapshot() -> Dictionary:
	var unlocked: PackedStringArray = PackedStringArray()
	for scenario: CampaignDef.ScenarioDef in _campaign.scenarios:
		if scenario != null and is_unlocked(scenario.id):
			unlocked.append(scenario.id)
	var ending: bool = errors.is_empty() and not _campaign.scenarios.is_empty() and _records.get(_campaign.scenarios[-1].id, {}).get("completed", false)
	return {"records": _records.duplicate(true), "unlocked": unlocked, "ending_unlocked": ending, "errors": errors.duplicate()}
