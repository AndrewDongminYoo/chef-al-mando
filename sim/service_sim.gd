extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const RecipeDef := preload("res://content/recipe_def.gd")
const ProcessDef := preload("res://content/process_def.gd")
const StationDef := preload("res://content/station_def.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const TERMINAL: Array[String] = ["served", "cancelled", "expired"]
const DUTIES: Array[String] = ["all", "cold", "hot", "off"]
const MOVE_TICKS: int = 5


class OrderState extends RefCounted:
	var id: String
	var recipe: RecipeDef
	var phases: Array[ProcessDef]
	var arrival_tick: int
	var deadline_tick: int
	var state: String = "waiting"
	var terminal_reason: String = ""
	var phase_index: int = 0
	var priority: int = 1
	var wait_reason: String = ""
	var wait_detail: String = ""
	var raw_consumed: bool = false
	var input_consumed: bool = false
	var uses_prepared: bool = false
	var reserved_inputs: Dictionary[String, int] = {}
	var consumed_cost: int = 0
	var intermediate_ready: bool = false
	var intermediate_consumed: bool = false
	var ended_tick: int = -1
	var metrics: Dictionary[String, int] = {"missing_ingredients": 0, "no_responsible_employee": 0,
		"station_in_use": 0, "no_route": 0, "responsible_employee_busy": 0, "moving": 0, "working": 0}
	var ingredients_reserved: bool = false
	var has_result: bool = false
	var result_position: Vector2i = Vector2i.ZERO
	var carrying: bool = false


class EmployeeState extends RefCounted:
	var id: String
	var tile: Vector2i
	var next_tile: Vector2i
	var progress: int = 0
	var duty: String = "all"
	var pending_duty: String = ""
	var order_id: String = ""


class TaskState extends RefCounted:
	var order_id: String
	var employee_id: String
	var station: StationDef
	var path: Array[Vector2i] = []
	var path_index: int = 0
	var collection_index: int = -1
	var started_tick: int = -1
	var completion_tick: int = -1


var tick: int = 0
var closed: bool = false
var errors: Array[String] = []
var _data: Definitions
var _routes: GridRoutes
var _schedule: Array[Dictionary] = []
var _schedule_cursor: int = 0
var _orders: Array[OrderState] = []
var _order_by_id: Dictionary[String, OrderState] = {}
var _employees: Array[EmployeeState] = []
var _employee_by_id: Dictionary[String, EmployeeState] = {}
var _stations: Array[StationDef] = []
var _tasks: Dictionary[String, TaskState] = {}
var _inventory: Dictionary[String, int] = {}
var _reserved: Dictionary[String, int] = {}
var _commands: Array[Dictionary] = []
var _last_sequence: int = 0
var _revenue: int = 0
var _events: Array[Dictionary] = []
var _station_reserved_ticks: Dictionary[String, int] = {}


func _init(data: Definitions, routes: GridRoutes = null, preparation: Dictionary = {}) -> void:
	_data = data
	var initial: Dictionary = {}
	if data.supports_preparation() or not preparation.is_empty():
		initial = PreparationPlan.initial_state(data, preparation)
		errors = initial.errors
	else:
		errors = data.validate()
	if not errors.is_empty():
		closed = true
		return
	_routes = routes if routes != null else GridRoutes.new(data.grid_size, data.blocked_tiles())
	_schedule = data.order_schedule()
	_stations.assign(data.stations)
	_stations.sort_custom(func(a: StationDef, b: StationDef) -> bool: return a.id < b.id)
	for station: StationDef in _stations:
		_station_reserved_ticks[station.id] = 0
	for definition: Definitions.EmployeeDef in data.employees:
		var employee := EmployeeState.new()
		employee.id = definition.id
		employee.tile = definition.starting_tile
		employee.next_tile = employee.tile
		if not initial.is_empty():
			employee.duty = initial.duties[employee.id]
		_employees.append(employee)
		_employee_by_id[employee.id] = employee
	_employees.sort_custom(func(a: EmployeeState, b: EmployeeState) -> bool: return a.id < b.id)
	for ingredient: Definitions.IngredientDef in data.ingredients:
		_inventory[ingredient.id] = data.purchases.get(ingredient.id, 0) if initial.is_empty() else initial.inventory[ingredient.id]
		_reserved[ingredient.id] = 0


func enqueue_command(command: Dictionary) -> Dictionary:
	var reason := _validate_command(command, true)
	if not reason.is_empty():
		return {"accepted": false, "reason": reason}
	_commands.append(command.duplicate(true))
	_last_sequence = command.sequence
	_commands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.sequence < b.sequence if a.apply_tick == b.apply_tick else a.apply_tick < b.apply_tick)
	return {"accepted": true, "reason": ""}


