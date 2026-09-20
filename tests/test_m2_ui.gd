extends "res://tests/harness.gd"


func run(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	if not screen.has_method("submit_preparation"):
		expect(false, "the main screen must submit M2 preparation commands")
		screen.free()
		return
	screen.set("scenario_path", "res://content/m2_first_service.tres")
	var settings_path := "user://test_m2_ui_main_%d.json" % Time.get_ticks_usec()
	var settings := {"locale": "ko", "sound_enabled": false, "text_size": "normal"}
	expect(HarnessSettingsStore.new(settings_path).save_settings(settings).accepted,
		"the M2 UI fixture disables audio in its isolated settings")
	screen.set("settings_path", settings_path)
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(settings_path))
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	var plan: RefCounted = screen.get("preparation")
	var panel: Control = screen.get("preparation_panel")
	var employee_status := screen.get("duty_labels")[0] as Label
	expect(employee_status.get_theme_font_size("font_size") == 18,
		"employee status uses the readable normal text size")
	expect(employee_status.max_lines_visible == 4,
		"employee status preserves translated destinations in dense layouts")
	expect(screen.get("app_preferences").update_settings({"text_size": "large"}).accepted,
		"employee status fixture enables large text")
	expect(employee_status.get_theme_font_size("font_size") == 22,
		"employee status follows the readable large text size")
	expect(screen.get("app_preferences").update_settings({"text_size": "normal"}).accepted,
		"employee status fixture restores normal text")
	expect(panel.visible and screen.get("simulation").tick == 0, "M2 starts in preparation with no running game time")
	expect(screen.get("summary_label").is_visible_in_tree(), "preparation budget is visible on the initial stock tab")
	var initial_summary: String = screen.get("summary_label").text
	var ingredient_id: String = panel.get("purchase_plus").keys()[0]
	panel.get("purchase_plus")[ingredient_id].pressed.emit()
	expect(screen.get("summary_label").is_visible_in_tree() and screen.get("summary_label").text != initial_summary, "a purchase updates the visible preparation budget")
	panel.get("purchase_minus")[ingredient_id].pressed.emit()
	panel.get("prep_plus")["prepped_grill"].pressed.emit()
	panel.get("prep_plus")["prepped_grill"].pressed.emit()
	expect(plan.call("snapshot").inventory.prepped_grill == 2, "preparation buttons submit real conversion commands")
	expect(screen.get("summary_label").text.contains("6 / 6"), "the main summary always shows used preparation labor")
	panel.get("move_buttons")["up"].pressed.emit()
	expect(screen.get("feedback_label").text.contains("벽"), "an invalid station move displays a readable rejection")
	panel.call("select_station", "pass_01")
	panel.get("move_buttons")["left"].pressed.emit()
	expect(screen.get("definitions").stations[3].tile == Vector2i(8, 5), "an accepted placement updates the board definition")
	panel.get("duty_buttons")["employee_01"].item_selected.emit(1)
	expect(plan.call("snapshot").duties.employee_01 == "cold", "preparation duties belong to the plan")
	screen.get("start_button").pressed.emit()
	var sim: RefCounted = screen.get("simulation")
	expect(not panel.visible and sim.call("snapshot").inventory.prepped_grill == 2, "start commits the prepared inventory and switches to service")
	expect(screen.get("summary_label").is_visible_in_tree(), "service keeps its stock summary visible after preparation")
	expect(sim.call("snapshot").employees[0].duty == "cold", "start applies the selected initial duty")
	var original: String = sim.call("state_hash")
	screen.get("start_button").pressed.emit()
	expect(sim.call("state_hash") == original, "repeated start cannot prepare inventory twice")
	expect(not screen.call("submit_preparation", "move_station", "pass_01", "left").accepted, "service refuses placement commands")
	screen.call("advance", 1.0)
	expect(screen.get("duty_labels")[0].text.contains("채소 샐러드") and screen.get("duty_labels")[0].text.contains("재료 보관대로 이동 중"),
		"the employee status names the menu and pickup destination")
	screen.call("advance", 1.0)
	expect(screen.get("duty_labels")[0].text.contains("원재료 챙기는 중"),
		"the employee status distinguishes active raw ingredient pickup")
	screen.call("advance", 1.0)
	expect(screen.get("duty_labels")[0].text.contains("손질하러 이동 중"),
		"the employee status distinguishes movement toward preparation")
	screen.call("advance", 30.0)
	expect(screen.get("summary_label").text.contains("프렙"), "service distinguishes prepared stock from raw ingredients")
	screen.get("speed_buttons")[2].pressed.emit()
	screen.call("advance", 75.0)
	expect(sim.get("closed") and screen.get("analysis_scroll").visible, "closing displays the M2 time analysis panel")
	var analysis_text: String = screen.get("analysis_label").accessibility_name
	expect(analysis_text.contains("다음 영업 추천") and analysis_text.contains("주문별 누적 시간")
		and analysis_text.contains("예약·사용"),
		"closing shows actionable recommendations before the existing detailed metrics")
	var action_index := analysis_text.find("다음 영업 추천")
	var accounting_index := analysis_text.find("손익")
	var cumulative_index := analysis_text.find("주문별 누적 시간")
	expect(action_index >= 0 and accounting_index > action_index and cumulative_index > action_index,
		"closing places next-service changes before accounting and cumulative metrics")
	var analysis: Control = screen.get("analysis_label")
	expect(analysis is RichTextLabel, "closing analysis supports distinct text hierarchy")
	expect(int(analysis.get_meta("action_heading_font_size", 0)) > int(analysis.get_meta("action_font_size", 0)),
		"closing analysis makes the action heading larger than each proposed change")
	expect(int(analysis.get_meta("action_font_size", 0)) == 18,
		"closing analysis keeps each proposed change at the readable body size")
	expect(analysis.get_meta("action_color", Color.TRANSPARENT) == Color("eab06c"),
		"closing analysis emphasizes each proposed change with the action color")
	var analysis_scroll: ScrollContainer = screen.get("analysis_scroll")
	analysis.set("fit_content", false)
	analysis.custom_minimum_size.y = 3000.0
	await tree.process_frame
	await _expect_analysis_drag_scrolls(tree, analysis_scroll, analysis)
	analysis_scroll.scroll_vertical = 1000
	await tree.process_frame
	expect(analysis_scroll.scroll_vertical > 0, "analysis restart fixture scrolls away from the recommendations")
	screen.get("restart_button").pressed.emit()
	plan = screen.get("preparation")
	expect(panel.visible and plan.call("snapshot").inventory.prepped_grill == 2 and plan.call("snapshot").purchased_cost == 6600, "retry reconstructs the previous choices with fresh purchases")
	expect(screen.get("simulation").tick == 0 and screen.get("driver").paused, "retry cannot inherit service progress")
	expect(screen.get("summary_label").is_visible_in_tree(), "retry restores the visible preparation budget")
	panel.get("reset_button").pressed.emit()
	expect(plan.call("snapshot").inventory.prepped_grill == 0 and screen.get("definitions").stations[3].tile == Vector2i(9, 5), "reset restores default preparation and layout")
	screen.get("start_button").pressed.emit()
	screen.call("advance", 300.0)
	await tree.process_frame
	expect(screen.get("simulation").closed and analysis_scroll.scroll_vertical == 0,
		"each closing opens at the next-service recommendations")
	await _expect_korean_word_stays_whole(tree, screen, analysis)
	screen.queue_free()
	await tree.process_frame
	await _extra_menu(tree)
	await _custom_ingredients(tree)


func _expect_analysis_drag_scrolls(tree: SceneTree, scroll: ScrollContainer, content: Control) -> void:
	scroll.scroll_vertical = 0
	var drag_events := {"count": 0}
	scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenDrag:
			drag_events.count += 1
	)
	var current := tree.root.get_screen_transform() * scroll.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = current
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	for offset: Vector2 in [Vector2(0, -32), Vector2(0, -32), Vector2(0, -32), Vector2(0, -32)]:
		current += offset
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = current
		drag.relative = offset
		Input.parse_input_event(drag)
		await tree.process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = current
	release.pressed = false
	Input.parse_input_event(release)
	await tree.process_frame
	expect(content.get_global_rect().has_point(scroll.get_global_rect().get_center()),
		"analysis drag fixture starts on the actual result content")
	expect(drag_events.count > 0, "dragging the result content reaches its scroll container")


func _expect_korean_word_stays_whole(tree: SceneTree, screen: Control, content: RichTextLabel) -> void:
	content.reparent(tree.root)
	content.clear()
	screen.call("_analysis_text", "버섯", 18, Color.WHITE)
	content.custom_minimum_size = Vector2.ZERO
	content.size = Vector2(content.get_theme_font("normal_font").get_string_size("버").x + 1.0, 120.0)
	await tree.process_frame
	expect(content.get_parsed_text() == "버\u2060섯"
		and content.get_character_line(0) == content.get_character_line(2),
		"a Korean word stays on one line instead of splitting between syllables")
	content.queue_free()
	await tree.process_frame


