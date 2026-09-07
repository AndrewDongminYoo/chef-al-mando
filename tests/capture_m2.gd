extends "res://tests/capture_m0.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: M2 capture requires a rendered window")
		quit(1)
		return
	if "--tablet" in OS.get_cmdline_user_args():
		root.size = Vector2i(1024, 768)
	elif "--phone-wide" in OS.get_cmdline_user_args():
		root.size = Vector2i(1566, 720)
	var screen := Harness.boot_main(self, "res://content/m2_first_service.tres") as KitchenScreen
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/check")
	var insets := Vector2i(48, 30) if "--tablet" not in OS.get_cmdline_user_args() else Vector2i(0, 24)
	screen.call("_apply_safe_area", Rect2i(insets.x, 0, int(screen.size.x) - insets.x * 2, int(screen.size.y) - insets.y), Transform2D.IDENTITY)
	await process_frame
	await process_frame
	await save_frame("res://build/check/m2-ready.png")
	var panel := screen.preparation_panel
	panel.pages[0].ensure_control_visible(panel.prep_plus.grill)
	await process_frame
	await process_frame
	await _safe_click(screen, panel.prep_plus.grill)
	await _safe_click(screen, panel.prep_plus.grill)
	checks.expect(screen.preparation.snapshot().inventory.prepped_grill == 2, "rendered preparation taps convert two grill portions")
	checks.expect(panel.prep_labels.grill.text.contains("2개"), "the preparation label follows the committed quantity preview")
	await process_frame
	await process_frame
	await save_frame("res://build/check/m2-prepped.png")
	await _safe_click(screen, panel.tabs[1])
	await _safe_click(screen, panel.move_buttons.up)
	checks.expect(screen.feedback_label.text.contains("벽"), "rendered invalid placement reports the wall rejection")
	await save_frame("res://build/check/m2-placement-rejected.png")
	await _choose(screen, panel.station_picker, 3)
	await _safe_click(screen, panel.move_buttons.left)
	checks.expect(screen.definitions.stations[3].tile == Vector2i(8, 5), "rendered station picker and movement change the actual board")
	await _safe_click(screen, panel.move_buttons.rotate)
	checks.expect(screen.definitions.stations[3].work_position == Vector2i(9, 5), "rendered rotation changes the station work position")
	panel.pages[1].ensure_control_visible(panel.duty_buttons.employee_01)
	await process_frame
	await process_frame
	await _choose(screen, panel.duty_buttons.employee_01, 1)
	checks.expect(screen.preparation.snapshot().duties.employee_01 == "cold", "rendered duty selection changes the preparation plan")
	await save_frame("res://build/check/m2-layout.png")
	await _safe_click(screen, screen.start_button)
	checks.expect(screen.is_running() and screen.simulation.snapshot().inventory.prepped_grill == 2, "rendered start commits the prepared inventory")
	checks.expect(screen.details_toggle.visible == screen.compact_layout and screen.detail_panel.visible, "M2 service uses a collapsible phone panel and parallel tablet details")
	screen.advance(30.0)
	await _safe_click(screen, screen.pause_button)
	await save_frame("res://build/check/m2-service.png")
	await _safe_click(screen, screen.resume_button)
	await _safe_click(screen, screen.speed_buttons[2])
	screen.advance(75.0)
	checks.expect(screen.simulation.closed and screen.analysis_scroll.visible, "rendered service reaches the M2 result panel")
	await save_frame("res://build/check/m2-closed.png")
	screen.analysis_scroll.scroll_vertical = 1000
	await process_frame
	await process_frame
	await save_frame("res://build/check/m2-station-times.png")
	await _safe_click(screen, screen.restart_button)
	checks.expect(screen.preparation.snapshot().inventory.prepped_grill == 2 and screen.simulation.tick == 0, "rendered retry restores the previous preparation without service progress")
	await _safe_click(screen, panel.tabs[2])
	panel.pages[2].ensure_control_visible(panel.reset_button)
	await process_frame
	await process_frame
	await _safe_click(screen, panel.reset_button)
	checks.expect(screen.preparation.snapshot().inventory.prepped_grill == 0, "rendered reset restores default preparation")
	if "--negative-layout" in OS.get_cmdline_user_args():
		screen.start_button.position.x = screen.size.x + 100
	checks.expect(screen.safe_area.get_global_rect().encloses(screen.start_button.get_global_rect()), "M2 rendered start must remain in the safe area")
	screen.queue_free()
	await process_frame
	var extra := Harness.boot_main(self, "res://tests/fixtures/m2_extra_menu.tres") as KitchenScreen
	await process_frame
	await process_frame
	panel = extra.preparation_panel
	panel.pages[0].ensure_control_visible(panel.prep_plus.grain_salad)
	await process_frame
	await process_frame
	await _safe_click(extra, panel.prep_plus.grain_salad)
	await save_frame("res://build/check/m2-extra-menu-prep.png")
	await _safe_click(extra, extra.start_button)
	extra.advance(20.0)
	await _safe_click(extra, extra.pause_button)
	checks.expect(extra.order_buttons.order_01.text.contains("곡물 샐러드") and extra.simulation.snapshot().orders[0].state == "served", "rendered fourth-menu name belongs to a served order")
	await save_frame("res://build/check/m2-extra-menu-served.png")
	extra.queue_free()
	await process_frame
	print("M2 rendered input checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(1 if checks.failures > 0 else 0)


func save_frame(file_path: String) -> void:
	if "--tablet" in OS.get_cmdline_user_args():
		file_path = file_path.replace("m2-", "m2-tablet-")
	elif "--phone-wide" in OS.get_cmdline_user_args():
		file_path = file_path.replace("m2-", "m2-phone-wide-")
	await super.save_frame(file_path)


func _safe_click(screen: KitchenScreen, button: Button) -> void:
	checks.expect(button.is_visible_in_tree() and screen.safe_area.get_global_rect().encloses(button.get_global_rect()), "M2 rendered hit target must be visible inside the safe area: " + button.text)
	await click(button)
	await process_frame


func _choose(screen: KitchenScreen, picker: OptionButton, index: int) -> void:
	await _safe_click(screen, picker)
	var popup := picker.get_popup()
	await process_frame
	checks.expect(popup.visible, "a coordinate tap opens the selection popup")
	var local_point := Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * (index + 0.5) / popup.item_count)
	var point := root.get_screen_transform() * local_point
	await tap(point, _mouse_event)
	await process_frame
	checks.expect(picker.selected == index, "a coordinate tap selects popup item %d" % index)
