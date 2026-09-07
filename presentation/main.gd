extends Control

## Displays service snapshots and submits commands at the next tick boundary.

enum State { READY, RUNNING, PAUSED, CLOSED }

const AppLifecycle := preload("res://platform/app_lifecycle.gd")
const SafeAreaSource := preload("res://platform/safe_area.gd")
const Definitions := preload("res://content/definitions.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const TickDriver := preload("res://presentation/tick_driver.gd")
const KitchenBoard := preload("res://presentation/kitchen_board.gd")
const STATUS_TEXT := {
	State.READY: "준비 완료 · 시작을 눌러 주방을 확인하세요",
	State.RUNNING: "진행 중 · 언제든지 일시정지할 수 있습니다",
	State.PAUSED: "일시정지 · 재개를 눌러 계속하세요",
	State.CLOSED: "영업 종료 · 결과를 확인하고 다시 준비할 수 있습니다",
}
const STATE_TEXT := {"waiting": "대기", "moving": "이동", "working": "작업", "served": "제공 완료", "cancelled": "취소", "expired": "미제공"}
const PHASE_TEXT := {"pickup": "재료 수거", "cook": "조리", "serve": "제공", "": "완료"}
const WAIT_TEXT := {"missing_ingredients": "재료 부족", "no_responsible_employee": "담당 없음", "responsible_employee_busy": "담당 직원 작업 중", "station_in_use": "작업대 사용 중", "no_route": "경로 없음", "": ""}
const DUTY_TEXT: Array[String] = ["전체 담당", "냉식 담당", "온식 담당", "담당 해제"]

var state: State = State.READY
var input_actions: int = 0
var elapsed_seconds: float = 0.0
var shown_tenths: int = -1
var last_usable_area: Rect2 = Rect2()
var last_canvas_size: Vector2 = Vector2.ZERO
var definitions: Definitions
var simulation: ServiceSim
var driver: TickDriver
var selected_order_id: String = ""
var command_sequence: int = 0
var latest_view: Dictionary = {}
var order_buttons: Dictionary[String, Button] = {}
var duty_buttons: Array[OptionButton] = []
var duty_labels: Array[Label] = []
var speed_buttons: Array[Button] = []
var compact_layout: bool = true

@onready var start_button: Button = $SafeArea/Layout/Controls/Start
@onready var pause_button: Button = $SafeArea/Layout/Controls/Pause
@onready var resume_button: Button = $SafeArea/Layout/Controls/Resume
@onready var counter: Label = $SafeArea/Layout/Header/Counter
@onready var status_label: Label = $SafeArea/Layout/Status
@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource
@onready var lifecycle: AppLifecycle = $Lifecycle
@onready var summary_label: Label = $SafeArea/Layout/Kitchen/Body/KitchenView/Summary
@onready var board: KitchenBoard = $SafeArea/Layout/Kitchen/Body/KitchenView/Board
@onready var employee_controls: HBoxContainer = $SafeArea/Layout/Kitchen/Body/KitchenView/Employees
@onready var order_list: VBoxContainer = $SafeArea/Layout/Kitchen/Body/Side/OrdersScroll/Orders
@onready var detail_panel: VBoxContainer = $SafeArea/Layout/Kitchen/Body/Side/Details
@onready var details_toggle: Button = $SafeArea/Layout/Kitchen/Body/Side/DetailsToggle
@onready var detail_label: Label = $SafeArea/Layout/Kitchen/Body/Side/Details/Selected
@onready var priority_up_button: Button = $SafeArea/Layout/Kitchen/Body/Side/Details/Actions/PriorityUp
@onready var priority_down_button: Button = $SafeArea/Layout/Kitchen/Body/Side/Details/Actions/PriorityDown
@onready var cancel_button: Button = $SafeArea/Layout/Kitchen/Body/Side/Details/Actions/Cancel
@onready var feedback_label: Label = $SafeArea/Layout/Kitchen/Body/Side/Feedback
@onready var remaining_label: Label = $SafeArea/Layout/Header/Remaining
@onready var restart_button: Button = $SafeArea/Layout/Controls/Restart


func _ready() -> void:
	start_button.pressed.connect(_record_input.bind("start"))
	start_button.pressed.connect(_start)
	pause_button.pressed.connect(_record_input.bind("pause"))
	pause_button.pressed.connect(_pause)
	resume_button.pressed.connect(_record_input.bind("resume"))
	resume_button.pressed.connect(_resume)
	lifecycle.backgrounded.connect(_pause)
	safe_area_source.changed.connect(_on_safe_area_changed)
	resized.connect(_update_safe_area)
	resized.connect(_update_layout)
	priority_up_button.pressed.connect(_change_priority.bind(1))
	priority_down_button.pressed.connect(_change_priority.bind(-1))
	cancel_button.pressed.connect(func() -> void: submit_command("cancel_order", selected_order_id, null))
	details_toggle.pressed.connect(_toggle_details)
	restart_button.pressed.connect(_restart)
	speed_buttons = [$SafeArea/Layout/Controls/Speed1, $SafeArea/Layout/Controls/Speed2, $SafeArea/Layout/Controls/Speed4]
	for index: int in speed_buttons.size():
		speed_buttons[index].pressed.connect(_set_speed.bind([1, 2, 4][index]))
	_new_service()
	_update_safe_area()
	_update_layout()
	_refresh()


func _record_input(action: String) -> void:
	input_actions += 1
	if OS.is_debug_build():
		print("M0_INPUT action=%s total=%d" % [action, input_actions])


func _process(delta: float) -> void:
	advance(delta)


## Supplies elapsed time only while running; paused wall time never enters the accumulator.
func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	var previous_tick := simulation.tick
	driver.advance_microseconds(roundi(delta * 1000000.0))
	elapsed_seconds = simulation.tick / 10.0
	if simulation.closed:
		_set_state(State.CLOSED)
	elif previous_tick != simulation.tick:
		_refresh_service()
		_show_counter()


func is_running() -> bool:
	return state == State.RUNNING


func _start() -> void:
	if state == State.READY and simulation.errors.is_empty():
		_set_state(State.RUNNING)


func _pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)


