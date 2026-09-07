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


## Instantiates the project's main scene under `tree.root` with frame processing disabled.
## Returns null when the main scene setting is empty or the scene cannot be loaded.
static func boot_main(tree: SceneTree) -> Control:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty() or not ResourceLoader.exists(main_scene):
		return null
	var scene := load(main_scene) as PackedScene
	if scene == null:
		return null
	var screen := scene.instantiate() as Control
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen
