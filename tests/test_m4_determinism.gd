extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")
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
	_test_reserved_input_json_type(started.definitions, started.options, original, service_sim_script)
	_test_corruption_table(started.definitions, started.options, original, service_sim_script)
	_test_canonical_task_paths(service_sim_script)
	_test_identity_and_type_corruption(started.definitions, started.options, service_sim_script)
	_test_task_back_references(started.definitions, started.options, service_sim_script)
	_test_between_process_waiting(service_sim_script)
	_test_active_state_relationships(service_sim_script)
	_test_terminal_relationships(service_sim_script)
	_test_command_canonicalization(service_sim_script)
	_test_work_timing_relationships(service_sim_script)
	_test_tick_zero_employee_relationships(service_sim_script)
	_test_active_duty_relationships(service_sim_script)
	_test_restore_checkpoints(service_sim_script)


func _test_inventory_corruption(data: Resource, preparation: Dictionary, original: RefCounted,
	service_sim_script: GDScript) -> void:
	var before: String = original.call("state_hash")
	var corrupted: Dictionary = original.call("export_state")
	corrupted.inventory.vegetable += 1
	var result: Dictionary = service_sim_script.call("restore", data, corrupted, preparation)
	expect(not result.get("accepted", false), "restore rejects inventory that cannot follow from preparation and consumption")
	expect(original.call("state_hash") == before, "failed restore leaves the existing simulation unchanged")


func _test_reserved_input_json_type(data: Resource, preparation: Dictionary, original: RefCounted,
	service_sim_script: GDScript) -> void:
	var source_hash: String = original.state_hash()
	var state: Dictionary = original.export_state()
	expect(state is Dictionary and state.orders[0].state == "moving"
		and state.orders[0].ingredients_reserved and state.orders[0].reserved_inputs.vegetable is int,
		"the reservation type fixture is an API-valid moving state with reserved input")
	var malformed_reservation: Variant = JSON.parse_string("{\"vegetable\":\"x\"}")
	expect(malformed_reservation is Dictionary and malformed_reservation.vegetable is String,
		"the malformed reservation is parsed from untyped JSON")
	state.orders[0].reserved_inputs = malformed_reservation
	var result: Dictionary = service_sim_script.call("restore", data, state, preparation)
	print("M4_RESERVED_INPUT_DIRECT_RESULT " + JSON.stringify(result))
	expect(not result.accepted and result.reason == "invalid_reservation",
		"direct restore rejects a JSON string reservation with a structured reason")
	expect(original.state_hash() == source_hash,
		"the rejected JSON reservation leaves the source simulation unchanged")


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


func _test_task_back_references(data: Resource, preparation: Dictionary, service_sim_script: GDScript) -> void:
	var working := _advance_until_working(data, preparation)
	var working_state: Dictionary = working.export_state()
	var task: Dictionary = working_state.tasks[0]
	var worker: Dictionary = {}
	for employee: Dictionary in working_state.employees:
		if employee.id == task.employee_id:
			worker = employee
			break
	expect(not worker.is_empty() and worker.progress == 0 and worker.tile == worker.next_tile
		and worker.order_id == task.order_id, "the back-reference fixture is valid active work")
	worker.order_id = ""
	var missing_back_reference: Dictionary = service_sim_script.call("restore", data, working_state, preparation)
	expect(not missing_back_reference.get("accepted", false),
		"restore rejects a working task whose employee lost the order back-reference")
	var idle: RefCounted = service_sim_script.new(data, null, preparation)
	var orphan_state: Dictionary = idle.export_state()
	expect(orphan_state.orders.is_empty() and orphan_state.tasks.is_empty(), "the orphan fixture starts at an empty tick boundary")
	orphan_state.tasks.append(task.duplicate(true))
	var orphan_result: Dictionary = service_sim_script.call("restore", data, orphan_state, preparation)
	expect(not orphan_result.get("accepted", false), "restore rejects a task that has no saved order")


