extends "res://tests/capture_m0.gd"

const CampaignScreen := preload("res://presentation/campaign_screen.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")
const StoreTests := preload("res://tests/test_campaign_store.gd")

var locale: String = "ko"
var large_text: bool = false
var layout_name: String = "phone-wide"
var input_pointer_position: Vector2
var has_input_pointer_position: bool = false
var popup_frame_saved: bool = false
var last_application_focus_msec: int = Time.get_ticks_msec()


func _notification(what: int) -> void:
	if what in [MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		last_application_focus_msec = Time.get_ticks_msec()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: M4 capture requires a rendered window")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	locale = "en" if "--locale=en" in args else "ko"
	large_text = "--large-text" in args
	if "--tablet" in args:
		layout_name = "tablet"
		root.size = Vector2i(1024, 768)
	else:
		root.size = Vector2i(1566, 720)
	var directory := "user://capture_m4_%d" % Time.get_ticks_usec()
	checks.expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "M4 render fixture directory is created")
	var screen := _boot(directory + "/campaign.json", directory + "/settings.json")
	await _settle(screen)
	if "--negative-layout" in args:
		screen.settings_button.position.x = screen.size.x + 100
	checks.expect(screen.safe_area.get_global_rect().encloses(screen.settings_button.get_global_rect()),
		"M4 settings target remains in the safe area")
	if checks.failures > 0:
		await _finish(screen, directory)
		return
	await _wait_for_render_focus()
	await _safe_click(screen.settings_button, screen.safe_area.get_global_rect())
	if "--negative-popup-theme" in args:
		screen.settings_locale.get_popup().remove_theme_constant_override("v_separation")
	var sound_toggles: Array[bool] = []
	screen.settings_sound.toggled.connect(func(enabled: bool) -> void: sound_toggles.append(enabled))
	checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
		and sound_toggles.is_empty(),
		"settings start with sound on and no toggle events")
	var requested_locale := 1 if locale == "en" else 0
	await _dialog_choose(screen.settings_locale, 1 - requested_locale, screen.safe_area.get_global_rect())
	if "--negative-popup-theme" in args and checks.failures > 0:
		await _finish(screen, directory)
		return
	checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
		and sound_toggles.is_empty(),
		"opposite locale input does not toggle sound")
	await _dialog_choose(screen.settings_locale, requested_locale, screen.safe_area.get_global_rect())
	checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
		and sound_toggles.is_empty(),
		"requested locale input does not toggle sound")
	var requested_text_size := 1 if large_text else 0
	await _dialog_choose(screen.settings_text_size, 1 - requested_text_size, screen.safe_area.get_global_rect())
	checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
		and sound_toggles.is_empty(),
		"opposite text-size input does not toggle sound")
	await _dialog_choose(screen.settings_text_size, requested_text_size, screen.safe_area.get_global_rect())
	checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
		and sound_toggles.is_empty(),
		"requested text-size input does not toggle sound")
	if large_text:
		popup_frame_saved = false
		await _dialog_choose(screen.settings_locale, requested_locale, screen.safe_area.get_global_rect())
		checks.expect(screen.settings_sound.button_pressed and screen.preferences.snapshot().sound_enabled
			and sound_toggles.is_empty(),
			"large settings popup input does not toggle sound")
	checks.expect(screen.preferences.snapshot().locale == locale
		and screen.preferences.snapshot().text_size == ("large" if large_text else "normal"),
		"settings popup input applies the requested locale and text size")
	var settings_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/settings.json"))
	checks.expect(settings_document.sound_enabled,
		"popup input keeps sound enabled in the settings file")
	await _dialog_click(screen.settings_sound, screen.safe_area.get_global_rect())
	settings_document = JSON.parse_string(FileAccess.get_file_as_string(directory + "/settings.json"))
	checks.expect(not screen.settings_sound.button_pressed
		and not screen.preferences.snapshot().sound_enabled and not settings_document.sound_enabled
		and sound_toggles == [false],
		"settings coordinate input turns sound off once")
	await _dialog_click(screen.settings_sound, screen.safe_area.get_global_rect())
	settings_document = JSON.parse_string(FileAccess.get_file_as_string(directory + "/settings.json"))
	checks.expect(screen.settings_sound.button_pressed
		and screen.preferences.snapshot().sound_enabled and settings_document.sound_enabled
		and sound_toggles == [false, true],
		"settings coordinate input turns sound on once")
	await save_frame("res://build/check/m4-settings.png")
	await _dialog_click(screen.settings_dialog.get_ok_button(), screen.safe_area.get_global_rect())
	checks.expect(not screen.settings_dialog.visible, "settings close input returns to the catalog")
	_check_text(screen.briefing_title, "campaign briefing title")
	await save_frame("res://build/check/m4-catalog.png")
	await _safe_click(screen.begin_button, screen.safe_area.get_global_rect())
	var service = screen.active_service
	checks.expect(service != null, "catalog input opens service preparation")
	if service == null:
		await _finish(screen, directory)
		return
	service.set_process(false)
	await _settle(service)
	await _safe_click(service.start_button, service.safe_area.get_global_rect())
	service.advance(10.05)
	var checkpoint := CampaignStore.new(screen.campaign, screen.save_path).load_records()
	checks.expect(checkpoint.accepted and checkpoint.active_session.simulation.tick == 100,
		"rendered service writes a real tick-100 checkpoint")
	await _safe_click(screen.service_menu_button, service.safe_area.get_global_rect())
	await _dialog_click(screen.leave_dialog.get_ok_button(), screen.safe_area.get_global_rect())
	await process_frame
	checks.expect(screen.active_service == null and screen.continue_button.visible,
		"menu input leaves a distinct saved continue action")
	screen.queue_free()
	await process_frame
	await process_frame
	screen = _boot(directory + "/campaign.json", directory + "/settings.json")
	await _settle(screen)
	await _safe_click(screen.continue_button, screen.safe_area.get_global_rect())
	service = screen.active_service
	checks.expect(service != null and service.state == 2 and service.simulation.tick == 100,
		"a new rendered screen restores the checkpoint paused")
	if service == null:
		await _finish(screen, directory)
		return
	service.set_process(false)
	await _settle(service)
	var failing := StoreTests.FailedStore.new(screen.campaign, screen.save_path)
	failing.failure = "write"
	screen.store = failing
	await _safe_click(service.resume_button, service.safe_area.get_global_rect())
	service.advance(0.1)
	await _safe_click(service.pause_button, service.safe_area.get_global_rect())
	await process_frame
	var expected_error := "another save attempt" if locale == "en" else "다시 시도"
	checks.expect(screen.save_error_dialog.visible and screen.save_error_dialog.dialog_text.contains(expected_error),
		"localized save failure is visible in the rendered trigger state")
	await save_frame("res://build/check/m4-save-error.png")
	failing.failure = ""
	await _dialog_click(screen.retry_checkpoint_button, service.safe_area.get_global_rect())
	checks.expect(not screen.pending_save, "rendered save retry preserves and writes the active service")
	await _safe_click(service.resume_button, service.safe_area.get_global_rect())
	service.advance((3000 - service.simulation.tick) / 10.0)
	await process_frame
	var expected_result := "Served" if locale == "en" else "제공"
	checks.expect(screen.result_dialog.visible and screen.result_dialog.dialog_text.contains(expected_result),
		"localized service result is visible after actual closing")
	_check_text(screen.result_dialog.get_label(), "service result")
	await save_frame("res://build/check/m4-result.png")
	service.audio_feedback.set_enabled(false)
	await create_timer(0.3).timeout
	screen.queue_free()
	await process_frame
	await process_frame
	await _capture_dense_service(directory)
	await _finish(null, directory)


