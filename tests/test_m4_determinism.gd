extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const SERVICE_SIM_PATH := "res://sim/service_sim.gd"


func run(_tree: SceneTree) -> void:
	var plan := PreparationPlan.new(_fresh())
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the real preparation fixture starts service")
	var service_sim_script := load(SERVICE_SIM_PATH) as GDScript
	var original: RefCounted = service_sim_script.new(started.definitions, null, started.options)
	_advance_until_moving(original)
	expect(original.snapshot().tasks.size() == 1 and original.snapshot().employees[0].progress in [1, 2, 3, 4],
		"the restore fixture contains actual partial movement")
	var method_names: Array[String] = []
	for method: Dictionary in service_sim_script.get_script_method_list():
		method_names.append(method.name)
	if not original.has_method("export_state") or not method_names.has("restore"):
		expect(false, "an in-progress service exports and restores through the M4 simulation contract")
		return
	var restored: Dictionary = service_sim_script.call("restore", started.definitions, original.call("export_state"), started.options)
	expect(restored.get("accepted") == true, "an in-progress service restores after full validation")
	if restored.get("accepted") == true:
		expect(restored.simulation.state_hash() == original.state_hash(), "restoration preserves the immediate simulation hash")
		expect(not original.events().is_empty() and restored.simulation.events().is_empty(),
			"restore does not replay one-time simulation events")
	_test_export_copy(original)
	_test_inventory_corruption(started.definitions, started.options, original, service_sim_script)
	_test_corruption_table(started.definitions, started.options, original, service_sim_script)
	_test_identity_and_type_corruption(started.definitions, started.options, service_sim_script)
	_test_restore_checkpoints(service_sim_script)


func _test_inventory_corruption(data: Resource, preparation: Dictionary, original: RefCounted,
	service_sim_script: GDScript) -> void:
	var before: String = original.call("state_hash")
	var corrupted: Dictionary = original.call("export_state")
	corrupted.inventory.vegetable += 1
	var result: Dictionary = service_sim_script.call("restore", data, corrupted, preparation)
	expect(not result.get("accepted", false), "restore rejects inventory that cannot follow from preparation and consumption")
	expect(original.call("state_hash") == before, "failed restore leaves the existing simulation unchanged")


func _test_export_copy(original: RefCounted) -> void:
	var before: String = original.call("state_hash")
	var exported: Dictionary = original.call("export_state")
	expect(exported.get("prng_state", "missing") == null and not exported.has("accounting") \
		and not exported.has("events") and not exported.has("errors"),
		"the restoration state includes null PRNG state and excludes transient or derived fields")
	exported.inventory.vegetable = -1
	exported.orders[0].priority = -1
	exported.employees[0].tile[0] = -1
	exported.tasks[0].path[0][0] = -1
	expect(original.call("state_hash") == before, "mutating a nested exported state cannot change the simulation")


func _test_corruption_table(data: Resource, preparation: Dictionary, moving: RefCounted,
	service_sim_script: GDScript) -> void:
	var working: RefCounted = _advance_until_working(data, preparation)
	var queued: RefCounted = service_sim_script.new(data, null, preparation)
	_advance_until_moving(queued)
	queued.call("enqueue_command", {"kind": "set_priority", "target_id": "order_01", "value": 2,
		"apply_tick": queued.get("tick") + 2, "sequence": 1})
	queued.call("enqueue_command", {"kind": "set_priority", "target_id": "order_01", "value": 0,
		"apply_tick": queued.get("tick") + 2, "sequence": 2})
	var fixtures: Dictionary = {
		"unknown_order_id": moving,
		"invalid_order_state": moving,
		"reservation_sum": moving,
		"task_employee_link": moving,
		"path_gap": moving,
		"consumption_flags": working,
		"unconsumed_work": working,
		"working_without_result": working,
		"working_result_position": working,
		"working_employee_progress": working,
		"duplicate_command_sequence": queued,
		"invalid_closing_state": moving,
	}
	for corruption: String in fixtures:
		var source: RefCounted = fixtures[corruption]
		var before: String = source.call("state_hash")
		var state: Dictionary = source.call("export_state")
		_apply_corruption(state, corruption)
		var result: Dictionary = service_sim_script.call("restore", data, state, preparation)
		expect(not result.get("accepted", false), "restore rejects cross-field corruption: " + corruption)
		expect(source.call("state_hash") == before, "corruption rejection preserves the source: " + corruption)