func _test_between_process_waiting(service_sim_script: GDScript) -> void:
	for prepared: bool in [false, true]:
		var fixture := _between_process_fixture(service_sim_script, prepared)
		var simulation: RefCounted = fixture.simulation
		var view: Dictionary = simulation.snapshot()
		var waiting_order: Dictionary = view.orders[0]
		expect(waiting_order.state == "waiting" and waiting_order.phase_index > 0 and waiting_order.has_result
			and not waiting_order.carrying and view.tasks.is_empty(),
			"the real between-process fixture waits with an uncollected result: " + str(prepared))
		if prepared:
			expect(waiting_order.uses_prepared and waiting_order.intermediate_ready
				and not waiting_order.raw_consumed and not waiting_order.intermediate_consumed,
				"the prepared fixture preserves its ready intermediate")
		else:
			expect(waiting_order.raw_consumed and not waiting_order.uses_prepared
				and not waiting_order.intermediate_ready and not waiting_order.intermediate_consumed,
				"the raw fixture preserves its pickup result before preparation")
		var restored: Dictionary = service_sim_script.call("restore", fixture.definitions,
			simulation.export_state(), fixture.options)
		expect(restored.get("accepted", false) and restored.simulation.state_hash() == simulation.state_hash(),
			"restore preserves a reachable between-process waiting state: " + str(prepared))
		var lost_result: Dictionary = simulation.export_state()
		lost_result.orders[0].has_result = false
		var rejected: Dictionary = service_sim_script.call("restore", fixture.definitions, lost_result, fixture.options)
		expect(not rejected.get("accepted", false),
			"restore rejects a between-process order that lost its required result: " + str(prepared))
		var invalid_intermediate: Dictionary = simulation.export_state()
		invalid_intermediate.orders[0].intermediate_ready = not prepared
		var invalid_intermediate_result: Dictionary = service_sim_script.call("restore", fixture.definitions,
			invalid_intermediate, fixture.options)
		expect(not invalid_intermediate_result.get("accepted", false),
			"restore rejects unreachable between-process intermediate state: " + str(prepared))
		for sequence: int in [3, 4]:
			var employee_id := "employee_0%d" % (sequence - 2)
			var command := {"kind": "set_duty", "target_id": employee_id, "value": "all",
				"apply_tick": simulation.tick + 1, "sequence": sequence}
			expect(simulation.enqueue_command(command).accepted and restored.simulation.enqueue_command(command).accepted,
				"the resumed between-process fixture accepts the same duty command")
		while simulation.tick < 600:
			simulation.step()
			restored.simulation.step()
			var active_order: Dictionary = simulation.snapshot().orders[0]
			if active_order.state == "moving" and active_order.phase_index > 0:
				break
		var moving_view: Dictionary = simulation.snapshot()
		expect(moving_view.orders[0].state == "moving" and moving_view.orders[0].phase_index > 0
			and moving_view.orders[0].has_result and moving_view.tasks[0].collection_index >= 0,
			"the resumed fixture moves through a real result-collection path: " + str(prepared))
		var skipped_collection: Dictionary = simulation.export_state()
		skipped_collection.orders[0].has_result = false
		skipped_collection.orders[0].carrying = false
		skipped_collection.tasks[0].collection_index = -1
		var skipped_collection_result: Dictionary = service_sim_script.call("restore", fixture.definitions,
			skipped_collection, fixture.options)
		expect(not skipped_collection_result.get("accepted", false),
			"restore rejects a later-phase movement that skips result collection: " + str(prepared))
		while not simulation.closed:
			simulation.step()
			restored.simulation.step()
		expect(restored.simulation.state_hash() == simulation.state_hash(),
			"between-process restore preserves the final hash: " + str(prepared))


func _between_process_fixture(service_sim_script: GDScript, prepared: bool) -> Dictionary:
	var plan := PreparationPlan.new(_fresh())
	var preparation_sequence: int = 0
	if prepared:
		preparation_sequence = 1
		expect(plan.apply_command({"kind": "set_prep", "target_id": "salad", "value": 1,
			"apply_tick": 0, "sequence": preparation_sequence}).accepted,
			"the between-process fixture prepares one salad")
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": preparation_sequence + 1})
	expect(started.accepted, "the between-process fixture starts")
	var simulation: RefCounted = service_sim_script.new(started.definitions, null, started.options)
	while simulation.tick < 300 and (simulation.snapshot().orders.is_empty()
		or simulation.snapshot().orders[0].state != "working"):
		simulation.step()
	expect(simulation.snapshot().orders[0].state == "working", "the between-process fixture reaches pickup work")
	for sequence: int in [1, 2]:
		var employee_id := "employee_0%d" % sequence
		expect(simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id, "value": "off",
			"apply_tick": simulation.tick + 1, "sequence": sequence}).accepted,
			"the between-process fixture schedules an off duty")
	while simulation.tick < 500:
		simulation.step()
		var order: Dictionary = simulation.snapshot().orders[0]
		if order.state == "waiting" and order.phase_index > 0:
			break
	return {"simulation": simulation, "definitions": started.definitions, "options": started.options}


func _test_canonical_task_paths(service_sim_script: GDScript) -> void:
	var direct := _prepared_service(service_sim_script)
	_advance_to_progress(direct.simulation, 1)
	var direct_state: Dictionary = direct.simulation.export_state()
	expect(direct_state.tasks[0].collection_index == -1,
		"the direct-path fixture moves without a collection leg")
	_assert_detour_rejected(direct, service_sim_script, "direct")
	_compare_restored_run(direct, service_sim_script, "canonical_direct_path")

	var before_collection := _collection_path_fixture(service_sim_script, false)
	var before_state: Dictionary = before_collection.simulation.export_state()
	var before_task: Dictionary = before_state.tasks[0]
	var before_routes := GridRoutes.new(before_collection.definitions.grid_size,
		before_collection.definitions.blocked_tiles())
	expect(before_task.collection_index > 0 and before_task.path_index < before_task.collection_index
		and not before_state.orders[0].carrying,
		"the collection fixture is moving before pickup on a nonempty first leg")
	expect(before_task.path[0] == [3, 4] and before_task.path[before_task.collection_index] == [2, 3]
		and before_task.path[-1] == [5, 3] and before_routes.is_walkable(Vector2i(2, 4))
		and before_routes.is_walkable(Vector2i(3, 3)),
		"the collection fixture exposes two walkable equal-length first-leg route candidates")
	expect(_path_has_overlap(before_task.path),
		"the real two-leg collection path legitimately revisits a route tile")
	_assert_detour_rejected(before_collection, service_sim_script, "before_collection")
	_compare_restored_run(before_collection, service_sim_script, "canonical_before_collection")

	var after_collection := _collection_path_fixture(service_sim_script, true)
	var after_state: Dictionary = after_collection.simulation.export_state()
	var after_task: Dictionary = after_state.tasks[0]
	expect(after_task.collection_index > 0 and after_task.path_index >= after_task.collection_index
		and after_state.orders[0].carrying,
		"the collection fixture is moving after pickup on its onward leg")
	_assert_detour_rejected(after_collection, service_sim_script, "after_collection")
	_compare_restored_run(after_collection, service_sim_script, "canonical_after_collection")


