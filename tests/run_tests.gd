extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--suite" or args[1] != "m0":
		printerr("FAIL: supported suite is m0")
		quit(1)
		return
	var suite_script := load("res://tests/test_m0.gd") as GDScript
	if suite_script == null or not suite_script.can_instantiate():
		printerr("FAIL: cannot load m0 suite")
		quit(1)
		return
	var suite = suite_script.new()
	await suite.run(self)
	if suite.checked == 0 or suite.failures > 0:
		printerr("FAIL: m0 checks=%d failures=%d" % [suite.checked, suite.failures])
		quit(1)
		return
	print("PASS: m0 checks=%d failures=0" % suite.checked)
	quit(0)
