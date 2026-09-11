extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")


func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var scenario: Resource = campaign.scenario_for("hot_queue")
	var plan := PreparationPlan.new(scenario)
	var changed := _command(plan, "set_menu_priority", "grill", 2)
	expect(changed.accepted, "preparation accepts a menu default priority")
	if not changed.accepted:
		return
	for invalid: Variant in [-1, 3, 1.5, "2", true, null]:
		var before := JSON.stringify(plan.snapshot())
		expect(not _command(plan, "set_menu_priority", "grill", invalid).accepted, "preparation rejects invalid priority: " + str(invalid))
		expect(JSON.stringify(plan.snapshot()) == before, "invalid priority preserves preparation and sequence")
	expect(not _command(plan, "set_menu_priority", "unknown", 2).accepted, "unknown menu priority is rejected")
	var retry := PreparationPlan.new(scenario, plan.snapshot().selection)
	expect(retry.snapshot().menu_priorities.grill == 2, "retry retains menu priorities")
	var exposed := retry.snapshot()
	exposed.menu_priorities.grill = 0
	expect(retry.snapshot().menu_priorities.grill == 2, "display snapshots cannot change menu defaults")
	_command(retry, "reset", "", null)
	expect(retry.snapshot().menu_priorities.grill == 1, "reset restores default menu priority")
	var legacy: Dictionary = plan.snapshot().selection
	legacy.erase("menu_priorities")
	expect(PreparationPlan.new(scenario, legacy).snapshot().menu_priorities.grill == 1, "legacy preparation defaults to one")
	var policy := Policies.reference_policy("hot_queue")
	policy.priorities = {}
	policy.preparation.append({"kind": "set_menu_priority", "target_id": "grill", "value": 2})
	var normal := Policies.run_policy(scenario, policy, 1)
	var fast := Policies.run_policy(scenario, policy, 4)
	expect(normal.accepted and fast.accepted, "menu defaults run at both service speeds")
	if normal.accepted and fast.accepted:
		expect(normal.snapshot.accounting.served >= scenario.minimum_served and normal.snapshot.accounting.profit >= scenario.minimum_profit,
			"hot queue passes without service-time priority commands")
		expect(normal.hash == fast.hash, "menu defaults produce identical final states at 1x and 4x")
		print("HOT_QUEUE_MENU_DEFAULT_RESULT ", JSON.stringify(normal.snapshot.accounting))
	var closer := policy.duplicate(true)
	closer.preparation.append({"kind": "move_station", "target_id": "hot_01", "value": "right"})
	var closer_result := Policies.run_policy(scenario, closer, 4)
	expect(closer_result.accepted and (closer_result.snapshot.accounting != normal.snapshot.accounting
		or closer_result.snapshot.metrics != normal.snapshot.metrics),
		"a second legal hot-station layout changes the pressure result at 4x")
	if closer_result.accepted:
		print("HOT_QUEUE_CLOSER_MENU_DEFAULT_RESULT ", JSON.stringify(closer_result.snapshot.accounting))
	_test_restore(campaign)
	await _test_ui(tree, scenario, policy)


func _command(plan: RefCounted, kind: String, target: String, value: Variant) -> Dictionary:
	return plan.apply_command({"kind": kind, "target_id": target, "value": value,
		"apply_tick": 0, "sequence": plan.snapshot().sequence + 1})


func _test_restore(campaign: Resource) -> void:
	var scenario: Resource = campaign.scenario_for("first_shift")
	var plan := PreparationPlan.new(scenario)
	_command(plan, "set_menu_priority", "salad", 0)
	var started := _command(plan, "start", "", null)
	var sim := ServiceSim.new(started.definitions, null, started.options)
	while sim.snapshot().orders.is_empty():
		sim.step()
	expect(sim.snapshot().orders[0].priority == 0, "arriving order receives its menu default before any command")
	var session := ServiceSession.capture("first_shift", started.selection, sim, 4)
	var restored := ServiceSession.restore(campaign, JSON.parse_string(JSON.stringify(session)), {})
	expect(restored.accepted, "a nondefault priority restores without any applied commands")
	if not restored.accepted:
		return
	while not sim.closed:
		sim.step()
		restored.simulation.step()
	expect(sim.state_hash() == restored.simulation.state_hash(), "resumed future arrivals retain menu priorities to closing")
	for order: Dictionary in restored.simulation.snapshot().orders:
		expect(order.priority == 0, "every resumed future order retains the chosen default")
	var changed_sim := ServiceSim.new(started.definitions, null, started.options)
	changed_sim.step()
	while changed_sim.snapshot().orders.is_empty():
		changed_sim.step()
	var first_id: String = changed_sim.snapshot().orders[0].id
	expect(changed_sim.enqueue_command({"kind": "set_priority", "target_id": first_id, "value": 2,
		"apply_tick": changed_sim.tick + 1, "sequence": 1}).accepted, "an order override remains available")
	changed_sim.step()
	var overridden := ServiceSession.capture("first_shift", started.selection, changed_sim)
	var restored_override := ServiceSession.restore(campaign, overridden, {})
	expect(restored_override.accepted and restored_override.simulation.snapshot().orders[0].priority == 2
		and restored_override.simulation.state_hash() == changed_sim.state_hash(),
		"a per-order override restores independently of the menu default")
	for invalid: Variant in [{}, {"salad": 3}, {"salad": -1}, {"salad": true}, {"salad": 1.5}, {"salad": "2"}, {"salad": 1, "unknown": 2}]:
		var bad := session.duplicate(true)
		bad.preparation.menu_priorities = invalid
		expect(not ServiceSession.restore(campaign, bad, {}).accepted, "stored priorities reject incomplete or invalid menu values: " + str(invalid))
	var forged := session.duplicate(true)
	forged.simulation.orders[0].priority = 1
	expect(not ServiceSession.restore(campaign, forged, {}).accepted, "a priority inconsistent with a command-free menu default is rejected")
	var old_plan := PreparationPlan.new(scenario)
	var old_start := _command(old_plan, "start", "", null)
	var old_sim := ServiceSim.new(old_start.definitions, null, old_start.options)
	old_sim.step()
	var old_session := ServiceSession.capture("first_shift", old_start.selection, old_sim)
	old_session.preparation.erase("menu_priorities")
	var directory := "user://menu_priority_store_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var target := directory + "/records.json"
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 2, "content_version": 3, "sim_version": 1,
		"records": {}, "active_session": old_session}))
	file.close()
	var bytes := FileAccess.get_file_as_bytes(target)
	var store := CampaignStore.new(campaign, target)
	var loaded := store.load_records()
	expect(loaded.accepted and FileAccess.get_file_as_bytes(target) == bytes, "schema 2 loads without rewriting old save bytes")
	if loaded.accepted:
		var old_restored := ServiceSession.restore(campaign, loaded.active_session, {})
		expect(old_restored.accepted and old_restored.simulation.state_hash() == old_sim.state_hash(), "legacy session retains exact simulation state")
	expect(store.save_active_session(session, {}).accepted, "a new menu-default session replaces the valid legacy save")
	var new_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target))
	expect(new_document.schema_version == 3, "new writes use schema 3 for older-app future-version protection")
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(loaded.accepted and ServiceSession.restore(campaign, loaded.active_session, {}).accepted, "a fresh store reads saved menu defaults")
	for owned: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned)
	DirAccess.remove_absolute(directory)


func _test_ui(tree: SceneTree, scenario: Resource, policy: Dictionary) -> void:
	var hashes: Array[String] = []
	for speed: int in [1, 4]:
		var scene: PackedScene = load("res://presentation/main.tscn")
		var screen: Control = scene.instantiate()
		screen.set("scenario_path", scenario.resource_path)
		var settings_path := "user://menu_priorities_ui_%d.json" % Time.get_ticks_usec()
		HarnessSettingsStore.new(settings_path).save_settings({"locale": "ko", "sound_enabled": false, "text_size": "normal"})
		screen.set("settings_path", settings_path)
		tree.root.add_child(screen)
		screen.set_process(false)
		await tree.process_frame
		for choice: Dictionary in policy.preparation:
			if choice.kind != "set_menu_priority":
				expect(screen.call("submit_preparation", choice.kind, choice.target_id, choice.value).accepted, "UI accepts reference preparation")
		var panel: Control = screen.get("preparation_panel")
		var button: Button = panel.get("priority_plus").grill
		await tree.process_frame
		panel.get("pages")[0].ensure_control_visible(button)
		await tree.process_frame
		await tree.process_frame
		expect(panel.get("pages")[0].get_global_rect().encloses(button.get_global_rect()), "the actual menu priority button is inside the scroll viewport")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.global_position = click.position
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.pressed = true
		screen.get_viewport().push_input(click, true)
		await tree.process_frame
		expect(button.is_pressed(), "the actual menu priority button receives pointer-down")
		click = click.duplicate()
		click.pressed = false
		click.button_mask = 0
		screen.get_viewport().push_input(click, true)
		await tree.process_frame
		expect(screen.get("preparation").snapshot().menu_priorities.grill == 2 and button.disabled, "pointer release sets priority two and disables the upper bound")
		expect(panel.get("priority_labels").grill.text.contains("우선순위 2"), "the preparation screen displays the selected priority")
		screen.get("start_button").pressed.emit()
		screen.get("speed_buttons")[0 if speed == 1 else 2].pressed.emit()
		screen.call("advance", 300.0 / speed)
		var view: Dictionary = screen.get("simulation").snapshot()
		expect(view.closed and view.accounting.served >= scenario.minimum_served and view.accounting.profit >= scenario.minimum_profit,
			"actual scene passes without service-time input at speed " + str(speed))
		expect(screen.get("command_sequence") == 0, "menu-default playthrough submits no service-time commands")
		hashes.append(screen.get("simulation").state_hash())
		screen.queue_free()
		await tree.process_frame
		DirAccess.remove_absolute(settings_path)
	expect(hashes[0] == hashes[1], "actual menu-button playthrough matches at 1x and 4x")
