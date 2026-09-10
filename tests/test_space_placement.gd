extends "res://tests/harness.gd"

const Definitions := preload("res://content/definitions.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")


func run(_tree: SceneTree) -> void:
	_test_shared_work_position()
	_test_fixed_station()
	_test_cold_hot_clearance()
	_test_restore_selection()
	_test_legacy_layout()
	_test_preview()


func fresh() -> Definitions:
	var data := load("res://content/m2_first_service.tres").duplicate(true) as Definitions
	data.space_rules = true
	return data


func command(plan: PreparationPlan, kind: String, station_id: String, value: Variant, sequence: int = 1) -> Dictionary:
	return plan.apply_command({"kind": kind, "target_id": station_id, "value": value, "apply_tick": 0, "sequence": sequence})


func _test_shared_work_position() -> void:
	var data := fresh()
	data.stations[1].tile = Vector2i(4, 2)
	data.stations[1].work_position = Vector2i(3, 2)
	var plan := PreparationPlan.new(data)
	expect(plan.snapshot().can_start, "the separate work positions can start before the overlap attempt")
	var before := JSON.stringify(plan.snapshot(), "", true)
	var result := command(plan, "move_station", "cold_01", "left")
	expect(not result.accepted and result.reason == "work_position_overlap", "moving two work positions onto one tile is rejected")
	expect(JSON.stringify(plan.snapshot(), "", true) == before, "an overlap rejection preserves choices and command sequence")
	data.stations[1].tile = Vector2i(3, 2)
	data.stations[1].work_position = Vector2i(2, 2)
	expect(data.placement_error() == "work_position_overlap", "initial content cannot share a work position under space rules")
	expect(not PreparationPlan.new(data).snapshot().can_start, "overlapping source work positions cannot start service")


func _test_fixed_station() -> void:
	var data := fresh()
	data.stations[3].fixed = true
	var plan := PreparationPlan.new(data)
	var before := JSON.stringify(plan.snapshot(), "", true)
	for choice: Array in [["move_station", "left"], ["rotate_station", null]]:
		var result := command(plan, choice[0], "pass_01", choice[1])
		expect(not result.accepted and result.reason == "fixed_station", "a fixed pass rejects movement and rotation")
		expect(JSON.stringify(plan.snapshot(), "", true) == before, "fixed-station rejection preserves the complete preparation")
	expect(command(plan, "move_station", "cold_01", "left").accepted, "a movable station still accepts a valid move")


func _test_cold_hot_clearance() -> void:
	var plan := PreparationPlan.new(fresh())
	expect(command(plan, "move_station", "hot_01", "left").accepted, "one tile between cold and hot station bodies is allowed")
	var before := JSON.stringify(plan.snapshot(), "", true)
	var result := command(plan, "move_station", "hot_01", "left", 2)
	expect(not result.accepted and result.reason == "cold_hot_adjacent", "direct cold and hot neighbors are rejected")
	expect(JSON.stringify(plan.snapshot(), "", true) == before, "clearance rejection preserves the accepted layout")
	var data := fresh()
	data.stations[2].tile = Vector2i(6, 1)
	data.stations[2].work_position = Vector2i(6, 2)
	expect(data.placement_error() == "cold_hot_adjacent", "initial content follows the same cold-hot rule")


func _test_restore_selection() -> void:
	var data := fresh()
	data.stations[3].fixed = true
	var started := command(PreparationPlan.new(data), "start", "", null)
	expect(started.accepted, "the experiment default preparation commits")
	var selection: Dictionary = started.selection.duplicate(true)
	selection.placements.pass_01.tile = [8, 5]
	selection.placements.pass_01.work_position = [8, 4]
	var restored := PreparationPlan.new(data, selection)
	expect(not restored.snapshot().can_start and "fixed_station" in restored.snapshot().errors, "restoring preparation cannot bypass a fixed station")
	selection = started.selection.duplicate(true)
	selection.placements.cold_01.tile = [3, 2]
	selection.placements.cold_01.work_position = [2, 2]
	restored = PreparationPlan.new(data, selection)
	expect(not restored.snapshot().can_start and "work_position_overlap" in restored.snapshot().errors, "restoring preparation cannot bypass independent work positions")


func _test_legacy_layout() -> void:
	var data := fresh()
	data.space_rules = false
	data.stations[1].tile = Vector2i(3, 2)
	data.stations[1].work_position = Vector2i(2, 2)
	expect(data.placement_error().is_empty(), "baseline content keeps its existing placement contract")
	var plan := PreparationPlan.new(data)
	expect(command(plan, "move_station", "pass_01", "left").accepted, "baseline pass relocation remains compatible")


func _test_preview() -> void:
	var data := fresh()
	data.stations[3].fixed = true
	var plan := PreparationPlan.new(data)
	var state := plan.snapshot()
	expect(state.get("space_rules", false), "preparation exposes its active spatial rule set")
	var pass_view: Dictionary = state.stations[3]
	expect(pass_view.get("fixed", false), "a fixed station is identified before a placement attempt")
	var options: Dictionary = pass_view.get("placement_options", {})
	expect(options.get("left") == "fixed_station" and options.get("rotate") == "fixed_station", "fixed movement and rotation are explained before tapping")
	expect(command(plan, "move_station", "hot_01", "left").accepted, "the clearance preview fixture starts one move before the limit")
	state = plan.snapshot()
	options = state.stations[2].get("placement_options", {})
	expect(options.get("left") == "cold_hot_adjacent" and options.get("right") == "", "placement preview distinguishes an invalid direction from a valid one")
	var sequence: int = state.sequence
	plan.snapshot()
	expect(plan.snapshot().sequence == sequence, "reading placement previews never submits a command")
