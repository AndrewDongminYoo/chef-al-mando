extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = [
	"res://tests/test_schedule_generator.gd",
	"res://tests/test_service_seed.gd",
	"res://tests/test_mise_items.gd",
	"res://tests/test_seed_gate.gd"
]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		if not ResourceLoader.exists(script_path):
			expect(false, "required mise suite is missing: " + script_path)
			continue
		var suite: ChildHarness = load(script_path).new()
		await suite.run(tree)
		expect(suite.checked > 0, "mise child suite must run checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
