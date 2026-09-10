extends "res://tests/harness.gd"


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists("res://sim/campaign_progress.gd") or not ResourceLoader.exists("res://content/campaign/campaign.tres"):
		expect(false, "campaign progress and static content must exist")
		return
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var progress_script: GDScript = load("res://sim/campaign_progress.gd")
	var progress: RefCounted = progress_script.new(campaign)
	var first: Resource = campaign.scenarios[0]
	var second: Resource = campaign.scenarios[1]
	expect(progress.errors.is_empty(), "fresh campaign progress is valid")
	expect(progress.is_unlocked(first.id) and not progress.is_unlocked(second.id), "only the first service starts unlocked")
	expect(not progress.is_unlocked("missing_scenario"), "an unknown service cannot unlock")
	expect(not progress.record_result(first.id, _result(first, 10, 4000)).accepted, "impossible profit cannot unlock a service")
	expect(not progress.record_result(first.id, _result(first, 1, 1000)).accepted, "profit must fit the actual served count")
	var boundary: RefCounted = progress_script.new(campaign)
	expect(boundary.record_result(first.id, _result(first, 12, 3200)).accepted, "the exact maximum profit remains valid")
	expect(not boundary.record_result(first.id, _result(first, 12, 3201)).accepted, "one above the profit bound is invalid")
	var independent: RefCounted = progress_script.new(campaign)
	independent.record_result(first.id, _result(first, 12, 1000))
	independent.record_result(first.id, _result(first, 11, 2800))
	expect(independent.snapshot().records[first.id].best_served == 12 and independent.snapshot().records[first.id].best_profit == 2800, "served and profit bests can come from different valid attempts")
	var result := _result(first, first.minimum_served, first.minimum_profit)
	expect(not progress.record_result(second.id, result).accepted, "a locked service cannot record a result")
	result.closed = false
	expect(not progress.record_result(first.id, result).accepted, "a running service cannot record a result")
	result.closed = true
	result.tick -= 1
	expect(not progress.record_result(first.id, result).accepted, "a premature close cannot record a result")
	result.tick += 1
	result.errors = ["invalid service"]
	expect(not progress.record_result(first.id, result).accepted, "a service error cannot record a result")
	result.errors = []
	result.accounting.served -= 1
	expect(not progress.record_result(first.id, result).passed and not progress.is_unlocked(second.id), "profit alone does not pass the service")
	result.accounting.served += 1
	result.accounting.profit -= 1
	expect(not progress.record_result(first.id, result).passed and not progress.is_unlocked(second.id), "served count alone does not pass the service")
	result.accounting.profit += 1
	expect(progress.record_result(first.id, result).passed and progress.is_unlocked(second.id), "both exact target values unlock the next service")
	var saved: Dictionary = progress.snapshot()
	expect(not progress.record_result(first.id, result).changed and progress.snapshot() == saved, "repeated result delivery is idempotent")
	var invalid_result := result.duplicate(true)
	invalid_result.accounting.served = -1
	expect(not progress.record_result(first.id, invalid_result).accepted, "existing best results cannot hide an invalid negative result")
	result.accounting.served = 0
	result.accounting.profit = -first.starting_budget
	progress.record_result(first.id, result)
	expect(progress.snapshot() == saved, "a failed retry preserves completion and best results")
	var exposed: Dictionary = progress.snapshot()
	exposed.records.clear()
	expect(progress.snapshot() == saved, "callers cannot mutate campaign records through a snapshot")
	var reopened: RefCounted = progress_script.new(campaign, saved.records)
	expect(reopened.is_unlocked(second.id), "new progress restores the recorded unlock")
	var pressure: Resource = campaign.scenarios[2]
	var legacy_records := {
		first.id: {"completed": true, "best_served": first.minimum_served, "best_profit": first.minimum_profit},
		second.id: {"completed": true, "best_served": second.minimum_served, "best_profit": second.minimum_profit},
		pressure.id: {"completed": true, "best_served": 14, "best_profit": 1500, "legacy_completed": true},
	}
	var grandfathered: RefCounted = progress_script.new(campaign, legacy_records)
	expect(grandfathered.errors.is_empty() and grandfathered.is_unlocked(campaign.scenarios[3].id),
		"an explicitly migrated legacy completion remains unlocked below the current targets")
	expect(grandfathered.record_result(pressure.id,
		_result(pressure, pressure.minimum_served, pressure.minimum_profit)).passed,
		"a grandfathered service can meet the current targets on a later attempt")
	expect(not grandfathered.snapshot().records[pressure.id].has("legacy_completed"),
		"meeting the current targets removes the legacy completion marker")
	var unmarked_completion: RefCounted = progress_script.new(campaign,
		{first.id: {"completed": true, "best_served": first.minimum_served - 1,
			"best_profit": -first.starting_budget}})
	expect(not unmarked_completion.errors.is_empty(),
		"a current completion below the current targets requires migration provenance")
	for forged_record: Dictionary in [
		{"completed": true, "best_served": 13, "best_profit": 1500, "legacy_completed": true},
		{"completed": true, "best_served": 14, "best_profit": 1499, "legacy_completed": true},
	]:
		var forged_legacy_completion: RefCounted = progress_script.new(campaign, {
			first.id: legacy_records[first.id], second.id: legacy_records[second.id], pressure.id: forged_record,
		})
		expect(not forged_legacy_completion.errors.is_empty(),
			"a legacy marker below its original targets cannot unlock the next service")
	for scenario: Resource in campaign.scenarios:
		expect(progress.record_result(scenario.id, _result(scenario, scenario.minimum_served, scenario.minimum_profit)).passed, "each passing service unlocks its successor: " + scenario.id)
	expect(progress.snapshot().ending_unlocked, "the last service unlocks the ending")
	var invalid: RefCounted = progress_script.new(campaign, {second.id: {"completed": true, "best_served": second.minimum_served, "best_profit": second.minimum_profit}})
	expect(not invalid.errors.is_empty() and not invalid.is_unlocked(second.id), "records cannot skip an incomplete earlier service")
	invalid = progress_script.new(campaign, {"missing_scenario": {"completed": false, "best_served": 0, "best_profit": 0}})
	expect(not invalid.errors.is_empty(), "records reject unknown scenario IDs")
	invalid = progress_script.new(campaign, {first.id: {"completed": "true", "best_served": 0, "best_profit": 0}})
	expect(not invalid.errors.is_empty(), "records reject an invalid completion type")
	var missing_last: Resource = campaign.duplicate()
	missing_last.scenarios = campaign.scenarios.duplicate()
	missing_last.scenarios[-1] = null
	invalid = progress_script.new(missing_last)
	expect(not invalid.errors.is_empty() and not invalid.snapshot().ending_unlocked, "invalid campaign data cannot publish an ending")


func _result(scenario: Resource, served: int, profit: int) -> Dictionary:
	return {"closed": true, "tick": scenario.closing_tick, "errors": [], "accounting": {"served": served, "profit": profit}}
