extends "res://tests/harness.gd"

const ServiceSim := preload("res://sim/service_sim.gd")
const Definitions := preload("res://content/definitions.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")
const DRIVER_PATH := "res://presentation/tick_driver.gd"
const COMMAND_LOG: Array[Dictionary] = [
	{"submit_tick": 10, "apply_tick": 12, "sequence": 1, "kind": "set_priority", "target_id": "order_01", "value": 2},
	{"submit_tick": 160, "apply_tick": 170, "sequence": 2, "kind": "set_duty", "target_id": "employee_01", "value": "cold"},
	{"submit_tick": 300, "apply_tick": 305, "sequence": 3, "kind": "cancel_order", "target_id": "order_03", "value": null},
	{"submit_tick": 500, "apply_tick": 510, "sequence": 4, "kind": "set_duty", "target_id": "employee_02", "value": "off"},
	{"submit_tick": 600, "apply_tick": 605, "sequence": 5, "kind": "set_duty", "target_id": "employee_02", "value": "all"},
]
var driver_script: GDScript


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists(DRIVER_PATH):
		expect(false, "the real presentation tick driver must exist")
		return
	driver_script = load(DRIVER_PATH) as GDScript
	var first := _replay(1, [16667, 5001, 220003])
	var repeat := _replay(1, [16667, 5001, 220003])
	var fast := _replay(4, [999999, 127, 33001])
	expect(first.tick == 3000 and fast.tick == 3000, "each real driver reaches exactly the closing tick")
	expect(first.state_hash() == repeat.state_hash(), "same seed and command log repeat the final hash")
	expect(first.state_hash() == fast.state_hash(), "one and four speed give the same state with different frame intervals")
	var original := first.state_hash()
	var exposed := first.snapshot()
	exposed.inventory.vegetable = -999
	exposed.orders[0].priority = -999
	exposed.employees[0].tile[0] = -999
	expect(first.state_hash() == original, "mutating the display snapshot cannot change simulation state")
	_test_pause_and_accumulator()
	var data := fresh()
	var a := GridRoutes.new(data.grid_size, data.blocked_tiles())
	var b := GridRoutes.new(data.grid_size, data.blocked_tiles())
	var path_a := a.path_between(Vector2i(2, 4), Vector2i(9, 4))
	expect(path_a.size() > 1 and path_a == b.path_between(Vector2i(2, 4), Vector2i(9, 4)), "the same obstacle grid produces the same tile path")
	print("M1_COMMAND_LOG_HASH ", first.state_hash())


func fresh() -> Definitions:
	return ResourceLoader.load("res://content/m1_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Definitions


func _replay(speed: int, frames: Array[int]) -> ServiceSim:
	var sim := ServiceSim.new(fresh())
	var driver: RefCounted = driver_script.new(sim)
	driver.call("set_speed", speed)
	driver.call("set_paused", false)
	for command: Dictionary in COMMAND_LOG:
		_drive_to(driver, sim, command.submit_tick, frames, speed)
		expect(sim.enqueue_command(command).accepted, "the recorded command is accepted: " + str(command.sequence))
	_drive_to(driver, sim, 3000, frames, speed)
	expect(driver.get("accumulator_us") == 0, "exact game-time input leaves no dropped or surplus tick remainder")
	return sim


func _drive_to(driver: RefCounted, sim: ServiceSim, target: int, frames: Array[int], speed: int) -> void:
	var remaining: int = (target - sim.tick) * 100000 / speed
	var index: int = 0
	while remaining > 0:
		var amount: int = mini(remaining, frames[index % frames.size()])
		driver.call("advance_microseconds", amount)
		remaining -= amount
		index += 1


func _test_pause_and_accumulator() -> void:
	var sim := ServiceSim.new(fresh())
	var driver: RefCounted = driver_script.new(sim)
	driver.call("advance_microseconds", 1000000)
	expect(sim.tick == 0, "the prepared driver starts paused")
	driver.call("set_paused", false)
	driver.call("advance_microseconds", 1250000)
	expect(sim.tick == 12 and driver.get("accumulator_us") == 50000, "a long frame preserves and executes every full tick")
	driver.call("set_paused", true)
	var result := sim.enqueue_command({"kind": "set_priority", "target_id": "order_01", "value": 2, "apply_tick": 13, "sequence": 1})
	var second := sim.enqueue_command({"kind": "set_priority", "target_id": "order_01", "value": 0, "apply_tick": 13, "sequence": 2})
	driver.call("advance_microseconds", 10000000)
	expect(result.accepted and second.accepted and sim.tick == 12 and sim.snapshot().orders[0].priority == 1 and sim.snapshot().commands.size() == 2, "pause queues several commands without advancing their gameplay effects")
	driver.call("set_paused", false)
	driver.call("advance_microseconds", 50000)
	expect(sim.tick == 13 and sim.snapshot().orders[0].priority == 0, "resume applies queued commands in sequence order and excludes paused wall time")
	driver.call("set_speed", 4)
	driver.call("advance_microseconds", 125000)
	expect(sim.tick == 18, "speed changes the number of fixed-size ticks")
	expect(not driver.call("set_speed", 3) and driver.get("speed") == 4, "unsupported speed does not change the driver")
