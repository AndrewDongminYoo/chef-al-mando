extends "res://tests/harness.gd"

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const StoreTests := preload("res://tests/test_campaign_store.gd")


func run(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	expect(entry == "res://presentation/campaign.tscn", "the project boots the campaign scene")
	if entry != "res://presentation/campaign.tscn":
		return
	var directory := "user://test_campaign_ui_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "campaign UI fixture directory is created")
	var file_path := directory + "/records.json"
	await _save_failure_navigation(tree, entry, directory + "/failed.json")
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.get("scenario_buttons").size() == 8, "the real scene displays all eight services")
	expect(screen.get("scenario_buttons").lunch_prep.disabled, "a locked service button is disabled")
	expect(not screen.call("select_scenario", "lunch_prep"), "the scene rejects direct selection of a locked service")
	expect(screen.call("select_scenario", "first_shift"), "the first service can be selected")
	expect(screen.get("briefing_label").text.contains("채소 샐러드"), "briefing shows the actual first menu")
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	expect(service.get("definitions").id == "first_shift", "the campaign supplies its selected definition to the existing service")
	expect(service.get("simulation").tick == 0, "selection starts in preparation without advancing service")
	service.get("start_button").pressed.emit()
	service.call("advance", 2.0)
	screen.call("request_menu")
	expect(not service.call("is_running") and screen.get("leave_dialog").visible, "leaving a running service pauses it and asks before discard")
	screen.get("leave_dialog").canceled.emit()
	screen.get("leave_dialog").hide()
	expect(not service.call("is_running"), "cancelling exit does not resume the service")
	service.get("resume_button").pressed.emit()
	service.call("advance", 298.0)
	expect(screen.get("last_result").passed and screen.get("result_dialog").visible, "actual closing displays a passing result")
	expect(not screen.get("pending_save") and FileAccess.file_exists(file_path), "closing writes the campaign result")
	var closed: Dictionary = service.get("simulation").snapshot()
	var bytes := FileAccess.get_file_as_bytes(file_path)
	service.emit_signal("service_closed", closed)
	expect(FileAccess.get_file_as_bytes(file_path) == bytes, "a duplicate closing signal does not change the saved record")
	screen.get("retry_service_button").pressed.emit()
	expect(service.get("simulation").tick == 0 and service.get("state") == 0, "retry returns the current service to preparation")
	expect(service.get("definitions").starting_budget == screen.get("campaign").scenarios[0].starting_budget, "retry restores the scenario budget")
	service.call("submit_preparation", "set_duty", "employee_01", "off")
	service.call("submit_preparation", "set_duty", "employee_02", "off")
	service.get("start_button").pressed.emit()
	service.call("advance", 300.0)
	expect(not screen.get("last_result").passed and screen.get("next_button").disabled, "a real failed retry does not offer next service")
	expect(screen.get("progress").snapshot().records.first_shift.completed, "the failed retry preserves the earlier completion")
	screen.call("return_to_menu")
	await tree.process_frame
	expect(not screen.get("scenario_buttons").lunch_prep.disabled, "the previously unlocked service remains available after failure")
	screen.queue_free()
	await tree.process_frame
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(not screen.get("scenario_buttons").lunch_prep.disabled, "restarting the actual scene reloads its saved unlock")
	var campaign: Resource = screen.get("campaign")
	for index: int in range(1, campaign.scenarios.size()):
		var scenario: Resource = campaign.scenarios[index]
		if index == 1:
			expect(screen.call("select_scenario", scenario.id), "the next service is selectable after reopening")
			screen.get("begin_button").pressed.emit()
		service = screen.get("active_service")
		service.set_process(false)
		await tree.process_frame
		expect(service.get("definitions").id == scenario.id, "next-service input loads the correct scenario")
		var policy := Policies.reference_policy(scenario.id)
		for command: Dictionary in policy.preparation:
			var changed: Dictionary = service.call("submit_preparation", command.kind, command.target_id, command.value)
			expect(changed.accepted, "campaign UI accepts the real reference preparation command")
		service.get("start_button").pressed.emit()
		if scenario.id == "hot_queue":
			expect(service.get("summary_label").text.contains("주문 0 / 20건"), "the running summary distinguishes arrived orders from the full schedule")
		for arrival: Dictionary in scenario.order_schedule():
			service.call("advance", (arrival.arrival_tick - service.get("simulation").tick) / (10.0 * service.get("driver").speed))
			if scenario.id == "hot_queue" and arrival.id == "order_01":
				expect(service.get("summary_label").text.contains("주문 1 / 20건"), "the running summary counts actual arrivals before any order is served")
			if policy.priorities.has(arrival.recipe_id):
				if scenario.id == "hot_queue":
					await _tap_hot_queue_priority(tree, service, arrival.id)
				else:
					var changed: Dictionary = service.call("submit_command", "set_priority", arrival.id, policy.priorities[arrival.recipe_id])
					expect(changed.accepted, "campaign UI submits priority through the normal command path")
		if scenario.id == "hot_queue":
			var view: Dictionary = service.get("simulation").snapshot()
			expect(view.orders.size() == 20 and view.accounting.expired > 0 and not view.closed, "the hot-queue fixture includes all arrivals and real expired orders before closing")
			var counts: Array = [view.orders.size(), scenario.order_count, view.accounting.served, view.accounting.expired, view.accounting.cancelled]
			expect(service.get("summary_label").text.contains("주문 %d / %d건 · 제공 %d · 미제공 %d · 취소 %d" % counts), "the Korean running summary separates arrivals, served orders, expirations, and cancellations")
			var before_locale: String = service.get("simulation").state_hash()
			screen.get("settings_locale").item_selected.emit(1)
			expect(service.get("summary_label").text.contains("Orders %d / %d · served %d · unserved %d · cancelled %d" % counts), "the English running summary shows the same measured order counts")
			screen.get("settings_locale").item_selected.emit(0)
			expect(service.get("simulation").state_hash() == before_locale, "order summary locale changes preserve the simulation state")
		service.call("advance", (3000 - service.get("simulation").tick) / 10.0)
		expect(screen.get("last_result").passed, "the actual scene passes its service goals: " + scenario.id)
		if scenario.id == "hot_queue":
			print("HOT_QUEUE_BUTTON_RESULT ", JSON.stringify(service.get("simulation").snapshot().accounting))
		expect(screen.get("result_dialog").dialog_text.contains("제공") and screen.get("result_dialog").dialog_text.contains("손익"), "result text shows both measured target values")
		if index == 1 or index == campaign.scenarios.size() - 1:
			var final_service: bool = index == campaign.scenarios.size() - 1
			var korean_action := "엔딩 보기" if final_service else "다음 영업"
			var english_action := "View ending" if final_service else "Next service"
			var result_hash: String = service.get("simulation").state_hash()
			expect(screen.get("result_dialog").visible and not screen.get("next_button").disabled
				and screen.get("next_button").text == korean_action, "the passing result shows its enabled Korean action: " + scenario.id)
			screen.get("settings_locale").item_selected.emit(1)
			expect(screen.get("next_button").text == english_action, "the result locale refresh preserves its English action: " + scenario.id)
			screen.get("settings_locale").item_selected.emit(0)
			expect(screen.get("next_button").text == korean_action, "the result locale refresh restores its Korean action: " + scenario.id)
			expect(screen.get("result_dialog").visible and not screen.get("next_button").disabled
				and service.get("simulation").state_hash() == result_hash, "result locale changes preserve dialog visibility, action availability, and simulation state: " + scenario.id)
		if index == 5:
			expect(service.get("duty_buttons").size() == 4, "the service creates four employee controls")
		screen.get("next_button").pressed.emit()
		await tree.process_frame
	expect(screen.get("ending_panel").visible and screen.get("active_service") == null, "the final next action displays the ending and leaves service")
	screen.queue_free()
	await tree.process_frame
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.get("ending_button").visible, "a new scene can replay the saved ending")
	screen.queue_free()
	await tree.process_frame
	var future: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	future.schema_version = 99
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(future))
	file.close()
	bytes = FileAccess.get_file_as_bytes(file_path)
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.get("begin_button").disabled and not screen.get("recover_button").visible, "future records block normal start and unsafe recovery")
	screen.get("session_only_button").pressed.emit()
	expect(not screen.get("begin_button").disabled and screen.get("save_label").text.contains("저장 없이"), "explicit session-only play explains that results will not be saved")
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	service.get("start_button").pressed.emit()
	service.call("advance", 300.0)
	expect(FileAccess.get_file_as_bytes(file_path) == bytes, "session-only completion preserves the future record bytes")
	screen.queue_free()
	await tree.process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)


