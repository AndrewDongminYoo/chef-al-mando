extends "res://tests/harness.gd"

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ScenarioDef := preload("res://content/scenario_def.gd")
const CampaignDef := preload("res://content/campaign_def.gd")


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists("res://tests/fixtures/space_experiment.gd"):
		expect(false, "the spatial experiment must provide the two real scenario clones")
		return
	var experiment: GDScript = load("res://tests/fixtures/space_experiment.gd")
	for scenario_id: String in ["hot_queue", "long_route"]:
		var scenario: ScenarioDef = experiment.scenario(scenario_id)
		var baseline: ScenarioDef = load("res://content/campaign/scenarios/" + scenario_id + ".tres")
		expect(scenario != baseline and scenario.space_rules and baseline.space_rules, "spatial experiments clone the campaign space rules")
		expect(scenario.order_schedule() == baseline.order_schedule() and scenario.purchases == baseline.purchases, "an experiment preserves orders and purchases: " + scenario_id)
		for index: int in scenario.stations.size():
			var station: Resource = scenario.stations[index]
			var expected_fixed: bool = baseline.stations[index].fixed
			expect(station.fixed == expected_fixed, "the experiment preserves each campaign fixture anchor: " + scenario_id + "/" + station.role)
			expect(scenario.stations[index].tile == baseline.stations[index].tile and scenario.stations[index].work_position == baseline.stations[index].work_position, "fixed experiment anchors use their original positions")
		var results: Dictionary = {}
		for layout: String in ["original", "clustered"]:
			for duties: String in ["all", "dedicated"]:
				var policy: Dictionary = experiment.policy(scenario_id, layout, duties)
				expect(policy.priorities == {}, "policy comparisons keep runtime priority commands empty: " + scenario_id + "/" + layout + "/" + duties)
				var result := Policies.run_policy(scenario, policy)
				expect(result.accepted, "the compared policy is legal: " + scenario_id + "/" + layout + "/" + duties + " " + result.get("reason", ""))
				if not result.accepted:
					continue
				results[layout + "/" + duties] = result
				expect(result.snapshot.tick == scenario.closing_tick, "policy comparison runs to closing")
				expect(result.selection.purchases == baseline.purchases and result.selection.prep_quantities.grill == 4, "layout and duty comparisons use the same ingredient and prep choices")
				if layout == "clustered" and duties == "all":
					var repeat := Policies.run_policy(scenario, policy)
					var fast := Policies.run_policy(scenario, policy, 4)
					expect(repeat.accepted and repeat.hash == result.hash and fast.accepted and fast.hash == result.hash, "repeated spatial policies and 1x/4x preserve the same final state")
		if results.size() == 4:
			expect(results["original/all"].snapshot.metrics.orders.moving != results["clustered/all"].snapshot.metrics.orders.moving, "changing the legal layout changes actual movement time")
			var common: Dictionary = results["original/all"].selection
			for result: Dictionary in results.values():
				expect(result.selection.purchases == common.purchases and result.selection.prep_quantities == common.prep_quantities and result.selection.menu_priorities == common.menu_priorities, "policy comparisons isolate layout and duty changes")
		var legacy_policy: Dictionary = experiment.policy(scenario_id, "legacy", "all")
		var legacy := Policies.run_policy(experiment.scenario(scenario_id, false), legacy_policy)
		var rejected := Policies.run_policy(scenario, legacy_policy)
		expect(legacy.accepted, "the old dense policy remains executable under baseline rules")
		expect(not rejected.accepted and rejected.reason.contains("fixed_station"), "an old policy that moves the pass is classified as invalid instead of a service loss")
	_test_session_rules(experiment)


func _test_session_rules(experiment: GDScript) -> void:
	var baseline: CampaignDef = load("res://content/campaign/campaign.tres")
	var legacy_campaign := baseline.duplicate(true) as CampaignDef
	legacy_campaign.scenarios[2] = experiment.scenario("hot_queue", false)
	var progress := CampaignProgress.new(baseline)
	for index: int in 2:
		var scenario: Resource = baseline.scenarios[index]
		var run := Policies.run_policy(scenario, Policies.reference_policy(scenario.id))
		expect(run.accepted, "session comparison unlocks the real prior campaign service")
		if not run.accepted:
			return
		var recorded := progress.record_result(scenario.id, run.snapshot)
		expect(recorded.accepted and recorded.passed, "session comparison uses genuine completion records")
	var records: Dictionary = progress.snapshot().records
	for variant: String in ["valid", "moved_pass", "shared_work"]:
		var source: Resource = legacy_campaign.scenarios[2]
		var plan := PreparationPlan.new(source)
		var selection: Dictionary = plan.snapshot().selection
		if variant == "moved_pass":
			selection.placements.pass_01.tile = [8, 5]
			selection.placements.pass_01.work_position = [8, 4]
		elif variant == "shared_work":
			selection.placements.cold_01.tile = [3, 3]
			selection.placements.cold_01.work_position = [2, 3]
		plan = PreparationPlan.new(source, selection)
		var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
		expect(started.accepted, "the legacy producer can create the tested session: " + variant)
		if not started.accepted:
			continue
		var simulation := ServiceSim.new(started.definitions, null, started.options)
		for tick: int in 11:
			simulation.step()
		var session: Dictionary = JSON.parse_string(JSON.stringify(ServiceSession.capture("hot_queue", started.selection, simulation)))
		var legacy_restore := ServiceSession.restore(legacy_campaign, session, records)
		expect(legacy_restore.accepted and legacy_restore.simulation.state_hash() == simulation.state_hash(), "a legacy kitchen restores its original session")
		var experiment_restore := ServiceSession.restore(baseline, session, records)
		if variant == "valid":
			expect(experiment_restore.accepted and experiment_restore.simulation.state_hash() == simulation.state_hash(), "a legal campaign session restores its exact running state")
		else:
			expect(not experiment_restore.accepted and experiment_restore.reason == "invalid_preparation", "campaign session restoration applies the current spatial rules: " + variant)
