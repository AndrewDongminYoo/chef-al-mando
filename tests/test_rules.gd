extends "res://tests/harness.gd"

const Definitions := preload("res://content/definitions.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")
const SIM_PATH := "res://sim/service_sim.gd"
var sim_script: GDScript


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists(SIM_PATH):
		expect(false, "the service simulation must exist")
		return
	sim_script = load(SIM_PATH) as GDScript
	_test_invalid_load()
	_test_process_boundaries()
	_test_cancel_and_last_ingredient()
	_test_expiration_and_closing()
	_test_assignment_and_commands()
	_test_handoff_and_path_failure()
	_test_work_positions_and_cooking_duty()
	_test_default_service()


func fresh() -> Definitions:
	return ResourceLoader.load("res://content/m1_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func single() -> Definitions:
	var data := fresh()
	data.order_count = 1
	data.first_arrival_tick = 1
	data.menu_ids = ["salad"]
	return data


func _test_invalid_load() -> void:
	var data := fresh()
	data.ingredients[0] = null
	var sim: RefCounted = sim_script.new(data)
	var view := snapshot(sim)
	expect(view.closed and not view.errors.is_empty(), "a missing ingredient definition returns a readable rejected state")
	expect(view.accounting is Dictionary and view.accounting.is_empty(), "invalid content must not calculate or display accounting")
	sim.call("step")
	expect(sim.get("tick") == 0 and view.orders.is_empty(), "invalid content cannot start a service")


func advance(sim: RefCounted, target: int) -> void:
	while sim.get("tick") < target and not sim.get("closed"):
		sim.call("step")


func snapshot(sim: RefCounted) -> Dictionary:
	return sim.call("snapshot")


func order(sim: RefCounted, index: int = 0) -> Dictionary:
	return snapshot(sim).orders[index]


func command(sim: RefCounted, kind: String, target: String, value: Variant, at: int, sequence: int) -> Dictionary:
	return sim.call("enqueue_command", {
		"kind": kind, "target_id": target, "value": value,
		"apply_tick": at, "sequence": sequence,
	})


func _test_process_boundaries() -> void:
	var sim: RefCounted = sim_script.new(single())
	expect(snapshot(sim).orders.is_empty(), "tick zero has no orders")
	advance(sim, 1)
	expect(order(sim).state == "moving", "pickup begins with movement")
	expect(snapshot(sim).inventory.vegetable == 22 and snapshot(sim).reserved.vegetable == 1, "assignment reserves without consuming")
	advance(sim, 10)
	expect(order(sim).state == "moving" and not order(sim).raw_consumed, "arrival does not start work on the same tick")
	advance(sim, 11)
	expect(order(sim).state == "working" and order(sim).completion_tick == 21, "pickup starts after arrival and lasts ten ticks")
	expect(snapshot(sim).inventory.vegetable == 21 and snapshot(sim).reserved.vegetable == 0, "pickup consumes one reserved ingredient")
	advance(sim, 21)
	expect(order(sim).phase_id == "cook" and order(sim).state == "moving", "pickup releases its station before cooking movement")
	advance(sim, 36)
	expect(order(sim).state == "working" and order(sim).completion_tick == 96, "cooking starts after three grid tiles")
	advance(sim, 126)
	expect(order(sim).phase_id == "serve" and order(sim).completion_tick == 136, "serving includes six tiles and ten work ticks")
	advance(sim, 136)
	expect(order(sim).state == "served" and snapshot(sim).accounting.revenue == 500, "completed service awards revenue once")
	expect(snapshot(sim).inventory.vegetable == 21, "later processes do not consume raw ingredients again")
	advance(sim, 3000)
	expect(snapshot(sim).accounting.profit == -8100 and snapshot(sim).accounting.cash == 1900, "profit subtracts purchases and labor once")
	expect(snapshot(sim).accounting.waste_cost == 6500, "closing waste includes remaining purchased inventory")


func _test_cancel_and_last_ingredient() -> void:
	var sim: RefCounted = sim_script.new(single())
	advance(sim, 1)
	command(sim, "cancel_order", "order_01", null, 2, 1)
	advance(sim, 2)
	expect(order(sim).state == "cancelled" and snapshot(sim).tasks.is_empty(), "cancellation releases moving assignment")
	expect(snapshot(sim).inventory.vegetable == 22 and snapshot(sim).reserved.vegetable == 0, "cancel before pickup restores availability")
	expect(snapshot(sim).employees[0].progress == 0 and snapshot(sim).employees[0].tile == [2, 4], "moving cancellation restores the edge origin")
	sim = sim_script.new(single())
	advance(sim, 11)
	command(sim, "cancel_order", "order_01", null, 12, 1)
	advance(sim, 12)
	expect(snapshot(sim).inventory.vegetable == 21 and snapshot(sim).accounting.waste_cost == 100, "cancel after pickup retains consumed loss")
	expect(snapshot(sim).tasks.is_empty() and snapshot(sim).reserved.values().all(func(value: int) -> bool: return value == 0), "cancel after consumption releases every reservation")
	var data := single()
	data.purchases.vegetable = 1
	var second_storage := Definitions.StationDef.new()
	second_storage.id = "storage_02"
	second_storage.role = "storage"
	second_storage.tile = Vector2i(3, 1)
	second_storage.work_position = Vector2i(3, 2)
	data.stations.append(second_storage)
	sim = _waiting_pair(data)
	expect(snapshot(sim).tasks.is_empty() and snapshot(sim).orders.size() == 2 and snapshot(sim).reserved.vegetable == 0, "two waiting orders reach the same assignment pass with the last ingredient unreserved")
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	command(sim, "set_duty", "employee_02", "all", 4, 4)
	advance(sim, 4)
	expect(snapshot(sim).tasks.size() == 1 and snapshot(sim).reserved.vegetable == 1, "last ingredient belongs to only one assignment")
	expect(order(sim, 1).wait_reason == "missing_ingredients", "second employee cannot claim a reserved ingredient")
	advance(sim, 139)
	expect(snapshot(sim).inventory.vegetable == 0 and order(sim, 1).state == "waiting", "last ingredient is consumed only once")
	data = single()
	data.menu_ids = ["soup"]
	data.order_count = 2
	data.arrival_interval_ticks = 1
	data.purchases.vegetable = 4
	data.purchases.grain = 1
	sim = sim_script.new(data)
	advance(sim, 2)
	expect(order(sim, 1).wait_reason == "missing_ingredients" and snapshot(sim).reserved.vegetable == 2 and snapshot(sim).reserved.grain == 1, "missing grain prevents a partial vegetable reservation for the second soup")
	advance(sim, 11)
	expect(snapshot(sim).inventory.vegetable == 2 and snapshot(sim).inventory.grain == 0, "the soup shortage fixture actually exhausts grain while vegetables remain")
	expect(snapshot(sim).reserved.values().all(func(value: int) -> bool: return value == 0) and snapshot(sim).tasks.size() == 1, "grain shortage leaves no partial reservation or assignment")


func _test_expiration_and_closing() -> void:
	var data := single()
	data.recipe_for("salad").patience_ticks = 135
	var sim: RefCounted = sim_script.new(data)
	advance(sim, 135)
	expect(order(sim).state == "working" and order(sim).completion_tick == 136, "deadline fixture reaches serving before the collision")
	advance(sim, 136)
	expect(order(sim).state == "expired" and order(sim).terminal_reason == "deadline", "deadline wins over same-tick service completion")
	expect(snapshot(sim).accounting.revenue == 0 and snapshot(sim).tasks.is_empty(), "expiration releases tasks without revenue")
	data = single()
	data.closing_tick = 136
	sim = sim_script.new(data)
	advance(sim, 136)
	expect(order(sim).terminal_reason == "service_closed" and snapshot(sim).accounting.revenue == 0, "closing wins over same-tick completion")
	expect(snapshot(sim).accounting.waste_cost == 6600 and snapshot(sim).accounting.profit == -8600, "closing loss is not subtracted twice")
	var closed_hash: String = sim.call("state_hash")
	sim.call("step")
	expect(sim.call("state_hash") == closed_hash, "a closed service cannot advance or award revenue")
	data.recipe_for("salad").patience_ticks = 135
	sim = sim_script.new(data)
	advance(sim, 136)
	expect(order(sim).terminal_reason == "deadline", "deadline reason wins when closing also expires the order")


func _waiting_pair(data: Definitions = null) -> RefCounted:
	if data == null:
		data = single()
	data.order_count = 2
	data.arrival_interval_ticks = 1
	var sim: RefCounted = sim_script.new(data)
	command(sim, "set_duty", "employee_01", "off", 1, 1)
	command(sim, "set_duty", "employee_02", "off", 1, 2)
	advance(sim, 3)
	return sim


func _test_assignment_and_commands() -> void:
	var sim := _waiting_pair()
	expect(order(sim).wait_reason == "no_responsible_employee", "off-duty employees report a readable wait reason")
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	command(sim, "set_priority", "order_02", 2, 4, 4)
	advance(sim, 4)
	expect(snapshot(sim).tasks[0].order_id == "order_02", "player priority precedes the earlier deadline")
	expect(order(sim).wait_detail == "responsible_employee_busy", "a responsible but occupied employee has a distinct detail")
	sim = _waiting_pair()
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	advance(sim, 4)
	expect(snapshot(sim).tasks[0].order_id == "order_01", "equal priority uses the earlier deadline")
	var data := single()
	data.menu_ids = ["salad", "soup"]
	data.recipe_for("salad").patience_ticks = 401
	data.recipe_for("soup").patience_ticks = 400
	sim = _waiting_pair(data)
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	advance(sim, 4)
	expect(order(sim).deadline_tick == order(sim, 1).deadline_tick and snapshot(sim).tasks[0].order_id == "order_01", "equal deadlines use the stable order ID")
	sim = _waiting_pair()
	command(sim, "set_priority", "order_01", 2, 4, 3)
	command(sim, "set_priority", "order_01", 0, 4, 4)
	advance(sim, 4)
	expect(order(sim).priority == 0, "same-tick commands apply in sequence order")
	var before: String = sim.call("state_hash")
	for invalid: Array in [
		["unknown", "order_01", 1, 5, 5],
		["set_priority", "missing", 1, 5, 5],
		["set_priority", "order_01", 3, 5, 5],
		["set_priority", "order_01", 1, 4, 5],
		["set_priority", "order_01", 1, 5, 4],
		["set_duty", "employee_01", "missing", 5, 5],
	]:
		var result := command(sim, invalid[0], invalid[1], invalid[2], invalid[3], invalid[4])
		expect(not result.accepted and sim.call("state_hash") == before, "invalid command must not mutate state: " + str(invalid))
	command(sim, "cancel_order", "order_01", null, 5, 5)
	advance(sim, 5)
	before = sim.call("state_hash")
	expect(not command(sim, "set_priority", "order_01", 2, 6, 6).accepted and sim.call("state_hash") == before, "terminal orders reject commands without mutation")


func _test_handoff_and_path_failure() -> void:
	var data := single()
	var routes := GridRoutes.new(data.grid_size, data.blocked_tiles())
	var sim: RefCounted = sim_script.new(data, routes)
	advance(sim, 1)
	command(sim, "set_duty", "employee_01", "off", 2, 1)
	advance(sim, 2)
	expect(snapshot(sim).employees[0].duty == "all" and snapshot(sim).employees[0].pending_duty == "off", "duty remains pending during movement")
	advance(sim, 21)
	expect(snapshot(sim).employees[0].duty == "off" and snapshot(sim).tasks[0].employee_id == "employee_02", "duty changes after the current process")
	expect(order(sim).result_position == [2, 2] and not order(sim).carrying, "handoff preserves the pickup result position")
	var next_tile: Array = snapshot(sim).employees[1].next_tile
	routes.grid.set_point_solid(Vector2i(next_tile[0], next_tile[1]), true)
	advance(sim, 22)
	expect(order(sim).wait_reason == "no_route" and snapshot(sim).tasks.is_empty(), "runtime path failure releases the assignment")
	expect(order(sim).result_position == [2, 2] and snapshot(sim).inventory.vegetable == 21, "failure before collection preserves the result and consumed stock")
	data = single()
	routes = GridRoutes.new(data.grid_size, data.blocked_tiles())
	sim = sim_script.new(data, routes)
	advance(sim, 1)
	command(sim, "set_duty", "employee_01", "off", 2, 1)
	advance(sim, 36)
	expect(order(sim).carrying, "the second employee actually collects the result")
	next_tile = snapshot(sim).employees[1].next_tile
	var origin: Array = snapshot(sim).employees[1].tile
	routes.grid.set_point_solid(Vector2i(next_tile[0], next_tile[1]), true)
	advance(sim, 37)
	expect(order(sim).result_position == origin and not order(sim).carrying, "failure after collection drops the result at the recovered tile")
	expect(snapshot(sim).inventory.vegetable == 21 and snapshot(sim).reserved.vegetable == 0, "path recovery never restores consumed ingredients")
	data = single()
	routes = GridRoutes.new(data.grid_size, data.blocked_tiles())
	sim = sim_script.new(data, routes)
	advance(sim, 1)
	next_tile = snapshot(sim).employees[0].next_tile
	routes.grid.set_point_solid(Vector2i(next_tile[0], next_tile[1]), true)
	advance(sim, 2)
	expect(snapshot(sim).reserved.vegetable == 0 and snapshot(sim).inventory.vegetable == 22, "failure before consumption releases raw reservations")
	advance(sim, 136)
	expect(snapshot(sim).inventory.vegetable == 21, "a later route retry consumes the ingredient only once")


func _test_default_service() -> void:
	var sim: RefCounted = sim_script.new(fresh())
	var valid: bool = true
	var shared_corridor: bool = false
	var work_positions: Array[Array] = [[2, 2], [5, 2], [8, 2], [9, 4]]
	for next_tick: int in range(1, 3001):
		sim.call("step")
		var view := snapshot(sim)
		if view.employees[0].tile == view.employees[1].tile and view.employees[0].tile not in work_positions:
			shared_corridor = true
		var workers: Dictionary = {}
		var stations: Dictionary = {}
		var positions: Dictionary = {}
		for task: Dictionary in view.tasks:
			valid = valid and not workers.has(task.employee_id) and not stations.has(task.station_id) and not positions.has(task.work_position)
			workers[task.employee_id] = true
			stations[task.station_id] = true
			positions[task.work_position] = true
		for ingredient_id: String in view.inventory:
			valid = valid and view.reserved[ingredient_id] >= 0 and view.reserved[ingredient_id] <= view.inventory[ingredient_id]
		for worker: Dictionary in view.employees:
			valid = valid and worker.progress >= 0 and worker.progress < 5
		if not valid:
			expect(false, "assignment, movement and inventory invariants at tick " + str(next_tick))
			break
	expect(valid, "every tick preserves exclusive tasks and nonnegative stock")
	expect(shared_corridor, "two employees actually share a corridor tile during the default service")
	var view := snapshot(sim)
	var served: Dictionary = {"salad": 0, "soup": 0, "grill": 0}
	var terminal: bool = true
	for item: Dictionary in view.orders:
		terminal = terminal and item.state in ["served", "expired", "cancelled"]
		if item.state == "served":
			served[item.recipe_id] += 1
	expect(view.orders.size() == 20 and terminal, "closing makes all twenty orders terminal")
	expect(served.salad > 0 and served.soup > 0 and served.grill > 0, "the basic fixture serves every menu")
	expect(view.tasks.is_empty() and view.reserved.values().all(func(value: int) -> bool: return value == 0), "closing releases every task and ingredient reservation")
	print("M1_BASELINE ", JSON.stringify({"served": served, "accounting": view.accounting, "hash": sim.call("state_hash")}))


func _test_work_positions_and_cooking_duty() -> void:
	var data := single()
	var second_storage := Definitions.StationDef.new()
	second_storage.id = "storage_02"
	second_storage.role = "storage"
	second_storage.tile = Vector2i(3, 1)
	second_storage.work_position = Vector2i(2, 2)
	data.stations.append(second_storage)
	var sim := _waiting_pair(data)
	command(sim, "set_duty", "employee_01", "all", 4, 3)
	command(sim, "set_duty", "employee_02", "all", 4, 4)
	advance(sim, 4)
	expect(snapshot(sim).tasks.size() == 1 and order(sim, 1).wait_reason == "station_in_use", "different station IDs cannot reserve the same work position twice")
	sim = sim_script.new(single())
	advance(sim, 36)
	expect(order(sim).state == "working" and order(sim).phase_id == "cook", "the duty fixture reaches active cooking")
	command(sim, "set_duty", "employee_01", "hot", 37, 1)
	command(sim, "set_duty", "employee_01", "off", 38, 2)
	advance(sim, 38)
	expect(snapshot(sim).employees[0].duty == "all" and snapshot(sim).employees[0].pending_duty == "off" and order(sim).completion_tick == 96, "the last duty request waits without changing active cooking")
	advance(sim, 96)
	expect(snapshot(sim).employees[0].duty == "off" and snapshot(sim).tasks[0].employee_id == "employee_02", "the next employee receives the serving process after cooking finishes")
