extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = [
	"res://tests/test_content.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_determinism.gd",
	"res://tests/test_m1_ui.gd",
]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		if not ResourceLoader.exists(script_path):
			expect(false, "required M1 suite is missing: " + script_path)
			continue
		var suite_script := load(script_path) as GDScript
		var suite: ChildHarness = suite_script.new()
		await suite.run(tree)
		expect(suite.checked > 0, "M1 child suite must run checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