func _tap_hot_queue_priority(tree: SceneTree, service: Control, order_id: String) -> void:
	var row: Button = service.get("order_buttons")[order_id]
	var scroll := row.get_parent().get_parent() as ScrollContainer
	await tree.process_frame
	await tree.process_frame
	scroll.ensure_control_visible(row)
	await tree.process_frame
	await tree.process_frame
	expect(scroll.get_global_rect().encloses(row.get_global_rect()), "the input fixture exposes the actual order row in its scroll viewport")
	var sequence_before: int = service.get("command_sequence")
	for button: Button in [row, service.get("priority_up_button")]:
		var point := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		tree.root.push_input(motion, true)
		var press := InputEventMouseButton.new()
		press.position = point
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.pressed = true
		tree.root.push_input(press, true)
		expect(button.is_pressed(), "the playthrough holds the actual order or priority button")
		var before_tick: int = service.get("simulation").tick
		service.call("advance", 0.2)
		expect(service.get("simulation").tick == before_tick + 2 * service.get("driver").speed
			and button.is_pressed(), "the held pointer survives the real service ticks at the selected speed")
		var release := InputEventMouseButton.new()
		release.position = point
		release.button_index = MOUSE_BUTTON_LEFT
		tree.root.push_input(release, true)
		expect(not button.is_pressed(), "each playthrough pointer returns to its released state")
		expect(service.get("selected_order_id") == order_id, "the actual row tap selects the requested grill order")
	expect(service.get("command_sequence") == sequence_before + 1, "one actual priority tap produces exactly one command")
	expect(service.get("detail_label").text.contains("우선순위 2") and row.text.contains("우선 2"), "the actual priority tap displays its queued value immediately")
	service.call("advance", 0.1 / service.get("driver").speed)
	for order: Dictionary in service.get("simulation").snapshot().orders:
		if order.id == order_id:
			expect(order.priority == 2, "the priority selected through actual buttons is applied on the next tick")