func _advance_until_working(data: Resource, preparation: Dictionary) -> RefCounted:
	var simulation: RefCounted = (load(SERVICE_SIM_PATH) as GDScript).new(data, null, preparation)
	while simulation.tick < 300 and (simulation.snapshot().orders.is_empty()
		or simulation.snapshot().orders[0].state != "working"):
		simulation.step()
	expect(simulation.snapshot().orders[0].state == "working", "the corruption fixture reaches active work")
	return simulation


func _advance_until_moving(simulation: RefCounted) -> void:
	while simulation.get("tick") < 300:
		simulation.call("step")
		var view: Dictionary = simulation.call("snapshot")
		if not view.tasks.is_empty() and view.employees[0].progress in [1, 2, 3, 4]:
			return
	expect(false, "the fixture reaches partial movement before tick 300")


func _apply_corruption(state: Dictionary, corruption: String) -> void:
	match corruption:
		"unknown_order_id":
			state.orders[0].id = "missing"
		"invalid_order_state":
			state.orders[0].state = "invalid"
		"reservation_sum":
			state.reserved.vegetable = 0
		"task_employee_link":
			state.employees[0].order_id = ""
		"path_gap":
			state.tasks[0].path[1][0] += 2
		"consumption_flags":
			state.orders[0].raw_consumed = false
		"unconsumed_work":
			state.orders[0].input_consumed = false
			state.orders[0].raw_consumed = false
			state.inventory.vegetable += 1
		"working_without_result":
			state.orders[0].has_result = false
		"working_result_position":
			state.orders[0].result_position = [10, 6]
		"working_employee_progress":
			state.employees[0].progress = 1
		"duplicate_command_sequence":
			state.commands[1].sequence = state.commands[0].sequence
		"invalid_closing_state":
			state.closed = true


func _test_identity_and_type_corruption(data: Resource, preparation: Dictionary,
	service_sim_script: GDScript) -> void:
	var idle: RefCounted = service_sim_script.new(data, null, preparation)
	var duplicate_employee: Dictionary = idle.call("export_state")
	duplicate_employee.employees[1].id = duplicate_employee.employees[0].id
	var duplicate_result: Variant = service_sim_script.call("restore", data, duplicate_employee, preparation)
	expect(duplicate_result is Dictionary and not duplicate_result.get("accepted", false),
		"restore rejects a duplicate idle employee ID")
	var terminal: RefCounted = service_sim_script.new(data, null, preparation)
	while not terminal.get("closed"):
		terminal.call("step")
	var invalid_ended_tick: Dictionary = terminal.call("export_state")
	invalid_ended_tick.orders[0].ended_tick = "invalid"
	var terminal_result: Variant = service_sim_script.call("restore", data, invalid_ended_tick, preparation)
	expect(terminal_result is Dictionary and not terminal_result.get("accepted", false),
		"restore rejects a malformed terminal tick without a runtime error")