func _validate_command(command: Dictionary, enqueue: bool) -> String:
	if closed:
		return "service_closed"
	for field: String in ["kind", "target_id", "apply_tick", "sequence", "value"]:
		if not command.has(field):
			return "invalid_command"
	if not command.kind is String or not command.target_id is String or not command.apply_tick is int or not command.sequence is int:
		return "invalid_command"
	if enqueue and (command.apply_tick <= tick or command.sequence <= _last_sequence):
		return "invalid_command_order"
	if command.kind == "set_duty":
		if not _employee_by_id.has(command.target_id):
			return "unknown_employee"
		return "" if command.value is String and command.value in DUTIES else "invalid_duty"
	if command.kind not in ["set_priority", "cancel_order"]:
		return "unknown_command"
	if not _order_by_id.has(command.target_id):
		return "unknown_order"
	if _order_by_id[command.target_id].state in TERMINAL:
		return "terminal_order"
	if command.kind == "set_priority" and (not command.value is int or command.value < 0 or command.value > 2):
		return "invalid_priority"
	return ""


func step() -> void:
	if closed:
		return
	tick += 1
	_events.clear()
	_apply_commands()
	_arrive_and_expire()
	if closed:
		return
	_complete_work()
	_assign_work()
	_move_employees()
	_accumulate_metrics()


func _apply_commands() -> void:
	while not _commands.is_empty() and _commands[0].apply_tick <= tick:
		var command: Dictionary = _commands.pop_front()
		var reason := _validate_command(command, false)
		if not reason.is_empty():
			_events.append({"kind": "command_rejected", "sequence": command.sequence, "reason": reason})
			continue
		match command.kind:
			"set_priority":
				_order_by_id[command.target_id].priority = command.value
			"cancel_order":
				_terminate_order(_order_by_id[command.target_id], "cancelled", "player_cancelled")
			"set_duty":
				var employee: EmployeeState = _employee_by_id[command.target_id]
				if employee.order_id.is_empty():
					employee.duty = command.value
				else:
					employee.pending_duty = command.value
		_events.append({"kind": "command_applied", "sequence": command.sequence})


func _arrive_and_expire() -> void:
	while _schedule_cursor < _schedule.size() and _schedule[_schedule_cursor].arrival_tick <= tick:
		var arrival: Dictionary = _schedule[_schedule_cursor]
		var order := OrderState.new()
		order.id = arrival.id
		order.recipe = _data.recipe_for(arrival.recipe_id)
		order.phases = order.recipe.ordered_processes()
		order.arrival_tick = arrival.arrival_tick
		order.deadline_tick = arrival.deadline_tick
		_orders.append(order)
		_order_by_id[order.id] = order
		_schedule_cursor += 1
		_events.append({"kind": "order_arrived", "order_id": order.id})
	for order: OrderState in _orders:
		if order.state not in TERMINAL and order.deadline_tick <= tick:
			_terminate_order(order, "expired", "deadline")
	if tick >= _data.closing_tick:
		for order: OrderState in _orders:
			if order.state not in TERMINAL:
				_terminate_order(order, "expired", "service_closed")
		closed = true
		_commands.clear()
		_events.append({"kind": "service_closed"})