func _collection_path_fixture(service_sim_script: GDScript, after_collection: bool) -> Dictionary:
	var fixture := _between_process_fixture(service_sim_script, false)
	var simulation: RefCounted = fixture.simulation
	expect(simulation.enqueue_command({"kind": "set_duty", "target_id": "employee_02", "value": "all",
		"apply_tick": simulation.tick + 1, "sequence": 3}).accepted,
		"the collection fixture enables only the employee away from the result")
	while simulation.tick < 700:
		simulation.step()
		var state: Dictionary = simulation.export_state()
		if state.tasks.is_empty() or state.orders[0].state != "moving":
			continue
		var task: Dictionary = state.tasks[0]
		var worker: Dictionary = {}
		for employee: Dictionary in state.employees:
			if employee.id == task.employee_id:
				worker = employee
				break
		if worker.get("progress", 0) not in [1, 2, 3, 4]:
			continue
		if after_collection == (task.path_index >= task.collection_index):
			break
	var final_state: Dictionary = simulation.export_state()
	expect(not final_state.tasks.is_empty() and final_state.tasks[0].employee_id == "employee_02",
		"the collection fixture assigns the result to the enabled distant employee")
	return fixture


func _assert_detour_rejected(fixture: Dictionary, service_sim_script: GDScript, label: String) -> void:
	var simulation: RefCounted = fixture.simulation
	var source_hash: String = simulation.state_hash()
	var corrupted: Dictionary = simulation.export_state()
	var task: Dictionary = corrupted.tasks[0]
	var worker: Dictionary = {}
	for employee: Dictionary in corrupted.employees:
		if employee.id == task.employee_id:
			worker = employee
			break
	expect(not worker.is_empty() and worker.progress in [1, 2, 3, 4]
		and worker.tile == task.path[task.path_index]
		and worker.next_tile == task.path[task.path_index + 1],
		"the detour fixture preserves real partial movement coordinates: " + label)
	if not _insert_path_detour(task):
		expect(false, "the detour fixture has a current and next path tile: " + label)
		return
	var result: Dictionary = service_sim_script.call("restore", fixture.definitions, corrupted, fixture.options)
	print("M4_PATH_SOURCE_HASH %s %s" % [label, source_hash])
	print("M4_PATH_DIRECT_RESULT %s %s" % [label, JSON.stringify(result)])
	expect(not result.get("accepted", false) and result.get("reason", "") == "invalid_path",
		"restore rejects a connected noncanonical task detour: " + label)
	expect(simulation.state_hash() == source_hash,
		"the rejected task detour preserves the source simulation: " + label)


func _insert_path_detour(task: Dictionary) -> bool:
	var insertion_index: int = task.path_index + 2
	if insertion_index > task.path.size():
		return false
	var current_tile: Variant = task.path[task.path_index].duplicate(true)
	var next_tile: Variant = task.path[task.path_index + 1].duplicate(true)
	task.path.insert(insertion_index, current_tile)
	task.path.insert(insertion_index + 1, next_tile)
	if task.collection_index >= insertion_index:
		task.collection_index += 2
	return true


func _path_has_overlap(path: Array) -> bool:
	for first_index: int in path.size():
		for second_index: int in range(first_index + 1, path.size()):
			if path[first_index] == path[second_index]:
				return true
	return false


