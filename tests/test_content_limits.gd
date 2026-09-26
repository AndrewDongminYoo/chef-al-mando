extends "res://tests/harness.gd"

## Fails when a content change would make a record that an earlier shipped content version accepted
## invalid under the live content, unless the legacy tables in sim/campaign_progress.gd cover it:
## one such record makes CampaignStore reject the whole save (and its backup) as corrupt_records.

const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const ContentLimits := preload("res://tests/fixtures/content_limits.gd")
const DumpContentLimits := preload("res://tests/dump_content_limits.gd")
const DUMP_HINT := "run tests/dump_content_limits.gd (see its header) and append its row to tests/fixtures/content_limits.gd"


func run(_tree: SceneTree) -> void:
	var campaign: Resource = load(DumpContentLimits.CAMPAIGN_PATH)
	var live_version: int = CampaignStore.VERSIONS.content_version
	var live := DumpContentLimits.limits_row(campaign, live_version)
	var rows: Array[Dictionary] = ContentLimits.ROWS
	var versions: Array[int] = []
	for row: Dictionary in rows:
		versions.append(row.content_version)
	var expected_versions: Array[int] = []
	for version: int in range(1, live_version + 1):
		expected_versions.append(version)
	expect(versions == expected_versions, "content limits rows must cover versions 1 to %d in order, found %s; %s" % [live_version, versions, DUMP_HINT])
	var latest: Dictionary = rows[-1] if not rows.is_empty() else {}
	expect(latest.get("content_version") == live_version,
		"the last content limits row is content %s but the live content version is %d; %s" % [latest.get("content_version"), live_version, DUMP_HINT])
	expect(latest == live, "the live content differs from the last content limits row; bump the content version if a save could notice, then %s" % DUMP_HINT)
	# Dictionary == ignores key order, and the key order is the campaign order validate_records checks.
	expect(latest.get("scenarios", {}).keys() == live.scenarios.keys(),
		"the live campaign order %s differs from the last content limits row %s; bump the content version if a save could notice, then %s"
		% [live.scenarios.keys(), latest.get("scenarios", {}).keys(), DUMP_HINT])
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var problems := compatibility_problems(row, campaign, rows.slice(index + 1))
		for problem: String in problems:
			expect(false, problem)
		expect(problems.is_empty(), "every record content %d accepted stays valid under the live content" % row.content_version)
	_expect_detects_each_lockout(campaign, live)


## Every way a record valid under row could fail CampaignProgress.validate_records on the live
## campaign, as one message per service and cause. later_rows are the rows shipped after row: a
## completion that one of them loaded under a different target pair carries a legacy_completed
## marker, and validate_records keeps checking that marker against targets even once the live pair
## equals row's pair again.
static func compatibility_problems(row: Dictionary, campaign: Resource, later_rows: Array = [],
		targets: Dictionary = CampaignProgress.LEGACY_COMPLETION_TARGETS) -> Array[String]:
	var problems: Array[String] = []
	var version: int = row.content_version
	for scenario_id: String in row.scenarios:
		var old: Dictionary = row.scenarios[scenario_id]
		var prefix := "content %d %s: " % [version, scenario_id]
		var scenario: Resource = campaign.scenario_for(scenario_id)
		if scenario == null:
			problems.append(prefix + "the service no longer exists, so its records are rejected as unknown")
			continue
		if old.order_count > scenario.order_count:
			problems.append(prefix + "order_count fell from %d to %d; a best_served above it is rejected and no legacy table can cover that"
				% [old.order_count, scenario.order_count])
		var uncovered: Array[int] = []
		for served: int in mini(old.order_count, scenario.order_count) + 1:
			var bound: int = maxi(scenario.maximum_profit(served), CampaignProgress.legacy_maximum_profit(scenario_id, served))
			if old.maximum_profit[served] > bound:
				uncovered.append(served)
		if not uncovered.is_empty():
			var first: int = uncovered[0]
			problems.append(prefix + "maximum_profit(%d) was %d but the live bound is %d (%d served counts affected); add a LEGACY_PROFIT_CAPS entry"
				% [first, old.maximum_profit[first], maxi(scenario.maximum_profit(first), CampaignProgress.legacy_maximum_profit(scenario_id, first)), uncovered.size()])
		if old.starting_budget > scenario.starting_budget:
			problems.append(prefix + "starting_budget fell from %d to %d; a best_profit down to -%d is rejected and no legacy table can cover that"
				% [old.starting_budget, scenario.starting_budget, old.starting_budget])
		var pair_changed: bool = old.minimum_served != scenario.minimum_served or old.minimum_profit != scenario.minimum_profit
		for later: Dictionary in later_rows:
			var next: Dictionary = later.scenarios.get(scenario_id, {})
			if not next.is_empty() and (next.minimum_served != old.minimum_served or next.minimum_profit != old.minimum_profit):
				pair_changed = true
		if pair_changed:
			var covered := false
			for pair: Dictionary in targets.get(scenario_id, []):
				if pair.minimum_served == old.minimum_served and pair.minimum_profit == old.minimum_profit and pair.since_content <= version:
					covered = true
			if not covered:
				problems.append(prefix + "target pair %d served / %d profit needs a LEGACY_COMPLETION_TARGETS entry with since_content at most %d"
					% [old.minimum_served, old.minimum_profit, version])
	# validate_records rejects a record that follows an incomplete service in the live order, so a save
	# that completed exactly the services the row's order put before a service must still reach it.
	var live_order: Array[String] = []
	for scenario: Resource in campaign.scenarios:
		if scenario != null:
			live_order.append(scenario.id)
	var old_order: Array = row.scenarios.keys()
	for index: int in old_order.size():
		var position := live_order.find(old_order[index])
		var missing: Array[String] = []
		for earlier_id: String in live_order.slice(0, maxi(position, 0)):
			if not earlier_id in old_order.slice(0, index):
				missing.append(earlier_id)
		if not missing.is_empty():
			problems.append("content %d %s: the live campaign order puts %s before it, so its record in a save that completed only the services content %d put before it is rejected; no legacy table can cover that, so keep the old order and add new services after it"
				% [version, old_order[index], missing, version])
	return problems


