extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const TickDriver := preload("res://presentation/tick_driver.gd")


static func reference_policy(scenario_id: String) -> Dictionary:
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	match scenario_id:
		"lunch_prep":
			_add(policy, "set_prep", "soup", 4)
			_add(policy, "set_prep", "grain_salad", 1)
		"hot_queue":
			_add(policy, "set_prep", "grill", 4)
			_moves(policy, "cold_01", "left", 2)
			_moves(policy, "hot_01", "left", 3)
			_moves(policy, "pass_01", "left", 5)
			policy.priorities = {"grill": 2}
		"shared_stock":
			_add(policy, "set_prep", "soup", 4)
			_add(policy, "set_prep", "salad", 1)
		"long_route":
			_add(policy, "set_prep", "grill", 4)
			_moves(policy, "cold_01", "up", 1)
			_moves(policy, "cold_01", "left", 3)
			_moves(policy, "hot_01", "up", 1)
			_moves(policy, "hot_01", "left", 5)
			_add(policy, "rotate_station", "hot_02", null)
			_moves(policy, "hot_02", "up", 2)
			_moves(policy, "pass_01", "down", 1)
			_moves(policy, "pass_01", "left", 6)
			_moves(policy, "pass_01", "up", 3)
		"split_duties":
			_add(policy, "set_duty", "employee_01", "cold")
			_add(policy, "set_duty", "employee_02", "cold")
			_add(policy, "set_duty", "employee_03", "hot")
			_add(policy, "set_duty", "employee_04", "hot")
			_add(policy, "set_prep", "protein_bowl", 5)
			_add(policy, "set_prep", "grain_grill", 2)
			_add(policy, "set_prep", "salad", 1)
		"rush_hour", "final_service":
			_add(policy, "set_prep", "grill", 4)
			_add(policy, "set_prep", "protein_bowl", 3)
			_moves(policy, "pass_01", "left", 1)
			policy.priorities = {"grill": 2, "protein_bowl": 2}
	return policy


static func run_policy(scenario: Definitions, policy: Dictionary = {}, speed: int = 1) -> Dictionary:
	var plan := PreparationPlan.new(scenario)
	var sequence: int = 0
	for choice: Dictionary in policy.get("preparation", []):
		sequence += 1
		var command := choice.duplicate(true)
		command.apply_tick = 0
		command.sequence = sequence
		var result := plan.apply_command(command)
		if not result.accepted:
			return {"accepted": false, "reason": "preparation: " + str(command) + " " + result.reason}
	var committed := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": sequence + 1})
	if not committed.accepted:
		return {"accepted": false, "reason": "start: " + committed.reason}
	var sim := ServiceSim.new(committed.definitions, null, committed.options)
	var driver := TickDriver.new(sim)
	driver.set_speed(speed)
	driver.set_paused(false)
	sequence = 0
	for arrival: Dictionary in scenario.order_schedule():
		_drive_to(driver, sim, arrival.arrival_tick, speed)
		if policy.get("priorities", {}).has(arrival.recipe_id):
			sequence += 1
			var result := sim.enqueue_command({"kind": "set_priority", "target_id": arrival.id,
				"value": policy.priorities[arrival.recipe_id], "apply_tick": sim.tick + 1, "sequence": sequence})
			if not result.accepted:
				return {"accepted": false, "reason": "priority: " + result.reason}
	_drive_to(driver, sim, scenario.closing_tick, speed)
	return {"accepted": true, "snapshot": sim.snapshot(), "hash": sim.state_hash(), "selection": committed.selection}


static func _drive_to(driver: TickDriver, sim: ServiceSim, target_tick: int, speed: int) -> void:
	var frames: Array[int] = [16667, 5001, 33001]
	if speed == 4:
		frames.assign([99991, 333, 70001])
	var frame: int = 0
	while sim.tick < target_tick and not sim.closed:
		var remaining: int = (target_tick - sim.tick) * 100000 - driver.accumulator_us
		driver.advance_microseconds(mini(frames[frame % frames.size()], remaining / speed))
		driver.take_events()
		frame += 1


static func _add(policy: Dictionary, kind: String, target: String, value: Variant) -> void:
	policy.preparation.append({"kind": kind, "target_id": target, "value": value})


static func _moves(policy: Dictionary, target: String, direction: String, count: int) -> void:
	for _index: int in count:
		_add(policy, "move_station", target, direction)