func _test_active_state_relationships(service_sim_script: GDScript) -> void:
	var waiting := _single_order_fixture(service_sim_script, 10)
	for sequence: int in [1, 2]:
		var employee_id := "employee_0%d" % sequence
		expect(waiting.simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id,
			"value": "off", "apply_tick": 1, "sequence": sequence}).accepted,
			"the initial-waiting fixture disables an employee")
	while waiting.simulation.tick < 10:
		waiting.simulation.step()
	var waiting_view: Dictionary = waiting.simulation.snapshot()
	expect(waiting_view.orders[0].state == "waiting" and waiting_view.orders[0].phase_index == 0
		and not waiting_view.orders[0].has_result and waiting_view.tasks.is_empty(),
		"the initial-waiting fixture has no process result")
	var waiting_state: Dictionary = waiting.simulation.export_state()
	var waiting_restore: Dictionary = service_sim_script.call("restore", waiting.definitions,
		waiting_state, waiting.options)
	expect(waiting_restore.get("accepted", false), "restore accepts the actual initial-waiting state")
	var fake_waiting_result := waiting_state.duplicate(true)
	fake_waiting_result.orders[0].has_result = true
	fake_waiting_result.orders[0].result_position = [2, 3]
	var fake_waiting_restore: Dictionary = service_sim_script.call("restore", waiting.definitions,
		fake_waiting_result, waiting.options)
	expect(not fake_waiting_restore.get("accepted", false),
		"restore rejects a fabricated result on an initial-waiting order")
	var premature_consumption := waiting_state.duplicate(true)
	premature_consumption.orders[0].input_consumed = true
	premature_consumption.orders[0].raw_consumed = true
	premature_consumption.inventory.vegetable -= 1
	var premature_consumption_restore: Dictionary = service_sim_script.call("restore", waiting.definitions,
		premature_consumption, waiting.options)
	expect(not premature_consumption_restore.get("accepted", false),
		"restore rejects raw input consumed before initial work")

	var moving := _single_order_fixture(service_sim_script, 10)
	while moving.simulation.tick < 100:
		moving.simulation.step()
		if not moving.simulation.snapshot().orders.is_empty() \
			and moving.simulation.snapshot().orders[0].state == "moving":
			break
	var moving_view: Dictionary = moving.simulation.snapshot()
	expect(moving_view.orders[0].state == "moving" and moving_view.orders[0].phase_index == 0
		and not moving_view.orders[0].has_result and moving_view.tasks[0].collection_index == -1,
		"the initial-moving fixture has no result-collection path")
	var moving_state: Dictionary = moving.simulation.export_state()
	var moving_restore: Dictionary = service_sim_script.call("restore", moving.definitions, moving_state, moving.options)
	expect(moving_restore.get("accepted", false), "restore accepts the actual initial-moving state")
	var fake_moving_result := moving_state.duplicate(true)
	var path_index: int = fake_moving_result.tasks[0].path_index
	fake_moving_result.orders[0].has_result = true
	fake_moving_result.orders[0].carrying = true
	fake_moving_result.orders[0].result_position = fake_moving_result.tasks[0].path[path_index].duplicate()
	fake_moving_result.tasks[0].collection_index = path_index
	var fake_moving_restore: Dictionary = service_sim_script.call("restore", moving.definitions,
		fake_moving_result, moving.options)
	expect(not fake_moving_restore.get("accepted", false),
		"restore rejects a fabricated result-collection path on initial movement")

	var prepared := _between_process_fixture(service_sim_script, true)
	for sequence: int in [3, 4]:
		var employee_id := "employee_0%d" % (sequence - 2)
		expect(prepared.simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id,
			"value": "all", "apply_tick": prepared.simulation.tick + 1, "sequence": sequence}).accepted,
			"the prepared active-state fixture enables an employee")
	while prepared.simulation.tick < 600:
		prepared.simulation.step()
		var order: Dictionary = prepared.simulation.snapshot().orders[0]
		if order.state == "moving" and order.phase_id == "cook":
			break
	var cook_moving_view: Dictionary = prepared.simulation.snapshot()
	expect(cook_moving_view.orders[0].state == "moving" and cook_moving_view.orders[0].phase_id == "cook"
		and cook_moving_view.orders[0].intermediate_ready
		and not cook_moving_view.orders[0].intermediate_consumed,
		"the prepared result remains ready while moving to cooking")
	var cook_moving_state: Dictionary = prepared.simulation.export_state()
	var cook_moving_restore: Dictionary = service_sim_script.call("restore", prepared.definitions,
		cook_moving_state, prepared.options)
	expect(cook_moving_restore.get("accepted", false), "restore accepts the actual movement to cooking")
	cook_moving_state.orders[0].intermediate_ready = false
	var erased_intermediate_restore: Dictionary = service_sim_script.call("restore", prepared.definitions,
		cook_moving_state, prepared.options)
	expect(not erased_intermediate_restore.get("accepted", false),
		"restore rejects a prepared result erased while moving to cooking")
	while prepared.simulation.tick < 700:
		prepared.simulation.step()
		var order: Dictionary = prepared.simulation.snapshot().orders[0]
		if order.state == "working" and order.phase_id == "cook":
			break
	var cook_working_view: Dictionary = prepared.simulation.snapshot()
	expect(cook_working_view.orders[0].state == "working" and cook_working_view.orders[0].phase_id == "cook"
		and not cook_working_view.orders[0].intermediate_ready
		and cook_working_view.orders[0].intermediate_consumed,
		"cooking consumes the prepared result when work begins")
	var cook_working_state: Dictionary = prepared.simulation.export_state()
	var cook_working_restore: Dictionary = service_sim_script.call("restore", prepared.definitions,
		cook_working_state, prepared.options)
	expect(cook_working_restore.get("accepted", false), "restore accepts the actual active cooking state")
	cook_working_state.orders[0].intermediate_ready = true
	cook_working_state.orders[0].intermediate_consumed = false
	var skipped_consumption_restore: Dictionary = service_sim_script.call("restore", prepared.definitions,
		cook_working_state, prepared.options)
	expect(not skipped_consumption_restore.get("accepted", false),
		"restore rejects cooking that skipped prepared-result consumption")


