extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = ["res://tests/test_m4_determinism.gd", "res://tests/test_service_session.gd", "res://tests/test_m4_store.gd", "res://tests/test_restore_command_history.gd"]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		var suite: ChildHarness = load(script_path).new()
		await suite.run(tree)
		expect(suite.checked > 0, "the storage core suite executes checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
