extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")

var case_index: int = 0


func run(_tree: SceneTree) -> void:
	var directory := "user://test_restore_history_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "the command history directory is created")
	for target_tick: int in [0, 1, 9]:
		var fixture := _fixture()
		while fixture.simulation.tick < target_tick:
			fixture.simulation.step()
		var state: Dictionary = fixture.simulation.export_state()
		expect(state.schedule_cursor == 0 and state.last_sequence == 0 and state.tasks.is_empty(),
			"the fixture has no arrivals or submitted commands at tick %d" % target_tick)
		_reject_initial_changes(fixture, directory, "before_arrival_%d" % target_tick)
		_round_trip(fixture, "before_arrival_%d" % target_tick)

	var queued := _fixture()
	_queue(queued, "set_duty", "employee_01", "all", 1, 8)
	queued.simulation.step()
	expect(queued.simulation.export_state().commands.size() == 1
		and queued.simulation.export_state().last_sequence == 1,
		"the queued-only fixture has one submitted command that has not applied")
	_reject_initial_changes(queued, directory, "queued_before_arrival")
	_round_trip(queued, "queued_before_arrival")

	var early_duty := _fixture()
	_queue(early_duty, "set_duty", "employee_01", "all", 1, 1)
	early_duty.simulation.step()
	expect(early_duty.simulation.export_state().employees[0].duty == "all"
		and early_duty.simulation.export_state().commands.is_empty(),
		"a real tick-one duty command changes the prepared duty before any arrival")
	_reject_position(early_duty, directory, "applied_duty_before_arrival")
	_round_trip(early_duty, "applied_duty_before_arrival")

	var gap := _fixture()
	_queue(gap, "set_duty", "employee_01", "all", 7, 8)
	gap.simulation.step()
	expect(gap.simulation.export_state().last_sequence == 7 and gap.simulation.export_state().commands.size() == 1,
		"the public command API permits a sequence gap")
	_round_trip(gap, "queued_sequence_gap")
	var reordered := _fixture()
	_advance_to_work(reordered)
	_queue(reordered, "set_priority", "order_01", 0, 1, reordered.simulation.tick + 5)
	_queue(reordered, "set_duty", "employee_01", "off", 2, reordered.simulation.tick + 1)
	reordered.simulation.step()
	expect(reordered.simulation.export_state().commands.size() == 1
		and reordered.simulation.export_state().employees[0].pending_duty == "off",
		"a later sequence can apply while an earlier sequence remains queued")
	_round_trip(reordered, "applied_with_pending_command")

	for queued_only: bool in [false, true]:
		var working := _fixture()
		_advance_to_work(working)
		if queued_only:
			_queue(working, "set_priority", "order_01", 2, 1, working.simulation.tick + 5)
		var state: Dictionary = working.simulation.export_state()
		expect(state.orders[0].state == "working" and state.orders[0].priority == 1
			and state.last_sequence == state.commands.size(),
			"the working fixture has not applied a command: " + str(queued_only))
		for priority: int in [0, 2]:
			var corrupted := state.duplicate(true)
			corrupted.orders[0].priority = priority
			_reject(working, corrupted, "invalid_order", directory, "working_priority_%s_%d" % [queued_only, priority])
		var pending := state.duplicate(true)
		pending.employees[0].pending_duty = "off"
		_reject(working, pending, "invalid_employee", directory, "working_pending_%s" % queued_only)
		var duty := state.duplicate(true)
		duty.employees[0].duty = "all"
		_reject(working, duty, "invalid_employee", directory, "working_duty_%s" % queued_only)
		_round_trip(working, "working_%s" % queued_only)

	for kind: String in ["set_priority", "set_duty", "cancel_order"]:
		var applied := _fixture()
		_advance_to_work(applied)
		var target := "employee_01" if kind == "set_duty" else "order_01"
		var value: Variant = "off" if kind == "set_duty" else (2 if kind == "set_priority" else null)
		_queue(applied, kind, target, value, 1, applied.simulation.tick + 1)
		applied.simulation.step()
		var state: Dictionary = applied.simulation.export_state()
		expect(state.last_sequence == 1 and state.commands.is_empty(), "the real command applied: " + kind)
		var changed: bool = state.orders[0].priority == 2 if kind == "set_priority" else (
			state.employees[0].pending_duty == "off" if kind == "set_duty" else state.orders[0].state == "cancelled")
		expect(changed, "the applied command produced its target state: " + kind)
		var corrupted := state.duplicate(true)
		corrupted.last_sequence = 0
		_reject(applied, corrupted, "invalid_employee" if kind == "set_duty" else "invalid_order",
			directory, "erased_sequence_" + kind)
		_round_trip(applied, "applied_" + kind)

	var closed := _fixture()
	while not closed.simulation.closed:
		closed.simulation.step()
	var closed_state: Dictionary = closed.simulation.export_state()
	expect(closed_state.last_sequence == 0 and closed_state.orders[0].state == "served",
		"the command-free terminal fixture contains an actually served order")
	closed_state.orders[0].priority = 2
	_reject(closed, closed_state, "invalid_order", directory, "closed_priority")
	_round_trip(closed, "closed")
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(directory) == OK, "the command history fixtures are removed")


