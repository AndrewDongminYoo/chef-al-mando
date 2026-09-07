extends "res://tests/harness.gd"

const Definitions := preload("res://content/definitions.gd")
const PLAN_PATH := "res://sim/preparation_plan.gd"
const CONTENT_PATH := "res://content/m2_first_service.tres"
var plan_script: GDScript


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists(PLAN_PATH) or not ResourceLoader.exists(CONTENT_PATH):
		expect(false, "M2 preparation must load the real plan and content")
		return
	plan_script = load(PLAN_PATH) as GDScript
	_test_conversion_and_commit()
	_test_budget_and_invalid_commands()
	_test_shared_raw_stock()
	_test_placement()
	_test_source_isolation_and_restart()
	_test_invalid_content()


func fresh() -> Definitions:
	return ResourceLoader.load(CONTENT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func command(plan: RefCounted, kind: String, target: String, value: Variant, sequence: int) -> Dictionary:
	return plan.call("apply_command", {"kind": kind, "target_id": target, "value": value, "apply_tick": 0, "sequence": sequence})


func view(plan: RefCounted) -> Dictionary:
	return plan.call("snapshot")


func _test_conversion_and_commit() -> void:
	var data := fresh()
	var plan: RefCounted = plan_script.new(data)
	expect(command(plan, "set_prep", "soup", 2, 1).accepted, "two soup portions fit the preparation budget")
	var prepared := view(plan)
	expect(prepared.inventory.vegetable == 18 and prepared.inventory.grain == 6 and prepared.inventory.prepped_soup == 2, "soup preparation converts two complete raw portions")
	expect(prepared.labor_used == 4 and prepared.purchased_cost == 6600, "preparation spends labor without adding a second cash cost")
	var before := JSON.stringify(prepared, "", true)
	expect(not command(plan, "set_prep", "grill", 1, 2).accepted, "a seventh labor unit cannot be spent")
	expect(JSON.stringify(view(plan), "", true) == before, "rejected preparation changes neither stock nor sequence")
	expect(command(plan, "set_prep", "soup", 1, 2).accepted, "reducing uncommitted preparation is allowed")
	prepared = view(plan)
	expect(prepared.inventory.vegetable == 20 and prepared.inventory.grain == 7 and prepared.inventory.prepped_soup == 1 and prepared.labor_used == 2, "reducing preparation restores only the preview inputs")
	var result := command(plan, "start", "", null, 3)
	expect(result.accepted and view(plan).committed, "a valid preparation plan commits once")
	expect(result.inventory.prepped_soup == 1 and result.inventory.vegetable == 20, "the committed inventory matches the selected conversion")
	expect(not command(plan, "start", "", null, 4).accepted, "a repeated start cannot convert ingredients twice")
	expect(not command(plan, "set_prep", "soup", 0, 4).accepted, "preparation cannot change after service starts")
	expect(data.purchases.vegetable == 22 and data.purchased_cost() == 6600, "committing does not consume the source resource")


func _test_budget_and_invalid_commands() -> void:
	var plan: RefCounted = plan_script.new(fresh())
	expect(not command(plan, "set_purchase", "protein", 12, 1).accepted, "purchases cannot consume the fixed labor allowance")
	expect(command(plan, "set_purchase", "protein", 11, 1).accepted, "a purchase below the combined budget is allowed")
	expect(command(plan, "set_purchase", "vegetable", 24, 2).accepted, "purchases plus labor may equal the budget exactly")
	expect(view(plan).budget_remaining == 0, "the exact budget boundary has no uncommitted money")
	for invalid: Array in [
		["set_purchase", "vegetable", 25], ["set_purchase", "vegetable", -1],
		["set_purchase", "protein", 9223372036854775807],
		["set_purchase", "vegetable", "24"], ["set_purchase", "prepped_salad", 1],
		["set_prep", "unknown", 1], ["set_prep", "salad", -1],
		["set_duty", "employee_01", "unknown"], ["set_duty", "unknown", "all"],
		["move_station", "storage_01", "diagonal"], ["unknown", "", null],
	]:
		var before := JSON.stringify(view(plan), "", true)
		expect(not command(plan, invalid[0], invalid[1], invalid[2], 3).accepted, "invalid preparation command is rejected: " + str(invalid))
		expect(JSON.stringify(view(plan), "", true) == before, "invalid preparation command has no partial effect")
	expect(not command(plan, "set_prep", "salad", 1, 2).accepted, "preparation sequences cannot be reused")
	var future := {"kind": "set_prep", "target_id": "salad", "value": 1, "apply_tick": 1, "sequence": 3}
	expect(not plan.call("apply_command", future).accepted, "preparation applies only at tick zero")


func _test_shared_raw_stock() -> void:
	var data := fresh()
	data.purchases = {"vegetable": 2, "grain": 1, "protein": 1}
	var plan: RefCounted = plan_script.new(data)
	expect(command(plan, "set_prep", "soup", 1, 1).accepted, "one soup consumes the two available vegetables")
	expect(not view(plan).can_start, "soup preparation must not hide the salad ingredient shortage")
	expect(not command(plan, "start", "", null, 2).accepted and not view(plan).committed, "an unsellable menu blocks service without committing")
	expect(not command(plan, "set_prep", "salad", 1, 2).accepted, "different preparations cannot spend the same vegetable")
	expect(not command(plan, "set_purchase", "vegetable", 1, 2).accepted, "purchases cannot fall below the selected preparation inputs")
	expect(command(plan, "set_purchase", "vegetable", 3, 2).accepted, "purchasing one more vegetable restores menu coverage")
	expect(view(plan).can_start and view(plan).inventory.vegetable == 1, "coverage uses the remaining raw and prepared inventory")
	expect(command(plan, "start", "", null, 3).accepted, "mixed raw and prepared menu coverage can start service")


func _test_placement() -> void:
	var plan: RefCounted = plan_script.new(fresh())
	var before := JSON.stringify(view(plan), "", true)
	expect(not command(plan, "move_station", "storage_01", "up", 1).accepted, "a station cannot move into the wall")
	expect(JSON.stringify(view(plan), "", true) == before, "a blocked placement preserves the complete plan")
	expect(command(plan, "move_station", "pass_01", "left", 1).accepted, "the approved closer pass position is reachable")
	expect(_station(view(plan), "pass_01").tile == [8, 5] and _station(view(plan), "pass_01").work_position == [8, 4], "movement carries the station work position with it")
	expect(command(plan, "rotate_station", "pass_01", null, 2).accepted, "a clockwise work position rotation is accepted")
	expect(_station(view(plan), "pass_01").work_position == [9, 5], "rotation follows up then right around the station")
	var data := fresh()
	data.stations[1].tile = Vector2i(3, 1)
	data.stations[1].work_position = Vector2i(3, 2)
	plan = plan_script.new(data)
	expect(not command(plan, "move_station", "storage_01", "right", 1).accepted, "station tiles cannot overlap")
	data = fresh()
	data.stations[1].tile = Vector2i(5, 3)
	data.stations[1].work_position = Vector2i(6, 3)
	for y: int in range(1, 7):
		if y not in [2, 3]:
			data.extra_obstacles.append(Vector2i(4, y))
	data.extra_obstacles.append(Vector2i(3, 2))
	plan = plan_script.new(data)
	expect(view(plan).can_start, "the partition fixture has a working open corridor before placement")
	expect(not command(plan, "move_station", "cold_01", "left", 1).accepted, "closing the only corridor must reject a globally disconnected kitchen")
	plan = plan_script.new(fresh())
	expect(command(plan, "move_station", "storage_01", "down", 1).accepted, "the first downward move keeps the employee start open")
	expect(command(plan, "move_station", "storage_01", "down", 2).accepted, "a work position may share an employee starting tile")
	expect(not command(plan, "move_station", "storage_01", "down", 3).accepted, "a station may not block an employee starting tile")


func _station(snapshot: Dictionary, station_id: String) -> Dictionary:
	for station: Dictionary in snapshot.stations:
		if station.id == station_id:
			return station
	return {}


func _test_source_isolation_and_restart() -> void:
	var data := fresh()
	var first: RefCounted = plan_script.new(data)
	var second: RefCounted = plan_script.new(data)
	command(first, "move_station", "pass_01", "left", 1)
	command(first, "set_prep", "grill", 2, 2)
	command(first, "set_duty", "employee_01", "hot", 3)
	var committed := command(first, "start", "", null, 4)
	expect(_station(view(second), "pass_01").tile == [9, 5] and view(second).inventory.prepped_grill == 0, "preparing one session does not change another session")
	var repeated: RefCounted = plan_script.new(data, committed.selection)
	expect(view(repeated).inventory.protein == 6 and view(repeated).inventory.prepped_grill == 2 and view(repeated).duties.employee_01 == "hot", "retry rebuilds fresh inventory from the last preparation choices")
	expect(not view(repeated).committed and view(repeated).sequence == 0 and view(repeated).purchased_cost == 6600, "retry resets the service boundary without carrying revenue or loss")
	var exposed := view(repeated)
	exposed.inventory.protein = -999
	exposed.stations[0].tile[0] = -999
	expect(view(repeated).inventory.protein == 6 and view(repeated).stations[0].tile[0] != -999, "display snapshots cannot mutate preparation state")
	expect(command(repeated, "reset", "", null, 1).accepted, "the default preparation can be restored explicitly")
	expect(view(repeated).inventory.protein == 8 and view(repeated).inventory.prepped_grill == 0 and _station(view(repeated), "pass_01").tile == [9, 5], "default reset restores source purchases and layout")


func _test_invalid_content() -> void:
	var data := fresh()
	data.ingredients[0] = null
	var plan: RefCounted = plan_script.new(data)
	expect(not view(plan).can_start and not view(plan).errors.is_empty(), "malformed content returns a rejected preparation state")
	expect(not command(plan, "start", "", null, 1).accepted, "malformed content cannot start service")
