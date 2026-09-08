extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = ["res://tests/test_m3_content.gd", "res://tests/test_campaign_progress.gd", "res://tests/test_campaign_store.gd", "res://tests/test_m3_playthrough.gd", "res://tests/test_m3_ui.gd"]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		if not ResourceLoader.exists(script_path):
			expect(false, "required M3 suite is missing: " + script_path)
			continue
		var suite: ChildHarness = load(script_path).new()
		await suite.run(tree)
		expect(suite.checked > 0, "M3 child suite must run checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
