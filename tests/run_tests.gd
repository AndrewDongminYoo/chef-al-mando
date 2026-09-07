extends SceneTree

const Harness := preload("res://tests/harness.gd")
## Required suites are registered here even before their script exists, so that a missing
## suite fails as "cannot load" instead of passing or looking like a typo.
const SUITES := {
	"m0": "res://tests/test_m0.gd",
	"m1": "res://tests/test_m1.gd",
}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--suite" or not SUITES.has(args[1]):
		printerr("FAIL: usage is --suite <%s>" % "|".join(PackedStringArray(SUITES.keys())))
		quit(1)
		return
	var suite_name: String = args[1]
	var suite_script := load(SUITES[suite_name]) as GDScript
	if suite_script == null:
		printerr("FAIL: cannot load %s suite" % suite_name)
		quit(1)
		return
	var suite: Harness = suite_script.new()
	await suite.run(self)
	if suite.checked == 0 or suite.failures > 0:
		printerr("FAIL: %s checks=%d failures=%d" % [suite_name, suite.checked, suite.failures])
		quit(1)
		return
	print("PASS: %s checks=%d failures=0" % [suite_name, suite.checked])
	quit(0)