func _save_failure_navigation(tree: SceneTree, entry: String, file_path: String) -> void:
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	var store := StoreTests.FailedStore.new(screen.get("campaign"), file_path)
	screen.set("store", store)
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	service.get("start_button").pressed.emit()
	store.failure = "write"
	service.call("advance", 300.0)
	expect(screen.get("last_result").passed and screen.get("pending_save"), "a real passing service reaches the failed save path")
	expect(screen.get("next_button").disabled and screen.get("retry_service_button").disabled and service.get("restart_button").disabled, "pending saves disable next service and both restart controls")
	for action: String in ["next", "retry", "menu", "direct_menu"]:
		if action == "menu":
			screen.call("request_menu")
		elif action == "direct_menu":
			screen.call("return_to_menu")
		else:
			screen.call("_result_action", action)
		expect(screen.get("active_service") == service and service.get("simulation").tick == 3000, "pending save preserves the closed service after navigation: " + action)
		expect(not screen.get("last_result").is_empty() and screen.get("result_dialog").visible and screen.get("retry_save_button").visible, "pending save keeps the result and retry action available: " + action)
	screen.get("retry_save_button").pressed.emit()
	expect(screen.get("pending_save") and screen.get("next_button").disabled, "another save failure keeps navigation blocked")
	store.failure = ""
	screen.get("retry_save_button").pressed.emit()
	expect(not screen.get("pending_save") and not screen.get("next_button").disabled and not screen.get("retry_service_button").disabled and not service.get("restart_button").disabled, "successful save retry restores navigation")
	var reopened := StoreTests.CampaignStore.new(screen.get("campaign"), file_path)
	expect(reopened.load_records().records == screen.get("progress").snapshot().records, "a new store reads the retried completion from disk")
	screen.get("next_button").pressed.emit()
	var next_service: Control = screen.get("active_service")
	expect(next_service != null and next_service != service and next_service.get("definitions").id == "lunch_prep", "next service opens after the save succeeds")
	screen.queue_free()
	await tree.process_frame


func _boot(tree: SceneTree, scene_path: String, file_path: String) -> Control:
	var scene: PackedScene = load(scene_path)
	var screen: Control = scene.instantiate()
	screen.set("save_path", file_path)
	var settings_path := file_path + ".settings.json"
	var settings := {"locale": "ko", "sound_enabled": false, "text_size": "normal"}
	if not HarnessSettingsStore.new(settings_path).save_settings(settings).accepted:
		return null
	screen.set("settings_path", settings_path)
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(settings_path))
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen
