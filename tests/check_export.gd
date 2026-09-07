extends SceneTree


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	if not FileAccess.file_exists("res://content/m1_first_service.tres.remap"):
		printerr("FAIL: the check must read converted content from an exported pack")
		quit(1)
		return
	var data: Resource = load("res://content/m1_first_service.tres")
	if data == null or not data.call("validate").is_empty():
		printerr("FAIL: exported kitchen content is invalid")
		quit(1)
		return
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen: Control = scene.instantiate()
	root.add_child(screen)
	screen.set_process(false)
	await process_frame
	var can_start: bool = not screen.get("start_button").disabled
	screen.get("start_button").pressed.emit()
	screen.call("advance", 1.0)
	var sim: RefCounted = screen.get("simulation")
	var started: bool = can_start and sim.get("tick") == 10 and sim.call("snapshot").orders.size() == 1
	screen.queue_free()
	await process_frame
	if not started:
		printerr("FAIL: the exported screen must start service and receive the first order")
		quit(1)
		return
	print("PASS: exported M1 content and first order")
	quit(0)
