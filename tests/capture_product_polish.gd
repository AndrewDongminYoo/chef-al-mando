extends SceneTree

const Harness := preload("res://tests/harness.gd")
const CampaignScreen := preload("res://presentation/campaign_screen.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")
var checks := Harness.new()
var variant: String


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: product capture requires a rendered window")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://build/check/polish")
	for tablet: bool in [false, true]:
		for locale: String in ["ko", "en"]:
			for text_size: String in ["normal", "large"]:
				variant = "%s-%s-%s" % ["tablet" if tablet else "phone", locale, text_size]
				root.size = Vector2i(1024, 768) if tablet else Vector2i(1566, 720)
				await _capture(tablet, locale, text_size)
				if checks.failures > 0:
					quit(1)
					return
	print("PASS: product rendered layouts checks=%d failures=0" % checks.checked)
	quit(0)


func _capture(tablet: bool, locale: String, text_size: String) -> void:
	var directory := "user://product_capture_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	checks.expect(Harness.HarnessSettingsStore.new(directory + "/settings.json").save_settings(
		{"locale": locale, "sound_enabled": false, "text_size": text_size}).accepted, "capture settings are saved")
	var screen := load("res://presentation/campaign.tscn").instantiate() as CampaignScreen
	screen.save_path = directory + "/records.json"
	screen.settings_path = directory + "/settings.json"
	root.add_child(screen)
	await _settle(screen, tablet)
	if "--negative-layout" in OS.get_cmdline_user_args():
		screen.begin_button.position.x += screen.size.x
	_check_target(screen.begin_button, screen.safe_area.get_global_rect())
	_check_text(screen.briefing_title)
	await _frame("catalog")
	screen.settings_button.pressed.emit()
	await _settle(screen, tablet)
	checks.expect(screen.settings_dialog.visible, "settings fixture opens the actual dialog")
	_check_dialog(screen.settings_dialog, screen.safe_area.get_global_rect())
	await _frame("settings")
	screen.settings_dialog.hide()
	checks.expect(screen.begin_service(), "catalog opens service preparation")
	var service := screen.active_service
	service.set_process(false)
	await _settle(service, tablet)
	_check_target(service.start_button, service.safe_area.get_global_rect())
	for tab: Button in service.preparation_panel.tabs:
		_check_target(tab, service.safe_area.get_global_rect())
	await _frame("preparation")
	service.preparation_panel.pages[0].ensure_control_visible(service.preparation_panel.priority_heading)
	await _settle(service, tablet)
	await _frame("priorities")
	service.preparation_panel.show_tab(1)
	await _settle(service, tablet)
	await _frame("placement")
	service.settings_button.pressed.emit()
	await _settle(service, tablet)
	_check_dialog(service.settings_dialog, service.safe_area.get_global_rect())
	await _frame("service-settings")
	service.settings_dialog.hide()
	service.start_button.pressed.emit()
	checks.expect(service.is_running(), "service fixture starts the real simulation")
	service.advance(1.0)
	await _settle(service, tablet)
	checks.expect(not service.order_buttons.is_empty(), "service fixture contains actual orders")
	if service.details_toggle.visible:
		var expected_toggle := "주문 상세 접기" if service.detail_panel.visible else "주문 상세 펼치기"
		checks.expect(service.details_toggle.text == TranslationServer.translate(expected_toggle),
			"order detail action describes the current panel visibility")
		if not service.detail_panel.visible:
			service.details_toggle.pressed.emit()
			await _settle(service, tablet)
			checks.expect(service.detail_panel.visible,
				"the compact detail action opens the selected order before the cancel-state capture")
	_check_target(service.pause_button, service.safe_area.get_global_rect())
	await _frame("service")
	await _capture_cancel_states(service)
	service.pause_button.pressed.emit()
	await _settle(service, tablet)
	checks.expect(not service.is_running(), "paused fixture stops the service")
	_check_target(service.resume_button, service.safe_area.get_global_rect())
	await _frame("paused")
	service.resume_button.pressed.emit()
	service.advance((3000 - service.simulation.tick) / 10.0)
	await _settle(service, tablet)
	checks.expect(screen.result_dialog.visible and service.simulation.snapshot().closed,
		"result fixture closes a real service")
	_check_text(screen.result_dialog.get_label())
	await _frame("result")
	screen.result_dialog.hide()
	await _settle(service, tablet)
	await _frame("analysis")
	checks.expect(service.analysis_label.text.begins_with(service.summary_label.text),
		"analysis keeps the accounting summary visible when the order panel is hidden")
	if text_size == "large":
		await _capture_completed_campaign(screen, tablet)
	screen.queue_free()
	await process_frame
	await process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)


func _capture_completed_campaign(screen: CampaignScreen, tablet: bool) -> void:
	for scenario: Resource in screen.campaign.scenarios:
		var played := Policies.run_policy(scenario, Policies.reference_policy(scenario.id))
		checks.expect(played.accepted and screen.progress.record_result(scenario.id, played.snapshot).passed,
			"completed catalog fixture earns its record: " + scenario.id)
	checks.expect(screen.store.save_records(screen.progress.snapshot().records).accepted,
		"completed catalog fixture saves real campaign records")
	screen.return_to_menu()
	await _settle(screen, tablet)
	checks.expect(screen.ending_button.visible and screen.continue_button.visible,
		"completed catalog fixture exposes both saved-service and ending actions")
	for button: Button in [screen.settings_button, screen.ending_button, screen.continue_button]:
		_check_target(button, screen.safe_area.get_global_rect())
	await _frame("completed-catalog")
	screen.ending_button.pressed.emit()
	await _settle(screen, tablet)
	_check_text(screen.ending_title)
	_check_text(screen.ending_copy)
	_check_target(screen.ending_return_button, screen.safe_area.get_global_rect())
	await _frame("ending")
	screen.ending_return_button.pressed.emit()
	checks.expect(screen.select_scenario("split_duties") and screen.begin_service(), "dense fixture opens the four-employee service")
	var service := screen.active_service
	service.set_process(false)
	for command: Dictionary in Policies.reference_policy("split_duties").preparation:
		checks.expect(service.submit_preparation(command.kind, command.target_id, command.value).accepted,
			"dense fixture accepts reference preparation")
	service.start_button.pressed.emit()
	service.advance(1.0)
	await _settle(service, tablet)
	checks.expect(service.duty_buttons.size() == 4 and service.board.size.y > 0, "dense fixture renders staff and the kitchen")
	for button: OptionButton in service.duty_buttons:
		_check_target(button, service.safe_area.get_global_rect())
	await _frame("four-employees")


func _settle(screen: Control, tablet: bool) -> void:
	for frame_index: int in 4:
		await process_frame
	var inset := Vector2i(0, 24) if tablet else Vector2i(48, 30)
	screen.call("_apply_safe_area", Rect2i(inset.x, 0, int(screen.size.x) - inset.x * 2,
		int(screen.size.y) - inset.y), Transform2D.IDENTITY)
	for frame_index: int in 4:
		await process_frame


func _capture_cancel_states(service: Control) -> void:
	var button: Button = service.get("cancel_button")
	checks.expect(not button.disabled and button.is_visible_in_tree(), "cancel fixture has an active order")
	if "--negative-cancel" in OS.get_cmdline_user_args():
		button.theme_type_variation = &"Button"
	var before: String = service.get("simulation").state_hash()
	var center := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion, true)
	checks.expect(root.gui_get_hovered_control() == button, "cancel hover reaches the actual control")
	await _frame("cancel-hover")
	_check_cancel_color(button)
	var press := InputEventMouseButton.new()
	press.position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	checks.expect(button.get_draw_mode() == BaseButton.DRAW_PRESSED, "cancel fixture renders the pressed state")
	await _frame("cancel-pressed")
	_check_cancel_color(button)
	motion.position = Vector2(-100, -100)
	root.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.position = motion.position
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)
	checks.expect(service.get("simulation").state_hash() == before, "cancel state capture does not submit an order command")


func _check_cancel_color(button: Button) -> void:
	var frame := root.get_texture().get_image()
	var point := (button.get_global_rect().position + Vector2(20, 10)) * Vector2(frame.get_size()) / root.get_visible_rect().size
	var pixel := frame.get_pixelv(Vector2i(point))
	checks.expect(pixel.r > pixel.g + 0.06 and pixel.r > pixel.b + 0.06,
		"rendered cancel interaction retains its warm warning color")


func _check_target(button: Button, allowed: Rect2) -> void:
	checks.expect(button.is_visible_in_tree() and button.size.x >= 64 and button.size.y >= 64
		and allowed.encloses(button.get_global_rect()), "product target fits inside the safe area: " + button.text)


func _check_text(label: Label) -> void:
	checks.expect(label.is_visible_in_tree() and label.get_visible_line_count() >= label.get_line_count(),
		"product critical text is fully visible: " + label.text)


func _check_dialog(dialog: AcceptDialog, allowed: Rect2) -> void:
	var close_rect := dialog.get_ok_button().get_global_rect()
	close_rect.position += Vector2(dialog.position)
	checks.expect(dialog.visible and allowed.encloses(Rect2(dialog.position, dialog.size))
		and allowed.encloses(close_rect) and close_rect.size.y >= 64,
		"product dialog and close target fit inside the safe area")


func _frame(state: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var frame := root.get_texture().get_image()
	checks.expect(not frame.is_empty() and frame.save_png("res://build/check/polish/%s-%s.png" % [variant, state]) == OK,
		"product frame is saved: " + state)