func _resume() -> void:
	if state == State.PAUSED:
		_set_state(State.RUNNING)


func _set_state(next: State) -> void:
	state = next
	driver.set_paused(state != State.RUNNING)
	_refresh()


func _refresh() -> void:
	start_button.disabled = state != State.READY or not simulation.errors.is_empty()
	pause_button.disabled = state != State.RUNNING
	resume_button.disabled = state != State.PAUSED
	restart_button.visible = state == State.CLOSED
	status_label.text = STATUS_TEXT[state]
	if not simulation.errors.is_empty():
		status_label.text = "주방 데이터를 불러올 수 없습니다"
	_refresh_service()
	_show_counter()


func _show_counter() -> void:
	var tenths := int(elapsed_seconds * 10.0)
	if tenths == shown_tenths:
		return
	shown_tenths = tenths
	counter.text = "%05.1f초" % elapsed_seconds
	remaining_label.text = "남은 시간 %05.1f초  ·  " % ((definitions.closing_tick - simulation.tick) / 10.0)


func _new_service() -> void:
	definitions = load("res://content/m1_first_service.tres") as Definitions
	simulation = ServiceSim.new(definitions)
	driver = TickDriver.new(simulation)
	selected_order_id = ""
	command_sequence = 0
	elapsed_seconds = 0.0
	shown_tenths = -1
	feedback_label.text = ""
	for button: Button in order_buttons.values():
		order_list.remove_child(button)
		button.queue_free()
	order_buttons.clear()
	if not simulation.errors.is_empty():
		return
	if duty_buttons.is_empty():
		for index: int in definitions.employees.size():
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			employee_controls.add_child(column)
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 20)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(label)
			duty_labels.append(label)
			var button := OptionButton.new()
			button.custom_minimum_size = Vector2(64, 64)
			for title: String in DUTY_TEXT:
				button.add_item(title)
			button.item_selected.connect(_set_duty.bind(definitions.employees[index].id))
			column.add_child(button)
			duty_buttons.append(button)


func _restart() -> void:
	if state == State.CLOSED:
		_new_service()
		_set_state(State.READY)


func submit_command(kind: String, target_id: String, value: Variant) -> Dictionary:
	var result := simulation.enqueue_command({"kind": kind, "target_id": target_id,
		"value": value, "apply_tick": simulation.tick + 1, "sequence": command_sequence + 1})
	if result.accepted:
		command_sequence += 1
		feedback_label.text = "적용 대기 · 재개하면 반영됩니다" if state == State.PAUSED else "적용 대기 · 곧 반영됩니다"
	else:
		feedback_label.text = "명령을 적용할 수 없습니다 · 대상과 상태를 확인하세요"
	_refresh_service()
	return result