func _test_restore_checkpoints(service_sim_script: GDScript) -> void:
	for progress: int in [1, 2, 3, 4]:
		var fixture := _prepared_service(service_sim_script)
		_advance_to_progress(fixture.simulation, progress)
		_compare_restored_run(fixture, service_sim_script, "movement_progress_%d" % progress)
	var working := _prepared_service(service_sim_script)
	while working.simulation.tick < 500 and (working.simulation.snapshot().orders.is_empty()
		or working.simulation.snapshot().orders[0].state != "working"):
		working.simulation.step()
	expect(working.simulation.snapshot().orders[0].state == "working", "the M4 checkpoint reaches active work")
	_compare_restored_run(working, service_sim_script, "working")
	var pending_duty := _prepared_service(service_sim_script)
	_advance_to_progress(pending_duty.simulation, 1)
	var duty_result: Dictionary = pending_duty.simulation.enqueue_command({"kind": "set_duty", "target_id": "employee_01",
		"value": "off", "apply_tick": pending_duty.simulation.tick + 1, "sequence": 1})
	pending_duty.simulation.step()
	expect(duty_result.accepted and pending_duty.simulation.snapshot().employees[0].pending_duty == "off",
		"the M4 checkpoint contains a pending duty change")
	_compare_restored_run(pending_duty, service_sim_script, "pending_duty")
	var queued := _prepared_service(service_sim_script)
	_advance_to_progress(queued.simulation, 1)
	var apply_tick: int = queued.simulation.tick + 4
	queued.simulation.enqueue_command({"kind": "set_priority", "target_id": "order_01", "value": 2,
		"apply_tick": apply_tick, "sequence": 1})
	queued.simulation.enqueue_command({"kind": "set_priority", "target_id": "order_01", "value": 0,
		"apply_tick": apply_tick, "sequence": 2})
	expect(queued.simulation.snapshot().commands.size() == 2, "the M4 checkpoint contains same-tick queued commands")
	_compare_restored_run(queued, service_sim_script, "same_tick_commands")
	var preclose := _prepared_service(service_sim_script)
	while preclose.simulation.tick < 2999:
		preclose.simulation.step()
	expect(not preclose.simulation.closed and preclose.simulation.tick == 2999, "the M4 checkpoint reaches one tick before closing")
	_compare_restored_run(preclose, service_sim_script, "preclose")
	var closed := _prepared_service(service_sim_script)
	while not closed.simulation.closed:
		closed.simulation.step()
	_compare_restored_run(closed, service_sim_script, "closed")
	var sequence := _prepared_service(service_sim_script)
	_advance_to_progress(sequence.simulation, 1)
	sequence.simulation.enqueue_command({"kind": "set_priority", "target_id": "order_01", "value": 2,
		"apply_tick": sequence.simulation.tick + 2, "sequence": 1})
	var sequence_restore: Dictionary = service_sim_script.call("restore", sequence.definitions,
		sequence.simulation.export_state(), sequence.options)
	var next_sequence: Dictionary = sequence_restore.simulation.enqueue_command({"kind": "set_priority",
		"target_id": "order_01", "value": 0, "apply_tick": sequence.simulation.tick + 3, "sequence": 2})
	var repeated_sequence: Dictionary = sequence_restore.simulation.enqueue_command({"kind": "set_priority",
		"target_id": "order_01", "value": 1, "apply_tick": sequence.simulation.tick + 4, "sequence": 1})
	expect(next_sequence.accepted and not repeated_sequence.accepted,
		"restored command sequencing continues after the saved last sequence")


func _prepared_service(service_sim_script: GDScript) -> Dictionary:
	var plan := PreparationPlan.new(_fresh())
	var commands: Array[Dictionary] = [
		{"kind": "set_prep", "target_id": "salad", "value": 1, "apply_tick": 0, "sequence": 1},
		{"kind": "move_station", "target_id": "pass_01", "value": "left", "apply_tick": 0, "sequence": 2},
		{"kind": "set_duty", "target_id": "employee_01", "value": "cold", "apply_tick": 0, "sequence": 3},
		{"kind": "set_duty", "target_id": "employee_02", "value": "hot", "apply_tick": 0, "sequence": 4},
		{"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 5},
	]
	var started: Dictionary = {}
	for command: Dictionary in commands:
		started = plan.apply_command(command)
		expect(started.accepted, "the M4 prepared checkpoint accepts " + command.kind)
	expect(started.selection.prep_quantities.salad == 1 and started.selection.placements.pass_01.tile == [8, 5],
		"the M4 checkpoint uses committed preparation and changed placement")
	return {"simulation": service_sim_script.new(started.definitions, null, started.options),
		"definitions": started.definitions, "options": started.options}


func _advance_to_progress(simulation: RefCounted, expected_progress: int) -> void:
	while simulation.get("tick") < 500:
		simulation.call("step")
		for employee: Dictionary in simulation.call("snapshot").employees:
			if employee.progress == expected_progress and not employee.order_id.is_empty():
				return
	expect(false, "the M4 checkpoint reaches movement progress %d" % expected_progress)


func _compare_restored_run(fixture: Dictionary, service_sim_script: GDScript, checkpoint: String) -> void:
	var simulation: RefCounted = fixture.simulation
	var restored: Dictionary = service_sim_script.call("restore", fixture.definitions,
		simulation.call("export_state"), fixture.options)
	expect(restored.get("accepted") == true, "restore accepts the reachable checkpoint: " + checkpoint)
	if not restored.get("accepted", false):
		return
	var resumed: RefCounted = restored.simulation
	expect(resumed.call("state_hash") == simulation.call("state_hash"),
		"restore preserves the immediate hash: " + checkpoint)
	while not simulation.get("closed"):
		simulation.call("step")
		resumed.call("step")
	expect(resumed.call("state_hash") == simulation.call("state_hash"),
		"restore preserves the final hash: " + checkpoint)


func _fresh() -> Resource:
	return ResourceLoader.load("res://content/campaign/scenarios/first_shift.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
