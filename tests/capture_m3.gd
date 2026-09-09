extends "res://tests/capture_m0.gd"

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const CampaignScreen := preload("res://presentation/campaign_screen.gd")
const StoreTests := preload("res://tests/test_campaign_store.gd")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: M3 capture requires a rendered window")
		quit(1)
		return
	if "--tablet" in OS.get_cmdline_user_args():
		root.size = Vector2i(1024, 768)
	elif "--phone-wide" in OS.get_cmdline_user_args():
		root.size = Vector2i(1566, 720)
	var directory := "user://capture_m3_%d" % Time.get_ticks_usec()
	checks.expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "rendered record fixture directory is created")
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen := scene.instantiate() as CampaignScreen
	screen.save_path = directory + "/records.json"
	screen.settings_path = directory + "/settings.json"
	root.add_child(screen)
	screen.set_process(false)
	await _settle(screen)
	if "--negative-layout" in OS.get_cmdline_user_args():
		screen.begin_button.position.x = screen.size.x + 100
	checks.expect(screen.safe_area.get_global_rect().encloses(screen.begin_button.get_global_rect()), "M3 rendered start must remain in the safe area")
	if checks.failures > 0:
		await _finish(screen, directory)
		return
	await save_frame("res://build/check/m3-catalog.png")
	await _safe_click(screen.scenario_buttons.first_shift, screen.safe_area.get_global_rect())
	await _safe_click(screen.begin_button, screen.safe_area.get_global_rect())
	checks.expect(screen.active_service != null and screen.active_service.definitions.id == "first_shift", "rendered catalog input starts the selected service preparation")
	if screen.active_service == null:
		await _finish(screen, directory)
		return
	for index: int in screen.campaign.scenarios.size():
		var scenario := screen.campaign.scenarios[index]
		var service := screen.active_service
		if service == null or service.definitions.id != scenario.id:
			checks.expect(false, "rendered next opens the expected service: " + scenario.id)
			await _finish(screen, directory)
			return
		service.set_process(false)
		await _settle(service)
		if index == 0:
			await save_frame("res://build/check/m3-first-preparation.png")
		if index == 6:
			var panel := service.preparation_panel
			panel.pages[0].ensure_control_visible(panel.prep_plus.protein_bowl)
			await process_frame
			await process_frame
			await _safe_click(panel.prep_plus.protein_bowl, service.safe_area.get_global_rect())
			checks.expect(service.preparation.snapshot().prep_quantities.protein_bowl == 1, "the eighth-menu preparation row accepts an actual coordinate tap")
			await save_frame("res://build/check/m3-eight-menu-preparation.png")
		var policy := Policies.reference_policy(scenario.id)
		for command: Dictionary in policy.preparation:
			var result := service.submit_preparation(command.kind, command.target_id, command.value)
			checks.expect(result.accepted, "rendered fixture uses a valid preparation command")
		await _safe_click(service.start_button, service.safe_area.get_global_rect())
		checks.expect(service.is_running(), "rendered start begins the actual service: " + scenario.id)
		if not service.is_running():
			await _finish(screen, directory)
			return
		for arrival: Dictionary in scenario.order_schedule():
			service.advance((arrival.arrival_tick - service.simulation.tick) / 10.0)
			if policy.priorities.has(arrival.recipe_id):
				checks.expect(service.submit_command("set_priority", arrival.id, policy.priorities[arrival.recipe_id]).accepted, "rendered fixture submits a real service priority command")
		if index == 5:
			await _safe_click(service.pause_button, service.safe_area.get_global_rect())
			checks.expect(service.duty_buttons.size() == 4, "rendered service has four employee controls")
			for button: OptionButton in service.duty_buttons:
				checks.expect(service.safe_area.get_global_rect().encloses(button.get_global_rect()), "each employee control fits inside the safe area")
			await save_frame("res://build/check/m3-four-employees.png")
			await _safe_click(service.resume_button, service.safe_area.get_global_rect())
			checks.expect(service.is_running(), "rendered resume must continue the paused service")
			if not service.is_running():
				await _finish(screen, directory)
				return
		var failed_store: StoreTests.FailedStore
		if index == 0 or index == 7:
			failed_store = StoreTests.FailedStore.new(screen.campaign, screen.save_path)
			failed_store.failure = "write"
			screen.store = failed_store
		service.advance((3000 - service.simulation.tick) / 10.0)
		await process_frame
		await process_frame
		checks.expect(screen.last_result.get("passed", false) and screen.result_dialog.visible, "rendered closing passes its actual campaign targets: " + scenario.id)
		if failed_store != null:
			checks.expect(screen.pending_save and screen.retry_save_button.visible, "rendered closing reaches a real save failure")
			await save_frame("res://build/check/m3-save-failure-%d.png" % index)
			for button: Button in [screen.next_button, screen.retry_service_button]:
				checks.expect(button.disabled, "unsaved completion disables the result navigation button: " + button.text)
				var dialog := button.get_viewport() as Window
				await _viewport_click(button, Vector2(dialog.position) + button.get_global_rect().get_center())
				checks.expect(screen.active_service == service and screen.last_result.get("passed", false), "a coordinate tap cannot discard the unsaved completion")
			await _dialog_click(screen.result_dialog.get_ok_button(), screen.safe_area.get_global_rect())
			checks.expect(service.restart_button.disabled, "unsaved completion disables the analysis restart button")
			await _viewport_click(service.restart_button, service.restart_button.get_global_rect().get_center())
			checks.expect(service.simulation.tick == 3000, "a coordinate tap cannot restart the unsaved service")
			await _safe_click(screen.service_menu_button, service.safe_area.get_global_rect())
			checks.expect(screen.active_service == service and screen.result_dialog.visible, "menu input restores the pending save dialog")
			await _dialog_click(screen.retry_save_button, service.safe_area.get_global_rect())
			checks.expect(screen.pending_save and screen.next_button.disabled, "another rendered save failure preserves the navigation gate")
			failed_store.failure = ""
			await _dialog_click(screen.retry_save_button, service.safe_area.get_global_rect())
			checks.expect(not screen.pending_save and not service.restart_button.disabled, "a successful rendered save retry restores navigation")
			var reopened := StoreTests.CampaignStore.new(screen.campaign, screen.save_path)
			checks.expect(reopened.load_records().records == screen.progress.snapshot().records, "a new store reads the rendered retry result from disk")
		if index == 0:
			await save_frame("res://build/check/m3-first-result.png")
			await _dialog_click(screen.result_dialog.get_ok_button(), screen.safe_area.get_global_rect())
			checks.expect(not screen.result_dialog.visible and service.analysis_scroll.visible, "rendered analysis input returns to the closing explanation")
			await save_frame("res://build/check/m3-first-analysis.png")
			await _safe_click(screen.service_goal_button, service.safe_area.get_global_rect())
		if index == 7:
			await save_frame("res://build/check/m3-final-result.png")
		await _dialog_click(screen.next_button, service.safe_area.get_global_rect())
		await process_frame
	checks.expect(screen.ending_panel.visible and screen.progress.snapshot().ending_unlocked, "rendered next input reaches the earned ending")
	await save_frame("res://build/check/m3-ending.png")
	var return_button := screen.ending_panel.get_child(screen.ending_panel.get_child_count() - 1) as Button
	await _safe_click(return_button, screen.safe_area.get_global_rect())
	screen.list_scroll.ensure_control_visible(screen.scenario_buttons.final_service)
	await process_frame
	await process_frame
	await _safe_click(screen.scenario_buttons.final_service, screen.safe_area.get_global_rect())
	checks.expect(screen.briefing_label.text.contains("개별 최고 기록"), "rendered completed service shows the saved best results")
	await save_frame("res://build/check/m3-completed-catalog.png")
	await _finish(screen, directory)


