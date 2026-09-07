extends "res://tests/test_determinism.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")


func fresh() -> Definitions:
	return ResourceLoader.load("res://content/m2_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func run(_tree: SceneTree) -> void:
	driver_script = load(DRIVER_PATH) as GDScript
	var first := _prepared_replay(1, [16667, 5001, 220003])
	var repeat := _prepared_replay(1, [16667, 5001, 220003])
	var fast := _prepared_replay(4, [999999, 127, 33001])
	expect(first.state_hash() == repeat.state_hash(), "M2 preparation, layout, duties, and service commands repeat the final hash")
	expect(first.state_hash() == fast.state_hash(), "M2 real tick drivers preserve the same state at one and four speed")
	_test_pause_and_accumulator()
	_measure_choices()
	_test_rotation_changes_service_route()
	print("M2_COMMAND_LOG_HASH ", first.state_hash())


func _prepared_replay(speed: int, frames: Array[int]) -> ServiceSim:
	var plan := PreparationPlan.new(fresh())
	_prep_command(plan, "set_prep", "grill", 2, 1)
	_prep_command(plan, "move_station", "pass_01", "left", 2)
	_prep_command(plan, "set_duty", "employee_01", "cold", 3)
	_prep_command(plan, "set_duty", "employee_02", "hot", 4)
	var committed := _prep_command(plan, "start", "", null, 5)
	var sim := ServiceSim.new(committed.definitions, null, committed.options)
	var driver: RefCounted = driver_script.new(sim)
	driver.call("set_speed", speed)
	driver.call("set_paused", false)
	for command: Dictionary in COMMAND_LOG:
		_drive_to(driver, sim, command.submit_tick, frames, speed)
		expect(sim.enqueue_command(command).accepted, "the M2 recorded command is accepted: " + str(command.sequence))
	_drive_to(driver, sim, 3000, frames, speed)
	expect(sim.tick == 3000 and driver.get("accumulator_us") == 0, "M2 driver reaches closing without dropping game time")
	return sim


func _prep_command(plan: PreparationPlan, kind: String, target: String, value: Variant, sequence: int) -> Dictionary:
	var result := plan.apply_command({"kind": kind, "target_id": target, "value": value, "apply_tick": 0, "sequence": sequence})
	expect(result.accepted, "recorded preparation command is accepted: " + kind)
	return result


func _measure_choices() -> void:
	var runs: Dictionary = {}
	for policy: String in ["baseline", "prep", "placement", "priority", "combined"]:
		var data := fresh()
		var plan := PreparationPlan.new(data)
		var sequence: int = 0
		if policy in ["prep", "combined"]:
			sequence += 1
			_prep_command(plan, "set_prep", "grill", 2, sequence)
		if policy in ["placement", "combined"]:
			sequence += 1
			_prep_command(plan, "move_station", "pass_01", "left", sequence)
		var committed := _prep_command(plan, "start", "", null, sequence + 1)
		var sim := ServiceSim.new(committed.definitions, null, committed.options)
		sequence = 0
		while not sim.closed:
			sim.step()
			if policy in ["priority", "combined"] and not sim.closed:
				for event: Dictionary in sim.events():
					if event.kind != "order_arrived":
						continue
					for order: Dictionary in sim.snapshot().orders:
						if order.id == event.order_id and order.recipe_id == "grill":
							sequence += 1
							expect(sim.enqueue_command({"kind": "set_priority", "target_id": order.id,
								"value": 2, "apply_tick": sim.tick + 1, "sequence": sequence}).accepted, "comparison priority is applied one tick after grill arrival")
		var view := sim.snapshot()
		expect(view.orders.size() == 20 and view.tick == 3000 and view.accounting.purchased_cost == 6600, "comparison preserves twenty orders, closing time, and purchases")
		var order_times: Array[Dictionary] = []
		for order: Dictionary in view.orders:
			var elapsed: int = 0
			for key: String in ["missing_ingredients", "no_responsible_employee", "station_in_use", "no_route", "moving", "working"]:
				elapsed += order.metrics[key]
			expect(elapsed == order.ended_tick - order.arrival_tick, "comparison order times partition residence: " + policy + "/" + order.id)
			order_times.append({"id": order.id, "ended_tick": order.ended_tick, "state": order.state})
		runs[policy] = {"accounting": view.accounting, "metrics": view.metrics, "order_times": order_times, "hash": sim.state_hash()}
		print("M2_COMPARISON ", policy, " ", JSON.stringify(runs[policy], "", true))
	for policy: String in ["prep", "placement", "priority"]:
		expect(runs[policy].metrics != runs.baseline.metrics, "the fixed comparison measures a time effect for " + policy)
	var outcome_changed: bool = false
	for policy: String in ["prep", "placement", "priority", "combined"]:
		if runs[policy].accounting.served != runs.baseline.accounting.served or runs[policy].accounting.profit != runs.baseline.accounting.profit:
			outcome_changed = true
	expect(outcome_changed, "at least one approved comparison changes served count or profit")


func _test_rotation_changes_service_route() -> void:
	var original := _placement_run(false)
	var rotated := _placement_run(true)
	expect(original.path_size == 7 and rotated.path_size == 9, "a committed pass rotation changes the actual serving route from six to eight edges")
	expect(rotated.moving_ticks == original.moving_ticks + 10, "two added serving edges consume ten additional movement ticks")


func _placement_run(rotated: bool) -> Dictionary:
	var data := fresh()
	data.order_count = 1
	data.first_arrival_tick = 1
	data.menu_ids = ["salad"]
	var plan := PreparationPlan.new(data)
	if rotated:
		_prep_command(plan, "rotate_station", "pass_01", null, 1)
	var committed := _prep_command(plan, "start", "", null, 2)
	var placement_sim := ServiceSim.new(committed.definitions, null, committed.options)
	var path_size: int = 0
	while not placement_sim.closed:
		placement_sim.step()
		var view := placement_sim.snapshot()
		if not view.orders.is_empty() and view.orders[0].phase_id == "serve" and view.orders[0].state == "moving" and path_size == 0:
			path_size = view.tasks[0].path.size()
	var order: Dictionary = placement_sim.snapshot().orders[0]
	expect(order.state == "served" and path_size > 0, "the rotation fixture must reach a moving serving task and complete service")
	return {"path_size": path_size, "moving_ticks": order.metrics.moving}