func _boot(save_path: String, settings_path: String) -> CampaignScreen:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen := scene.instantiate() as CampaignScreen
	screen.save_path = save_path
	screen.settings_path = settings_path
	root.add_child(screen)
	screen.set_process(false)
	return screen


func _capture_dense_service(directory: String) -> void:
	var campaign = load("res://content/campaign/campaign.tres")
	var progress := CampaignProgress.new(campaign)
	for index: int in 5:
		var scenario = campaign.scenarios[index]
		var played := Policies.run_policy(scenario, Policies.reference_policy(scenario.id))
		checks.expect(played.accepted, "dense render fixture completes prerequisite service: " + scenario.id)
		if played.accepted:
			checks.expect(progress.record_result(scenario.id, played.snapshot).passed,
				"dense render fixture earns prerequisite service: " + scenario.id)
	var save_path := directory + "/dense-campaign.json"
	checks.expect(CampaignStore.new(campaign, save_path).save_records(progress.snapshot().records).accepted,
		"dense render fixture saves legitimate unlock records")
	var screen := _boot(save_path, directory + "/settings.json")
	await _settle(screen)
	checks.expect(screen.select_scenario("split_duties"), "dense four-employee service is legitimately unlocked")
	await _safe_click(screen.begin_button, screen.safe_area.get_global_rect())
	var service = screen.active_service
	service.set_process(false)
	await _settle(service)
	for command: Dictionary in Policies.reference_policy("split_duties").preparation:
		checks.expect(service.submit_preparation(command.kind, command.target_id, command.value).accepted,
			"dense service accepts its reference preparation")
	await _safe_click(service.start_button, service.safe_area.get_global_rect())
	checks.expect(service.duty_buttons.size() == 4, "dense service renders four employee duty controls")
	for button: OptionButton in service.duty_buttons:
		checks.expect(button.custom_minimum_size.y >= 64.0
			and service.safe_area.get_global_rect().encloses(button.get_global_rect()),
			"dense employee duty control can receive taps inside the safe area")
	await save_frame("res://build/check/m4-four-employees.png")
	service.audio_feedback.set_enabled(false)
	screen.queue_free()
	await process_frame
	await process_frame


