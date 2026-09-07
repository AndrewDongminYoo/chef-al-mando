extends SceneTree

## Manual desktop tool: renders the M0 screen in a real window, saves two screenshots under
## build/check, and checks that rendered hit targets and one touch each produce one action.
## Not part of scripts/check.sh because it needs a rendered window; see docs/notes/m0-verification.md.
## Keep the window focused while it runs: losing focus pauses the counter through the lifecycle adapter.

const Harness := preload("res://tests/harness.gd")
const KitchenScreen := preload("res://presentation/main.gd")

var checks := Harness.new()
var touch_actions: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: capture requires a rendered window")
		quit(1)
		return
	var screen := Harness.boot_main(self) as KitchenScreen
	if screen == null:
		printerr("FAIL: main scene must exist")
		quit(1)
		return
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/check")
	await save_frame("res://build/check/m0-ready.png")
	await click(screen.start_button)
	checks.expect(screen.is_running(), "start hit target starts the counter")
	screen.advance(12.3)
	await click(screen.pause_button)
	checks.expect(not screen.is_running(), "pause hit target stops the counter")
	await save_frame("res://build/check/m0-paused.png")
	await click(screen.resume_button)
	checks.expect(screen.is_running(), "resume hit target resumes the counter")
	screen.pause_button.pressed.connect(func() -> void: touch_actions += 1)
	await tap(screen_point(screen.pause_button), _touch_event)
	checks.expect(touch_actions == 1 and not screen.is_running(), "one touch pauses exactly once (actions=%d)" % touch_actions)
	checks.expect(screen.get("input_actions") == 4, "the installed diagnostic reader counts each rendered button action once")
	print("Touch actions=%d" % touch_actions)
	print("Rendered input failures=%d" % checks.failures)
	screen.queue_free()
	await process_frame
	quit(1 if checks.failures > 0 else 0)


func screen_point(button: Button) -> Vector2:
	return root.get_screen_transform() * button.get_global_rect().get_center()


## Sends a press and a release built by `make_event(point, pressed)`, one frame apart.
func tap(point: Vector2, make_event: Callable) -> void:
	for pressed: bool in [true, false]:
		var event: InputEvent = make_event.call(point, pressed)
		Input.parse_input_event(event)
		await process_frame


func click(button: Button) -> void:
	var point := screen_point(button)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await tap(point, _mouse_event)


func _mouse_event(point: Vector2, pressed: bool) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _touch_event(point: Vector2, pressed: bool) -> InputEvent:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = pressed
	return touch


func save_frame(file_path: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(file_path)
	checks.expect(result == OK, "could not save rendered frame")