func _fixture() -> Dictionary:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var plan := PreparationPlan.new(campaign.scenario_for("first_shift"))
	expect(plan.apply_command({"kind": "set_duty", "target_id": "employee_01", "value": "cold",
		"apply_tick": 0, "sequence": 1}).accepted, "the fixture selects a nondefault first duty")
	expect(plan.apply_command({"kind": "set_duty", "target_id": "employee_02", "value": "hot",
		"apply_tick": 0, "sequence": 2}).accepted, "the fixture selects a nondefault second duty")
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 3})
	expect(started.accepted, "the history fixture starts through the preparation API")
	return {"campaign": campaign, "definitions": started.definitions, "options": started.options,
		"selection": started.selection, "simulation": ServiceSim.new(started.definitions, null, started.options)}


func _queue(fixture: Dictionary, kind: String, target: String, value: Variant, sequence: int, apply_tick: int) -> void:
	expect(fixture.simulation.enqueue_command({"kind": kind, "target_id": target, "value": value,
		"sequence": sequence, "apply_tick": apply_tick}).accepted, "the fixture submits a real command: " + kind)


func _advance_to_work(fixture: Dictionary) -> void:
	while fixture.simulation.tick < 300:
		fixture.simulation.step()
		var state: Dictionary = fixture.simulation.export_state()
		if not state.orders.is_empty() and state.orders[0].state == "working":
			expect(state.employees[0].order_id == "order_01" and state.employees[0].pending_duty.is_empty(),
				"the real working fixture binds the first employee without a pending duty")
			return
	expect(false, "the history fixture reaches actual work")


func _reject_initial_changes(fixture: Dictionary, directory: String, label: String) -> void:
	_reject_position(fixture, directory, label)
	var state: Dictionary = fixture.simulation.export_state()
	state.employees[0].duty = "all"
	_reject(fixture, state, "invalid_employee", directory, label + "_duty")


func _reject_position(fixture: Dictionary, directory: String, label: String) -> void:
	var state: Dictionary = fixture.simulation.export_state()
	state.employees[0].tile = [4, 4]
	state.employees[0].next_tile = [4, 4]
	_reject(fixture, state, "invalid_employee", directory, label + "_position")


func _reject(fixture: Dictionary, corrupted: Dictionary, reason: String, directory: String, label: String) -> void:
	var before: String = fixture.simulation.state_hash()
	var rejected := ServiceSim.restore(fixture.definitions, corrupted, fixture.options)
	expect(not rejected.accepted and rejected.reason == reason, "direct restore rejects command history corruption: " + label)
	expect(fixture.simulation.state_hash() == before, "rejection preserves the source simulation: " + label)
	case_index += 1
	var target := directory + "/case_%d.json" % case_index
	var session := ServiceSession.capture("first_shift", fixture.selection, fixture.simulation)
	var store := CampaignStore.new(fixture.campaign, target)
	expect(store.save_active_session(session, {}).accepted and store.save_active_session(session, {}).accepted,
		"the file fixture writes a valid primary and backup: " + label)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target))
	document.active_session.simulation = corrupted
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	var primary_bytes := FileAccess.get_file_as_bytes(target)
	var backup_bytes := FileAccess.get_file_as_bytes(target + ".backup")
	var loaded := CampaignStore.new(fixture.campaign, target).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records" and loaded.can_recover,
		"a fresh file reader offers recovery for command history corruption: " + label)
	expect(FileAccess.get_file_as_bytes(target) == primary_bytes
		and FileAccess.get_file_as_bytes(target + ".backup") == backup_bytes,
		"a failed read preserves primary and backup bytes: " + label)
	if loaded.accepted:
		return
	expect(store.recover_backup().accepted, "explicit backup recovery succeeds: " + label)
	var recovered := CampaignStore.new(fixture.campaign, target).load_records()
	var restored := ServiceSession.restore(fixture.campaign, recovered.active_session, recovered.records)
	expect(restored.accepted and restored.simulation.state_hash() == before,
		"the recovered file preserves the original simulation hash: " + label)
	expect(FileAccess.get_file_as_bytes(target + ".backup") == backup_bytes,
		"recovery preserves the valid backup bytes: " + label)


func _round_trip(fixture: Dictionary, label: String) -> void:
	var restored := ServiceSim.restore(fixture.definitions, fixture.simulation.export_state(), fixture.options)
	expect(restored.accepted and restored.simulation.state_hash() == fixture.simulation.state_hash(),
		"a reachable history checkpoint preserves its immediate hash: " + label)
	if not restored.accepted:
		return
	while not fixture.simulation.closed:
		fixture.simulation.step()
		restored.simulation.step()
	expect(restored.simulation.state_hash() == fixture.simulation.state_hash(),
		"a reachable history checkpoint preserves its final hash: " + label)
