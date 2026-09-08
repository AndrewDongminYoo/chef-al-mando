extends RefCounted

## Shared base for headless suites and the rendered capture script.

var checked: int = 0
var failures: int = 0


func expect(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


## Suites override this; the base fails so that a suite without a body cannot pass.
func run(_tree: SceneTree) -> void:
	expect(false, "suite must override run")


## Instantiates the standalone service scene with frame processing disabled.
## Campaign tests inspect the project's entry scene separately.
static func boot_main(tree: SceneTree, scenario_path: String = "res://content/m1_first_service.tres") -> Control:
	var main_scene: String = "res://presentation/main.tscn"
	if main_scene.is_empty() or not ResourceLoader.exists(main_scene):
		return null
	var scene := load(main_scene) as PackedScene
	if scene == null:
		return null
	var screen := scene.instantiate() as Control
	screen.set("scenario_path", scenario_path)
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen
