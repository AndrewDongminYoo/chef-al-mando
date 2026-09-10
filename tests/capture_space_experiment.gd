extends SceneTree

const Experiment := preload("res://tests/fixtures/space_experiment.gd")
const Harness := preload("res://tests/harness.gd")
var checks := Harness.new()


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: spatial preview capture requires a rendered window")
		quit(1)
		return
	root.size = Vector2i(1566, 720)
	DirAccess.make_dir_recursive_absolute("res://build/check/space")
	for scenario_id: String in Experiment.SCENARIOS:
		for locale: String in ["ko", "en"]:
			var temporary := "user://space_capture_%d.tres" % Time.get_ticks_usec()
			checks.expect(ResourceSaver.save(Experiment.scenario(scenario_id), temporary) == OK, "the rendered experiment saves an isolated scenario")
			var screen := Harness.boot_main(self, temporary)
			checks.expect(screen != null, "the spatial preview opens the actual preparation scene")
			if screen == null:
				quit(1)
				return
			if locale == "en":
				screen.settings_locale.item_selected.emit(1)
			screen.settings_text_size.item_selected.emit(1)
			await _settle(screen)
			var panel = screen.preparation_panel
			panel.show_tab(1)
			panel.select_station("pass_01")
			await _settle(screen)
			panel.pages[1].ensure_control_visible(panel.placement_preview)
			await _settle(screen)
			if "--negative-preview" in OS.get_cmdline_user_args():
				panel.placement_preview.visible = false
			checks.expect(screen.definitions.space_rules and panel.move_buttons.left.disabled and panel.move_buttons.rotate.disabled, "the actual preview identifies the frozen exit before input")
			checks.expect(panel.placement_preview.visible and panel.pages[1].get_global_rect().encloses(panel.placement_preview.get_global_rect()), "fixed-station rule text is fully visible in the scrolled phone panel")
			checks.expect(not panel.placement_preview.text.is_empty(), "the rendered fixed preview has explanatory text")
			if checks.failures > 0:
				screen.queue_free()
				await process_frame
				DirAccess.remove_absolute(temporary)
				quit(1)
				return
			await _save_frame(scenario_id + "-" + locale + "-fixed")
			if scenario_id == "hot_queue":
				checks.expect(screen.submit_preparation("move_station", "hot_01", "left").accepted, "the rendered clearance fixture reaches the last valid gap")
				panel.select_station("hot_01")
				await _settle(screen)
				panel.pages[1].ensure_control_visible(panel.placement_preview)
				await _settle(screen)
				checks.expect(panel.move_buttons.left.disabled and not panel.move_buttons.right.disabled, "the rendered panel distinguishes blocked and legal moves")
				await _save_frame(scenario_id + "-" + locale + "-clearance")
			screen.queue_free()
			await process_frame
			DirAccess.remove_absolute(temporary)
	print("PASS: spatial preview render checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(0 if checks.failures == 0 else 1)


func _settle(screen: Control) -> void:
	for _frame: int in 3:
		await process_frame
	screen._apply_safe_area(Rect2i(48, 0, 1470, 690), Transform2D.IDENTITY)
	for _frame: int in 3:
		await process_frame


func _save_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	checks.expect(screenshot.save_png("res://build/check/space/" + label + ".png") == OK, "the spatial preview saves its actual pixels")
