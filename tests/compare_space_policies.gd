extends SceneTree

const Experiment := preload("res://tests/fixtures/space_experiment.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var report: Array[Dictionary] = []
	for scenario_id: String in Experiment.SCENARIOS:
		for layout: String in Experiment.LAYOUTS:
			for duties: String in Experiment.DUTIES:
				if layout == "legacy" and duties == "dedicated":
					continue
				var constrained_variants: Array = [true, false] if layout == "legacy" else [true]
				for constrained: bool in constrained_variants:
					var scenario := Experiment.scenario(scenario_id, constrained)
					var policy := Experiment.policy(scenario_id, layout, duties)
					var result := Policies.run_policy(scenario, policy)
					var row := {"scenario": scenario_id, "layout": layout, "duties": duties,
						"space_rules": constrained, "policy": policy, "accepted": result.accepted}
					if result.accepted:
						var view: Dictionary = result.snapshot
						row.accounting = view.accounting
						row.metrics = view.metrics
						row.hash = result.hash
						row.selection = result.selection
						row.goals_met = view.accounting.served >= scenario.minimum_served and view.accounting.profit >= scenario.minimum_profit
					elif layout == "legacy" and constrained and result.reason.contains("fixed_station"):
						row.reason = result.reason
					else:
						printerr("FAIL: unexpected spatial policy rejection: " + str(result))
						quit(1)
						return
					report.append(row)
	DirAccess.make_dir_recursive_absolute("res://build/check")
	var file := FileAccess.open("res://build/check/space-policy-comparison.json", FileAccess.WRITE)
	if file == null:
		printerr("FAIL: cannot write spatial policy comparison")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true))
	file.close()
	for row: Dictionary in report:
		if row.accepted:
			print("SPACE_POLICY ", row.scenario, " ", row.layout, "/", row.duties, " rules=", row.space_rules,
				" served=", row.accounting.served, " profit=", row.accounting.profit,
				" moving=", row.metrics.orders.moving, " duty_wait=", row.metrics.orders.no_responsible_employee,
				" station_wait=", row.metrics.orders.station_in_use, " goals=", row.goals_met)
		else:
			print("SPACE_REJECTED ", row.scenario, " ", row.layout, " ", row.reason)
	print("PASS: spatial policy comparison rows=", report.size())
	quit(0)
