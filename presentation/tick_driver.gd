extends RefCounted

const ServiceSim := preload("res://sim/service_sim.gd")
const TICK_US: int = 100000

var simulation: ServiceSim
var accumulator_us: int = 0
var speed: int = 1
var paused: bool = true
var _pending_events: Array[Dictionary] = []


func _init(service: ServiceSim) -> void:
	simulation = service


func set_paused(value: bool) -> void:
	paused = value


func set_speed(value: int) -> bool:
	if value not in [1, 2, 4]:
		return false
	speed = value
	return true


func advance_microseconds(delta_us: int) -> void:
	if paused or simulation.closed or delta_us <= 0:
		return
	accumulator_us += delta_us * speed
	while accumulator_us >= TICK_US and not simulation.closed:
		accumulator_us -= TICK_US
		simulation.step()
		_pending_events.append_array(simulation.events())


func take_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending_events
	_pending_events = []
	return result
