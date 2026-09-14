extends "res://tests/capture_m0.gd"

const SettingsStore := preload("res://persistence/settings_store.gd")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: service feedback capture requires a rendered window")
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	var locale := "en" if "--locale=en" in arguments else "ko"
	var large_text := "--large-text" in arguments
	var layout_name := "tablet" if "--tablet" in arguments else "phone-wide"
	var hot_queue := "--hot-queue" in arguments
	root.size = Vector2i(1024, 768) if layout_name == "tablet" else Vector2i(1566, 720)
	var settings_path := "user://capture_service_feedback_%d.json" % Time.get_ticks_usec()
	var settings := {"locale": locale, "sound_enabled": false,
		"text_size": "large" if large_text else "normal"}
	checks.expect(SettingsStore.new(settings_path).save_settings(settings).accepted,
		"service feedback capture settings are saved")
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen := scene.instantiate() as KitchenScreen
	screen.scenario_path = ("res://content/campaign/scenarios/hot_queue.tres" if hot_queue
		else "res://content/m2_first_service.tres")
	screen.settings_path = settings_path
	root.add_child(screen)
	screen.set_process(false)
	await process_frame
	await process_frame
	var insets := Vector2i(0, 24) if layout_name == "tablet" else Vector2i(48, 30)
	screen.call("_apply_safe_area", Rect2i(insets.x, 0, int(screen.size.x) - insets.x * 2,
		int(screen.size.y) - insets.y), Transform2D.IDENTITY)
	await process_frame
	await process_frame
	var prep_recipe_id := "grill" if hot_queue else "salad"
	var prep_quantity := 2 if hot_queue else 1
	checks.expect(screen.submit_preparation("set_prep", prep_recipe_id, prep_quantity).accepted,
		"service feedback capture prepares the target portions")
	if hot_queue:
		checks.expect(screen.submit_preparation("set_menu_priority", "grill", 2).accepted,
			"hot queue capture applies the maximum grill priority")
	screen.start_button.pressed.emit()
	while screen.board.chatter.is_empty() and screen.simulation.tick < 1500:
		screen.advance(0.1)
	await process_frame
	var chatter: Dictionary = screen.board.chatter
	checks.expect(chatter.get("kind", "") in ["order_wait_started", "prepared_stock_depleted", "order_ended"]
		and not chatter.get("text", "").is_empty(), "rendered service shows an evidence-based chef bubble")
	await RenderingServer.frame_post_draw
	checks.expect(not screen.board.chatter_obscures_content(),
		"rendered chef bubble does not cover an employee or station")
	checks.expect(screen.safe_area.get_global_rect().encloses(screen.board.get_global_rect())
		and screen.duty_labels[0].is_visible_in_tree(),
		"rendered activity and board remain inside the safe area")
	_expect_header_fits(screen, "activity")
	DirAccess.make_dir_recursive_absolute("res://build/check")
	var prefix := "service-feedback-hot-queue" if hot_queue else "service-feedback"
	var variant := "%s-%s-%s" % [locale, "large" if large_text else "normal", layout_name]
	await save_frame("res://build/check/%s-%s-activity.png" % [prefix, variant])
	screen.advance(float(screen.definitions.closing_tick - screen.simulation.tick) / 10.0)
	await process_frame
	checks.expect(screen.simulation.closed and screen.analysis_scroll.visible
		and screen.analysis_label.get_parsed_text().contains(tr("다음 영업에서 바꿀 것")),
		"rendered closing shows actionable service feedback")
	screen.chatter_event.clear()
	screen.chatter_seconds_left = 0.0
	screen.board.show_chatter({})
	await process_frame
	_expect_header_fits(screen, "analysis")
	_expect_analysis_action_style(screen)
	await save_frame("res://build/check/%s-%s-analysis.png" % [prefix, variant])
	screen.queue_free()
	await process_frame
	DirAccess.remove_absolute(settings_path)
	TranslationServer.set_locale("ko")
	print("Service feedback rendered checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(1 if checks.failures > 0 else 0)


func _expect_header_fits(screen: KitchenScreen, phase: String) -> void:
	var title_rect := screen.title_label.get_global_rect()
	var remaining_rect := screen.remaining_label.get_global_rect()
	var counter_rect := screen.counter.get_global_rect()
	var settings_rect := screen.settings_button.get_global_rect()
	checks.expect(title_rect.size.x >= screen.title_label.get_combined_minimum_size().x,
		"rendered %s header keeps the full scenario title" % phase)
	checks.expect(title_rect.end.x <= remaining_rect.position.x
		and remaining_rect.end.x <= counter_rect.position.x
		and counter_rect.end.x <= settings_rect.position.x,
		"rendered %s header keeps title and time labels separate" % phase)
	checks.expect(screen.safe_area.get_global_rect().encloses(settings_rect),
		"rendered %s header keeps settings inside the safe area" % phase)


func _expect_analysis_action_style(screen: KitchenScreen) -> void:
	var label := screen.analysis_label
	var action_index := label.get_parsed_text().find("→")
	checks.expect(action_index >= 0, "rendered analysis contains an action line")
	if action_index < 0:
		return
	var action_line := label.get_character_line(action_index)
	var action_range := label.get_line_range(action_line)
	var action_text := label.get_parsed_text().substr(action_range.x,
		action_range.y - action_range.x).trim_suffix("\n")
	var expected_font_size := 22 if "--large-text" in OS.get_cmdline_user_args() else 18
	var expected_color := Color("eab06c")
	if "--negative-analysis-style" in OS.get_cmdline_user_args():
		expected_font_size += 1
		expected_color = Color.MAGENTA
	var expected_width := label.get_theme_font("normal_font").get_string_size(action_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, expected_font_size).x
	checks.expect(absf(label.get_line_width(action_line) - expected_width) < 2.0,
		"rendered analysis action uses the observation font size")
	RenderingServer.force_draw(false)
	var frame := root.get_texture().get_image()
	var line_rect := Rect2(label.get_global_rect().position
		+ Vector2(0, label.get_line_offset(action_line)),
		Vector2(label.size.x, label.get_line_height(action_line)))
	checks.expect(_region_contains_color(frame, line_rect, expected_color),
		"rendered analysis action uses the copper action color")


func _region_contains_color(frame: Image, region: Rect2, target: Color) -> bool:
	var scale := Vector2(frame.get_size()) / root.get_visible_rect().size
	var start := Vector2i(region.position * scale).clamp(Vector2i.ZERO, frame.get_size() - Vector2i.ONE)
	var finish := Vector2i(region.end * scale).clamp(Vector2i.ZERO, frame.get_size())
	for pixel_y: int in range(start.y, finish.y):
		for pixel_x: int in range(start.x, finish.x):
			var pixel := frame.get_pixel(pixel_x, pixel_y)
			if absf(pixel.r - target.r) < 0.08 and absf(pixel.g - target.g) < 0.08 \
				and absf(pixel.b - target.b) < 0.08:
				return true
	return false