func _extra_menu(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", "res://tests/fixtures/m2_extra_menu.tres")
	var settings_path := "user://test_m2_ui_extra_%d.json" % Time.get_ticks_usec()
	var settings := {"locale": "ko", "sound_enabled": false, "text_size": "normal"}
	expect(HarnessSettingsStore.new(settings_path).save_settings(settings).accepted,
		"the extra-menu fixture disables audio in its isolated settings")
	screen.set("settings_path", settings_path)
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(settings_path))
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	var panel: Control = screen.get("preparation_panel")
	expect(panel.get("prep_plus").has("prepped_grain_salad") and panel.get("prep_labels")["prepped_grain_salad"].text.contains("곡물 샐러드"), "a data-only menu receives a named preparation control")
	panel.get("prep_plus")["prepped_grain_salad"].pressed.emit()
	screen.get("start_button").pressed.emit()
	screen.call("advance", 20.0)
	expect(screen.get("order_buttons")["order_01"].text.contains("곡물 샐러드"), "the fourth-menu order shows its resource name")
	expect(screen.get("simulation").snapshot().orders[0].state == "served", "the displayed fourth-menu order actually serves")
	screen.queue_free()
	await tree.process_frame


func _custom_ingredients(tree: SceneTree) -> void:
	for source_path: String in ["res://content/m1_first_service.tres", "res://content/m2_first_service.tres"]:
		var data: Resource = load(source_path).duplicate(true)
		var ingredient: Resource = data.call("ingredient_for", "vegetable")
		ingredient.set("id", "greens")
		ingredient.set("display_name", "잎채소")
		data.get("purchases")["greens"] = data.get("purchases")["vegetable"]
		data.get("purchases").erase("vegetable")
		for recipe: Resource in data.get("recipes"):
			var inputs: Dictionary = recipe.get("ingredients")
			if inputs.has("vegetable"):
				inputs["greens"] = inputs["vegetable"]
				inputs.erase("vegetable")
		for other_ingredient: Resource in data.get("ingredients"):
			var mise_inputs: Dictionary = other_ingredient.get("inputs")
			if mise_inputs.has("vegetable"):
				mise_inputs["greens"] = mise_inputs["vegetable"]
				mise_inputs.erase("vegetable")
		var oil: Resource = load("res://content/ingredient_def.gd").new()
		oil.set("id", "oil")
		oil.set("display_name", "식용유")
		data.get("ingredients").append(oil)
		expect(data.call("validate").is_empty(), "the custom ingredient fixture is valid for service")
		var fixture_path: String = "user://test_summary_%s.tres" % data.get("id")
		expect(ResourceSaver.save(data, fixture_path) == OK, "the custom ingredient fixture is saved for the real scene")
		var screen := boot_main(tree, fixture_path)
		await tree.process_frame
		if data.call("supports_preparation"):
			expect(screen.get("preparation_panel").purchase_labels.greens.text.contains("잎채소"), "preparation names a renamed raw ingredient")
		else:
			expect(screen.get("summary_label").text.contains("잎채소 22") and screen.get("summary_label").text.contains("식용유 0"), "ready summary lists custom raw ingredients including those with no purchases")
		screen.get("start_button").pressed.emit()
		screen.call("advance", 20.0)
		var snapshot: Dictionary = screen.get("simulation").snapshot()
		expect(snapshot.orders[0].state == "served", "a recipe using the renamed ingredient actually serves")
		var summary: String = screen.get("summary_label").text
		expect(summary.contains("잎채소 %d" % snapshot.inventory.greens) and summary.contains("식용유 0"), "service summary shows the actual custom raw stock")
		expect(not summary.split("\n프렙 · ")[0].contains("손질한"), "raw stock summary excludes prepared ingredient definitions")
		screen.queue_free()
		await tree.process_frame
		DirAccess.remove_absolute(fixture_path)
