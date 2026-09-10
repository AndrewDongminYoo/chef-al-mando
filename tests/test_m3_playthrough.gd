extends "res://tests/harness.gd"

const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")


func run(_tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var progress := CampaignProgress.new(campaign)
	var directory := "user://test_campaign_playthrough_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "playthrough record directory is created")
	var file_path := directory + "/records.json"
	var store := CampaignStore.new(campaign, file_path)
	for scenario: Resource in campaign.scenarios:
		var policy := Policies.reference_policy(scenario.id)
		var run := Policies.run_policy(scenario, policy)
		expect(run.accepted, "reference policy is accepted: " + scenario.id + " " + str(run.get("reason", "")))
		if not run.accepted:
			continue
		var view: Dictionary = run.snapshot
		expect(view.closed and view.errors.is_empty() and view.tick == 3000, "the actual service closes without errors: " + scenario.id)
		expect(view.orders.size() == scenario.order_count, "all scheduled orders appear in the real service")
		var result := progress.record_result(scenario.id, view)
		expect(result.accepted and result.get("passed", false), "the reference policy passes both goals: " + scenario.id)
		expect(store.save_records(progress.snapshot().records).accepted, "a real service result saves at closing")
		var loaded := CampaignStore.new(campaign, file_path).load_records()
		expect(loaded.accepted and loaded.records == progress.snapshot().records, "a new store reads each real completed service")
		progress = CampaignProgress.new(campaign, loaded.records)
		for quantity: int in view.inventory.values():
			expect(quantity >= 0, "campaign inventory remains nonnegative")
		expect(view.accounting.profit == view.accounting.revenue - view.accounting.purchased_cost - view.accounting.labor_cost, "campaign closing uses the existing accounting equation")
		var repeat := Policies.run_policy(scenario, policy)
		var fast := Policies.run_policy(scenario, policy, 4)
		expect(repeat.accepted and repeat.hash == run.hash, "fixed campaign policy repeats the final state hash: " + scenario.id)
		expect(fast.accepted and fast.hash == run.hash, "one and four speed match at the same campaign ticks: " + scenario.id)
		print("M3_PLAYTHROUGH ", scenario.id, " ", JSON.stringify({"accounting": view.accounting, "metrics": view.metrics, "hash": run.hash}, "", true))
		if campaign.scenarios.find(scenario) >= 2:
			var no_plan := Policies.run_policy(scenario)
			expect(no_plan.accepted, "the no-plan comparison runs: " + scenario.id)
			if no_plan.accepted:
				var no_plan_view: Dictionary = no_plan.snapshot
				var no_plan_passes: bool = no_plan_view.accounting.served >= scenario.minimum_served and no_plan_view.accounting.profit >= scenario.minimum_profit
				expect(not no_plan_passes, "a pressure service requires a scenario-specific plan: " + scenario.id)
				expect(view.accounting.served - scenario.minimum_served <= 1
					and view.accounting.profit - scenario.minimum_profit <= 2000,
					"the reference policy passes with at most one extra order and 2000 extra profit: " + scenario.id)
				expect(no_plan_view.accounting != view.accounting or no_plan_view.metrics != view.metrics,
					"the reference plan changes the pressure-service result: " + scenario.id)
				print("M3_PRESSURE ", scenario.id, " ", JSON.stringify({
					"goals": {"served": scenario.minimum_served, "profit": scenario.minimum_profit},
					"no_plan": {"accounting": no_plan_view.accounting, "metrics": no_plan_view.metrics},
					"reference": {"accounting": view.accounting, "metrics": view.metrics}}, "", true))
	expect(progress.snapshot().ending_unlocked, "the real sequential playthrough reaches the ending")
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
	_compare_choices(campaign)


func _compare_choices(campaign: Resource) -> void:
	var variants := {
		"prep": {"scenario": "lunch_prep", "policy": Policies.reference_policy("lunch_prep")},
		"placement": {"scenario": "long_route", "policy": {"preparation": [], "priorities": {}}},
		"duties": {"scenario": "split_duties", "policy": {"preparation": [], "priorities": {}}},
		"priority": {"scenario": "hot_queue", "policy": {"preparation": [], "priorities": {"grill": 2}}},
		"purchases": {"scenario": "shared_stock", "policy": {"preparation": [], "priorities": {}}},
	}
	for choice: Dictionary in Policies.reference_policy("long_route").preparation:
		if choice.kind in ["move_station", "rotate_station"]:
			variants.placement.policy.preparation.append(choice)
	for choice: Dictionary in Policies.reference_policy("split_duties").preparation:
		if choice.kind == "set_duty":
			variants.duties.policy.preparation.append(choice)
	var stock: Resource = campaign.scenario_for("shared_stock")
	variants.purchases.policy.preparation.append({"kind": "set_purchase", "target_id": "vegetable", "value": stock.purchases.vegetable + 5})
	for kind: String in variants:
		var variant: Dictionary = variants[kind]
		var scenario: Resource = campaign.scenario_for(variant.scenario)
		var before := Policies.run_policy(scenario)
		var after := Policies.run_policy(scenario, variant.policy)
		expect(before.accepted and after.accepted, "both comparison policies execute: " + kind)
		if not before.accepted or not after.accepted:
			continue
		var baseline: Dictionary = before.snapshot
		var changed: Dictionary = after.snapshot
		expect(baseline.accounting != changed.accounting or baseline.metrics != changed.metrics, "the choice changes actual outcomes or measured work: " + kind)
		if kind == "placement":
			expect(changed.metrics.orders.moving < baseline.metrics.orders.moving, "the shorter route reduces measured movement")
		if kind == "prep":
			expect(changed.metrics.orders.working < baseline.metrics.orders.working, "preparation removes measured service work")
		if kind == "purchases":
			expect(changed.accounting.served == baseline.accounting.served and changed.accounting.profit == baseline.accounting.profit - 500, "five extra vegetables cost 500 without changing served orders")
		print("M3_COMPARISON ", kind, " ", JSON.stringify({"scenario": scenario.id,
			"before": {"accounting": baseline.accounting, "metrics": baseline.metrics},
			"after": {"accounting": changed.accounting, "metrics": changed.metrics}}, "", true))
