extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const SESSION_PATH := "res://persistence/service_session.gd"


func run(_tree: SceneTree) -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var scenario: Resource = campaign.scenario_for("first_shift")
	var plan := PreparationPlan.new(scenario)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while simulation.tick < 300:
		simulation.step()
		var view: Dictionary = simulation.snapshot()
		if not view.tasks.is_empty() and view.employees[0].progress in [1, 2, 3, 4]:
			break
	expect(simulation.snapshot().tasks.size() == 1 and simulation.snapshot().employees[0].progress in [1, 2, 3, 4],
		"the session fixture contains actual partial movement")
	if not ResourceLoader.exists(SESSION_PATH):
		expect(false, "a JSON session restores the prepared in-progress service")
		return
	var session_script := load(SESSION_PATH) as GDScript
	var session: Dictionary = session_script.call("capture", "first_shift", started.selection, simulation, 4, 43210)
	var document: Variant = JSON.parse_string(JSON.stringify(session))
	var restored: Dictionary = session_script.call("restore", campaign, document, {})
	expect(restored.get("accepted") == true, "a JSON session restores the prepared in-progress service")
	if restored.get("accepted") == true:
		expect(restored.scenario_id == "first_shift" and restored.speed == 4 and restored.accumulator_us == 43210,
			"session restore preserves the scenario, speed, and partial tick time")
		expect(restored.simulation.state_hash() == simulation.state_hash(), "JSON integer normalization preserves the simulation hash")
		expect(restored.definitions != null and restored.selection == started.selection,
			"session restore returns the rebuilt definitions and exact preparation selection")
	_test_capture_copy(session_script, started.selection, simulation)
	_test_preparation_shape(campaign, session_script, session)
	_test_numeric_boundaries(campaign, session_script, session)
	_test_session_contract(campaign, session_script, session)


func _test_preparation_shape(campaign: Resource, session_script: GDScript, valid_session: Dictionary) -> void:
	for corruption: String in ["missing_duty", "extra_duty", "missing_prep", "extra_prep", "extra_purchase"]:
		var session := valid_session.duplicate(true)
		match corruption:
			"missing_duty":
				session.preparation.duties.erase("employee_01")
			"extra_duty":
				session.preparation.duties.unknown = "all"
			"missing_prep":
				session.preparation.prep_quantities.erase("salad")
			"extra_prep":
				session.preparation.prep_quantities.unknown = 0
			"extra_purchase":
				session.preparation.purchases.unknown = 0
		var result: Dictionary = session_script.call("restore", campaign, session, {})
		expect(not result.get("accepted", false), "session rejects a non-exact preparation selection: " + corruption)


func _test_numeric_boundaries(campaign: Resource, session_script: GDScript, valid_session: Dictionary) -> void:
	var too_large := valid_session.duplicate(true)
	too_large.simulation.last_sequence = 9223372036854775807
	var large_result: Dictionary = session_script.call("restore", campaign, too_large, {})
	expect(not large_result.get("accepted", false), "session rejects an integer that cannot survive an exact JSON round trip")
	for invalid_value: Variant in [1.5, INF, NAN, "1", true]:
		var malformed := valid_session.duplicate(true)
		malformed.speed = invalid_value
		var result: Dictionary = session_script.call("restore", campaign, malformed, {})
		expect(not result.get("accepted", false), "session rejects a non-integer speed value: " + str(invalid_value))


func _test_capture_copy(session_script: GDScript, selection: Dictionary, simulation: RefCounted) -> void:
	var before: String = simulation.call("state_hash")
	var captured: Dictionary = session_script.call("capture", "first_shift", selection, simulation, 1, 0)
	captured.preparation.duties.employee_01 = "off"
	captured.simulation.inventory.vegetable = -1
	expect(selection.duties.employee_01 == "all" and simulation.call("state_hash") == before,
		"mutating a captured session cannot change preparation or simulation inputs")


func _test_session_contract(campaign: Resource, session_script: GDScript, valid_session: Dictionary) -> void:
	for corruption: String in ["missing_prng", "wrong_prng", "extra_simulation", "missing_root", "extra_root",
		"invalid_speed", "invalid_accumulator", "locked_scenario"]:
		var session := valid_session.duplicate(true)
		match corruption:
			"missing_prng":
				session.simulation.erase("prng_state")
			"wrong_prng":
				session.simulation.prng_state = 0
			"extra_simulation":
				session.simulation.derived_accounting = {}
			"missing_root":
				session.erase("speed")
			"extra_root":
				session.unexpected = true
			"invalid_speed":
				session.speed = 3
			"invalid_accumulator":
				session.accumulator_us = 100000
			"locked_scenario":
				session.scenario_id = "lunch_prep"
		var result: Dictionary = session_script.call("restore", campaign, session, {})
		expect(not result.get("accepted", false), "session rejects invalid stored state: " + corruption)