func _test_terminal_relationships(service_sim_script: GDScript) -> void:
	var late := _single_order_fixture(service_sim_script, 2988)
	while late.simulation.tick < 2999:
		late.simulation.step()
	var preclose: Dictionary = late.simulation.snapshot()
	expect(not late.simulation.closed and late.simulation.tick == 2999 and preclose.tasks.size() == 1
		and preclose.orders[0].state in ["moving", "working"] and preclose.orders[0].raw_consumed,
		"the late-order fixture has consumed raw input and remains active one tick before closing")
	var active_station_id: String = preclose.tasks[0].station_id
	var resumed: Dictionary = service_sim_script.call("restore", late.definitions,
		late.simulation.export_state(), late.options)
	expect(resumed.get("accepted", false) and resumed.simulation.state_hash() == late.simulation.state_hash(),
		"restore accepts the reachable raw-consuming pre-close state")
	late.simulation.step()
	resumed.simulation.step()
	expect(late.simulation.closed and resumed.simulation.state_hash() == late.simulation.state_hash(),
		"the restored raw-consuming pre-close state reaches the same final hash")
	var closed_state: Dictionary = late.simulation.export_state()
	var closed_order: Dictionary = closed_state.orders[0]
	expect(closed_order.state == "expired" and closed_order.terminal_reason == "service_closed"
		and closed_order.ended_tick == late.definitions.closing_tick and closed_state.tasks.is_empty(),
		"the late order reaches a coherent service-close terminal state")
	var closed_restore: Dictionary = service_sim_script.call("restore", late.definitions, closed_state, late.options)
	expect(closed_restore.get("accepted", false), "restore accepts the actual late-order closed state")
	var served_at_close := closed_state.duplicate(true)
	served_at_close.orders[0].state = "served"
	served_at_close.orders[0].terminal_reason = ""
	served_at_close.orders[0].phase_index = late.definitions.recipe_for("salad").ordered_processes().size()
	var served_at_close_result: Dictionary = service_sim_script.call("restore", late.definitions,
		served_at_close, late.options)
	expect(not served_at_close_result.get("accepted", false), "restore rejects an order served at the closing tick")
	var active_closed := closed_state.duplicate(true)
	active_closed.orders[0].state = "waiting"
	active_closed.orders[0].terminal_reason = ""
	active_closed.orders[0].ended_tick = -1
	active_closed.orders[0].metrics.missing_ingredients += 1
	var active_closed_result: Dictionary = service_sim_script.call("restore", late.definitions,
		active_closed, late.options)
	expect(not active_closed_result.get("accepted", false), "restore rejects an active order in a closed service")
	var early_close := closed_state.duplicate(true)
	expect(early_close.orders[0].metrics.working > 0, "the service-close fixture records active work before closing")
	early_close.orders[0].ended_tick -= 1
	early_close.orders[0].metrics.working -= 1
	early_close.station_reserved_ticks[active_station_id] -= 1
	var early_close_result: Dictionary = service_sim_script.call("restore", late.definitions, early_close, late.options)
	expect(not early_close_result.get("accepted", false),
		"restore ties a service-closed order's end tick to the closing tick")

	var deadline := _single_order_fixture(service_sim_script, 10)
	for sequence: int in [1, 2]:
		var employee_id := "employee_0%d" % sequence
		expect(deadline.simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id,
			"value": "off", "apply_tick": 1, "sequence": sequence}).accepted,
			"the deadline fixture disables an employee")
	while deadline.simulation.tick < deadline.definitions.order_schedule()[0].deadline_tick:
		deadline.simulation.step()
	var deadline_state: Dictionary = deadline.simulation.export_state()
	var deadline_order: Dictionary = deadline_state.orders[0]
	expect(deadline_order.state == "expired" and deadline_order.terminal_reason == "deadline"
		and deadline_order.ended_tick == deadline_order.deadline_tick
		and deadline_order.metrics.no_responsible_employee > 0,
		"the deadline fixture reaches a coherent deadline terminal state")
	deadline_order.ended_tick -= 1
	deadline_order.metrics.no_responsible_employee -= 1
	var deadline_result: Dictionary = service_sim_script.call("restore", deadline.definitions,
		deadline_state, deadline.options)
	expect(not deadline_result.get("accepted", false), "restore ties a deadline expiration to its deadline tick")
	var actual_deadline_state: Dictionary = deadline.simulation.export_state()
	var actual_deadline_restore: Dictionary = service_sim_script.call("restore", deadline.definitions,
		actual_deadline_state, deadline.options)
	expect(actual_deadline_restore.get("accepted", false), "restore accepts the actual deadline-expired state")
	var active_after_deadline := actual_deadline_state.duplicate(true)
	active_after_deadline.orders[0].state = "waiting"
	active_after_deadline.orders[0].terminal_reason = ""
	active_after_deadline.orders[0].ended_tick = -1
	active_after_deadline.orders[0].metrics.no_responsible_employee += 1
	var active_after_deadline_restore: Dictionary = service_sim_script.call("restore", deadline.definitions,
		active_after_deadline, deadline.options)
	expect(not active_after_deadline_restore.get("accepted", false),
		"restore rejects an active order at its deadline")
	var deadline_at_close := _single_order_fixture(service_sim_script, 2500)
	for sequence: int in [1, 2]:
		var employee_id := "employee_0%d" % sequence
		expect(deadline_at_close.simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id,
			"value": "off", "apply_tick": 1, "sequence": sequence}).accepted,
			"the closing-deadline fixture disables an employee")
	while not deadline_at_close.simulation.closed:
		deadline_at_close.simulation.step()
	var deadline_at_close_state: Dictionary = deadline_at_close.simulation.export_state()
	var deadline_at_close_order: Dictionary = deadline_at_close_state.orders[0]
	expect(deadline_at_close_order.deadline_tick == deadline_at_close.definitions.closing_tick
		and deadline_at_close_order.state == "expired" and deadline_at_close_order.terminal_reason == "deadline"
		and deadline_at_close_order.ended_tick == deadline_at_close.definitions.closing_tick,
		"the deadline loop wins when the deadline equals closing")
	var deadline_at_close_restore: Dictionary = service_sim_script.call("restore", deadline_at_close.definitions,
		deadline_at_close_state, deadline_at_close.options)
	expect(deadline_at_close_restore.get("accepted", false), "restore accepts the actual closing-deadline state")
	deadline_at_close_state.orders[0].terminal_reason = "service_closed"
	var swapped_close_reason: Dictionary = service_sim_script.call("restore", deadline_at_close.definitions,
		deadline_at_close_state, deadline_at_close.options)
	expect(not swapped_close_reason.get("accepted", false),
		"restore rejects service-closed when the deadline equals closing")

	var served := _single_order_fixture(service_sim_script, 10)
	var served_deadline: int = served.definitions.order_schedule()[0].deadline_tick
	while served.simulation.tick < served_deadline:
		served.simulation.step()
	var served_state: Dictionary = served.simulation.export_state()
	var served_order: Dictionary = served_state.orders[0]
	expect(served_order.state == "served" and served_order.ended_tick < served_order.deadline_tick,
		"the served fixture completes before its deadline")
	served_order.metrics.missing_ingredients += served_order.deadline_tick - served_order.ended_tick
	served_order.ended_tick = served_order.deadline_tick
	var served_result: Dictionary = service_sim_script.call("restore", served.definitions,
		served_state, served.options)
	expect(not served_result.get("accepted", false), "restore rejects service recorded at or after the deadline")


