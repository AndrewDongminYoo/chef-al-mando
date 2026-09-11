extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = ["res://tests/test_preparation.gd", "res://tests/test_space_placement.gd", "res://tests/test_space_ui.gd", "res://tests/test_m2_rules.gd", "res://tests/test_m2_determinism.gd", "res://tests/test_m2_content.gd", "res://tests/test_m2_ui.gd", "res://tests/test_service_feedback.gd"]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		if not ResourceLoader.exists(script_path):
			expect(false, "required M2 suite is missing: " + script_path)
			continue
		var suite: ChildHarness = load(script_path).new()
		await suite.run(tree)
		expect(suite.checked > 0, "M2 child suite must run checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
