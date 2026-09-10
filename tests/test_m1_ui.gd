extends "res://tests/harness.gd"


func run(tree: SceneTree) -> void:
	for speed: int in [1, 4]:
		await _test_priority_press_survives_refresh(tree, speed)
	var screen := boot_main(tree)
	if screen == null or not screen.has_method("submit_command"):
		expect(false, "the main screen must expose the M1 command flow")
		if screen != null:
			screen.queue_free()
			await tree.process_frame
		return
	await tree.process_frame
	var sim: RefCounted = screen.get("simulation")
	var summary: Label = screen.get("summary_label")
	expect(summary.text.contains("6,600") and summary.text.contains("샐러드"), "preparation shows the actual purchase cost and menus")
	screen.get("start_button").pressed.emit()
	screen.call("advance", 1.0)
	expect(sim.get("tick") == 10 and sim.call("snapshot").orders.size() == 1, "start runs the real order simulation")
	screen.get("pause_button").pressed.emit()
	screen.call("select_order", "order_01")
	screen.get("priority_up_button").pressed.emit()
	expect(sim.call("snapshot").orders[0].priority == 1 and sim.call("snapshot").commands.size() == 1, "a priority tap while paused queues one command")
	expect(screen.get("feedback_label").text.contains("적용 대기"), "paused commands display their pending state")
	expect(screen.get("detail_label").text.contains("우선순위 2")
		and screen.get("order_buttons").order_01.text.contains("우선 2"), "paused priority taps immediately update both displayed priority values")
	screen.call("advance", 10.0)
	expect(sim.get("tick") == 10, "paused UI does not supply wall time to the simulation")
	screen.get("resume_button").pressed.emit()
	screen.call("advance", 0.1)
	expect(sim.call("snapshot").orders[0].priority == 2, "resume applies the selected order priority")
	screen.get("pause_button").pressed.emit()
	var duty: OptionButton = screen.get("duty_buttons")[0]
	duty.item_selected.emit(3)
	screen.get("cancel_button").pressed.emit()
	expect(sim.call("snapshot").commands.size() == 2, "duty and cancellation taps queue separate commands")
	screen.get("resume_button").pressed.emit()
	screen.call("advance", 0.1)
	expect(sim.call("snapshot").orders[0].state == "cancelled" and sim.call("snapshot").employees[0].duty == "off", "cancel and duty changes reach the simulation")
	screen.call("set_compact_layout", true)
	expect(not screen.get("detail_panel").visible, "phone details start collapsed")
	screen.get("details_toggle").pressed.emit()
	expect(screen.get("detail_panel").visible, "phone details expand with one tap")
	screen.get("details_toggle").pressed.emit()
	expect(not screen.get("detail_panel").visible, "phone details can collapse with a tap")
	screen.call("set_compact_layout", false)
	expect(screen.get("detail_panel").visible and not screen.get("details_toggle").visible, "tablet layout keeps details visible in parallel")
	screen.get("speed_buttons")[2].pressed.emit()
	expect(screen.get("driver").speed == 4, "the four-speed button controls the real tick driver")
	screen.call("advance", 75.0)
	expect(sim.get("closed") and screen.get("restart_button").visible, "closing exposes restart on the real result screen")
	expect(screen.get("summary_label").text.contains("손익") and screen.get("summary_label").text.contains("폐기"), "closing displays accounting and waste")
	screen.get("restart_button").pressed.emit()
	var restarted: RefCounted = screen.get("simulation")
	expect(restarted != sim and restarted.get("tick") == 0 and restarted.call("snapshot").orders.is_empty(), "restart creates a fresh prepared service")
	expect(restarted.call("snapshot").inventory.vegetable == 22 and screen.get("driver").paused, "restart restores inventory and stays paused")
	screen.get("start_button").pressed.emit()
	screen.call("advance", 1.0)
	screen.get("pause_button").pressed.emit()
	screen.get("cancel_button").pressed.emit()
	screen.get("priority_up_button").pressed.emit()
	expect(restarted.call("snapshot").commands.size() == 2, "the rejection fixture queues cancellation before priority on the same order")
	screen.get("resume_button").pressed.emit()
	screen.call("advance", 0.2)
	expect(restarted.call("snapshot").orders[0].state == "cancelled", "the rejection fixture executes cancellation across multiple ticks")
	expect(screen.get("feedback_label").text.contains("적용하지 못했습니다"), "a rejected command remains visible after later ticks in the same frame")
	var data: Resource = ResourceLoader.load("res://content/m1_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	data.get("ingredients")[0] = null
	var invalid: RefCounted = load("res://sim/service_sim.gd").new(data)
	screen.set("definitions", data)
	screen.set("simulation", invalid)
	screen.call("_refresh")
	expect(screen.get("start_button").disabled and screen.get("summary_label").text.contains("오류"), "the screen presents invalid content as an error and disables start")
	expect(screen.get("board").definitions == null, "the error screen does not draw rejected content")
	screen.queue_free()
	await tree.process_frame
	await _test_reordered_employees(tree)


func _test_priority_press_survives_refresh(tree: SceneTree, speed: int) -> void:
	var screen := boot_main(tree)
	await tree.process_frame
	await tree.process_frame
	screen.get("start_button").pressed.emit()
	screen.get("speed_buttons")[0 if speed == 1 else 2].pressed.emit()
	expect(screen.get("driver").speed == speed, "the held priority fixture uses the requested speed")
	screen.call("advance", 1.0)
	await tree.process_frame
	var button: Button = screen.get("priority_up_button")
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
	expect(button.is_pressed(), "the priority input fixture holds the actual button before the next tick")
	screen.call("advance", 0.2)
	expect(button.is_pressed(), "a service refresh preserves a held priority press")
	var release := InputEventMouseButton.new()
	release.position = point
	release.button_index = MOUSE_BUTTON_LEFT
	tree.root.push_input(release, true)
	var view: Dictionary = screen.get("simulation").snapshot()
	expect(view.commands.size() == 1 and view.commands[0].kind == "set_priority"
		and view.commands[0].value == 2, "release after service ticks submits exactly one priority command")
	expect(screen.get("detail_label").text.contains("우선순위 2")
		and screen.get("order_buttons").order_01.text.contains("우선 2"), "queued priority appears in the selected detail and order row before the next tick")
	screen.call("advance", 0.1)
	expect(screen.get("simulation").snapshot().orders[0].priority == 2, "the held priority tap reaches the simulation on the next tick")
	screen.queue_free()
	await tree.process_frame


func _test_reordered_employees(tree: SceneTree) -> void:
	var data: Resource = load("res://content/m1_first_service.tres")
	data.get("employees").reverse()
	var screen := boot_main(tree)
	await tree.process_frame
	var sim: RefCounted = screen.get("simulation")
	var displayed: Dictionary = screen.get("latest_view").employees[0]
	var duty: OptionButton = screen.get("duty_buttons")[0]
	duty.item_selected.emit(1)
	expect(sim.call("snapshot").commands[0].target_id == displayed.id, "a duty control targets its displayed employee after resource reordering")
	screen.get("start_button").pressed.emit()
	screen.call("advance", 0.1)
	var employees: Array = sim.call("snapshot").employees
	expect(employees[0].duty == "cold" and employees[1].duty == "all", "a duty change applies only to the displayed employee after resource reordering")
	screen.queue_free()
	await tree.process_frame
	data.get("employees").reverse()