func _settle(screen: Control) -> void:
	await process_frame
	await process_frame
	var insets := Vector2i(0, 24) if "--tablet" in OS.get_cmdline_user_args() else Vector2i(48, 30)
	screen.call("_apply_safe_area", Rect2i(insets.x, 0, int(screen.size.x) - insets.x * 2, int(screen.size.y) - insets.y), Transform2D.IDENTITY)
	await process_frame
	await process_frame


func _safe_click(button: Button, allowed: Rect2) -> void:
	await process_frame
	checks.expect(button.is_visible_in_tree() and not button.disabled and allowed.encloses(button.get_global_rect()), "M3 rendered hit target must fit in the safe area: " + button.text)
	await _viewport_click(button, button.get_global_rect().get_center())


func _dialog_click(button: Button, allowed: Rect2) -> void:
	await process_frame
	var dialog := button.get_viewport() as Window
	var button_rect := button.get_global_rect()
	button_rect.position += Vector2(dialog.position)
	checks.expect(button.is_visible_in_tree() and not button.disabled and allowed.encloses(button_rect), "M3 dialog hit target must fit in the safe area: " + button.text)
	await _viewport_click(button, button_rect.get_center())


func _viewport_click(button: Button, point: Vector2) -> void:
	if "--negative-input" in OS.get_cmdline_user_args():
		point = Vector2(-100, -100)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var hovered := button.get_viewport().gui_get_hovered_control()
	checks.expect(hovered == button or (hovered != null and button.is_ancestor_of(hovered)), "viewport input must reach the rendered button: " + button.text)
	if checks.failures > 0:
		quit(1)
		await process_frame
		return
	for pressed: bool in [true, false]:
		var event := _mouse_event(point, pressed) as InputEventMouseButton
		event.global_position = point
		root.push_input(event, true)
	await process_frame


func save_frame(file_path: String) -> void:
	if "--tablet" in OS.get_cmdline_user_args():
		file_path = file_path.replace("m3-", "m3-tablet-")
	elif "--phone-wide" in OS.get_cmdline_user_args():
		file_path = file_path.replace("m3-", "m3-phone-wide-")
	await super.save_frame(file_path)


func _finish(screen: Control, directory: String) -> void:
	screen.queue_free()
	await process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
	print("M3 rendered input checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(1 if checks.failures > 0 else 0)