func _single_order_fixture(service_sim_script: GDScript, arrival_tick: int) -> Dictionary:
	var data := _fresh()
	data.order_count = 1
	data.order_recipe_ids = PackedStringArray(["salad"])
	data.first_arrival_tick = arrival_tick
	data.minimum_served = 1
	data.minimum_profit = -data.starting_budget
	expect(data.validate(false).is_empty(), "the single-order restoration fixture is valid")
	var plan := PreparationPlan.new(data)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the single-order restoration fixture starts")
	return {"simulation": service_sim_script.new(started.definitions, null, started.options),
		"definitions": started.definitions, "options": started.options}


func _test_command_canonicalization(service_sim_script: GDScript) -> void:
	var fixture := _single_order_fixture(service_sim_script, 10)
	while fixture.simulation.snapshot().orders.is_empty():
		fixture.simulation.step()
	var command := {"kind": "cancel_order", "target_id": "order_01", "value": {"ignored": true},
		"apply_tick": fixture.simulation.tick + 2, "sequence": 1, "extra": "discard"}
	var original_command := command.duplicate(true)
	expect(fixture.simulation.enqueue_command(command).accepted,
		"the command API accepts a cancel value and an extra caller field")
	expect(command == original_command, "command canonicalization leaves the caller's dictionary unchanged")
	var exported: Dictionary = fixture.simulation.export_state()
	var saved_command: Dictionary = exported.commands[0]
	expect(saved_command.size() == 5 and saved_command.has("kind") and saved_command.has("target_id")
		and saved_command.has("value") and saved_command.has("apply_tick") and saved_command.has("sequence")
		and saved_command.value == null,
		"an accepted command exports only authoritative fields with a canonical cancel value")
	var restored: Dictionary = service_sim_script.call("restore", fixture.definitions, exported, fixture.options)
	expect(restored.get("accepted", false), "restore accepts an exported command that the enqueue API accepted")
	if not restored.get("accepted", false):
		return
	expect(restored.simulation.state_hash() == fixture.simulation.state_hash(),
		"canonical command restoration preserves the immediate hash")
	while not fixture.simulation.closed:
		fixture.simulation.step()
		restored.simulation.step()
	expect(restored.simulation.state_hash() == fixture.simulation.state_hash(),
		"canonical command restoration preserves the final hash")


func _test_work_timing_relationships(service_sim_script: GDScript) -> void:
	var fixtures: Array[Dictionary] = []
	var initial := _single_order_fixture(service_sim_script, 10)
	while initial.simulation.tick < 100 and (initial.simulation.snapshot().orders.is_empty()
		or initial.simulation.snapshot().orders[0].state != "working"):
		initial.simulation.step()
	fixtures.append({"label": "initial_raw", "fixture": initial})
	for prepared: bool in [false, true]:
		var later := _between_process_fixture(service_sim_script, prepared)
		for sequence: int in [3, 4]:
			var employee_id := "employee_0%d" % (sequence - 2)
			expect(later.simulation.enqueue_command({"kind": "set_duty", "target_id": employee_id,
				"value": "all", "apply_tick": later.simulation.tick + 1, "sequence": sequence}).accepted,
				"the later-phase timing fixture enables an employee: " + str(prepared))
		while later.simulation.tick < 700:
			later.simulation.step()
			var order: Dictionary = later.simulation.snapshot().orders[0]
			if order.state == "working" and order.phase_index > 0:
				break
		fixtures.append({"label": "later_prepared" if prepared else "later_raw", "fixture": later})
	for entry: Dictionary in fixtures:
		var label: String = entry.label
		var fixture: Dictionary = entry.fixture
		var simulation: RefCounted = fixture.simulation
		var view: Dictionary = simulation.snapshot()
		var task: Dictionary = view.tasks[0]
		expect(view.orders[0].state == "working" and task.started_tick >= view.orders[0].arrival_tick
			and task.completion_tick > simulation.tick + 1,
			"the timing fixture contains active work with room for a one-tick shift: " + label)
		if label.begins_with("later"):
			expect(view.orders[0].phase_index > 0, "the timing fixture reached a later process: " + label)
		var state: Dictionary = simulation.export_state()
		var restored: Dictionary = service_sim_script.call("restore", fixture.definitions, state, fixture.options)
		expect(restored.get("accepted", false) and restored.simulation.state_hash() == simulation.state_hash(),
			"restore accepts the actual working checkpoint: " + label)
		var before_hash: String = simulation.state_hash()
		print("M4_CORE_SOURCE_HASH working_time_%s %s" % [label, before_hash])
		var shifted := state.duplicate(true)
		shifted.tasks[0].started_tick -= 1
		shifted.tasks[0].completion_tick -= 1
		var shifted_restore: Dictionary = service_sim_script.call("restore", fixture.definitions,
			shifted, fixture.options)
		expect(not shifted_restore.get("accepted", false),
			"restore rejects working timestamps shifted before accumulated work: " + label)
		expect(simulation.state_hash() == before_hash,
			"a rejected working-time shift preserves the source simulation: " + label)
		if restored.get("accepted", false):
			while not simulation.closed:
				simulation.step()
				restored.simulation.step()
			expect(restored.simulation.state_hash() == simulation.state_hash(),
				"the valid working checkpoint preserves the final hash: " + label)


func _test_tick_zero_employee_relationships(service_sim_script: GDScript) -> void:
	var fixture := _prepared_service(service_sim_script)
	var simulation: RefCounted = fixture.simulation
	var state: Dictionary = simulation.export_state()
	expect(state.tick == 0 and state.orders.is_empty() and state.tasks.is_empty()
		and state.employees[0].duty == "cold" and state.employees[1].duty == "hot",
		"the tick-zero fixture contains committed nondefault preparation duties")
	var restored: Dictionary = service_sim_script.call("restore", fixture.definitions, state, fixture.options)
	expect(restored.get("accepted", false) and restored.simulation.state_hash() == simulation.state_hash(),
		"restore accepts the unmodified prepared tick-zero employees")
	var source_hash: String = simulation.state_hash()
	var moved_employee := state.duplicate(true)
	moved_employee.employees[0].tile = [4, 4]
	moved_employee.employees[0].next_tile = [4, 4]
	var moved_result: Dictionary = service_sim_script.call("restore", fixture.definitions,
		moved_employee, fixture.options)
	expect(not moved_result.get("accepted", false),
		"restore rejects a walkable tick-zero employee position that differs from preparation")
	expect(simulation.state_hash() == source_hash,
		"the rejected tick-zero position preserves the source simulation")
	var changed_duty := state.duplicate(true)
	changed_duty.employees[0].duty = "hot"
	var duty_result: Dictionary = service_sim_script.call("restore", fixture.definitions,
		changed_duty, fixture.options)
	expect(not duty_result.get("accepted", false),
		"restore rejects a valid tick-zero duty that differs from preparation")
	expect(simulation.state_hash() == source_hash,
		"the rejected tick-zero duty preserves the source simulation")
	if not restored.get("accepted", false):
		return
	var command := {"kind": "set_duty", "target_id": "employee_01", "value": "all",
		"apply_tick": 1, "sequence": 1}
	expect(simulation.enqueue_command(command).accepted and restored.simulation.enqueue_command(command).accepted,
		"the prepared tick-zero pair accepts the same real duty command")
	while simulation.tick < 300:
		simulation.step()
		restored.simulation.step()
		var view: Dictionary = simulation.snapshot()
		if not view.tasks.is_empty() and view.employees[0].progress in [1, 2, 3, 4]:
			break
	var later_state: Dictionary = simulation.export_state()
	expect(later_state.tick > 0 and later_state.employees[0].duty == "all"
		and not later_state.tasks.is_empty() and later_state.employees[0].progress in [1, 2, 3, 4],
		"the tick-positive fixture contains an applied duty command and actual path progress")
	var later_restore: Dictionary = service_sim_script.call("restore", fixture.definitions,
		later_state, fixture.options)
	expect(later_restore.get("accepted", false)
		and later_restore.simulation.state_hash() == simulation.state_hash(),
		"tick-positive command and path state remain independently restorable")
	while not simulation.closed:
		simulation.step()
		restored.simulation.step()
	expect(restored.simulation.state_hash() == simulation.state_hash(),
		"the valid prepared tick-zero restore preserves the final hash")