func _settle(screen: Control) -> void:
	await process_frame
	await process_frame
	var insets := Vector2i(0, 24) if layout_name == "tablet" else Vector2i(48, 30)
	screen.call("_apply_safe_area", Rect2i(insets.x, 0, int(screen.size.x) - insets.x * 2,
		int(screen.size.y) - insets.y), Transform2D.IDENTITY)
	await process_frame
	await process_frame


func _wait_for_render_focus() -> void:
	root.grab_focus()
	var deadline_msec := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
		if root.has_focus() and Time.get_ticks_msec() - last_application_focus_msec >= 500:
			break
	checks.expect(root.has_focus() and Time.get_ticks_msec() - last_application_focus_msec >= 500,
		"render window holds focus without an application focus event for 500 milliseconds")


func _safe_click(button: Button, allowed: Rect2) -> void:
	var current_allowed := allowed
	for frame_index: int in range(4):
		var live_safe_area := button.find_parent("SafeArea") as Control
		if live_safe_area != null:
			current_allowed = live_safe_area.get_global_rect()
		if (button.is_visible_in_tree() and not button.disabled
			and button.custom_minimum_size.y >= 64.0 and current_allowed.encloses(button.get_global_rect())):
			break
		await process_frame
	if (not button.is_visible_in_tree() or button.disabled or button.custom_minimum_size.y < 64.0
		or not current_allowed.encloses(button.get_global_rect())):
		printerr("SAFE_TARGET visible=%s disabled=%s min_height=%s button=%s allowed=%s" % [
			button.is_visible_in_tree(), button.disabled, button.custom_minimum_size.y,
			button.get_global_rect(), current_allowed])
	checks.expect(button.is_visible_in_tree() and not button.disabled
		and button.custom_minimum_size.y >= 64.0 and current_allowed.encloses(button.get_global_rect()),
		"rendered hit target can receive taps inside the safe area: " + button.text)
	await _viewport_click(button, button.get_global_rect().get_center())


func _dialog_click(button: BaseButton, allowed: Rect2, settle: bool = true) -> void:
	var dialog := button.get_viewport() as Window
	var button_rect := button.get_global_rect()
	button_rect.position += Vector2(dialog.position)
	for frame_index: int in range(4):
		if (button.is_visible_in_tree() and not button.disabled
			and button_rect.size.y >= 64.0 and allowed.encloses(button_rect) and dialog.has_focus()):
			break
		await process_frame
		button_rect = button.get_global_rect()
		button_rect.position += Vector2(dialog.position)
	checks.expect(button.is_visible_in_tree() and not button.disabled and dialog.has_focus()
		and button_rect.size.y >= 64.0 and allowed.encloses(button_rect),
		"rendered dialog target can receive taps inside the safe area: " + button.text)
	await _viewport_click(button, button_rect.get_center(), settle)


