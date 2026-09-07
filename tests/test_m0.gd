extends RefCounted

var checked: int = 0
var failures: int = 0


func expect(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func run(tree: SceneTree) -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty() or not ResourceLoader.exists(main_scene):
		expect(false, "main scene must exist")
		return
	var scene := load(main_scene) as PackedScene
	var screen = scene.instantiate()
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	expect(screen.elapsed_seconds == 0.0, "counter starts at zero")
	screen._process(1.0)
	expect(screen.elapsed_seconds == 0.0, "ready screen must not advance")
	screen.get_node("SafeArea/Layout/Controls/Start").pressed.emit()
	screen._process(1.0)
	expect(screen.elapsed_seconds == 1.0, "start advances the counter")
	screen.get_node("SafeArea/Layout/Controls/Pause").pressed.emit()
	screen._process(10.0)
	expect(screen.elapsed_seconds == 1.0, "pause freezes the counter")
	screen.get_node("SafeArea/Layout/Controls/Resume").pressed.emit()
	screen._process(1.0)
	expect(screen.elapsed_seconds == 2.0, "resume continues without resetting")
	screen.get_node("Lifecycle").notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	screen._process(10.0)
	expect(screen.elapsed_seconds == 2.0, "background notification freezes the counter")
	screen.get_node("Lifecycle").notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	screen._process(10.0)
	expect(screen.elapsed_seconds == 2.0, "foreground must not resume automatically")
	expect(not screen.get_node("SafeArea/Layout/Controls/Resume").disabled, "resume remains usable")
	screen.get_node("SafeArea/Layout/Controls/Resume").pressed.emit()
	screen._process(1.0)
	expect(screen.elapsed_seconds == 3.0, "manual resume excludes background time")
	expect(screen.has_method("_apply_safe_area"), "safe area must support inset changes without a resize")
	if screen.has_method("_apply_safe_area"):
		var scale_to_screen := Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2.ZERO)
		screen._apply_safe_area(Rect2i(100, 0, 2460, 1440), scale_to_screen.affine_inverse())
		expect(screen.get_node("SafeArea").offset_left == 74.0, "physical left inset converts to logical units")
		expect(screen.get_node("SafeArea").offset_right == -24.0, "unobscured right edge keeps padding")
		screen._apply_safe_area(Rect2i(0, 0, 2460, 1440), scale_to_screen.affine_inverse())
		expect(screen.get_node("SafeArea").offset_left == 24.0, "rotation releases the old left inset")
		expect(screen.get_node("SafeArea").offset_right == -74.0, "rotation applies the new right inset without resizing")
	screen.queue_free()
	await tree.process_frame
