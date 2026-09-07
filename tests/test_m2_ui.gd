extends "res://tests/harness.gd"


func run(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	if not screen.has_method("submit_preparation"):
		expect(false, "the main screen must submit M2 preparation commands")
		screen.free()
		return
	screen.set("scenario_path", "res://content/m2_first_service.tres")
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	var plan: RefCounted = screen.get("preparation")
	var panel: Control = screen.get("preparation_panel")
	expect(panel.visible and screen.get("simulation").tick == 0, "M2 starts in preparation with no running game time")
	panel.get("prep_plus")["grill"].pressed.emit()
	panel.get("prep_plus")["grill"].pressed.emit()
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
	expect(sim.call("snapshot").employees[0].duty == "cold", "start applies the selected initial duty")
	var original: String = sim.call("state_hash")
	screen.get("start_button").pressed.emit()
	expect(sim.call("state_hash") == original, "repeated start cannot prepare inventory twice")
	expect(not screen.call("submit_preparation", "move_station", "pass_01", "left").accepted, "service refuses placement commands")
	screen.call("advance", 30.0)
	expect(screen.get("summary_label").text.contains("프렙"), "service distinguishes prepared stock from raw ingredients")
	screen.get("speed_buttons")[2].pressed.emit()
	screen.call("advance", 75.0)
	expect(sim.get("closed") and screen.get("analysis_scroll").visible, "closing displays the M2 time analysis panel")
	expect(screen.get("analysis_label").text.contains("주문별 누적 시간") and screen.get("analysis_label").text.contains("예약·사용"), "closing names cumulative order time and reservation-inclusive station time accurately")
	screen.get("restart_button").pressed.emit()
	plan = screen.get("preparation")
	expect(panel.visible and plan.call("snapshot").inventory.prepped_grill == 2 and plan.call("snapshot").purchased_cost == 6600, "retry reconstructs the previous choices with fresh purchases")
	expect(screen.get("simulation").tick == 0 and screen.get("driver").paused, "retry cannot inherit service progress")
	panel.get("reset_button").pressed.emit()
	expect(plan.call("snapshot").inventory.prepped_grill == 0 and screen.get("definitions").stations[3].tile == Vector2i(9, 5), "reset restores default preparation and layout")
	screen.queue_free()
	await tree.process_frame
	await _extra_menu(tree)


func _extra_menu(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", "res://tests/fixtures/m2_extra_menu.tres")
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	var panel: Control = screen.get("preparation_panel")
	expect(panel.get("prep_plus").has("grain_salad") and panel.get("prep_labels")["grain_salad"].text.contains("곡물 샐러드"), "a data-only menu receives a named preparation control")
	panel.get("prep_plus")["grain_salad"].pressed.emit()
	screen.get("start_button").pressed.emit()
	screen.call("advance", 20.0)
	expect(screen.get("order_buttons")["order_01"].text.contains("곡물 샐러드"), "the fourth-menu order shows its resource name")
	expect(screen.get("simulation").snapshot().orders[0].state == "served", "the displayed fourth-menu order actually serves")
	screen.queue_free()
	await tree.process_frame
