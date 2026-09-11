extends SceneTree

const Harness := preload("res://tests/harness.gd")
const KitchenBoard := preload("res://presentation/kitchen_board.gd")
const Policies := preload("res://tests/fixtures/m3_policies.gd")

var checks := Harness.new()


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: kitchen screen test requires a rendered window")
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute("res://build/check")
	checks.expect(directory_error == OK, "the rendered test creates its output directory")
	if directory_error != OK:
		quit(1)
		return
	root.size = Vector2i(1566, 720)
	var screen := Harness.boot_main(self, "res://content/campaign/scenarios/split_duties.tres")
	if screen == null:
		printerr("FAIL: kitchen screen fixture cannot load")
		quit(1)
		return
	await _settle(screen)
	checks.expect(screen.summary_label.is_visible_in_tree(), "the rendered preparation screen shows its budget")
	checks.expect(screen.preparation_panel.pages[0].get_global_rect().encloses(screen.summary_label.get_global_rect()), "the preparation budget fits inside the visible stock scroll area")
	await RenderingServer.frame_post_draw
	checks.expect(root.get_texture().get_image().save_png("res://build/check/kitchen-screen-preparation.png") == OK, "the preparation budget saves a rendered frame")
	for command: Dictionary in Policies.reference_policy("split_duties").preparation:
		checks.expect(screen.submit_preparation(command.kind, command.target_id, command.value).accepted,
			"the dense fixture accepts its real preparation command")
	screen.start_button.pressed.emit()
	screen.advance(1.0)
	await _settle(screen)
	var normal_board_rect: Rect2 = screen.board.get_global_rect()
	var normal_kitchen_rect: Rect2 = screen.get_node("SafeArea/Layout/Kitchen").get_global_rect()
	checks.expect(not screen.detail_panel.visible and screen.details_toggle.visible,
		"phone service starts with order details collapsed")
	checks.expect(_cell_size(screen.board, screen.definitions.grid_size) >= 36.0,
		"the rendered 14 by 9 kitchen keeps cells at least 36 pixels")
	checks.expect(screen.duty_buttons.size() == 4 and screen.summary_label.get_line_count() >= 3,
		"the dense fixture has four staff and wrapped stock text")
	screen.settings_text_size.item_selected.emit(1)
	await _settle(screen)
	var board_rect: Rect2 = screen.board.get_global_rect()
	var large_kitchen_rect: Rect2 = screen.get_node("SafeArea/Layout/Kitchen").get_global_rect()
	checks.expect(normal_board_rect == board_rect,
		"changing to large text does not resize the phone kitchen board: %s -> %s, kitchen %s -> %s" % [normal_board_rect, board_rect, normal_kitchen_rect, large_kitchen_rect])
	var working := await _advance_to_work(screen)
	checks.expect(not working.is_empty(), "the dense fixture reaches active station work")
	if not working.is_empty():
		checks.expect(screen.submit_command("set_duty", working.id, "off").accepted,
			"the working fixture queues a responsibility change")
		screen.advance(0.1)
		await _settle(screen)
		var refreshed := _employee_by_id(screen.latest_view.employees, working.id)
		checks.expect(refreshed.pending_duty == "off" and screen.duty_labels[_employee_index(screen.latest_view.employees, working.id)].text.contains("현재 공정 후 담당 변경"),
			"the rendered staff label shows the pending responsibility change")
	var refreshed_board_rect: Rect2 = screen.board.get_global_rect()
	checks.expect(board_rect == refreshed_board_rect,
		"wrapped stock, selected details, and pending duty text do not resize the kitchen board: %s -> %s" % [board_rect, refreshed_board_rect])
	screen.details_toggle.pressed.emit()
	await _settle(screen)
	checks.expect(screen.detail_panel.visible and board_rect == screen.board.get_global_rect(),
		"opening the selected order detail does not resize the kitchen board")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	checks.expect(not image.is_empty() and image.save_png("res://build/check/kitchen-screen-dense.png") == OK,
		"the dense kitchen state saves a rendered frame")
	var service_board_height: float = screen.board.size.y
	screen._set_speed(4)
	_advance_running(screen, (screen.definitions.closing_tick - screen.simulation.tick) / 40.0)
	await _settle(screen)
	checks.expect(screen.state == screen.State.CLOSED and screen.board.size.y > service_board_height,
		"analysis expands the board after the service staff controls are hidden: state=%s tick=%s height=%s -> %s paused=%s" % [screen.state, screen.simulation.tick, service_board_height, screen.board.size.y, screen.driver.paused])
	checks.expect(screen.analysis_label.get_parsed_text().contains("손익"),
		"analysis keeps its accounting summary visible")
	screen.queue_free()
	await process_frame
	await _assert_english_pending_layout(false)
	await _assert_english_pending_layout(true)
	root.size = Vector2i(1566, 720)
	await process_frame
	await _assert_directional_work_pixels()
	print("Kitchen screen rendered checks=%d failures=%d" % [checks.checked, checks.failures])
	quit(1 if checks.failures > 0 else 0)


