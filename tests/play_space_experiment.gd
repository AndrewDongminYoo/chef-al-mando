extends SceneTree

const Experiment := preload("res://tests/fixtures/space_experiment.gd")
const Harness := preload("res://tests/harness.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var options := {"--scenario": "hot_queue", "--layout": "original", "--duties": "all"}
	var args := OS.get_cmdline_user_args()
	if args.size() % 2 != 0:
		_fail_usage()
		return
	for index: int in range(0, args.size(), 2):
		if not options.has(args[index]):
			_fail_usage()
			return
		options[args[index]] = args[index + 1]
	if options["--scenario"] not in Experiment.SCENARIOS or options["--layout"] not in ["original", "clustered"] or options["--duties"] not in Experiment.DUTIES:
		_fail_usage()
		return
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: the playable spatial experiment requires a rendered window")
		quit(1)
		return
	var scenario := Experiment.scenario(options["--scenario"])
	if scenario == null or not scenario.validate().is_empty():
		printerr("FAIL: the spatial scenario is invalid")
		quit(1)
		return
	var temporary := "user://space_experiment_%d.tres" % Time.get_ticks_usec()
	if ResourceSaver.save(scenario, temporary) != OK:
		printerr("FAIL: cannot prepare the spatial experiment resource")
		quit(1)
		return
	root.size = Vector2i(1566, 720)
	root.title = "Chef al Mando · 공간 규칙 실험"
	var screen := Harness.boot_main(self, temporary)
	if screen == null:
		DirAccess.remove_absolute(temporary)
		printerr("FAIL: cannot open the spatial experiment screen")
		quit(1)
		return
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(temporary))
	var policy := Experiment.policy(scenario.id, options["--layout"], options["--duties"])
	for choice: Dictionary in policy.preparation:
		var result: Dictionary = screen.submit_preparation(choice.kind, choice.target_id, choice.value)
		if not result.accepted:
			printerr("FAIL: spatial experiment preparation rejected: " + str(result))
			quit(1)
			return
	screen.preparation_panel.show_tab(1)
	screen.set_process(true)
	print("SPACE_PLAY scenario=", scenario.id, " layout=", options["--layout"], " duties=", options["--duties"],
		" served_goal=", scenario.minimum_served, " profit_goal=", scenario.minimum_profit)
	print("SPACE_PLAY uses temporary settings and does not write campaign progress")


func _fail_usage() -> void:
	printerr("FAIL: usage: --scenario <hot_queue|long_route> --layout <original|clustered> --duties <all|dedicated>")
	quit(1)
