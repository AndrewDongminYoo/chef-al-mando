extends SceneTree

var failures: int = 0
var touch_actions: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: capture requires a rendered window")
		quit(1)
		return
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var screen = load(main_scene).instantiate()
	root.add_child(screen)
	screen.set_process(false)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/check")
	await save_frame("res://build/check/m0-ready.png")
	await click(screen.get_node("SafeArea/Layout/Controls/Start"))
	if not screen.running:
		failures += 1
		printerr("FAIL: start hit target did not start the counter")
	screen._process(12.3)
	await click(screen.get_node("SafeArea/Layout/Controls/Pause"))
	if screen.running:
		failures += 1
		printerr("FAIL: pause hit target did not stop the counter")
	await save_frame("res://build/check/m0-paused.png")
	await click(screen.get_node("SafeArea/Layout/Controls/Resume"))
	if not screen.running:
		failures += 1
		printerr("FAIL: resume hit target did not resume the counter")
	var pause_button := screen.get_node("SafeArea/Layout/Controls/Pause") as Button
	pause_button.pressed.connect(func() -> void: touch_actions += 1)
	var touch_point := root.get_screen_transform() * pause_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = touch_point
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await process_frame
	if touch_actions != 1 or screen.running:
		failures += 1
		printerr("FAIL: one touch must pause exactly once (actions=%d)" % touch_actions)
	print("Touch actions=%d" % touch_actions)
	print("Rendered input failures=%d" % failures)
	screen.queue_free()
	await process_frame
	quit(1 if failures else 0)


func click(button: Button) -> void:
	var point := root.get_screen_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func save_frame(file_path: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(file_path)
	if result != OK:
		failures += 1
		printerr("FAIL: could not save rendered frame")
