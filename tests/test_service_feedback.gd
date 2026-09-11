extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceAnalysis := preload("res://sim/service_analysis.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const TickDriver := preload("res://presentation/tick_driver.gd")


func run(tree: SceneTree) -> void:
	_test_hot_queue_limits()
	_test_incremental_prep_advice()
	_test_recommendation_branches()
	_test_no_priority_advice_without_evidence()
	_test_service_events()
	await _test_live_prepared_feedback(tree)
	await _test_fast_chatter_lifetime(tree)


func _test_hot_queue_limits() -> void:
	var scenario: Resource = load("res://content/campaign/scenarios/hot_queue.tres")
	var plan := PreparationPlan.new(scenario)
	expect(_prepare(plan, "set_prep", "grill", 4).accepted, "hot queue accepts four grill preparations")
	expect(_prepare(plan, "set_menu_priority", "grill", 2).accepted, "hot queue accepts maximum grill priority")
	var started: Dictionary = _prepare(plan, "start", "", null)
	expect(started.accepted, "hot queue feedback fixture starts from real preparation")
	if not started.accepted:
		return
	var simulation := _finish_service(started, 1)
	var report: Dictionary = ServiceAnalysis.build(started.definitions, simulation.snapshot(), started.selection)
	var fast_simulation := _finish_service(started, 4)
	var fast_report: Dictionary = ServiceAnalysis.build(started.definitions, fast_simulation.snapshot(), started.selection)
	expect(fast_simulation.state_hash() == simulation.state_hash() and fast_report == report,
		"hot queue final state and service analysis are identical at 1x and 4x")
	expect(report.prep.grill.planned == 4 and report.prep.grill.used == 4 and report.prep.grill.remaining == 0,
		"analysis reports selected, used, and remaining grill preparation")
	expect(report.priorities.grill.default_priority == 2 and report.priorities.grill.expired > 0,
		"analysis reports the maximum grill priority and its missed orders")
	expect(not _has_action(report.recommendations, "increase_prep", "grill"),
		"full preparation labor never recommends impossible extra grill preparation")
	expect(not _has_action(report.recommendations, "raise_priority", "grill"),
		"maximum menu priority never recommends an impossible priority increase")
	expect(_has_action(report.recommendations, "prep_at_capacity", "grill"),
		"analysis explains that grill preparation already consumes the available labor")
	expect(_has_action(report.recommendations, "purchase_consumed", "protein"),
		"analysis explains when costly purchases were consumed without ingredient shortages")
	var priority_limit := _find_action(report.recommendations, "priority_at_max", "grill")
	expect(not priority_limit.is_empty(),
		"analysis redirects a maximum-priority miss toward its observed bottleneck")
	expect(priority_limit.get("bottleneck") == "employee_busy" and priority_limit.has("bottleneck_ticks"),
		"maximum-priority feedback identifies the largest observed bottleneck and its duration")


func _test_incremental_prep_advice() -> void:
	var scenario: Resource = load("res://content/m2_first_service.tres")
	var plan := PreparationPlan.new(scenario)
	expect(_prepare(plan, "set_prep", "salad", 1).accepted,
		"incremental feedback fixture prepares one salad portion")
	var started: Dictionary = _prepare(plan, "start", "", null)
	expect(started.accepted, "incremental feedback fixture starts from real preparation")
	if not started.accepted:
		return
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while not simulation.closed:
		simulation.step()
	var report: Dictionary = ServiceAnalysis.build(started.definitions, simulation.snapshot(), started.selection)
	var recommendation := _find_action(report.recommendations, "increase_prep", "salad")
	expect(not recommendation.is_empty() and recommendation.amount == 1,
		"prep feedback recommends one incremental change instead of the theoretical maximum")


func _test_no_priority_advice_without_evidence() -> void:
	var priorities := {"salad": {"default_priority": 2, "expired": 1, "revenue": 500,
		"pressure_ticks": 0, "employee_busy_ticks": 0, "station_ticks": 0, "moving_ticks": 0}}
	expect(ServiceAnalysis._priority_recommendation(priorities).is_empty(),
		"maximum priority without observed contention or movement produces no route advice")


func _test_recommendation_branches() -> void:
	var scenario: Resource = load("res://content/m2_first_service.tres")
	var prep: Dictionary = {}
	for recipe_id: String in scenario.menu_ids:
		prep[recipe_id] = {"planned": 0, "remaining": 0, "raw_orders": 0,
			"prep_labor_units": scenario.recipe_for(recipe_id).prep_labor_units}
	prep.salad = {"planned": 3, "remaining": 2, "raw_orders": 0,
		"prep_labor_units": scenario.recipe_for("salad").prep_labor_units}
	var prep_recommendation := ServiceAnalysis._prep_recommendation(scenario, prep, 3)
	expect(prep_recommendation.action == "reduce_prep" and prep_recommendation.amount == 1,
		"remaining prepared stock produces a one-portion reduction experiment")
	var purchase_increase := ServiceAnalysis._ingredient_recommendation({"protein": {
		"purchased": 2, "remaining": 0, "related_shortage_ticks": 10, "unit_cost": 400}})
	expect(purchase_increase.action == "increase_purchase" and purchase_increase.amount == 1,
		"zero stock with observed ingredient shortage produces a one-unit purchase experiment")
	var purchase_reduce := ServiceAnalysis._ingredient_recommendation({"protein": {
		"purchased": 4, "remaining": 2, "related_shortage_ticks": 0, "unit_cost": 400}})
	expect(purchase_reduce.action == "reduce_purchase" and purchase_reduce.amount == 1,
		"remaining purchased stock produces a one-unit reduction experiment")
	var priority_raise := ServiceAnalysis._priority_recommendation({"salad": {"default_priority": 1,
		"expired": 1, "revenue": 500, "pressure_ticks": 10, "employee_busy_ticks": 10,
		"station_ticks": 0, "moving_ticks": 5}})
	expect(priority_raise.action == "raise_priority" and priority_raise.amount == 1,
		"missed orders with observed contention produce a one-level priority experiment")
	_test_purchase_advice_requires_valid_preparation()


func _test_purchase_advice_requires_valid_preparation() -> void:
	var hot_queue: Resource = load("res://content/campaign/scenarios/hot_queue.tres")
	var hot_plan := PreparationPlan.new(hot_queue)
	expect(_prepare(hot_plan, "set_purchase", "protein", 12).accepted,
		"budget fixture accepts the last affordable protein quantity")
	var over_budget: Dictionary = _prepare(hot_plan, "set_purchase", "protein", 13)
	expect(not over_budget.accepted and over_budget.reason == "insufficient_budget",
		"budget fixture rejects the one-unit increase reported by the review")
	var hot_selection: Dictionary = hot_plan.snapshot().selection
	var shortage_view := {"inventory": {"protein": 0}, "orders": [{"recipe_id": "grill",
		"raw_consumed": true, "state": "expired", "metrics": {"missing_ingredients": 10,
		"responsible_employee_busy": 0, "station_in_use": 0, "moving": 0}}]}
	var shortage_report: Dictionary = ServiceAnalysis.build(hot_queue, shortage_view, hot_selection)
	expect(not _has_action(shortage_report.recommendations, "increase_purchase", "protein"),
		"purchase feedback never exceeds the scenario budget")

	var first_shift: Resource = load("res://content/campaign/scenarios/first_shift.tres")
	var minimum_plan := PreparationPlan.new(first_shift)
	expect(_prepare(minimum_plan, "set_purchase", "vegetable", 1).accepted,
		"minimum-stock fixture keeps one sellable salad")
	var minimum_selection: Dictionary = minimum_plan.snapshot().selection
	var invalid_selection := minimum_selection.duplicate(true)
	invalid_selection.purchases.vegetable = 0
	var invalid_plan := PreparationPlan.new(first_shift, invalid_selection)
	var unsellable: Dictionary = _prepare(invalid_plan, "start", "", null)
	expect(not unsellable.accepted and unsellable.reason == "menu_missing_ingredients",
		"minimum-stock fixture rejects the one-unit reduction reported by the review")
	var idle_view := {"inventory": {"vegetable": 1}, "orders": []}
	var idle_report: Dictionary = ServiceAnalysis.build(first_shift, idle_view, minimum_selection)
	expect(not _has_action(idle_report.recommendations, "reduce_purchase", "vegetable"),
		"purchase feedback preserves enough stock to sell every configured menu")


func _test_service_events() -> void:
	var shortage_data: Resource = ResourceLoader.load("res://content/m1_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	shortage_data.order_count = 2
	shortage_data.first_arrival_tick = 1
	shortage_data.arrival_interval_ticks = 1
	shortage_data.menu_ids = ["salad"]
	shortage_data.purchases.vegetable = 1
	var shortage_sim := ServiceSim.new(shortage_data)
	var shortage_events: Array[Dictionary] = _advance_with_events(shortage_sim, 5)
	expect(_event_count(shortage_events, "order_wait_started") == 1,
		"an unchanged ingredient shortage emits one transition event")
	var shortage_event := _first_event(shortage_events, "order_wait_started")
	expect(shortage_event.get("reason") == "missing_ingredients" and shortage_event.get("recipe_id") == "salad",
		"the shortage transition identifies its reason and menu")
	var no_staff_data: Resource = ResourceLoader.load("res://content/m2_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	no_staff_data.order_count = 1
	no_staff_data.first_arrival_tick = 1
	no_staff_data.menu_ids = ["salad"]
	var no_staff_duties: Dictionary = {}
	for employee: Resource in no_staff_data.employees:
		no_staff_duties[employee.id] = "off"
	var no_staff_sim := ServiceSim.new(no_staff_data, null, {"duties": no_staff_duties})
	var no_staff_events := _advance_with_events(no_staff_sim, 5)
	expect(_event_count(no_staff_events, "order_wait_started") == 0,
		"non-ingredient wait transitions do not expand the presentation event contract")

	var prepared_data: Resource = ResourceLoader.load("res://content/m2_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	prepared_data.order_count = 1
	prepared_data.first_arrival_tick = 1
	prepared_data.menu_ids = ["salad"]
	var prepared_sim := ServiceSim.new(prepared_data, null, {"prep_quantities": {"salad": 1}})
	var prepared_events: Array[Dictionary] = _advance_with_events(prepared_sim, 20)
	var depleted := _first_event(prepared_events, "prepared_stock_depleted")
	expect(_event_count(prepared_events, "prepared_stock_depleted") == 1 and depleted.get("recipe_id") == "salad",
		"consuming the last prepared portion emits one menu-specific depletion event")

	var expiry_data: Resource = ResourceLoader.load("res://content/m1_first_service.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	expiry_data.order_count = 1
	expiry_data.first_arrival_tick = 1
	expiry_data.menu_ids = ["salad"]
	expiry_data.recipe_for("salad").patience_ticks = 135
	var expiry_sim := ServiceSim.new(expiry_data)
	var expiry_events: Array[Dictionary] = _advance_with_events(expiry_sim, 136)
	var ended := _first_event(expiry_events, "order_ended")
	expect(ended.get("reason") == "deadline" and ended.get("phase_id") == "serve" and ended.get("recipe_id") == "salad",
		"an order that expires after cooking identifies its final service phase")


func _test_live_prepared_feedback(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", "res://content/m2_first_service.tres")
	var settings_path := "user://service_feedback_%d.json" % Time.get_ticks_usec()
	HarnessSettingsStore.new(settings_path).save_settings({"locale": "ko", "sound_enabled": false, "text_size": "normal"})
	screen.set("settings_path", settings_path)
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	expect(screen.call("submit_preparation", "set_prep", "salad", 1).accepted,
		"live feedback fixture prepares one salad portion")
	screen.get("start_button").pressed.emit()
	screen.call("advance", 2.0)
	var board: Control = screen.get("board")
	var chatter: Variant = board.get("chatter")
	expect(screen.get("duty_labels")[0].text.contains("채소 샐러드") and screen.get("duty_labels")[0].text.contains("프렙 재료 챙기는 중"),
		"live feedback names prepared pickup work")
	expect(chatter is Dictionary and chatter.get("kind") == "prepared_stock_depleted" and chatter.get("text", "").contains("프렙 다 썼다"),
		"the board shows a localized chef bubble when prepared stock runs out")
	var badges: Variant = board.get("employee_badges")
	expect(badges is Dictionary and badges.get("employee_01", {}).get("phase") == "pickup",
		"the board exposes the active phase badge for the assigned employee")
	while screen.get("simulation").snapshot().orders[0].phase_id != "cook" or screen.get("simulation").snapshot().orders[0].state != "working":
		screen.call("advance", 0.1)
	expect(screen.get("duty_labels")[0].text.contains("찬 조리대에서 조리 중"),
		"live feedback names the active cooking station")
	var active_employee: Dictionary = screen.get("simulation").snapshot().employees[0]
	expect(screen.call("submit_command", "set_duty", active_employee.id, active_employee.duty).accepted,
		"live feedback fixture queues a duty change during active cooking")
	screen.call("advance", 0.1)
	expect(screen.get("duty_labels")[0].text.contains("찬 조리대에서 조리 중")
		and screen.get("duty_labels")[0].text.contains("현재 공정 후 담당 변경"),
		"pending duty feedback preserves the current menu and cooking activity")
	while screen.get("simulation").snapshot().orders[0].phase_id != "serve" or screen.get("simulation").snapshot().orders[0].state != "moving":
		screen.call("advance", 0.1)
	expect(screen.get("duty_labels")[0].text.contains("제공대로 운반 중"),
		"live feedback distinguishes carrying a completed dish to the pass")
	expect(screen.get("app_preferences").update_settings({"locale": "en"}).accepted,
		"live feedback fixture switches to English")
	chatter = board.get("chatter")
	expect(screen.get("duty_labels")[0].text.contains("carrying the dish to the pass")
		and chatter is Dictionary and chatter.get("text", "").contains("prep is gone"),
		"locale refresh retranslates the employee activity and visible chef bubble")
	expect(board.call("_phase_mark", "pickup") == "I",
		"the English board translates the compact phase badge")
	screen.get("pause_button").pressed.emit()
	screen.call("_process", 2.19)
	expect(not board.get("chatter").is_empty(), "the chef bubble remains visible before 2.2 real seconds")
	screen.call("_process", 0.02)
	expect(board.get("chatter").is_empty(), "the chef bubble expires after 2.2 real seconds at 1x")
	screen.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(settings_path)
	TranslationServer.set_locale("ko")


func _test_fast_chatter_lifetime(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", "res://content/m2_first_service.tres")
	var settings_path := "user://service_feedback_fast_%d.json" % Time.get_ticks_usec()
	HarnessSettingsStore.new(settings_path).save_settings({"locale": "ko", "sound_enabled": false, "text_size": "normal"})
	screen.set("settings_path", settings_path)
	tree.root.add_child(screen)
	screen.set_process(false)
	await tree.process_frame
	expect(screen.call("submit_preparation", "set_prep", "salad", 1).accepted,
		"fast chatter fixture prepares one salad portion")
	screen.get("start_button").pressed.emit()
	screen.get("speed_buttons")[2].pressed.emit()
	screen.call("advance", 0.5)
	var board: Control = screen.get("board")
	expect(board.get("chatter").get("kind", "") == "prepared_stock_depleted",
		"the 4x driver preserves the prepared-stock event")
	screen.get("pause_button").pressed.emit()
	screen.call("_process", 2.19)
	expect(not board.get("chatter").is_empty(), "the chef bubble remains visible before 2.2 real seconds at 4x")
	screen.call("_process", 0.02)
	expect(board.get("chatter").is_empty(), "the chef bubble expires after 2.2 real seconds at 4x")
	screen.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(settings_path)


func _prepare(plan: RefCounted, kind: String, target_id: String, value: Variant) -> Dictionary:
	return plan.call("apply_command", {"kind": kind, "target_id": target_id, "value": value,
		"apply_tick": 0, "sequence": plan.call("snapshot").sequence + 1})


func _has_action(recommendations: Array, action: String, target_id: String) -> bool:
	return not _find_action(recommendations, action, target_id).is_empty()


func _find_action(recommendations: Array, action: String, target_id: String) -> Dictionary:
	for recommendation: Dictionary in recommendations:
		if recommendation.action == action and recommendation.target_id == target_id:
			return recommendation
	return {}


func _advance_with_events(simulation: RefCounted, target_tick: int) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	while simulation.get("tick") < target_tick and not simulation.get("closed"):
		simulation.call("step")
		collected.append_array(simulation.call("events"))
	return collected


func _finish_service(started: Dictionary, speed: int) -> RefCounted:
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	var driver := TickDriver.new(simulation)
	driver.set_speed(speed)
	driver.set_paused(false)
	while not simulation.closed:
		driver.advance_microseconds(100000)
	return simulation


func _event_count(events: Array[Dictionary], kind: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.kind == kind:
			count += 1
	return count


func _first_event(events: Array[Dictionary], kind: String) -> Dictionary:
	for event: Dictionary in events:
		if event.kind == kind:
			return event
	return {}