func _settle(screen: Control) -> void:
	for frame_index: int in 4:
		await process_frame
	var inset := 48 if screen.compact_layout else 0
	screen._apply_safe_area(Rect2i(inset, 0, int(screen.size.x) - inset * 2, int(screen.size.y) - 30), Transform2D.IDENTITY)
	for frame_index: int in 4:
		await process_frame


func _cell_size(board: Control, grid_size: Vector2i) -> float:
	return minf((board.size.x - 16.0) / grid_size.x, (board.size.y - 16.0) / grid_size.y)


func _advance_to_work(screen: Control) -> Dictionary:
	for tick: int in 160:
		for employee: Dictionary in screen.latest_view.employees:
			if not employee.order_id.is_empty():
				var order := _order_by_id(screen.latest_view.orders, employee.order_id)
				if order.state == "working":
					return employee
		_advance_running(screen, 0.1)
		await process_frame
	return {}


func _advance_running(screen: Control, seconds: float) -> void:
	if screen.state == screen.State.PAUSED:
		screen.resume_button.pressed.emit()
	screen.advance(seconds)


func _employee_by_id(employees: Array, employee_id: String) -> Dictionary:
	for employee: Dictionary in employees:
		if employee.id == employee_id:
			return employee
	return {}


func _employee_index(employees: Array, employee_id: String) -> int:
	for index: int in employees.size():
		if employees[index].id == employee_id:
			return index
	return -1


func _order_by_id(orders: Array, order_id: String) -> Dictionary:
	for order: Dictionary in orders:
		if order.id == order_id:
			return order
	return {}


func _assert_directional_work_pixels() -> void:
	var hashes: Dictionary[String, String] = {}
	for direction: String in ["north", "east", "south", "west"]:
		var definitions: Resource = load("res://content/m1_first_service.tres").duplicate(true)
		var work_tile := Vector2i(6, 4)
		var station: Resource = definitions.stations[0]
		station.tile = {"north": Vector2i(6, 3), "east": Vector2i(7, 4), "south": Vector2i(6, 5), "west": Vector2i(5, 4)}[direction]
		station.work_position = work_tile
		if "--negative-facing" in OS.get_cmdline_user_args():
			station.tile = Vector2i(6, 3)
		var board := KitchenBoard.new()
		board.size = Vector2(720, 480)
		root.add_child(board)
		var snapshot := {"employees": [{"id": "employee_01", "tile": [work_tile.x, work_tile.y], "next_tile": [work_tile.x, work_tile.y], "progress": 0, "duty": "all", "order_id": "order_01"}], "orders": [{"id": "order_01", "state": "working"}], "tasks": [{"employee_id": "employee_01", "station_id": station.id, "work_position": [work_tile.x, work_tile.y]}]}
		board.show_state(definitions, snapshot)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var cell := _cell_size(board, definitions.grid_size)
		var origin := (board.size - Vector2(definitions.grid_size) * cell) / 2.0
		var center := origin + (Vector2(work_tile) + Vector2.ONE * 0.5) * cell
		var crop_size := roundi(cell * 0.5)
		var crop := root.get_texture().get_image().get_region(Rect2i(Vector2i(center) - Vector2i.ONE * crop_size / 2, Vector2i.ONE * crop_size))
		crop.save_png("res://build/check/kitchen-facing-" + direction + ".png")
		hashes[direction] = crop.get_data().hex_encode().sha256_text()
		board.queue_free()
		await process_frame
	var unique: Dictionary[String, bool] = {}
	for image_hash: String in hashes.values():
		unique[image_hash] = true
	checks.expect(hashes.size() == 4 and unique.size() == 4,
		"four rendered station-work fixtures use four distinct directional chef images")