func select_order(order_id: String) -> void:
	selected_order_id = order_id
	_refresh_service()


func _change_priority(amount: int) -> void:
	for order: Dictionary in latest_view.orders:
		if order.id == selected_order_id:
			var value: int = order.priority
			for command: Dictionary in latest_view.commands:
				if command.kind == "set_priority" and command.target_id == order.id:
					value = command.value
			submit_command("set_priority", order.id, clampi(value + amount, 0, 2))
			return


func _set_duty(index: int, employee_id: String) -> void:
	submit_command("set_duty", employee_id, ServiceSim.DUTIES[index])


func _set_speed(value: int) -> void:
	driver.set_speed(value)
	_refresh_service()


func _update_layout() -> void:
	if size.y > 0:
		set_compact_layout(size.x / size.y >= 1.7)


func set_compact_layout(value: bool) -> void:
	compact_layout = value
	details_toggle.visible = value
	if not value:
		detail_panel.visible = true
	_update_details_toggle()


func _toggle_details() -> void:
	detail_panel.visible = not detail_panel.visible
	_update_details_toggle()


func _update_details_toggle() -> void:
	details_toggle.text = "주문 상세 접기" if detail_panel.visible else "주문 상세 펼치기"


func _refresh_service() -> void:
	latest_view = simulation.snapshot()
	if not latest_view.errors.is_empty():
		board.show_state(null, {})
		summary_label.text = "주방 데이터 오류 · 영업을 시작할 수 없습니다"
		detail_label.text = "주문을 불러올 수 없습니다"
		for button: Button in [start_button, pause_button, resume_button, priority_up_button, priority_down_button, cancel_button] + speed_buttons:
			button.disabled = true
		for button: OptionButton in duty_buttons:
			button.disabled = true
		restart_button.visible = false
		return
	board.show_state(definitions, latest_view)
	_show_summary()
	for index: int in speed_buttons.size():
		speed_buttons[index].disabled = driver.speed == [1, 2, 4][index] or state == State.CLOSED
	for order: Dictionary in latest_view.orders:
		if selected_order_id.is_empty():
			selected_order_id = order.id
		if not order_buttons.has(order.id):
			var button := Button.new()
			button.custom_minimum_size = Vector2(64, 64)
			button.add_theme_font_size_override("font_size", 20)
			button.pressed.connect(select_order.bind(order.id))
			order_list.add_child(button)
			order_buttons[order.id] = button
		var selected := "▶ " if order.id == selected_order_id else ""
		var detail: String = _order_status(order)
		order_buttons[order.id].text = "%s%s %s · 우선 %d\n%s" % [selected, order.id.trim_prefix("order_"), order.name, order.priority, detail]
	_show_selected_order()
	for index: int in latest_view.employees.size():
		var employee: Dictionary = latest_view.employees[index]
		var chosen: String = employee.pending_duty if not employee.pending_duty.is_empty() else employee.duty
		for command: Dictionary in latest_view.commands:
			if command.kind == "set_duty" and command.target_id == employee.id:
				chosen = command.value
		duty_buttons[index].select(ServiceSim.DUTIES.find(chosen))
		duty_buttons[index].disabled = state == State.CLOSED
		var activity := "작업 중" if not employee.order_id.is_empty() else _employee_wait(employee)
		if not employee.pending_duty.is_empty():
			activity = "현재 공정 후 담당 변경"
		duty_labels[index].text = "직원 %d · %s" % [index + 1, activity]
	if not latest_view.commands.is_empty():
		feedback_label.text = "적용 대기 %d건%s" % [latest_view.commands.size(), " · 재개하면 반영" if state == State.PAUSED else ""]
	elif feedback_label.text.begins_with("적용 대기"):
		feedback_label.text = "명령 반영 완료"
	for event: Dictionary in driver.take_events():
		if event.kind == "command_rejected":
			feedback_label.text = "주문 상태가 바뀌어 명령을 적용하지 못했습니다"