func _complete_work() -> void:
	for order: OrderState in _orders:
		if order.state != "working":
			continue
		var task: TaskState = _tasks[order.id]
		if task.completion_tick > tick:
			continue
		order.result_position = task.station.work_position
		order.has_result = true
		order.carrying = false
		if order.phases[order.phase_index].id == "prep":
			order.intermediate_ready = true
		_release_task(order)
		order.phase_index += 1
		if order.uses_prepared and order.phase_index < order.phases.size() and order.phases[order.phase_index].id == "prep":
			order.phase_index += 1
		if order.phase_index == order.phases.size():
			order.state = "served"
			order.has_result = false
			order.ended_tick = tick
			_revenue += order.recipe.revenue
			_events.append({"kind": "order_served", "order_id": order.id})
		else:
			order.state = "waiting"


func _assign_work() -> void:
	for order: OrderState in _orders:
		if order.state == "moving":
			var task: TaskState = _tasks[order.id]
			if task.path_index == task.path.size() - 1:
				_begin_work(order, task)
	var candidates: Array[OrderState] = []
	for order: OrderState in _orders:
		if order.state == "waiting":
			candidates.append(order)
	candidates.sort_custom(func(a: OrderState, b: OrderState) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		if a.deadline_tick != b.deadline_tick:
			return a.deadline_tick < b.deadline_tick
		return a.id < b.id)
	for order: OrderState in candidates:
		_try_assignment(order)


func _try_assignment(order: OrderState) -> void:
	order.wait_detail = ""
	var inputs: Dictionary[String, int] = {}
	if not order.input_consumed:
		inputs = _available_inputs(order)
		if inputs.is_empty():
			order.wait_reason = "missing_ingredients"
			return
	var available: Array[EmployeeState] = []
	var responsible: bool = false
	for employee: EmployeeState in _employees:
		if employee.duty == "all" or employee.duty == order.recipe.cook_role:
			responsible = true
			if employee.order_id.is_empty():
				available.append(employee)
	if available.is_empty():
		order.wait_reason = "no_responsible_employee"
		order.wait_detail = "responsible_employee_busy" if responsible else ""
		return
	var stations: Array[StationDef] = []
	for station: StationDef in _stations:
		if station.role == order.phases[order.phase_index].station_role and _station_available(station):
			stations.append(station)
	if stations.is_empty():
		order.wait_reason = "station_in_use"
		return
	for employee: EmployeeState in available:
		for station: StationDef in stations:
			var task := _plan_task(order, employee, station)
			if task == null:
				continue
			if not order.input_consumed:
				order.reserved_inputs = inputs
				order.uses_prepared = inputs.has(order.recipe.prepared_ingredient_id)
				for ingredient_id: String in inputs:
					_reserved[ingredient_id] += inputs[ingredient_id]
				order.ingredients_reserved = true
			_tasks[order.id] = task
			employee.order_id = order.id
			employee.progress = 0
			employee.next_tile = task.path[1] if task.path.size() > 1 else employee.tile
			order.state = "moving"
			order.wait_reason = ""
			order.carrying = task.collection_index == 0
			if task.path.size() == 1:
				_begin_work(order, task)
			return
	order.wait_reason = "no_route"


func _available_inputs(order: OrderState) -> Dictionary[String, int]:
	var inputs: Dictionary[String, int] = {}
	var prepared_id := order.recipe.prepared_ingredient_id
	if not prepared_id.is_empty() and _inventory[prepared_id] - _reserved[prepared_id] > 0:
		inputs[prepared_id] = 1
		return inputs
	for ingredient_id: String in order.recipe.ingredients:
		if _inventory[ingredient_id] - _reserved[ingredient_id] < order.recipe.ingredients[ingredient_id]:
			return {}
	inputs.assign(order.recipe.ingredients)
	return inputs


func _station_available(station: StationDef) -> bool:
	for order: OrderState in _orders:
		if _tasks.has(order.id):
			var occupied: StationDef = _tasks[order.id].station
			if occupied.id == station.id or occupied.work_position == station.work_position:
				return false
	return true


func _plan_task(order: OrderState, employee: EmployeeState, station: StationDef) -> TaskState:
	var task := TaskState.new()
	task.order_id = order.id
	task.employee_id = employee.id
	task.station = station
	if order.has_result:
		task.path = _routes.path_between(employee.tile, order.result_position)
		var onward := _routes.path_between(order.result_position, station.work_position)
		if task.path.is_empty() or onward.is_empty():
			return null
		task.collection_index = task.path.size() - 1
		task.path.append_array(onward.slice(1))
	else:
		task.path = _routes.path_between(employee.tile, station.work_position)
	return null if task.path.is_empty() else task