func _dialog_choose(picker: OptionButton, index: int, allowed: Rect2) -> void:
	var popup := picker.get_popup()
	var dialog := picker.get_viewport() as Window
	var selected_before := picker.selected
	var pressed_frames: Array[int] = []
	var popup_frames: Array[Dictionary] = []
	var hidden_frames: Array[int] = []
	var on_pressed := func() -> void: pressed_frames.append(Engine.get_process_frames())
	var on_popup := func() -> void:
		popup_frames.append({"frame": Engine.get_process_frames(), "mask": Input.get_mouse_button_mask()})
	var on_hidden := func() -> void: hidden_frames.append(Engine.get_process_frames())
	picker.pressed.connect(on_pressed)
	popup.about_to_popup.connect(on_popup)
	popup.popup_hide.connect(on_hidden)
	await _dialog_click(picker, allowed, false)
	for frame_index: int in range(4):
		if popup.visible:
			break
		await process_frame
	var popup_rect := Rect2(popup.position, popup.size)
	var opening_once := pressed_frames.size() == 1 and popup_frames.size() == 1
	if not popup.visible or not opening_once:
		printerr("POPUP_OPEN selected_before=%d expected=%d pressed=%s about=%s hidden=%s popup=%s allowed=%s" % [
			selected_before, index, pressed_frames, popup_frames, hidden_frames, popup_rect, allowed])
	checks.expect(opening_once, "settings selection popup opens from one picker action")
	checks.expect(popup.visible, "settings selection popup opens after coordinate input")
	checks.expect(allowed.encloses(popup_rect),
		"settings selection popup fits inside the safe area")
	if not popup.visible:
		picker.pressed.disconnect(on_pressed)
		popup.about_to_popup.disconnect(on_popup)
		popup.popup_hide.disconnect(on_hidden)
		return
	await RenderingServer.frame_post_draw
	checks.expect(popup.visible, "settings selection popup remains visible through a rendered frame")
	var item_center_spacing := float(popup.size.y) / popup.item_count
	checks.expect(item_center_spacing >= 64.0,
		"settings popup renders item centers at least 64 pixels apart")
	if not popup_frame_saved:
		var variant := "%s-%s-%s" % [locale, "large" if large_text else "normal", layout_name]
		var frame_result := root.get_texture().get_image().save_png(
			"res://build/check/m4-%s-settings-popup.png" % variant)
		checks.expect(frame_result == OK, "settings selection popup frame is saved")
		popup_frame_saved = true
	if not popup.visible:
		picker.pressed.disconnect(on_pressed)
		popup.about_to_popup.disconnect(on_popup)
		popup.popup_hide.disconnect(on_hidden)
		return
	checks.expect(not popup.get_item_text(index).is_empty(),
		"settings selection popup shows the requested choice")
	var local_point := Vector2(popup.position) + Vector2(
		popup.size.x * 0.5, popup.size.y * (index + 0.5) / popup.item_count)
	_move_pointer(local_point)
	checks.expect(popup.get_focused_item() == index,
		"settings popup pointer reaches item %d" % index)
	await _press_release(local_point)
	for frame_index: int in range(4):
		if picker.selected == index:
			break
		await process_frame
	checks.expect(picker.selected == index, "settings popup input selects item %d" % index)
	for frame_index: int in range(4):
		if not popup.visible and dialog.has_focus():
			break
		await process_frame
	checks.expect(not popup.visible and dialog.has_focus(),
		"settings popup closes and returns input focus")
	checks.expect(hidden_frames.size() == 1,
		"settings selection closes one popup")
	picker.pressed.disconnect(on_pressed)
	popup.about_to_popup.disconnect(on_popup)
	popup.popup_hide.disconnect(on_hidden)


func _viewport_click(button: BaseButton, point: Vector2, settle: bool = true) -> void:
	if "--negative-input" in OS.get_cmdline_user_args():
		point = Vector2(-100, -100)
	_move_pointer(point)
	var hovered := button.get_viewport().gui_get_hovered_control()
	checks.expect(hovered == button or (hovered != null and button.is_ancestor_of(hovered)),
		"viewport input reaches the rendered target: " + button.text)
	if checks.failures > 0:
		quit(1)
		await process_frame
		return
	await _press_release(point, settle)


func _move_pointer(point: Vector2) -> void:
	var screen_point := root.get_screen_transform() * point
	if has_input_pointer_position and input_pointer_position.is_equal_approx(screen_point):
		_parse_motion(screen_point + Vector2(-1.0, 0.0))
	_parse_motion(screen_point)


func _parse_motion(screen_point: Vector2) -> void:
	var previous := input_pointer_position if has_input_pointer_position else screen_point - Vector2.ONE
	var relative := screen_point - previous
	var motion := InputEventMouseMotion.new()
	motion.position = screen_point
	motion.global_position = screen_point
	motion.relative = relative
	motion.velocity = relative * 60.0
	motion.window_id = root.get_window_id()
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	input_pointer_position = screen_point
	has_input_pointer_position = true


func _press_release(point: Vector2, settle: bool = true) -> void:
	var screen_point := root.get_screen_transform() * point
	for pressed: bool in [true, false]:
		var event := _mouse_event(screen_point, pressed) as InputEventMouseButton
		event.global_position = screen_point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.window_id = root.get_window_id()
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	if settle:
		await process_frame


func _check_text(label: Label, description: String) -> void:
	checks.expect(label != null and label.is_visible_in_tree()
		and label.get_visible_line_count() >= label.get_line_count(),
		"critical rendered text is fully visible: " + description)


func save_frame(file_path: String) -> void:
	var variant := "%s-%s-%s" % [locale, "large" if large_text else "normal", layout_name]
	file_path = file_path.replace("m4-", "m4-%s-" % variant)
	await super.save_frame(file_path)


func _finish(screen: Control, directory: String) -> void:
	if screen != null:
		screen.queue_free()
		await process_frame
	TranslationServer.set_locale("ko")
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
	print("M4 rendered input checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(1 if checks.failures > 0 else 0)