func _assert_english_pending_layout(tablet: bool) -> void:
	root.size = Vector2i(1024, 768) if tablet else Vector2i(1566, 720)
	await process_frame
	var screen := Harness.boot_main(self, "res://content/campaign/scenarios/split_duties.tres")
	screen.settings_locale.item_selected.emit(1)
	screen.settings_text_size.item_selected.emit(1)
	screen.start_button.pressed.emit()
	screen.advance(1.0)
	await _settle(screen)
	var before: Rect2 = screen.board.get_global_rect()
	var working := await _advance_to_work(screen)
	checks.expect(not working.is_empty(), "English large-text fixture reaches real work")
	if not working.is_empty():
		checks.expect(screen.submit_command("set_duty", working.id, "off").accepted, "English fixture requests a duty change during work")
		screen.advance(0.1)
		await _settle(screen)
		checks.expect(_employee_by_id(screen.latest_view.employees, working.id).pending_duty == "off", "English layout fixture actually has a pending duty")
		checks.expect(screen.board.get_global_rect() == before, "English pending duty cannot resize or move the board: %s -> %s" % [before, screen.board.get_global_rect()])
		var viewport_bounds := root.get_visible_rect()
		checks.expect(viewport_bounds.encloses(screen.board.get_global_rect()), "English pending duty keeps the board inside the actual viewport")
		checks.expect(viewport_bounds.encloses(screen.get_node("SafeArea/Layout/Kitchen/Body/Side").get_global_rect()), "English pending duty keeps the side panel inside the actual viewport")
		checks.expect(viewport_bounds.encloses(screen.get_node("SafeArea/Layout/Header").get_global_rect()), "English pending duty keeps the header inside the actual viewport: %s header=%s screen=%s safe=%s" % [viewport_bounds, screen.get_node("SafeArea/Layout/Header").get_global_rect(), screen.size, screen.safe_area.get_global_rect()])
		checks.expect(viewport_bounds.encloses(screen.pause_button.get_global_rect()), "English pending duty keeps time controls inside the actual viewport")
		checks.expect(viewport_bounds.encloses(screen.duty_buttons[-1].get_global_rect()), "English pending duty keeps staff controls inside the actual viewport")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/check/kitchen-screen-%s-en-pending.png" % ("tablet" if tablet else "phone"))
		if not tablet:
			screen.details_toggle.pressed.emit()
		await _settle(screen)
		checks.expect(screen.detail_panel.visible and screen.board.get_global_rect() == before, "English large-text details keep the same board area")
		var stable := true
		var activity_start: int = screen.simulation.tick
		var activity_texts: Dictionary = {}
		for second: int in 60:
			_advance_running(screen, 1.0)
			await process_frame
			await process_frame
			stable = stable and screen.board.get_global_rect() == before
			var text := ""
			for label: Label in screen.duty_labels:
				text += label.text + "\n"
			activity_texts[text] = true
		checks.expect(screen.simulation.tick == activity_start + 600 and activity_texts.size() > 1, "the activity fixture advances one minute and changes rendered staff text")
		checks.expect(stable, "English board remains stable through a minute of actual activity changes: tablet=%s" % tablet)
	screen.queue_free()
	await process_frame
