extends RefCounted

const Definitions := preload("res://content/definitions.gd")
const RecipeDef := preload("res://content/recipe_def.gd")
const ProcessDef := preload("res://content/process_def.gd")
const StationDef := preload("res://content/station_def.gd")
const GridRoutes := preload("res://sim/grid_routes.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const TERMINAL: Array[String] = ["served", "cancelled", "expired"]
const DUTIES: Array[String] = ["all", "cold", "hot", "off"]
const ORDER_STATES: Array[String] = ["waiting", "moving", "working", "served", "cancelled", "expired"]
const WAIT_REASONS: Array[String] = ["", "missing_ingredients", "no_responsible_employee", "station_in_use", "no_route"]
const METRIC_KEYS: Array[String] = ["missing_ingredients", "no_responsible_employee", "station_in_use", "no_route",
	"responsible_employee_busy", "moving", "working"]
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
	_commands.append({"kind": command.kind, "target_id": command.target_id,
		"value": null if command.kind == "cancel_order" else command.value,
		"apply_tick": command.apply_tick, "sequence": command.sequence})
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


func export_state() -> Dictionary:
	var state := snapshot()
	state.erase("accounting")
	state.erase("metrics")
	state.erase("events")
	state.erase("errors")
	state["prng_state"] = null
	state["station_reserved_ticks"] = _station_reserved_ticks.duplicate()
	for order: Dictionary in state.orders:
		for field: String in ["name", "phase_id", "employee_id", "station_id", "completion_tick", "consumed_cost"]:
			order.erase(field)
	for task: Dictionary in state.tasks:
		task.erase("work_position")
	return state.duplicate(true)


static func restore(data: Definitions, state: Dictionary, preparation: Dictionary = {}) -> Dictionary:
	var reason := _basic_restore_error(state)
	if reason.is_empty():
		reason = _state_restore_error(data, state)
	if reason.is_empty():
		reason = _inventory_restore_error(data, state, preparation)
	if not reason.is_empty():
		return {"accepted": false, "reason": reason}
	var simulation = (load("res://sim/service_sim.gd") as GDScript).new(data, null, preparation)
	if not simulation.errors.is_empty():
		return {"accepted": false, "reason": "invalid_content"}
	if state.tick == 0 and state.employees != simulation.export_state().employees:
		return {"accepted": false, "reason": "invalid_employee"}
	simulation.tick = state.tick
	simulation.closed = state.closed
	simulation._schedule_cursor = state.schedule_cursor
	simulation._orders.clear()
	simulation._order_by_id.clear()
	for saved_order: Dictionary in state.orders:
		var recipe: RecipeDef = data.recipe_for(saved_order.recipe_id)
		if recipe == null:
			return {"accepted": false, "reason": "invalid_order"}
		var order := OrderState.new()
		order.id = saved_order.id
		order.recipe = recipe
		order.phases = recipe.ordered_processes()
		order.arrival_tick = saved_order.arrival_tick
		order.deadline_tick = saved_order.deadline_tick
		order.state = saved_order.state
		order.terminal_reason = saved_order.terminal_reason
		order.phase_index = saved_order.phase_index
		order.priority = saved_order.priority
		order.wait_reason = saved_order.wait_reason
		order.wait_detail = saved_order.wait_detail
		order.raw_consumed = saved_order.raw_consumed
		order.ingredients_reserved = saved_order.ingredients_reserved
		order.input_consumed = saved_order.input_consumed
		order.uses_prepared = saved_order.uses_prepared
		order.reserved_inputs.assign(saved_order.reserved_inputs)
		order.consumed_cost = _consumed_cost(data, order)
		order.intermediate_ready = saved_order.intermediate_ready
		order.intermediate_consumed = saved_order.intermediate_consumed
		order.ended_tick = saved_order.ended_tick
		order.metrics.assign(saved_order.metrics)
		order.has_result = saved_order.has_result
		order.result_position = _array_tile(saved_order.result_position)
		order.carrying = saved_order.carrying
		simulation._orders.append(order)
		simulation._order_by_id[order.id] = order
	for saved_employee: Dictionary in state.employees:
		if not simulation._employee_by_id.has(saved_employee.id):
			return {"accepted": false, "reason": "invalid_employee"}
		var employee: EmployeeState = simulation._employee_by_id[saved_employee.id]
		employee.tile = _array_tile(saved_employee.tile)
		employee.next_tile = _array_tile(saved_employee.next_tile)
		employee.progress = saved_employee.progress
		employee.duty = saved_employee.duty
		employee.pending_duty = saved_employee.pending_duty
		employee.order_id = saved_employee.order_id
	simulation._tasks.clear()
	for saved_task: Dictionary in state.tasks:
		var station := _station_for(data, saved_task.station_id)
		if station == null:
			return {"accepted": false, "reason": "invalid_task"}
		var task := TaskState.new()
		task.order_id = saved_task.order_id
		task.employee_id = saved_task.employee_id
		task.station = station
		for tile: Array in saved_task.path:
			task.path.append(_array_tile(tile))
		task.path_index = saved_task.path_index
		task.collection_index = saved_task.collection_index
		task.started_tick = saved_task.started_tick
		task.completion_tick = saved_task.completion_tick
		simulation._tasks[task.order_id] = task
	simulation._inventory.clear()
	simulation._inventory.assign(state.inventory)
	simulation._reserved.clear()
	simulation._reserved.assign(state.reserved)
	simulation._commands.clear()
	simulation._commands.assign(state.commands)
	simulation._last_sequence = state.last_sequence
	simulation._revenue = 0
	for order: OrderState in simulation._orders:
		if order.state == "served":
			simulation._revenue += order.recipe.revenue
	simulation._events.clear()
	simulation._station_reserved_ticks.clear()
	simulation._station_reserved_ticks.assign(state.station_reserved_ticks)
	return {"accepted": true, "simulation": simulation}


static func _basic_restore_error(state: Dictionary) -> String:
	var fields: Array[String] = ["tick", "closed", "prng_state", "schedule_cursor", "orders", "employees", "tasks",
		"inventory", "reserved", "commands", "last_sequence", "station_reserved_ticks"]
	if not _exact_fields(state, fields):
		return "invalid_state"
	if not state.tick is int or not state.closed is bool or state.prng_state != null or not state.schedule_cursor is int:
		return "invalid_state"
	if not state.orders is Array or not state.employees is Array or not state.tasks is Array:
		return "invalid_state"
	if not state.inventory is Dictionary or not state.reserved is Dictionary or not state.commands is Array:
		return "invalid_state"
	if not state.last_sequence is int or not state.station_reserved_ticks is Dictionary:
		return "invalid_state"
	return ""


static func _state_restore_error(data: Definitions, state: Dictionary) -> String:
	if data == null or not data.validate(false).is_empty():
		return "invalid_content"
	if state.tick < 0 or state.tick > data.closing_tick or state.last_sequence < 0:
		return "invalid_state"
	if state.closed != (state.tick == data.closing_tick):
		return "invalid_closing_state"
	var schedule := data.order_schedule()
	var expected_cursor: int = 0
	while expected_cursor < schedule.size() and schedule[expected_cursor].arrival_tick <= state.tick:
		expected_cursor += 1
	if state.schedule_cursor != expected_cursor or state.orders.size() != expected_cursor:
		return "invalid_schedule"
	var task_by_order: Dictionary = {}
	var employee_tasks: Dictionary = {}
	var station_tasks: Dictionary = {}
	var work_position_tasks: Dictionary = {}
	var routes := GridRoutes.new(data.grid_size, data.blocked_tiles())
	for saved_task: Variant in state.tasks:
		var task_reason := _task_restore_error(data, routes, saved_task, task_by_order, employee_tasks,
			station_tasks, work_position_tasks)
		if not task_reason.is_empty():
			return task_reason
	var order_ids: Dictionary = {}
	var expected_reserved: Dictionary = {}
	var moving_and_working_ticks: int = 0
	for ingredient: Definitions.IngredientDef in data.ingredients:
		expected_reserved[ingredient.id] = 0
	for index: int in state.orders.size():
		var order_reason := _order_restore_error(data, routes, state, state.orders[index], schedule[index], task_by_order)
		if not order_reason.is_empty():
			return order_reason
		var saved_order: Dictionary = state.orders[index]
		order_ids[saved_order.id] = saved_order
		for ingredient_id: String in saved_order.reserved_inputs:
			if not expected_reserved.has(ingredient_id):
				return "invalid_reservation"
			expected_reserved[ingredient_id] += saved_order.reserved_inputs[ingredient_id]
		moving_and_working_ticks += saved_order.metrics.moving + saved_order.metrics.working
	if state.reserved.size() != expected_reserved.size():
		return "invalid_reservation"
	for ingredient_id: String in expected_reserved:
		if not state.reserved.get(ingredient_id) is int or state.reserved[ingredient_id] < 0:
			return "invalid_reservation"
		if not state.inventory.get(ingredient_id) is int or state.reserved[ingredient_id] > state.inventory[ingredient_id]:
			return "invalid_reservation"
	if state.reserved != expected_reserved:
		return "invalid_reservation"
	var employee_reason := _employees_restore_error(data, routes, state.employees, task_by_order, order_ids)
	if not employee_reason.is_empty():
		return employee_reason
	var command_reason := _commands_restore_error(state, order_ids, data)
	if not command_reason.is_empty():
		return command_reason
	if state.station_reserved_ticks.size() != data.stations.size():
		return "invalid_metrics"
	var station_ticks: int = 0
	for station: StationDef in data.stations:
		if not state.station_reserved_ticks.get(station.id) is int or state.station_reserved_ticks[station.id] < 0:
			return "invalid_metrics"
		station_ticks += state.station_reserved_ticks[station.id]
	if station_ticks != moving_and_working_ticks:
		return "invalid_metrics"
	if state.closed:
		if not state.tasks.is_empty() or not state.commands.is_empty():
			return "invalid_closing_state"
		for saved_order: Dictionary in state.orders:
			if saved_order.state not in TERMINAL:
				return "invalid_closing_state"
		for value: Variant in state.reserved.values():
			if value != 0:
				return "invalid_closing_state"
	return ""


static func _task_restore_error(data: Definitions, routes: GridRoutes, saved_task: Variant,
	task_by_order: Dictionary, employee_tasks: Dictionary, station_tasks: Dictionary,
	work_position_tasks: Dictionary) -> String:
	var fields: Array[String] = ["order_id", "employee_id", "station_id", "path", "path_index", "collection_index",
		"started_tick", "completion_tick"]
	if not _exact_fields(saved_task, fields):
		return "invalid_task"
	if not saved_task.order_id is String or not saved_task.employee_id is String or not saved_task.station_id is String:
		return "invalid_task"
	if not saved_task.path is Array or not saved_task.path_index is int or not saved_task.collection_index is int:
		return "invalid_task"
	if not saved_task.started_tick is int or not saved_task.completion_tick is int or saved_task.path.is_empty():
		return "invalid_task"
	if task_by_order.has(saved_task.order_id) or employee_tasks.has(saved_task.employee_id) or station_tasks.has(saved_task.station_id):
		return "invalid_task_link"
	var station := _station_for(data, saved_task.station_id)
	if station == null:
		return "invalid_task"
	var position_key := str(station.work_position)
	if work_position_tasks.has(position_key):
		return "invalid_task_link"
	for index: int in saved_task.path.size():
		var coordinates: Variant = saved_task.path[index]
		if not _valid_tile(coordinates):
			return "invalid_path"
		var tile := _array_tile(coordinates)
		if not routes.is_walkable(tile):
			return "invalid_path"
		if index > 0:
			var previous := _array_tile(saved_task.path[index - 1])
			# cspell:ignore absi
			if absi(previous.x - tile.x) + absi(previous.y - tile.y) != 1:
				return "invalid_path"
	if _array_tile(saved_task.path[-1]) != station.work_position:
		return "invalid_path"
	if saved_task.path_index < 0 or saved_task.path_index >= saved_task.path.size():
		return "invalid_path"
	if saved_task.collection_index < -1 or saved_task.collection_index >= saved_task.path.size():
		return "invalid_path"
	var origin := _array_tile(saved_task.path[0])
	var canonical_path: Array[Vector2i]
	if saved_task.collection_index >= 0:
		var collection_tile := _array_tile(saved_task.path[saved_task.collection_index])
		var first_path := routes.path_between(origin, collection_tile)
		var onward_path := routes.path_between(collection_tile, station.work_position)
		if first_path.is_empty() or onward_path.is_empty() \
			or saved_task.collection_index != first_path.size() - 1:
			return "invalid_path"
		canonical_path = first_path
		canonical_path.append_array(onward_path.slice(1))
	else:
		canonical_path = routes.path_between(origin, station.work_position)
	if canonical_path.size() != saved_task.path.size():
		return "invalid_path"
	for index: int in canonical_path.size():
		if canonical_path[index] != _array_tile(saved_task.path[index]):
			return "invalid_path"
	task_by_order[saved_task.order_id] = saved_task
	employee_tasks[saved_task.employee_id] = true
	station_tasks[saved_task.station_id] = true
	work_position_tasks[position_key] = true
	return ""


static func _order_restore_error(data: Definitions, routes: GridRoutes, state: Dictionary, saved_order: Variant,
	scheduled: Dictionary, task_by_order: Dictionary) -> String:
	var fields: Array[String] = ["id", "recipe_id", "arrival_tick", "deadline_tick", "state", "terminal_reason",
		"phase_index", "priority", "wait_reason", "wait_detail", "raw_consumed", "ingredients_reserved",
		"input_consumed", "uses_prepared", "reserved_inputs", "intermediate_ready", "intermediate_consumed",
		"ended_tick", "metrics", "has_result", "result_position", "carrying"]
	if not _exact_fields(saved_order, fields):
		return "invalid_order"
	if not saved_order.id is String or not saved_order.recipe_id is String:
		return "invalid_order"
	for field: String in ["arrival_tick", "deadline_tick", "phase_index", "priority", "ended_tick"]:
		if not saved_order[field] is int:
			return "invalid_order"
	if saved_order.id != scheduled.id:
		return "invalid_order"
	if saved_order.recipe_id != scheduled.recipe_id or saved_order.arrival_tick != scheduled.arrival_tick \
		or saved_order.deadline_tick != scheduled.deadline_tick:
		return "invalid_schedule"
	var recipe: RecipeDef = data.recipe_for(saved_order.recipe_id)
	if recipe == null or not saved_order.state is String or saved_order.state not in ORDER_STATES:
		return "invalid_order"
	if not saved_order.terminal_reason is String:
		return "invalid_order"
	if saved_order.priority < 0 or saved_order.priority > 2 or saved_order.phase_index < 0:
		return "invalid_order"
	var phases := recipe.ordered_processes()
	if saved_order.state == "served":
		if saved_order.phase_index != phases.size() or not saved_order.terminal_reason.is_empty():
			return "invalid_order"
	elif saved_order.phase_index >= phases.size():
		return "invalid_order"
	if saved_order.state in TERMINAL:
		if saved_order.ended_tick < saved_order.arrival_tick or saved_order.ended_tick > state.tick:
			return "invalid_order"
		if saved_order.state == "served" and (saved_order.ended_tick >= saved_order.deadline_tick \
			or saved_order.ended_tick >= data.closing_tick):
			return "invalid_order"
		if saved_order.state == "cancelled" and saved_order.terminal_reason != "player_cancelled":
			return "invalid_order"
		if saved_order.state == "expired" and saved_order.terminal_reason not in ["deadline", "service_closed"]:
			return "invalid_order"
		if saved_order.state == "expired" and saved_order.terminal_reason == "deadline" \
			and saved_order.ended_tick != saved_order.deadline_tick:
			return "invalid_order"
		if saved_order.state == "expired" and saved_order.terminal_reason == "service_closed" \
			and (saved_order.ended_tick != data.closing_tick or saved_order.deadline_tick <= data.closing_tick):
			return "invalid_order"
	else:
		if not saved_order.terminal_reason.is_empty() or saved_order.ended_tick != -1:
			return "invalid_order"
		if state.tick >= saved_order.deadline_tick:
			return "invalid_order"
	if not saved_order.wait_reason is String or saved_order.wait_reason not in WAIT_REASONS:
		return "invalid_order"
	if not saved_order.wait_detail is String or saved_order.wait_detail not in ["", "responsible_employee_busy"]:
		return "invalid_order"
	if saved_order.state != "waiting" and (not saved_order.wait_reason.is_empty() or not saved_order.wait_detail.is_empty()):
		return "invalid_order"
	if not saved_order.wait_detail.is_empty() and saved_order.wait_reason != "no_responsible_employee":
		return "invalid_order"
	for field: String in ["raw_consumed", "ingredients_reserved", "input_consumed", "uses_prepared",
		"intermediate_ready", "intermediate_consumed", "has_result", "carrying"]:
		if not saved_order[field] is bool:
			return "invalid_order"
	if not saved_order.reserved_inputs is Dictionary:
		return "invalid_order"
	if not saved_order.metrics is Dictionary or not _valid_tile(saved_order.result_position):
		return "invalid_order"
	if saved_order.raw_consumed != (saved_order.input_consumed and not saved_order.uses_prepared):
		return "invalid_consumption"
	if (saved_order.state in ["working", "served"] or saved_order.phase_index > 0) and not saved_order.input_consumed:
		return "invalid_consumption"
	if saved_order.uses_prepared and recipe.prepared_ingredient_id.is_empty():
		return "invalid_consumption"
	if saved_order.ingredients_reserved:
		if saved_order.input_consumed or saved_order.state != "moving" or saved_order.reserved_inputs.is_empty():
			return "invalid_reservation"
	else:
		if not saved_order.reserved_inputs.is_empty():
			return "invalid_reservation"
	if saved_order.ingredients_reserved:
		var expected_inputs: Dictionary = {recipe.prepared_ingredient_id: 1} if saved_order.uses_prepared else recipe.ingredients
		if saved_order.reserved_inputs != expected_inputs:
			return "invalid_reservation"
	if saved_order.carrying and (saved_order.state != "moving" or not saved_order.has_result):
		return "invalid_order"
	if saved_order.state in ["waiting", "moving", "working"]:
		var expected_has_result: bool = saved_order.state == "working" or saved_order.phase_index > 0
		if saved_order.has_result != expected_has_result:
			return "invalid_order"
		if saved_order.input_consumed != expected_has_result:
			return "invalid_consumption"
		var expected_intermediate_ready: bool = saved_order.uses_prepared and saved_order.input_consumed
		var expected_intermediate_consumed: bool = false
		for index: int in saved_order.phase_index:
			if phases[index].id == "cook" and expected_intermediate_ready:
				expected_intermediate_ready = false
				expected_intermediate_consumed = true
			if phases[index].id == "prep":
				expected_intermediate_ready = true
		if saved_order.state == "working" and phases[saved_order.phase_index].id == "cook" \
			and expected_intermediate_ready:
			expected_intermediate_ready = false
			expected_intermediate_consumed = true
		if saved_order.intermediate_ready != expected_intermediate_ready \
			or saved_order.intermediate_consumed != expected_intermediate_consumed:
			return "invalid_consumption"
	if saved_order.has_result and not routes.is_walkable(_array_tile(saved_order.result_position)):
		return "invalid_order"
	if saved_order.intermediate_ready and saved_order.intermediate_consumed:
		return "invalid_consumption"
	if (saved_order.intermediate_ready or saved_order.intermediate_consumed) and not saved_order.input_consumed:
		return "invalid_consumption"
	if saved_order.state in TERMINAL and (saved_order.has_result or saved_order.carrying):
		return "invalid_order"
	var has_task: bool = task_by_order.has(saved_order.id)
	if has_task != (saved_order.state in ["moving", "working"]):
		return "invalid_task_link"
	if not _valid_metrics(saved_order.metrics, saved_order, state.tick):
		return "invalid_metrics"
	if saved_order.state in ["waiting", "moving"] and saved_order.has_result and saved_order.metrics.no_route == 0:
		var previous_index: int = saved_order.phase_index - 1
		if previous_index >= 0 and saved_order.uses_prepared and phases[previous_index].id == "prep":
			previous_index -= 1
		var result_at_completed_station := false
		if previous_index >= 0:
			for completed_station: StationDef in data.stations:
				if completed_station.role == phases[previous_index].station_role \
					and completed_station.work_position == _array_tile(saved_order.result_position):
					result_at_completed_station = true
		if not result_at_completed_station:
			return "invalid_order"
	if has_task:
		var task: Dictionary = task_by_order[saved_order.id]
		var station := _station_for(data, task.station_id)
		if station == null or station.role != phases[saved_order.phase_index].station_role:
			return "invalid_task_link"
		if saved_order.state == "moving":
			if task.started_tick != -1 or task.completion_tick != -1:
				return "invalid_task"
			if task.collection_index >= 0:
				if not saved_order.has_result:
					return "invalid_path"
				if saved_order.carrying != (task.path_index >= task.collection_index):
					return "invalid_path"
				if _array_tile(task.path[task.collection_index]) != _array_tile(saved_order.result_position):
					return "invalid_path"
			elif saved_order.carrying or saved_order.has_result:
				return "invalid_path"
		else:
			if not saved_order.has_result or _array_tile(saved_order.result_position) != station.work_position:
				return "invalid_task"
			if task.path_index != task.path.size() - 1 or task.started_tick < 0 or task.started_tick > state.tick:
				return "invalid_task"
			if task.completion_tick != task.started_tick + phases[saved_order.phase_index].duration_ticks \
				or task.completion_tick <= state.tick:
				return "invalid_task"
			var expected_working_ticks: int = state.tick - task.started_tick + 1
			for index: int in saved_order.phase_index:
				if not saved_order.uses_prepared or phases[index].id != "prep":
					expected_working_ticks += phases[index].duration_ticks
			if saved_order.metrics.working != expected_working_ticks:
				return "invalid_metrics"
	return ""


static func _valid_metrics(metrics: Dictionary, saved_order: Dictionary, current_tick: int) -> bool:
	if not _exact_fields(metrics, METRIC_KEYS):
		return false
	for key: String in METRIC_KEYS:
		if not metrics[key] is int or metrics[key] < 0:
			return false
	if metrics.responsible_employee_busy > metrics.no_responsible_employee:
		return false
	var primary: int = metrics.missing_ingredients + metrics.no_responsible_employee + metrics.station_in_use \
		+ metrics.no_route + metrics.moving + metrics.working
	var expected: int = saved_order.ended_tick - saved_order.arrival_tick if saved_order.state in TERMINAL \
		else current_tick - saved_order.arrival_tick + 1
	return primary == expected


static func _employees_restore_error(data: Definitions, routes: GridRoutes, employees: Array,
	task_by_order: Dictionary, order_ids: Dictionary) -> String:
	if employees.size() != data.employees.size():
		return "invalid_employee"
	var employee_by_id: Dictionary = {}
	for saved_employee: Variant in employees:
		var fields: Array[String] = ["id", "tile", "next_tile", "progress", "duty", "pending_duty", "order_id"]
		if not _exact_fields(saved_employee, fields):
			return "invalid_employee"
		if not saved_employee.id is String or employee_by_id.has(saved_employee.id):
			return "invalid_employee"
		if not _employee_exists(data, saved_employee.id) or not _valid_tile(saved_employee.tile) \
			or not _valid_tile(saved_employee.next_tile):
			return "invalid_employee"
		if not routes.is_walkable(_array_tile(saved_employee.tile)) or not routes.is_walkable(_array_tile(saved_employee.next_tile)):
			return "invalid_path"
		if not saved_employee.progress is int or saved_employee.progress < 0 or saved_employee.progress >= MOVE_TICKS:
			return "invalid_employee"
		if not saved_employee.duty is String or saved_employee.duty not in DUTIES:
			return "invalid_employee"
		if not saved_employee.pending_duty is String or (not saved_employee.pending_duty.is_empty() \
			and saved_employee.pending_duty not in DUTIES):
			return "invalid_employee"
		if not saved_employee.order_id is String:
			return "invalid_employee"
		if saved_employee.order_id.is_empty():
			if saved_employee.progress != 0 or saved_employee.tile != saved_employee.next_tile \
				or not saved_employee.pending_duty.is_empty():
				return "invalid_employee"
		else:
			if not order_ids.has(saved_employee.order_id) or not task_by_order.has(saved_employee.order_id):
				return "invalid_task_link"
			var saved_order: Dictionary = order_ids[saved_employee.order_id]
			var recipe: RecipeDef = data.recipe_for(saved_order.recipe_id)
			if recipe == null or saved_employee.duty not in ["all", recipe.cook_role]:
				return "invalid_employee"
			var task: Dictionary = task_by_order[saved_employee.order_id]
			if task.employee_id != saved_employee.id:
				return "invalid_task_link"
			if _array_tile(task.path[task.path_index]) != _array_tile(saved_employee.tile):
				return "invalid_path"
			var expected_next := _array_tile(task.path[task.path_index + 1]) \
				if task.path_index + 1 < task.path.size() else _array_tile(saved_employee.tile)
			if _array_tile(saved_employee.next_tile) != expected_next:
				return "invalid_path"
			if task.started_tick >= 0 and saved_employee.progress != 0:
				return "invalid_employee"
			if saved_order.state == "moving" and saved_order.metrics.no_route == 0 \
				and saved_employee.progress != saved_order.metrics.moving % MOVE_TICKS:
				return "invalid_employee"
		employee_by_id[saved_employee.id] = saved_employee
	for task: Dictionary in task_by_order.values():
		if not order_ids.has(task.order_id) or not employee_by_id.has(task.employee_id):
			return "invalid_task_link"
		if employee_by_id[task.employee_id].order_id != task.order_id:
			return "invalid_task_link"
	return ""


static func _commands_restore_error(state: Dictionary, order_ids: Dictionary, data: Definitions) -> String:
	var sequences: Dictionary = {}
	var previous_apply_tick: int = -1
	var previous_sequence: int = -1
	for saved_command: Variant in state.commands:
		var fields: Array[String] = ["kind", "target_id", "apply_tick", "sequence", "value"]
		if not _exact_fields(saved_command, fields):
			return "invalid_command"
		if not saved_command.kind is String or not saved_command.target_id is String \
			or not saved_command.apply_tick is int or not saved_command.sequence is int:
			return "invalid_command"
		if saved_command.apply_tick <= state.tick or saved_command.sequence <= 0 \
			or saved_command.sequence > state.last_sequence or sequences.has(saved_command.sequence):
			return "invalid_command_sequence"
		if saved_command.apply_tick < previous_apply_tick or (saved_command.apply_tick == previous_apply_tick \
			and saved_command.sequence <= previous_sequence):
			return "invalid_command_sequence"
		match saved_command.kind:
			"set_duty":
				if not _employee_exists(data, saved_command.target_id) or not saved_command.value is String \
					or saved_command.value not in DUTIES:
					return "invalid_command"
			"set_priority":
				if not order_ids.has(saved_command.target_id) or not saved_command.value is int \
					or saved_command.value < 0 or saved_command.value > 2:
					return "invalid_command"
			"cancel_order":
				if not order_ids.has(saved_command.target_id) or saved_command.value != null:
					return "invalid_command"
			_:
				return "invalid_command"
		sequences[saved_command.sequence] = true
		previous_apply_tick = saved_command.apply_tick
		previous_sequence = saved_command.sequence
	return ""


static func _exact_fields(value: Variant, fields: Array[String]) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _valid_tile(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] is int and value[1] is int


static func _employee_exists(data: Definitions, employee_id: String) -> bool:
	for employee: Definitions.EmployeeDef in data.employees:
		if employee.id == employee_id:
			return true
	return false


static func _inventory_restore_error(data: Definitions, state: Dictionary, preparation: Dictionary) -> String:
	var initial_inventory: Dictionary = {}
	if data.supports_preparation() or not preparation.is_empty():
		var initial := PreparationPlan.initial_state(data, preparation)
		if not initial.errors.is_empty():
			return "invalid_preparation"
		initial_inventory = initial.inventory.duplicate()
	else:
		for ingredient: Definitions.IngredientDef in data.ingredients:
			initial_inventory[ingredient.id] = data.purchases.get(ingredient.id, 0)
	if state.inventory.size() != initial_inventory.size():
		return "invalid_inventory"
	for ingredient_id: String in initial_inventory:
		if not state.inventory.get(ingredient_id) is int or state.inventory[ingredient_id] < 0:
			return "invalid_inventory"
	for saved_order: Variant in state.orders:
		if not saved_order is Dictionary or not saved_order.get("recipe_id") is String:
			return "invalid_order"
		if not saved_order.get("input_consumed") is bool or not saved_order.get("uses_prepared") is bool:
			return "invalid_order"
		if not saved_order.input_consumed:
			continue
		var recipe: RecipeDef = data.recipe_for(saved_order.recipe_id)
		if recipe == null:
			return "invalid_order"
		if saved_order.uses_prepared:
			if recipe.prepared_ingredient_id.is_empty() or not initial_inventory.has(recipe.prepared_ingredient_id):
				return "invalid_order"
			initial_inventory[recipe.prepared_ingredient_id] -= 1
		else:
			for ingredient_id: String in recipe.ingredients:
				initial_inventory[ingredient_id] -= recipe.ingredients[ingredient_id]
	if state.inventory != initial_inventory:
		return "invalid_inventory"
	return ""


static func _consumed_cost(data: Definitions, order: OrderState) -> int:
	if not order.input_consumed:
		return 0
	if order.uses_prepared:
		return data.ingredient_for(order.recipe.prepared_ingredient_id).unit_cost
	var result: int = 0
	for ingredient_id: String in order.recipe.ingredients:
		result += data.ingredient_for(ingredient_id).unit_cost * order.recipe.ingredients[ingredient_id]
	return result


static func _station_for(data: Definitions, station_id: String) -> StationDef:
	for station: StationDef in data.stations:
		if station.id == station_id:
			return station
	return null


static func _array_tile(coordinates: Array) -> Vector2i:
	return Vector2i(coordinates[0], coordinates[1])


func state_hash() -> String:
	var canonical := snapshot()
	canonical.erase("events")
	return JSON.stringify(canonical, "", true).sha256_text()


func events() -> Array[Dictionary]:
	return _events.duplicate(true)


static func _tile_array(tile: Vector2i) -> Array[int]:
	return [tile.x, tile.y]