## The checker must report each lockout on its own, so a green run means the tables cover every row.
func _expect_detects_each_lockout(campaign: Resource, live: Dictionary) -> void:
	for cause: String in ["order_count", "maximum_profit", "starting_budget", "target pair"]:
		var row: Dictionary = live.duplicate(true)
		row.content_version = 1
		var old: Dictionary = row.scenarios.first_shift
		match cause:
			"order_count":
				old.order_count += 1
				old.maximum_profit.append(old.maximum_profit[-1])
			"maximum_profit":
				# The top cap: validate_records floors the bound at -1 for a service without a legacy
				# cap, so a raised cap below zero would not lock anyone out.
				old.maximum_profit[-1] += 1
			"starting_budget":
				old.starting_budget += 1
			"target pair":
				old.minimum_profit -= 1
		var problems := compatibility_problems(row, campaign)
		expect(problems.size() == 1 and problems[0].begins_with("content 1 first_shift: ") and cause in problems[0],
			"the content limits check reports a changed %s on its own, got %s" % [cause, problems])
	var early: Dictionary = live.duplicate(true)
	early.content_version = 2
	early.scenarios.hot_queue.minimum_served = 12
	early.scenarios.hot_queue.minimum_profit = 4750
	var early_problems := compatibility_problems(early, campaign)
	expect(early_problems.size() == 1 and "since_content at most 2" in early_problems[0],
		"a legacy pair introduced after the row's content version does not cover it, got %s" % [early_problems])
	# A later version replaces first_shift's pair and the live content restores it: a save migrated
	# through that version still carries legacy_completed, so the restored pair still needs its entry.
	var restored: Dictionary = live.duplicate(true)
	restored.content_version = 1
	var replaced: Dictionary = live.duplicate(true)
	replaced.content_version = 2
	replaced.scenarios.first_shift.minimum_profit += 1
	var without_first_shift: Dictionary = CampaignProgress.LEGACY_COMPLETION_TARGETS.duplicate(true)
	without_first_shift.erase("first_shift")
	var restored_problems := compatibility_problems(restored, campaign, [replaced], without_first_shift)
	expect(restored_problems.size() == 1 and restored_problems[0].begins_with("content 1 first_shift: ") and "target pair" in restored_problems[0],
		"the content limits check reports a restored target pair that no legacy entry covers, got %s" % [restored_problems])
	expect(compatibility_problems(restored, campaign, [replaced]).is_empty(),
		"the legacy first_shift entry covers the restored target pair")
	expect(compatibility_problems(restored, campaign, [], without_first_shift).is_empty(),
		"a target pair unchanged through the live content needs no legacy entry")
	var swapped: Dictionary = live.duplicate(true)
	swapped.content_version = 1
	var swapped_scenarios := {}
	for scenario_id: String in ["first_shift", "hot_queue", "lunch_prep"]:
		swapped_scenarios[scenario_id] = swapped.scenarios[scenario_id]
	for scenario_id: String in swapped.scenarios:
		if not swapped_scenarios.has(scenario_id):
			swapped_scenarios[scenario_id] = swapped.scenarios[scenario_id]
	swapped.scenarios = swapped_scenarios
	var swapped_problems := compatibility_problems(swapped, campaign)
	expect(swapped_problems.size() == 1 and swapped_problems[0].begins_with("content 1 hot_queue: the live campaign order puts [\"lunch_prep\"]"),
		"the content limits check reports a service the live campaign moved later, got %s" % [swapped_problems])
	var inserted: Dictionary = live.duplicate(true)
	inserted.content_version = 1
	inserted.scenarios.erase("lunch_prep")
	var inserted_problems := compatibility_problems(inserted, campaign)
	var all_name_lunch_prep := not inserted_problems.is_empty()
	for problem: String in inserted_problems:
		all_name_lunch_prep = all_name_lunch_prep and "[\"lunch_prep\"]" in problem
	expect(inserted_problems.size() == inserted.scenarios.size() - 1 and all_name_lunch_prep
		and inserted_problems[0].begins_with("content 1 hot_queue: "),
		"the content limits check reports a service the live campaign inserted before older ones, got %s" % [inserted_problems])
	var renamed: Dictionary = live.duplicate(true)
	renamed.scenarios["retired_service"] = renamed.scenarios.first_shift
	var renamed_problems := compatibility_problems(renamed, campaign)
	expect(renamed_problems.size() == 1 and renamed_problems[0].begins_with("content %d retired_service: the service no longer exists" % live.content_version),
		"the content limits check reports a service the live campaign dropped, got %s" % [renamed_problems])
