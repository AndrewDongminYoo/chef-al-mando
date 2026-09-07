extends "res://tests/test_rules.gd"


func fresh() -> Definitions:
	return ResourceLoader.load("res://content/m2_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func run(_tree: SceneTree) -> void:
	sim_script = load(SIM_PATH) as GDScript
	_test_prepared_route()
	_test_raw_intermediate()
	_test_prepared_reservations()
	_test_prepared_path_failure()
	_test_raw_handoff_path_failure()
	_test_intermediate_deadline_and_cost()
	_test_metrics()


func _prepared(data: Definitions = null, quantity: int = 1, routes: GridRoutes = null) -> RefCounted:
	return sim_script.new(single() if data == null else data, routes, {"prep_quantities": {"salad": quantity}})


func _test_prepared_route() -> void:
	var sim := _prepared()
	expect(snapshot(sim).inventory.prepped_salad == 1 and snapshot(sim).inventory.vegetable == 21, "service derives prepared inventory from raw purchases")
	advance(sim, 1)
	expect(snapshot(sim).reserved.prepped_salad == 1 and snapshot(sim).reserved.vegetable == 0, "pickup reserves a prepared portion before raw ingredients")
	advance(sim, 11)
	expect(snapshot(sim).inventory.prepped_salad == 0 and snapshot(sim).inventory.vegetable == 21, "prepared pickup consumes the prepared portion without raw consumption")
	expect(not order(sim).raw_consumed and order(sim).get("uses_prepared", false), "prepared route records its source separately from raw consumption")
	advance(sim, 21)
	expect(order(sim).phase_id == "cook", "prepared pickup skips the preparation process")
	advance(sim, 136)
	expect(order(sim).state == "served" and snapshot(sim).accounting.revenue == 500, "prepared route completes at the original three-process boundary")
	advance(sim, 3000)
	expect(snapshot(sim).accounting.waste_cost == 6500 and snapshot(sim).accounting.profit == -8100, "served prepared cost is neither wasted nor charged twice")
	var invalid: RefCounted = sim_script.new(single(), null, {"prep_quantities": {"salad": 7}})
	expect(snapshot(invalid).closed and not snapshot(invalid).errors.is_empty(), "service rejects preparation beyond capacity")
	invalid = sim_script.new(single(), null, {"inventory": {"prepped_salad": 999}})
	expect(snapshot(invalid).closed and not snapshot(invalid).errors.is_empty(), "callers cannot supply invented prepared inventory")


func _test_raw_intermediate() -> void:
	var sim: RefCounted = sim_script.new(single())
	advance(sim, 21)
	expect(order(sim).phase_id == "prep", "raw pickup enters the preparation process")
	advance(sim, 36)
	expect(order(sim).phase_id == "prep" and order(sim).completion_tick == 66, "raw preparation occupies the cold station for thirty ticks")
	advance(sim, 166)
	expect(order(sim).state == "served" and snapshot(sim).inventory.vegetable == 21, "raw preparation adds thirty ticks without consuming ingredients twice")
	expect(snapshot(sim).inventory.prepped_salad == 0, "service preparation never adds another order's portion to the shared pool")
	sim = sim_script.new(single())
	command(sim, "set_duty", "employee_02", "off", 1, 1)
	command(sim, "set_duty", "employee_01", "off", 65, 2)
	advance(sim, 66)
	expect(order(sim).phase_id == "cook" and order(sim).get("intermediate_ready", false), "completed preparation leaves an order-owned intermediate")
	expect(order(sim).wait_reason == "no_responsible_employee" and snapshot(sim).tasks.is_empty(), "the intermediate fixture waits after releasing its preparation station")
	command(sim, "cancel_order", "order_01", null, 67, 3)
	advance(sim, 67)
	expect(not order(sim).get("intermediate_ready", true) and snapshot(sim).accounting.waste_cost == 100, "cancelling an intermediate clears it and records its raw cost once")


func _pair(raw_quantity: int) -> RefCounted:
	var data := single()
	data.order_count = 2
	data.arrival_interval_ticks = 1
	data.purchases = {"vegetable": raw_quantity, "grain": 0, "protein": 0}
	var station := Definitions.StationDef.new()
	station.id = "storage_02"
	station.role = "storage"
	station.tile = Vector2i(3, 1)
	station.work_position = Vector2i(3, 2)
	data.stations.append(station)
	var sim := _prepared(data)
	command(sim, "set_duty", "employee_01", "off", 1, 1)
	command(sim, "set_duty", "employee_02", "off", 1, 2)
	advance(sim, 3)
	expect(snapshot(sim).orders.size() == 2 and snapshot(sim).tasks.is_empty(), "both prepared competitors wait before the same assignment pass")
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	command(sim, "set_duty", "employee_02", "all", 4, 4)
	advance(sim, 4)
	return sim


func _test_prepared_reservations() -> void:
	var sim := _pair(1)
	expect(snapshot(sim).tasks.size() == 1 and snapshot(sim).reserved.prepped_salad == 1, "two employees cannot reserve the last prepared portion twice")
	expect(order(sim, 1).wait_reason == "missing_ingredients", "prepared shortage falls back only when sufficient raw stock exists")
	sim = _pair(2)
	expect(snapshot(sim).tasks.size() == 2 and snapshot(sim).reserved.prepped_salad == 1 and snapshot(sim).reserved.vegetable == 1, "second assignment atomically falls back to raw stock")
	advance(sim, 20)
	expect(snapshot(sim).inventory.vegetable == 0 and snapshot(sim).inventory.prepped_salad == 0, "concurrent routes consume their distinct inputs once")
	sim = _prepared()
	advance(sim, 1)
	command(sim, "cancel_order", "order_01", null, 2, 1)
	advance(sim, 2)
	expect(snapshot(sim).reserved.prepped_salad == 0 and snapshot(sim).inventory.prepped_salad == 1, "cancel before pickup releases the prepared reservation")
	sim = _prepared()
	advance(sim, 11)
	command(sim, "cancel_order", "order_01", null, 12, 1)
	advance(sim, 12)
	expect(snapshot(sim).inventory.prepped_salad == 0 and snapshot(sim).accounting.waste_cost == 100, "cancel after prepared pickup retains one portion's loss")
	advance(sim, 3000)
	expect(snapshot(sim).accounting.waste_cost == 6600, "closing counts remaining raw inventory and cancelled prepared cost once each")


func _test_prepared_path_failure() -> void:
	var data := single()
	var routes := GridRoutes.new(data.grid_size, data.blocked_tiles())
	var sim := _prepared(data, 1, routes)
	advance(sim, 1)
	var next: Array = snapshot(sim).employees[0].next_tile
	routes.grid.set_point_solid(Vector2i(next[0], next[1]), true)
	advance(sim, 2)
	expect(order(sim).wait_reason == "no_route" and snapshot(sim).tasks.is_empty(), "prepared pickup reports an actual blocked movement edge")
	expect(snapshot(sim).reserved.prepped_salad == 0 and snapshot(sim).inventory.prepped_salad == 1, "path failure before pickup releases prepared stock")
	data = single()
	routes = GridRoutes.new(data.grid_size, data.blocked_tiles())
	sim = _prepared(data, 1, routes)
	advance(sim, 21)
	next = snapshot(sim).employees[0].next_tile
	routes.grid.set_point_solid(Vector2i(next[0], next[1]), true)
	advance(sim, 22)
	expect(order(sim).wait_reason == "no_route" and order(sim).has_result, "prepared handoff survives a failed cooking route")
	expect(snapshot(sim).inventory.prepped_salad == 0 and snapshot(sim).reserved.prepped_salad == 0, "path failure after pickup does not restore consumed preparation")


func _test_intermediate_deadline_and_cost() -> void:
	var data := single()
	data.recipe_for("salad").patience_ticks = 65
	var sim: RefCounted = sim_script.new(data)
	advance(sim, 65)
	expect(order(sim).phase_id == "prep" and order(sim).completion_tick == 66, "deadline fixture reaches the last tick of raw preparation")
	advance(sim, 66)
	expect(order(sim).terminal_reason == "deadline" and not order(sim).get("intermediate_ready", true), "expiration precedes same-tick intermediate production")
	data = single()
	data.closing_tick = 66
	sim = sim_script.new(data)
	advance(sim, 66)
	expect(order(sim).terminal_reason == "service_closed" and not order(sim).get("intermediate_ready", true), "closing precedes same-tick intermediate production")
	sim = _prepared(null, 2)
	advance(sim, 11)
	command(sim, "cancel_order", "order_01", null, 12, 1)
	advance(sim, 3000)
	expect(snapshot(sim).inventory.prepped_salad == 1 and snapshot(sim).inventory.vegetable == 20, "mixed waste fixture retains raw stock and one unused prepared portion")
	expect(snapshot(sim).accounting.waste_cost == 6600 and snapshot(sim).accounting.profit == -8600, "raw leftovers, prepared leftovers, and cancelled input each contribute cost once")


func _test_raw_handoff_path_failure() -> void:
	var data := single()
	data.menu_ids = ["grill"]
	var routes := GridRoutes.new(data.grid_size, data.blocked_tiles())
	var sim: RefCounted = sim_script.new(data, routes)
	command(sim, "set_duty", "employee_02", "off", 1, 1)
	command(sim, "set_duty", "employee_01", "off", 125, 2)
	command(sim, "set_duty", "employee_02", "all", 126, 3)
	advance(sim, 126)
	expect(order(sim).phase_id == "cook" and order(sim).state == "moving" and order(sim).employee_id == "employee_02", "the raw intermediate passes from the preparation worker to the second worker")
	expect(order(sim).intermediate_ready and order(sim).result_position == [5, 2] and snapshot(sim).tasks[0].collection_index > 0, "the handoff route visits the order-owned intermediate before cooking")
	var next: Array = snapshot(sim).employees[1].next_tile
	var blocked := Vector2i(next[0], next[1])
	routes.grid.set_point_solid(blocked, true)
	advance(sim, 127)
	expect(order(sim).wait_reason == "no_route" and snapshot(sim).tasks.is_empty(), "a real blocked handoff edge releases the employee and cooking station")
	expect(order(sim).intermediate_ready and order(sim).result_position == [5, 2] and snapshot(sim).inventory.protein == 7, "failed collection preserves the intermediate location and consumed raw loss")
	expect(snapshot(sim).reserved.values().all(func(value: int) -> bool: return value == 0), "raw intermediate path failure leaves no ingredient reservation")
	routes.grid.set_point_solid(blocked, false)
	advance(sim, 3000)
	expect(order(sim).state == "served" and order(sim).intermediate_consumed and not order(sim).intermediate_ready, "the recovered handoff consumes the intermediate at cooking and serves once")
	expect(snapshot(sim).inventory.protein == 7 and order(sim).consumed_cost == 400, "handoff recovery does not consume a second raw portion")
	for boundary: int in [1, 11, 125, 126]:
		data = single()
		data.menu_ids = ["grill"]
		sim = sim_script.new(data)
		advance(sim, boundary)
		command(sim, "cancel_order", "order_01", null, boundary + 1, 1)
		advance(sim, boundary + 1)
		expect(order(sim).state == "cancelled" and snapshot(sim).tasks.is_empty(), "raw cancellation releases the active phase at tick " + str(boundary))
		expect(snapshot(sim).inventory.protein == (8 if boundary == 1 else 7) and snapshot(sim).accounting.waste_cost == (0 if boundary == 1 else 400), "raw cancellation retains only the cost consumed before tick " + str(boundary))


func _test_metrics() -> void:
	var sim: RefCounted = sim_script.new(single(), null, {"duties": {"employee_01": "off", "employee_02": "off"}})
	command(sim, "set_duty", "employee_01", "all", 11, 1)
	advance(sim, 11)
	var metrics: Dictionary = order(sim).get("metrics", {})
	expect(metrics.get("no_responsible_employee", -1) == 10, "ten ticks without a responsible employee produce exactly ten waiting ticks")
	advance(sim, 3000)
	metrics = order(sim).get("metrics", {})
	var total: int = 0
	for key: String in ["missing_ingredients", "no_responsible_employee", "station_in_use", "no_route", "moving", "working"]:
		total += metrics.get(key, -10000)
	expect(total == order(sim).get("ended_tick", 0) - order(sim).arrival_tick, "waiting, movement, and work partition the order residence time")
	expect(metrics.get("responsible_employee_busy", -1) == 0, "disabled employees are not counted as busy employees")
	var exposed := snapshot(sim)
	if exposed.has("metrics"):
		exposed.metrics.station_reserved_ticks.clear()
		expect(not snapshot(sim).metrics.station_reserved_ticks.is_empty(), "metrics snapshots cannot erase simulation counters")