func _begin_work(order: OrderState, task: TaskState) -> void:
	if not order.input_consumed:
		for ingredient_id: String in order.reserved_inputs:
			_inventory[ingredient_id] -= order.reserved_inputs[ingredient_id]
			order.consumed_cost += _data.ingredient_for(ingredient_id).unit_cost * order.reserved_inputs[ingredient_id]
		_release_ingredients(order)
		order.input_consumed = true
		order.raw_consumed = not order.uses_prepared
		order.intermediate_ready = order.uses_prepared
	if order.phases[order.phase_index].id == "cook" and order.intermediate_ready:
		order.intermediate_ready = false
		order.intermediate_consumed = true
	order.state = "working"
	order.carrying = false
	order.has_result = true
	order.result_position = task.station.work_position
	task.started_tick = tick
	task.completion_tick = tick + order.phases[order.phase_index].duration_ticks


func _move_employees() -> void:
	for employee: EmployeeState in _employees:
		if employee.order_id.is_empty():
			continue
		var order: OrderState = _order_by_id[employee.order_id]
		if order.state != "moving":
			continue
		var task: TaskState = _tasks[order.id]
		if task.path_index == task.path.size() - 1:
			continue
		if not _routes.is_walkable(employee.next_tile):
			if order.carrying:
				order.result_position = employee.tile
			order.carrying = false
			_release_task(order)
			_release_ingredients(order)
			order.state = "waiting"
			order.wait_reason = "no_route"
			order.wait_detail = ""
			_events.append({"kind": "path_failed", "order_id": order.id})
			continue
		employee.progress += 1
		if employee.progress == MOVE_TICKS:
			employee.tile = employee.next_tile
			employee.progress = 0
			task.path_index += 1
			if task.path_index == task.collection_index:
				order.carrying = true
			employee.next_tile = task.path[task.path_index + 1] if task.path_index + 1 < task.path.size() else employee.tile


func _release_task(order: OrderState) -> void:
	if not _tasks.has(order.id):
		return
	var employee: EmployeeState = _employee_by_id[_tasks[order.id].employee_id]
	employee.order_id = ""
	employee.progress = 0
	employee.next_tile = employee.tile
	if not employee.pending_duty.is_empty():
		employee.duty = employee.pending_duty
		employee.pending_duty = ""
	_tasks.erase(order.id)


func _release_ingredients(order: OrderState) -> void:
	if not order.ingredients_reserved:
		return
	for ingredient_id: String in order.reserved_inputs:
		_reserved[ingredient_id] -= order.reserved_inputs[ingredient_id]
	order.reserved_inputs.clear()
	order.ingredients_reserved = false


func _terminate_order(order: OrderState, terminal: String, reason: String) -> void:
	_release_task(order)
	_release_ingredients(order)
	order.state = terminal
	order.terminal_reason = reason
	order.wait_reason = ""
	order.wait_detail = ""
	order.carrying = false
	order.has_result = false
	order.intermediate_ready = false
	order.ended_tick = tick
	_events.append({"kind": "order_ended", "order_id": order.id, "reason": reason})


func _accounting() -> Dictionary:
	if not errors.is_empty():
		return {}
	var waste_cost: int = 0
	var counts: Dictionary = {"served": 0, "cancelled": 0, "expired": 0}
	for order: OrderState in _orders:
		if order.state in TERMINAL:
			counts[order.state] += 1
		if order.state in ["cancelled", "expired"]:
			waste_cost += order.consumed_cost
	if closed:
		for ingredient: Definitions.IngredientDef in _data.ingredients:
			waste_cost += ingredient.unit_cost * _inventory.get(ingredient.id, 0)
	var purchased_cost := _data.purchased_cost()
	var profit := _revenue - purchased_cost - _data.labor_cost
	return {"revenue": _revenue, "purchased_cost": purchased_cost, "labor_cost": _data.labor_cost,
		"profit": profit, "cash": _data.starting_budget + profit, "waste_cost": waste_cost,
		"served": counts.served, "cancelled": counts.cancelled, "expired": counts.expired}