func _test_active_duty_relationships(service_sim_script: GDScript) -> void:
	var moving := _single_order_fixture(service_sim_script, 10)
	while moving.simulation.tick < 100 and (moving.simulation.snapshot().orders.is_empty()
		or moving.simulation.snapshot().orders[0].state != "moving"):
		moving.simulation.step()
	var moving_state: Dictionary = moving.simulation.export_state()
	var moving_employee_index: int = -1
	for index: int in moving_state.employees.size():
		if moving_state.employees[index].id == moving_state.tasks[0].employee_id:
			moving_employee_index = index
			break
	expect(moving_state.orders[0].state == "moving" and moving_employee_index >= 0
		and moving_state.employees[moving_employee_index].duty == "all",
		"the active-duty fixture contains an assigned employee moving under the all duty")
	var moving_restore: Dictionary = service_sim_script.call("restore", moving.definitions,
		moving_state, moving.options)
	expect(moving_restore.get("accepted", false), "restore accepts the actual active moving duty")
	var moving_before_hash: String = moving.simulation.state_hash()
	print("M4_CORE_SOURCE_HASH active_duty_moving %s" % moving_before_hash)
	var off_duty_moving := moving_state.duplicate(true)
	off_duty_moving.employees[moving_employee_index].duty = "off"
	var off_duty_restore: Dictionary = service_sim_script.call("restore", moving.definitions,
		off_duty_moving, moving.options)
	expect(not off_duty_restore.get("accepted", false),
		"restore rejects an active moving employee whose current duty is off")
	expect(moving.simulation.state_hash() == moving_before_hash,
		"a rejected moving-duty relation preserves the source simulation")

	var working := _single_order_fixture(service_sim_script, 10)
	while working.simulation.tick < 100 and (working.simulation.snapshot().orders.is_empty()
		or working.simulation.snapshot().orders[0].state != "working"):
		working.simulation.step()
	var working_state: Dictionary = working.simulation.export_state()
	var working_employee_index: int = -1
	for index: int in working_state.employees.size():
		if working_state.employees[index].id == working_state.tasks[0].employee_id:
			working_employee_index = index
			break
	expect(working_state.orders[0].state == "working" and working_state.orders[0].recipe_id == "salad"
		and working.definitions.recipe_for("salad").cook_role == "cold" and working_employee_index >= 0
		and working_state.employees[working_employee_index].duty == "all",
		"the active-duty fixture contains an assigned employee working on the cold recipe")
	var working_restore: Dictionary = service_sim_script.call("restore", working.definitions,
		working_state, working.options)
	expect(working_restore.get("accepted", false), "restore accepts the actual active working duty")
	var working_before_hash: String = working.simulation.state_hash()
	print("M4_CORE_SOURCE_HASH active_duty_working %s" % working_before_hash)
	var incompatible_working := working_state.duplicate(true)
	incompatible_working.employees[working_employee_index].duty = "hot"
	var incompatible_restore: Dictionary = service_sim_script.call("restore", working.definitions,
		incompatible_working, working.options)
	expect(not incompatible_restore.get("accepted", false),
		"restore rejects an active working employee with an incompatible cooking duty")
	expect(working.simulation.state_hash() == working_before_hash,
		"a rejected working-duty relation preserves the source simulation")

	var active_employee_id: String = working_state.employees[working_employee_index].id
	expect(working.simulation.enqueue_command({"kind": "set_duty", "target_id": active_employee_id,
		"value": "off", "apply_tick": working.simulation.tick + 1, "sequence": 1}).accepted,
		"the active-duty fixture accepts a deferred off duty command")
	working.simulation.step()
	var deferred_state: Dictionary = working.simulation.export_state()
	expect(deferred_state.orders[0].state == "working"
		and deferred_state.employees[working_employee_index].duty == "all"
		and deferred_state.employees[working_employee_index].pending_duty == "off",
		"an active duty change preserves the current duty and records the pending duty")
	var deferred_restore: Dictionary = service_sim_script.call("restore", working.definitions,
		deferred_state, working.options)
	expect(deferred_restore.get("accepted", false)
		and deferred_restore.simulation.state_hash() == working.simulation.state_hash(),
		"restore preserves a valid deferred duty change during active work")
	if deferred_restore.get("accepted", false):
		while not working.simulation.closed:
			working.simulation.step()
			deferred_restore.simulation.step()
		expect(deferred_restore.simulation.state_hash() == working.simulation.state_hash(),
			"the restored deferred duty change preserves the final hash")


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
