extends RefCounted

const CampaignDef := preload("res://content/campaign_def.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
## The lowest targets any shipped content version had, per field: a completion earned under an
## earlier content version keeps its legacy_completed marker only while it clears this floor.
## hot_queue shipped at 14 / 1,500 (content 1), 12 / 5,000 (content 2), 12 / 4,750 (content 3-6) and
## 14 / 5,600 (content 7);
## every other service only ever rose from its content 1 values.
const LEGACY_COMPLETION_TARGETS := {
	"first_shift": {"minimum_served": 10, "minimum_profit": 1000},
	"lunch_prep": {"minimum_served": 14, "minimum_profit": 1000},
	"hot_queue": {"minimum_served": 12, "minimum_profit": 1500},
	"shared_stock": {"minimum_served": 16, "minimum_profit": 1500},
	"long_route": {"minimum_served": 17, "minimum_profit": 2000},
	"split_duties": {"minimum_served": 19, "minimum_profit": 2500},
	"rush_hour": {"minimum_served": 22, "minimum_profit": 3000},
	"final_service": {"minimum_served": 24, "minimum_profit": 4000},
}
## The pre-content-7 composition of every scenario whose maximum_profit(served) content 7 lowered,
## as the margin multiset and labor cost ScenarioDef.maximum_profit would have summed: a best profit
## earned under that composition stays valid (validate_records widens its bound to this old cap)
## instead of being rewritten, so the widened bound only ever admits values a shipped composition
## could pay.
## hot_queue was grill 10 / soup 5 / salad 5 with no forecast_slack (grill 1,500 - protein 400 = 1,100;
## soup 900 - grain 150 - 2 x vegetable 100 = 550; salad 500 - vegetable 100 = 400; labor_cost 2,000).
## Extend this table whenever a future content version lowers a scenario's cap; without an entry an
## old best above the new cap is corrupt.
const LEGACY_PROFIT_CAPS := {
	"hot_queue": {"margins": [1100, 1100, 1100, 1100, 1100, 1100, 1100, 1100, 1100, 1100,
		550, 550, 550, 550, 550, 400, 400, 400, 400, 400], "labor_cost": 2000},
}

var errors: Array[String] = []
var _campaign: CampaignDef
var _records: Dictionary = {}
var _attempts: Dictionary = {}


func _init(campaign: CampaignDef, records: Dictionary = {}, attempts: Dictionary = {}) -> void:
	_campaign = campaign
	errors = campaign.validate()
	errors.append_array(validate_records(campaign, records))
	errors.append_array(validate_attempts(campaign, attempts))
	if errors.is_empty():
		_records = records.duplicate(true)
		_attempts = attempts.duplicate(true)


static func validate_attempts(campaign: CampaignDef, attempts: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for scenario_id: Variant in attempts:
		if not scenario_id is String or campaign.scenario_for(scenario_id) == null:
			problems.append("attempts contain an unknown service")
		elif not attempts[scenario_id] is int or attempts[scenario_id] < 0:
			problems.append("invalid attempt count")
	return problems


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
		# A best profit is bounded by the highest cap any shipped composition paid for that served
		# count, so a best earned before content 7 lowered hot_queue's cap stays valid without being
		# rewritten; scenarios without a legacy cap keep the strict current bound, and record_result
		# bounds every new result by the current cap alone.
		var profit_cap: int = maxi(scenario.maximum_profit(record.best_served), legacy_maximum_profit(scenario_id, record.best_served))
		if record.best_served < 0 or record.best_served > scenario.order_count or record.best_profit < -scenario.starting_budget or record.best_profit > profit_cap:
			problems.append("record value is outside the service limits")
		if has_legacy_completion and (not record.completed or not meets_legacy_completion_targets(scenario_id, record)):
			problems.append("invalid legacy completion marker")
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


static func meets_legacy_completion_targets(scenario_id: Variant, record: Dictionary) -> bool:
	var targets: Variant = LEGACY_COMPLETION_TARGETS.get(scenario_id)
	return targets is Dictionary and record.best_served >= targets.minimum_served \
		and record.best_profit >= targets.minimum_profit


## The maximum_profit(served) a scenario paid under content 1-6, or -1 when content 7 did not lower it.
static func legacy_maximum_profit(scenario_id: String, served: int) -> int:
	var table: Variant = LEGACY_PROFIT_CAPS.get(scenario_id)
	if not table is Dictionary:
		return -1
	var margins: Array = table.margins.duplicate()
	margins.sort()
	margins.reverse()
	var upper_bound: int = -table.labor_cost
	for index: int in mini(maxi(served, 0), margins.size()):
		upper_bound += maxi(margins[index], 0)
	return upper_bound


func is_unlocked(scenario_id: String) -> bool:
	if not errors.is_empty():
		return false
	for scenario: CampaignDef.ScenarioDef in _campaign.scenarios:
		if scenario.id == scenario_id:
			return true
		if not _records.get(scenario.id, {}).get("completed", false):
			return false
	return false


func next_service_seed(scenario_id: String) -> Dictionary:
	if not is_unlocked(scenario_id):
		return {"accepted": false, "reason": "locked_service", "service_seed": 0, "attempt_index": 0}
	var attempt_index: int = _attempts.get(scenario_id, 0)
	_attempts[scenario_id] = attempt_index + 1
	return {"accepted": true, "reason": "", "service_seed": ScheduleGenerator.service_seed_for(scenario_id, attempt_index),
		"attempt_index": attempt_index}


## Undoes the draw that produced attempt_index when the caller could not persist it.
## Only the most recent draw can be reverted, so a stale index is refused.
func revert_service_seed(scenario_id: String, attempt_index: int) -> bool:
	if _attempts.get(scenario_id, 0) != attempt_index + 1:
		return false
	if attempt_index == 0:
		_attempts.erase(scenario_id)
	else:
		_attempts[scenario_id] = attempt_index
	return true


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
	return {"records": _records.duplicate(true), "attempts": _attempts.duplicate(true), "unlocked": unlocked,
		"ending_unlocked": ending, "errors": errors.duplicate()}