func _accumulate_metrics() -> void:
	for order: OrderState in _orders:
		if order.state in TERMINAL:
			continue
		var key := order.wait_reason if order.state == "waiting" else order.state
		order.metrics[key] += 1
		if order.state == "waiting" and order.wait_detail == "responsible_employee_busy":
			order.metrics.responsible_employee_busy += 1
		if _tasks.has(order.id):
			_station_reserved_ticks[_tasks[order.id].station.id] += 1


func _metrics() -> Dictionary:
	var totals: Dictionary[String, int] = {"missing_ingredients": 0, "no_responsible_employee": 0,
		"station_in_use": 0, "no_route": 0, "responsible_employee_busy": 0, "moving": 0, "working": 0}
	for order: OrderState in _orders:
		for key: String in totals:
			totals[key] += order.metrics[key]
	return {"orders": totals, "station_reserved_ticks": _station_reserved_ticks.duplicate()}


func snapshot() -> Dictionary:
	var orders: Array[Dictionary] = []
	var tasks: Array[Dictionary] = []
	var employees: Array[Dictionary] = []
	var sorted_orders: Array[OrderState] = _orders.duplicate()
	sorted_orders.sort_custom(func(a: OrderState, b: OrderState) -> bool: return a.id < b.id)
	for order: OrderState in sorted_orders:
		var task: TaskState = _tasks.get(order.id)
		orders.append({"id": order.id, "recipe_id": order.recipe.id, "name": order.recipe.display_name,
			"arrival_tick": order.arrival_tick, "deadline_tick": order.deadline_tick,
			"state": order.state, "terminal_reason": order.terminal_reason,
			"phase_index": order.phase_index, "phase_id": order.phases[order.phase_index].id if order.phase_index < order.phases.size() else "",
			"priority": order.priority, "wait_reason": order.wait_reason, "wait_detail": order.wait_detail,
			"raw_consumed": order.raw_consumed, "ingredients_reserved": order.ingredients_reserved,
			"input_consumed": order.input_consumed, "uses_prepared": order.uses_prepared,
			"reserved_inputs": order.reserved_inputs.duplicate(), "consumed_cost": order.consumed_cost,
			"intermediate_ready": order.intermediate_ready, "intermediate_consumed": order.intermediate_consumed,
			"ended_tick": order.ended_tick, "metrics": order.metrics.duplicate(),
			"has_result": order.has_result, "result_position": _tile_array(order.result_position), "carrying": order.carrying,
			"employee_id": task.employee_id if task != null else "",
			"station_id": task.station.id if task != null else "",
			"completion_tick": task.completion_tick if task != null else -1})
		if task != null:
			var path: Array[Array] = []
			for tile: Vector2i in task.path:
				path.append(_tile_array(tile))
			tasks.append({"order_id": order.id, "employee_id": task.employee_id,
				"station_id": task.station.id, "work_position": _tile_array(task.station.work_position),
				"path": path, "path_index": task.path_index, "collection_index": task.collection_index,
				"started_tick": task.started_tick, "completion_tick": task.completion_tick})
	for employee: EmployeeState in _employees:
		employees.append({"id": employee.id, "tile": _tile_array(employee.tile),
			"next_tile": _tile_array(employee.next_tile), "progress": employee.progress,
			"duty": employee.duty, "pending_duty": employee.pending_duty, "order_id": employee.order_id})
	return {"tick": tick, "closed": closed, "schedule_cursor": _schedule_cursor,
		"orders": orders, "employees": employees, "tasks": tasks,
		"inventory": _inventory.duplicate(), "reserved": _reserved.duplicate(),
		"accounting": _accounting(), "metrics": _metrics(), "commands": _commands.duplicate(true),
		"last_sequence": _last_sequence, "events": _events.duplicate(true), "errors": errors.duplicate()}


func state_hash() -> String:
	var canonical := snapshot()
	canonical.erase("events")
	return JSON.stringify(canonical, "", true).sha256_text()


func events() -> Array[Dictionary]:
	return _events.duplicate(true)


static func _tile_array(tile: Vector2i) -> Array[int]:
	return [tile.x, tile.y]