func _show_summary() -> void:
	var accounting: Dictionary = latest_view.accounting
	if state == State.CLOSED:
		var total: int = latest_view.orders.size()
		var rate: float = accounting.served * 100.0 / maxi(total, 1)
		summary_label.text = "제공 %d / %d건 (%.0f%%) · 취소 %d · 미제공 %d\n매출 %s · 재료비 %s · 인건비 %s\n폐기 %s · 손익 %s · 남은 예산 %s" % [accounting.served, total, rate, accounting.cancelled, accounting.expired, _money(accounting.revenue), _money(accounting.purchased_cost), _money(accounting.labor_cost), _money(accounting.waste_cost), _money(accounting.profit), _money(accounting.cash)]
	elif state == State.READY:
		var menus: PackedStringArray = []
		for recipe_id: String in definitions.menu_ids:
			menus.append(definitions.recipe_for(recipe_id).display_name)
		summary_label.text = "메뉴 · %s\n예산 %s · 재료비 %s · 인건비 %s\n채소 %d · 곡물 %d · 단백질 %d · 주문 %d건" % [" / ".join(menus), _money(definitions.starting_budget), _money(accounting.purchased_cost), _money(accounting.labor_cost), latest_view.inventory.vegetable, latest_view.inventory.grain, latest_view.inventory.protein, definitions.order_count]
	else:
		summary_label.text = "제공 %d건 · 매출 %s\n남은 재료 · 채소 %d / 곡물 %d / 단백질 %d" % [accounting.served, _money(accounting.revenue), latest_view.inventory.vegetable, latest_view.inventory.grain, latest_view.inventory.protein]


func _order_status(order: Dictionary) -> String:
	if order.state in ServiceSim.TERMINAL:
		return STATE_TEXT[order.state]
	var description: String = PHASE_TEXT[order.phase_id] + " · " + STATE_TEXT[order.state]
	if order.state == "waiting":
		description = WAIT_TEXT[order.wait_detail if not order.wait_detail.is_empty() else order.wait_reason]
	return "%s · %.1f초 남음" % [description, maxf(0, (order.deadline_tick - simulation.tick) / 10.0)]


func _show_selected_order() -> void:
	priority_up_button.disabled = true
	priority_down_button.disabled = true
	cancel_button.disabled = true
	detail_label.text = "주문을 선택하세요"
	for order: Dictionary in latest_view.orders:
		if order.id != selected_order_id:
			continue
		detail_label.text = "%s · 우선순위 %d\n%s" % [order.name, order.priority, _order_status(order)]
		if order.state not in ServiceSim.TERMINAL:
			var priority: int = order.priority
			for command: Dictionary in latest_view.commands:
				if command.kind == "set_priority" and command.target_id == order.id:
					priority = command.value
			priority_up_button.disabled = priority >= 2
			priority_down_button.disabled = priority <= 0
			cancel_button.disabled = false
		return


func _employee_wait(employee: Dictionary) -> String:
	if employee.duty == "off":
		return "신규 담당 없음"
	for order: Dictionary in latest_view.orders:
		var recipe := definitions.recipe_for(order.recipe_id)
		if order.state == "waiting" and (employee.duty == "all" or employee.duty == recipe.cook_role):
			return WAIT_TEXT[order.wait_detail if not order.wait_detail.is_empty() else order.wait_reason]
	return "배정할 주문 없음"


# cspell:ignore absi
static func _money(amount: int) -> String:
	var result := str(absi(amount))
	var index := result.length() - 3
	while index > 0:
		result = result.insert(index, ",")
		index -= 3
	return ("−" if amount < 0 else "") + result


func _on_safe_area_changed(physical_safe: Rect2i) -> void:
	_apply_safe_area(physical_safe, get_viewport().get_screen_transform().affine_inverse())


func _update_safe_area() -> void:
	_on_safe_area_changed(safe_area_source.current())


## Applies the safe-area inset as pure offsets; design padding lives on the MarginContainer.
func _apply_safe_area(physical_safe: Rect2i, to_canvas: Transform2D) -> void:
	var canvas := Rect2(Vector2.ZERO, size)
	var usable := canvas
	if physical_safe.has_area():
		usable = canvas.intersection(to_canvas * Rect2(physical_safe))
		if not usable.has_area():
			usable = canvas
	if usable == last_usable_area and size == last_canvas_size:
		return
	last_usable_area = usable
	last_canvas_size = size
	safe_area.offset_left = usable.position.x
	safe_area.offset_top = usable.position.y
	safe_area.offset_right = usable.end.x - size.x
	safe_area.offset_bottom = usable.end.y - size.y
