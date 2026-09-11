extends Control

## Displays service snapshots and submits commands at the next tick boundary.

signal service_closed(snapshot: Dictionary)
signal checkpoint_requested(reason: String)

enum State { READY, RUNNING, PAUSED, CLOSED }

const AppLifecycle := preload("res://platform/app_lifecycle.gd")
const SafeAreaSource := preload("res://platform/safe_area.gd")
const Definitions := preload("res://content/definitions.gd")
const ScenarioDef := preload("res://content/scenario_def.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const ServiceAnalysis := preload("res://sim/service_analysis.gd")
const TickDriver := preload("res://presentation/tick_driver.gd")
const KitchenBoard := preload("res://presentation/kitchen_board.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const PreparationPanel := preload("res://presentation/preparation_panel.gd")
const AppPreferences := preload("res://presentation/app_preferences.gd")
const AudioFeedback := preload("res://presentation/audio_feedback.gd")
const STATUS_TEXT := {
	State.READY: "준비 완료 · 시작을 눌러 주방을 확인하세요",
	State.RUNNING: "진행 중 · 언제든지 일시정지할 수 있습니다",
	State.PAUSED: "일시정지 · 재개를 눌러 계속하세요",
	State.CLOSED: "영업 종료 · 결과를 확인하고 다시 준비할 수 있습니다",
}
const STATE_TEXT := {"waiting": "대기", "moving": "이동", "working": "작업", "served": "제공 완료", "cancelled": "취소", "expired": "미제공"}
const PHASE_TEXT := {"pickup": "재료 수거", "prep": "손질", "cook": "조리", "serve": "제공", "": "완료"}
const WAIT_TEXT := {"missing_ingredients": "재료 부족", "no_responsible_employee": "담당 없음", "responsible_employee_busy": "담당 직원 작업 중", "station_in_use": "작업대 사용 중", "no_route": "경로 없음", "": ""}
const DUTY_TEXT: Array[String] = ["전체 담당", "냉식 담당", "온식 담당", "담당 해제"]
const ANALYSIS_HEADING_COLOR := Color("eab06c")
const ANALYSIS_BODY_COLOR := Color("f5edda")
const ANALYSIS_ACTION_COLOR := Color("a6b5a8")
const ANALYSIS_DETAIL_COLOR := Color("c6c9b8")

@export_file("*.tres") var scenario_path: String = "res://content/m1_first_service.tres"
var scenario_definition: Definitions

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
var details_expanded: bool = false
var preparation: PreparationPlan
var preparation_panel: PreparationPanel
var last_preparation: Dictionary = {}
var analysis_scroll: ScrollContainer
var analysis_label: RichTextLabel
var last_saved_tick: int = -100
var settings_path: String = "user://settings.json"
var app_preferences: AppPreferences
var audio_feedback: AudioFeedback
var settings_button: Button
var settings_dialog: AcceptDialog
var settings_locale: OptionButton
var settings_sound: CheckButton
var settings_text_size: OptionButton
var settings_message: Label
var settings_locale_label: Label
var settings_text_size_label: Label
var feedback_kind: String = ""
var feedback_reason: String = ""
var settings_message_kind: String = ""
var settings_message_reason: String = ""
var modal_open_allowed: Callable
var chatter_event: Dictionary = {}
var chatter_seconds_left: float = 0.0
var chatter_last_tick: Dictionary[String, int] = {}

@onready var start_button: Button = $SafeArea/Layout/Controls/Start
@onready var pause_button: Button = $SafeArea/Layout/Controls/Pause
@onready var resume_button: Button = $SafeArea/Layout/Controls/Resume
@onready var counter: Label = $SafeArea/Layout/Header/Counter
@onready var status_label: Label = $SafeArea/Layout/Status
@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource
@onready var lifecycle: AppLifecycle = $Lifecycle
@onready var summary_label: Label = $SafeArea/Layout/Kitchen/Body/Side/OrdersScroll/Orders/Summary
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
@onready var title_label: Label = $SafeArea/Layout/Header/Title


func _ready() -> void:
	var settings_load := {"accepted": true}
	if app_preferences == null:
		app_preferences = AppPreferences.new(settings_path)
		settings_load = app_preferences.load_settings()
	if not app_preferences.changed.is_connected(_on_preferences_changed):
		app_preferences.changed.connect(_on_preferences_changed)
	audio_feedback = AudioFeedback.new()
	audio_feedback.name = "AudioFeedback"
	add_child(audio_feedback)
	audio_feedback.set_enabled(app_preferences.snapshot().sound_enabled)
	_build_settings()
	if not settings_load.accepted:
		_set_settings_message("error", settings_load.reason)
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
	apply_preferences()


func _record_input(action: String) -> void:
	input_actions += 1
	if OS.is_debug_build():
		print("M0_INPUT action=%s total=%d" % [action, input_actions])


func _process(delta: float) -> void:
	if chatter_seconds_left > 0.0:
		chatter_seconds_left = maxf(0.0, chatter_seconds_left - delta)
		if chatter_seconds_left == 0.0:
			chatter_event.clear()
			board.show_chatter({})
	advance(delta)


func _exit_tree() -> void:
	if audio_feedback != null:
		audio_feedback.set_enabled(false)


## Supplies elapsed time only while running; paused wall time never enters the accumulator.
func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	var previous_tick := simulation.tick
	driver.advance_microseconds(roundi(delta * 1000000.0))
	elapsed_seconds = simulation.tick / 10.0
	if simulation.closed:
		driver.accumulator_us = 0
		_set_state(State.CLOSED)
		service_closed.emit(simulation.snapshot())
	elif previous_tick != simulation.tick:
		_refresh_service()
		_show_counter()
		if simulation.tick - last_saved_tick >= 100:
			checkpoint_requested.emit("automatic")


func is_running() -> bool:
	return state == State.RUNNING


func checkpoint_saved() -> void:
	last_saved_tick = simulation.tick


func pause_after_save_failure() -> void:
	if state != State.RUNNING:
		return
	_set_state(State.PAUSED)
	audio_feedback.suspend()


func restore_service(restored: Dictionary) -> bool:
	if not restored.get("accepted", false):
		return false
	definitions = restored.definitions
	last_preparation = restored.selection.duplicate(true)
	simulation = restored.simulation
	driver = TickDriver.new(simulation)
	driver.set_speed(restored.speed)
	driver.accumulator_us = restored.accumulator_us
	command_sequence = simulation.export_state().last_sequence
	last_saved_tick = simulation.tick
	elapsed_seconds = simulation.tick / 10.0
	shown_tenths = -1
	selected_order_id = ""
	state = State.CLOSED if simulation.closed else State.PAUSED
	driver.set_paused(true)
	_refresh()
	return true


func _start() -> void:
	if state == State.READY and simulation.errors.is_empty():
		if preparation != null:
			var committed := submit_preparation("start", "", null)
			if not committed.accepted:
				return
			definitions = committed.definitions
			last_preparation = committed.selection
			simulation = ServiceSim.new(definitions, null, committed.options)
			if not simulation.errors.is_empty():
				_refresh()
				return
			driver = TickDriver.new(simulation)
			board.selected_station_id = ""
			_set_feedback("")
		audio_feedback.resume()
		_set_state(State.RUNNING)
		checkpoint_requested.emit("preparation")


func _pause() -> void:
	audio_feedback.suspend()
	if state == State.RUNNING:
		_set_state(State.PAUSED)
	elif state != State.PAUSED:
		return
	checkpoint_requested.emit("pause")


func _resume() -> void:
	if state == State.PAUSED:
		audio_feedback.resume()
		_set_state(State.RUNNING)


func _set_state(next: State) -> void:
	var entering_analysis := state != State.CLOSED and next == State.CLOSED
	state = next
	driver.set_paused(state != State.RUNNING)
	if entering_analysis and analysis_scroll != null:
		analysis_scroll.scroll_vertical = 0
	_refresh()


func _refresh() -> void:
	start_button.disabled = state != State.READY or not simulation.errors.is_empty()
	if state == State.READY and preparation != null:
		start_button.disabled = start_button.disabled or not preparation.snapshot().can_start
	pause_button.disabled = state != State.RUNNING
	resume_button.disabled = state != State.PAUSED
	restart_button.visible = state == State.CLOSED
	status_label.text = tr(STATUS_TEXT[state])
	if not simulation.errors.is_empty():
		status_label.text = tr("주방 데이터를 불러올 수 없습니다")
	_refresh_service()
	_show_counter()


func _show_counter() -> void:
	var tenths := int(elapsed_seconds * 10.0)
	if tenths == shown_tenths:
		return
	shown_tenths = tenths
	counter.text = tr("%05.1f초") % elapsed_seconds
	remaining_label.text = tr("남은 시간 %05.1f초  ·  ") % ((definitions.closing_tick - simulation.tick) / 10.0)


func _new_service() -> void:
	var source := scenario_definition if scenario_definition != null else load(scenario_path) as Definitions
	definitions = source
	simulation = ServiceSim.new(source)
	if source.supports_preparation():
		restart_button.text = tr("준비 다시 하기")
		preparation = PreparationPlan.new(source, last_preparation)
		var display := preparation.display_definition()
		if display != null:
			definitions = display
		if preparation_panel == null and display != null:
			preparation_panel = PreparationPanel.new()
			$SafeArea/Layout/Kitchen/Body/Side.add_child(preparation_panel)
			$SafeArea/Layout/Kitchen/Body/Side.move_child(preparation_panel, 0)
			preparation_panel.command_requested.connect(submit_preparation)
			preparation_panel.station_selected.connect(func(station_id: String) -> void:
				board.selected_station_id = station_id
				board.queue_redraw())
			preparation_panel.setup(source)
			analysis_scroll = ScrollContainer.new()
			analysis_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			analysis_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			$SafeArea/Layout/Kitchen/Body/Side.add_child(analysis_scroll)
			analysis_label = RichTextLabel.new()
			analysis_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			analysis_label.fit_content = true
			analysis_label.scroll_active = false
			analysis_label.add_theme_constant_override("line_separation", 3)
			analysis_scroll.add_child(analysis_label)
		if preparation_panel != null:
			board.selected_station_id = preparation_panel.selected_station_id
	driver = TickDriver.new(simulation)
	selected_order_id = ""
	command_sequence = 0
	last_saved_tick = -100
	elapsed_seconds = 0.0
	shown_tenths = -1
	_set_feedback("")
	chatter_event.clear()
	chatter_seconds_left = 0.0
	chatter_last_tick.clear()
	board.show_chatter({})
	for button: Button in order_buttons.values():
		order_list.remove_child(button)
		button.queue_free()
	order_buttons.clear()
	if not simulation.errors.is_empty():
		return
	if duty_buttons.is_empty():
		for employee: Dictionary in simulation.snapshot().employees:
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			employee_controls.add_child(column)
			var label := Label.new()
			label.custom_minimum_size = Vector2(0, 64)
			label.add_theme_font_size_override("font_size", 13)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.max_lines_visible = 3
			column.add_child(label)
			duty_labels.append(label)
			var button := OptionButton.new()
			button.custom_minimum_size = Vector2(64, 64)
			for title: String in DUTY_TEXT:
				button.add_item(tr(title))
			button.item_selected.connect(_set_duty.bind(employee.id))
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
		feedback_kind = "commands_pending"
	else:
		feedback_kind = "command_invalid"
		feedback_reason = result.reason
	_refresh_service()
	return result


func submit_preparation(kind: String, target_id: String, value: Variant) -> Dictionary:
	if preparation == null or state != State.READY:
		return {"accepted": false, "reason": "service_started"}
	var result := preparation.apply_command({"kind": kind, "target_id": target_id, "value": value,
		"apply_tick": 0, "sequence": preparation.snapshot().sequence + 1})
	_set_feedback("preparation_applied" if result.accepted else "preparation_error", result.reason)
	if result.accepted:
		definitions = preparation.display_definition()
	_refresh()
	return result


func select_order(order_id: String) -> void:
	selected_order_id = order_id
	_refresh_service()


func _change_priority(amount: int) -> void:
	for order: Dictionary in latest_view.orders:
		if order.id == selected_order_id:
			var value := _requested_priority(order)
			submit_command("set_priority", order.id, clampi(value + amount, 0, 2))
			return


func _requested_priority(order: Dictionary) -> int:
	var value: int = order.priority
	for command: Dictionary in latest_view.commands:
		if command.kind == "set_priority" and command.target_id == order.id:
			value = command.value
	return value


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
	detail_panel.visible = details_expanded or not value
	_update_board_layout()
	_update_details_toggle()


func _toggle_details() -> void:
	detail_panel.visible = not detail_panel.visible
	details_expanded = detail_panel.visible
	_update_details_toggle()


func _update_details_toggle() -> void:
	details_toggle.text = tr("주문 상세 접기") if detail_panel.visible else tr("주문 상세 펼치기")


func _update_board_layout() -> void:
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL if state == State.CLOSED or not compact_layout else Control.SIZE_SHRINK_BEGIN
	for label: Label in duty_labels:
		label.custom_minimum_size.y = 64 if compact_layout else 96


func _refresh_service() -> void:
	_update_board_layout()
	latest_view = simulation.snapshot()
	if preparation_panel != null:
		var preparing := state == State.READY
		var analyzing := state == State.CLOSED
		var summary_parent: Node = preparation_panel.pages[0].get_child(0) if preparing else order_list
		if summary_label.get_parent() != summary_parent:
			summary_label.reparent(summary_parent)
			summary_parent.move_child(summary_label, 0)
		preparation_panel.visible = preparing
		analysis_scroll.visible = analyzing
		employee_controls.visible = not preparing and not analyzing
		$SafeArea/Layout/Kitchen/Body/Side/Heading.visible = not preparing and not analyzing
		$SafeArea/Layout/Kitchen/Body/Side/OrdersScroll.visible = not preparing and not analyzing
		details_toggle.visible = not preparing and not analyzing and compact_layout
		detail_panel.visible = not preparing and not analyzing and (details_expanded or not compact_layout)
		_update_details_toggle()
		if preparing and latest_view.errors.is_empty():
			_show_preparation()
			_refresh_feedback()
			return
	if not latest_view.errors.is_empty():
		board.show_state(null, {})
		summary_label.text = tr("주방 데이터 오류 · 영업을 시작할 수 없습니다")
		detail_label.text = tr("주문을 불러올 수 없습니다")
		for button: Button in [start_button, pause_button, resume_button, priority_up_button, priority_down_button, cancel_button] + speed_buttons:
			button.disabled = true
		for button: OptionButton in duty_buttons:
			button.disabled = true
		restart_button.visible = false
		_refresh_feedback()
		return
	board.show_state(definitions, latest_view)
	_show_summary()
	for index: int in speed_buttons.size():
		speed_buttons[index].disabled = driver.speed == [1, 2, 4][index] or state == State.CLOSED
		speed_buttons[index].theme_type_variation = &"ActiveButton" if driver.speed == [1, 2, 4][index] and state != State.CLOSED else &"Button"
	for order: Dictionary in latest_view.orders:
		if selected_order_id.is_empty():
			selected_order_id = order.id
		if not order_buttons.has(order.id):
			var button := Button.new()
			button.custom_minimum_size = Vector2(64, 64)
			button.add_theme_font_size_override("font_size", 20)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.icon = definitions.recipe_for(order.recipe_id).icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 32)
			button.pressed.connect(select_order.bind(order.id))
			order_list.add_child(button)
			app_preferences.apply_to(button)
			order_buttons[order.id] = button
		var selected := "▶ " if order.id == selected_order_id else ""
		order_buttons[order.id].theme_type_variation = &"ActiveButton" if order.id == selected_order_id else &"Button"
		var detail: String = _order_status(order)
		order_buttons[order.id].text = tr("%s%s %s · 우선 %d\n%s") % [selected, order.id.trim_prefix("order_"), tr(order.name), _requested_priority(order), detail]
	_show_selected_order()
	for index: int in latest_view.employees.size():
		var employee: Dictionary = latest_view.employees[index]
		var chosen: String = employee.pending_duty if not employee.pending_duty.is_empty() else employee.duty
		for command: Dictionary in latest_view.commands:
			if command.kind == "set_duty" and command.target_id == employee.id:
				chosen = command.value
		duty_buttons[index].select(ServiceSim.DUTIES.find(chosen))
		duty_buttons[index].disabled = state == State.CLOSED
		var activity := _employee_activity(employee) if not employee.order_id.is_empty() else _employee_wait(employee)
		if not employee.pending_duty.is_empty():
			activity += "\n↳ " + tr("현재 공정 후 담당 변경")
		duty_labels[index].text = tr("직원 %d · %s") % [index + 1, activity]
	if not latest_view.commands.is_empty():
		feedback_kind = "commands_pending"
	elif feedback_kind == "commands_pending":
		feedback_kind = "commands_applied"
	for event: Dictionary in driver.take_events():
		match event.kind:
			"order_arrived":
				audio_feedback.play_cue("arrival")
			"order_served":
				audio_feedback.play_cue("served")
			"path_failed", "command_rejected":
				audio_feedback.play_cue("warning")
		if event.kind == "command_rejected":
			feedback_kind = "command_rejected"
		_consider_chatter(event)
	board.show_chatter(_visible_chatter())
	_refresh_feedback()


func _build_settings() -> void:
	settings_button = Button.new()
	settings_button.custom_minimum_size = Vector2(64, 64)
	settings_button.pressed.connect(_show_settings)
	$SafeArea/Layout/Header.add_child(settings_button)
	settings_dialog = AcceptDialog.new()
	settings_dialog.dialog_autowrap = true
	settings_dialog.add_theme_constant_override("buttons_min_height", 64)
	settings_dialog.add_theme_constant_override("buttons_min_width", 64)
	add_child(settings_dialog)
	settings_dialog.get_ok_button().custom_minimum_size.y = 64
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 12)
	settings_dialog.add_child(column)
	settings_locale_label = _settings_label("언어")
	column.add_child(settings_locale_label)
	settings_locale = OptionButton.new()
	settings_locale.custom_minimum_size = Vector2(64, 64)
	settings_locale.add_item("한국어")
	settings_locale.add_item("English")
	settings_locale.item_selected.connect(_change_locale)
	column.add_child(settings_locale)
	settings_sound = CheckButton.new()
	settings_sound.custom_minimum_size = Vector2(64, 64)
	settings_sound.toggled.connect(_change_sound)
	column.add_child(settings_sound)
	settings_text_size_label = _settings_label("글자 크기")
	column.add_child(settings_text_size_label)
	settings_text_size = OptionButton.new()
	settings_text_size.custom_minimum_size = Vector2(64, 64)
	settings_text_size.add_item("")
	settings_text_size.add_item("")
	settings_text_size.item_selected.connect(_change_text_size)
	column.add_child(settings_text_size)
	settings_message = _settings_label("")
	column.add_child(settings_message)
	_sync_settings_controls()


func _settings_label(text: String) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	return label


func _show_settings() -> void:
	_pause()
	if modal_open_allowed.is_valid() and not modal_open_allowed.call():
		return
	_sync_settings_controls()
	settings_dialog.popup_centered_clamped(Vector2i(620, 520))
	settings_dialog.get_ok_button().custom_minimum_size = Vector2(64, 64)
	await get_tree().process_frame
	if settings_dialog.visible:
		settings_dialog.size = Vector2i(620, 520)
		settings_dialog.popup_centered_clamped(Vector2i(620, 520))


func _change_locale(index: int) -> void:
	_update_settings({"locale": "ko" if index == 0 else "en"})


func _change_sound(enabled: bool) -> void:
	_update_settings({"sound_enabled": enabled})


func _change_text_size(index: int) -> void:
	_update_settings({"text_size": "normal" if index == 0 else "large"})


func _update_settings(changes: Dictionary) -> void:
	var result := app_preferences.update_settings(changes)
	_set_settings_message("saved" if result.accepted else "error", result.reason)
	_sync_settings_controls()


func _sync_settings_controls() -> void:
	var values := app_preferences.snapshot()
	settings_locale.select(0 if values.locale == "ko" else 1)
	settings_sound.set_pressed_no_signal(values.sound_enabled)
	settings_text_size.select(0 if values.text_size == "normal" else 1)
	var popup_font_size := 32 if values.text_size == "large" else 26
	for picker: OptionButton in [settings_locale, settings_text_size]:
		picker.get_popup().add_theme_font_size_override("font_size", popup_font_size)
		picker.get_popup().add_theme_constant_override("v_separation", 32)


func _on_preferences_changed() -> void:
	apply_preferences()


func apply_preferences() -> void:
	audio_feedback.set_enabled(app_preferences.snapshot().sound_enabled)
	app_preferences.apply_to(self)
	_refresh_translated_text()
	board.text_scale = 1.2 if app_preferences.snapshot().text_size == "large" else 1.0
	board.queue_redraw()
	if preparation_panel != null:
		preparation_panel.refresh_translations()


func _refresh_translated_text() -> void:
	settings_button.text = tr("설정")
	settings_dialog.title = tr("설정")
	settings_dialog.ok_button_text = tr("닫기")
	settings_dialog.get_ok_button().custom_minimum_size = Vector2(64, 64)
	settings_locale_label.text = tr("언어")
	settings_sound.text = tr("효과음")
	settings_text_size_label.text = tr("글자 크기")
	settings_text_size.set_item_text(0, tr("기본"))
	settings_text_size.set_item_text(1, tr("크게"))
	_refresh_settings_message()
	if definitions is ScenarioDef:
		title_label.text = tr(definitions.display_name)
	else:
		title_label.text = tr("Chef al Mando · 첫 영업")
	start_button.text = tr("시작")
	pause_button.text = tr("일시정지")
	resume_button.text = tr("재개")
	restart_button.text = tr("준비 다시 하기")
	$SafeArea/Layout/Kitchen/Body/Side/Heading.text = tr("주문 · 탭하여 선택")
	priority_down_button.text = tr("우선 −")
	priority_up_button.text = tr("우선 +")
	cancel_button.text = tr("취소")
	for button: OptionButton in duty_buttons:
		for index: int in DUTY_TEXT.size():
			button.set_item_text(index, tr(DUTY_TEXT[index]))
	shown_tenths = -1
	_refresh()
	_update_details_toggle()


func _set_feedback(kind: String, reason: String = "") -> void:
	feedback_kind = kind
	feedback_reason = reason
	_refresh_feedback()


func _refresh_feedback() -> void:
	match feedback_kind:
		"commands_pending":
			var count: int = latest_view.get("commands", []).size()
			feedback_label.text = tr("적용 대기 %d건%s") % [count,
				tr(" · 재개하면 반영") if state == State.PAUSED else ""]
		"commands_applied":
			feedback_label.text = tr("명령 반영 완료")
		"command_invalid":
			feedback_label.text = tr("명령을 적용할 수 없습니다 · 대상과 상태를 확인하세요")
		"command_rejected":
			feedback_label.text = tr("주문 상태가 바뀌어 명령을 적용하지 못했습니다")
		"preparation_applied":
			feedback_label.text = tr("준비 반영 완료")
		"preparation_error":
			feedback_label.text = PreparationPanel.reason_text(feedback_reason)
		_:
			feedback_label.text = ""


func _set_settings_message(kind: String, reason: String = "") -> void:
	settings_message_kind = kind
	settings_message_reason = reason
	_refresh_settings_message()


func _refresh_settings_message() -> void:
	match settings_message_kind:
		"saved":
			settings_message.text = tr("설정 저장 완료")
		"error":
			settings_message.text = _settings_error(settings_message_reason)
		_:
			settings_message.text = ""


func _settings_error(reason: String) -> String:
	if reason in ["future_version", "unsupported_version"]:
		return tr("이 앱에서 지원하지 않는 설정 파일입니다. 기존 파일을 보존합니다.")
	return tr("설정을 저장하거나 읽지 못했습니다. 기존 설정을 유지합니다.")


func _show_preparation() -> void:
	var preview := preparation.snapshot()
	preparation_panel.refresh(preview)
	if not preview.has("purchases"):
		board.show_state(null, {})
		summary_label.text = tr("준비 데이터 오류 · 영업을 시작할 수 없습니다")
		return
	var employees: Array[Dictionary] = []
	for definition: Definitions.EmployeeDef in definitions.employees:
		var tile: Array[int] = [definition.starting_tile.x, definition.starting_tile.y]
		employees.append({"id": definition.id, "tile": tile, "next_tile": tile.duplicate(), "progress": 0,
			"duty": preview.duties[definition.id], "order_id": ""})
	board.show_state(definitions, {"employees": employees})
	summary_label.text = tr("시작 예산 %s · 발주 %s · 고정 인건비 %s\n남은 예산 %s · 준비 노동량 %d / %d\n주문 %d건 · %s") % [_money(definitions.starting_budget), _money(preview.purchased_cost), _money(definitions.labor_cost), _money(preview.budget_remaining), preview.labor_used, preview.labor_capacity, definitions.order_count, tr("영업 시작 가능") if preview.can_start else tr("준비를 확인하세요")]
	status_label.text = tr("준비 중 · 발주·프렙과 배치·담당을 선택한 뒤 시작하세요")
	if not preview.errors.is_empty():
		status_label.text = PreparationPanel.reason_text(preview.errors[0])
	for button: Button in speed_buttons:
		button.disabled = true


func _show_summary() -> void:
	var accounting: Dictionary = latest_view.accounting
	if state == State.CLOSED:
		var total: int = latest_view.orders.size()
		var rate: float = accounting.served * 100.0 / maxi(total, 1)
		summary_label.text = tr("제공 %d / %d건 (%.0f%%) · 취소 %d · 미제공 %d\n매출 %s · 재료비 %s · 인건비 %s\n폐기 %s · 손익 %s · 남은 예산 %s") % [accounting.served, total, rate, accounting.cancelled, accounting.expired, _money(accounting.revenue), _money(accounting.purchased_cost), _money(accounting.labor_cost), _money(accounting.waste_cost), _money(accounting.profit), _money(accounting.cash)]
		if analysis_label != null:
			_show_analysis()
	elif state == State.READY:
		var menus: PackedStringArray = []
		for recipe_id: String in definitions.menu_ids:
			menus.append(tr(definitions.recipe_for(recipe_id).display_name))
		summary_label.text = tr("메뉴 · %s\n예산 %s · 재료비 %s · 인건비 %s\n%s · 주문 %d건") % [" / ".join(menus), _money(definitions.starting_budget), _money(accounting.purchased_cost), _money(accounting.labor_cost), _raw_stock(" · "), definitions.order_count]
	else:
		summary_label.text = tr("주문 %d / %d건 · 제공 %d · 미제공 %d · 취소 %d\n매출 %s · 남은 재료 · %s") % [latest_view.orders.size(), definitions.order_count, accounting.served, accounting.expired, accounting.cancelled, _money(accounting.revenue), _raw_stock(" / ")]
		if preparation != null:
			var prepared: PackedStringArray = []
			for recipe_id: String in definitions.menu_ids:
				var recipe := definitions.recipe_for(recipe_id)
				prepared.append(tr("%s %d") % [tr(recipe.display_name), latest_view.inventory.get(recipe.prepared_ingredient_id, 0)])
			summary_label.text += tr("\n프렙 · ") + " / ".join(prepared)


func _raw_stock(separator: String) -> String:
	var quantities: PackedStringArray = []
	for ingredient: Definitions.IngredientDef in definitions.ingredients:
		if ingredient.purchasable:
			quantities.append(tr("%s %d") % [tr(ingredient.display_name), latest_view.inventory.get(ingredient.id, 0)])
	return separator.join(quantities)


func _show_analysis() -> void:
	var report := ServiceAnalysis.build(definitions, latest_view, last_preparation)
	var totals: Dictionary = latest_view.metrics.orders
	var longest: String = "missing_ingredients"
	var recommendations: PackedStringArray = []
	if report.recommendations.is_empty():
		recommendations.append(tr("이번 영업에서는 준비 선택을 바꿀 근거가 충분하지 않습니다."))
	else:
		for recommendation: Dictionary in report.recommendations:
			recommendations.append(_recommendation_text(report, recommendation))
	var details: PackedStringArray = [tr("주문별 누적 시간"), tr("여러 주문을 합한 값입니다.\n영업 시간보다 클 수 있습니다."), ""]
	for reason: String in ["missing_ingredients", "no_responsible_employee", "station_in_use", "no_route"]:
		details.append(tr("%s · %.1f초") % [tr(WAIT_TEXT[reason]), totals[reason] / 10.0])
		if totals[reason] > totals[longest]:
			longest = reason
	details.append(tr("  담당 부재 %.1f초 / 작업 중 %.1f초") % [(totals.no_responsible_employee - totals.responsible_employee_busy) / 10.0, totals.responsible_employee_busy / 10.0])
	details.append(tr("이동 · %.1f초\n작업 · %.1f초") % [totals.moving / 10.0, totals.working / 10.0])
	details.append(tr("\n가장 긴 대기 · %s\n이 수치만으로 손실 원인을 단정할 수 없습니다.") % (tr(WAIT_TEXT[longest]) if totals[longest] > 0 else tr("대기 없음")))
	details.append(tr("\n설비별 예약·사용 시간\n재료를 가져오는 이동 중 예약도 포함합니다."))
	for station: Definitions.StationDef in definitions.stations:
		details.append(tr("%s · %.1f초") % [tr(station.display_name), latest_view.metrics.station_reserved_ticks[station.id] / 10.0])
	_render_analysis(summary_label.text, recommendations, "\n".join(details))


func _render_analysis(summary: String, recommendations: PackedStringArray, details: String) -> void:
	var heading_size := app_preferences.font_size(22)
	var body_size := app_preferences.font_size(18)
	var action_size := app_preferences.font_size(15)
	var detail_heading_size := app_preferences.font_size(19)
	var detail_size := app_preferences.font_size(16)
	analysis_label.set_meta("action_heading_font_size", heading_size)
	analysis_label.set_meta("action_font_size", action_size)
	analysis_label.set_meta("action_heading_color", ANALYSIS_HEADING_COLOR)
	analysis_label.set_meta("action_color", ANALYSIS_ACTION_COLOR)
	analysis_label.clear()
	_analysis_text(tr("다음 영업에서 바꿀 것"), heading_size, ANALYSIS_HEADING_COLOR)
	analysis_label.add_text("\n")
	for recommendation: String in recommendations:
		var parts := recommendation.split("\n", true, 1)
		_analysis_text(parts[0], body_size, ANALYSIS_BODY_COLOR)
		if parts.size() > 1:
			analysis_label.add_text("\n")
			_analysis_text(parts[1], action_size, ANALYSIS_ACTION_COLOR)
		analysis_label.add_text("\n\n")
	_analysis_text(tr("상세 지표"), detail_heading_size, ANALYSIS_HEADING_COLOR)
	analysis_label.add_text("\n")
	_analysis_text(summary, body_size, ANALYSIS_BODY_COLOR)
	analysis_label.add_text("\n\n")
	_analysis_text(details, detail_size, ANALYSIS_DETAIL_COLOR)


func _analysis_text(value: String, font_size: int, color: Color) -> void:
	analysis_label.push_font_size(font_size)
	analysis_label.push_color(color)
	analysis_label.add_text(value)
	analysis_label.pop()
	analysis_label.pop()


func _recommendation_text(report: Dictionary, recommendation: Dictionary) -> String:
	var target_id: String = recommendation.target_id
	match recommendation.action:
		"increase_prep":
			var row: Dictionary = report.prep[target_id]
			return tr("프렙 · %s %d개 준비 · %d개 사용 · 생재료 손질 %d건\n→ 준비 노동량 안에서 %d개 늘려 보세요.") % [tr(definitions.recipe_for(target_id).display_name), row.planned, row.used, row.raw_orders, recommendation.amount]
		"reduce_prep":
			var row: Dictionary = report.prep[target_id]
			return tr("프렙 · %s %d개 준비 · %d개 사용 · %d개 남음\n→ 다음 영업은 %d개 줄여 보세요.") % [tr(definitions.recipe_for(target_id).display_name), row.planned, row.used, row.remaining, recommendation.amount]
		"prep_at_capacity":
			var row: Dictionary = report.prep[target_id]
			var remaining_labor: int = report.labor_capacity - report.labor_used
			return tr("프렙 · %s %d개를 모두 사용 · 생재료 손질 %d건\n→ 준비 노동량 %d / %d · 남은 노동량 %d는 1개에 필요한 %d보다 적습니다. 다른 프렙 잔량이나 작업 병목을 확인하세요.") % [tr(definitions.recipe_for(target_id).display_name), row.used, row.raw_orders, report.labor_used, report.labor_capacity, remaining_labor, row.prep_labor_units]
		"increase_purchase":
			var row: Dictionary = report.ingredients[target_id]
			return tr("발주 · %s %d개 발주 · 종료 재고 0개 · 관련 메뉴 재료 부족 %.1f초\n→ 예산 안에서 1개 늘려 보세요.") % [tr(definitions.ingredient_for(target_id).display_name), row.purchased, row.related_shortage_ticks / 10.0]
		"reduce_purchase":
			var row: Dictionary = report.ingredients[target_id]
			return tr("발주 · %s %d개 발주 · %d개 사용 · %d개 남음\n→ 제공률을 확인하며 다음 영업은 %d개 줄여 보세요.") % [tr(definitions.ingredient_for(target_id).display_name), row.purchased, row.used, row.remaining, recommendation.amount]
		"purchase_consumed":
			var row: Dictionary = report.ingredients[target_id]
			return tr("발주 · %s %d개 발주 · %d개 사용 · 종료 재고 0개\n→ 관련 메뉴 재료 부족이 없었습니다. 이번 발주량은 유지하고 운영 선택 하나만 바꿔 비교해 보세요.") % [tr(definitions.ingredient_for(target_id).display_name), row.purchased, row.used]
		"raise_priority":
			var row: Dictionary = report.priorities[target_id]
			return tr("우선순위 · %s 기본 %d · 미제공 %d건 · 경합 %.1f초\n→ 다음 영업은 기본 우선순위를 1 올려 보세요.") % [tr(definitions.recipe_for(target_id).display_name), row.default_priority, row.expired, row.pressure_ticks / 10.0]
		"priority_at_max":
			var row: Dictionary = report.priorities[target_id]
			var header := tr("우선순위 · %s 기본 2 · 미제공 %d건 · 경합 %.1f초") % [tr(definitions.recipe_for(target_id).display_name), row.expired, row.pressure_ticks / 10.0]
			match recommendation.bottleneck:
				"movement":
					return header + "\n" + tr("→ 이미 최대입니다. 이동 %.1f초가 가장 큽니다. 다음 영업은 작업대 한 곳의 위치만 바꾸고 이동 시간을 비교해 보세요.") % (recommendation.bottleneck_ticks / 10.0)
				"employee_busy":
					return header + "\n" + tr("→ 이미 최대입니다. 담당 직원 대기 %.1f초가 가장 큽니다. 다음 영업은 작업대 한 곳의 위치만 바꾸고 담당 직원 대기와 이동 시간을 비교해 보세요.") % (recommendation.bottleneck_ticks / 10.0)
				"station":
					return header + "\n" + tr("→ 이미 최대입니다. 작업대 대기 %.1f초가 가장 큽니다. 다음 영업은 냉식대·화구 중 한 곳만 바꾸고 작업대 대기를 비교해 보세요.") % (recommendation.bottleneck_ticks / 10.0)
	return ""


func _employee_activity(employee: Dictionary) -> String:
	var order := _order_for_id(employee.order_id)
	if order.is_empty():
		return tr("작업 중")
	var recipe_name: String = tr(order.name)
	var task := _task_for_order(order.id)
	var collecting: bool = not task.is_empty() and task.collection_index >= 0 and task.path_index < task.collection_index
	var action := ""
	if order.state == "moving":
		match order.phase_id:
			"pickup":
				action = tr("프렙 재료 받으러 재료 보관대로 이동 중") if order.uses_prepared else tr("원재료 받으러 재료 보관대로 이동 중")
			"prep":
				action = tr("새 재료 손질하러 이동 중")
			"cook":
				action = tr("손질한 재료 가지러 이동 중") if collecting else tr("%s로 이동 중") % tr(_station_name(task.get("station_id", "")))
			"serve":
				action = tr("완성 요리 가지러 이동 중") if collecting else tr("제공대로 운반 중")
	elif order.state == "working":
		match order.phase_id:
			"pickup":
				action = tr("프렙 재료 챙기는 중") if order.uses_prepared else tr("원재료 챙기는 중")
			"prep":
				action = tr("새 재료 손질하는 중")
			"cook":
				action = tr("%s에서 조리 중") % tr(_station_name(task.get("station_id", "")))
			"serve":
				action = tr("요리 내놓는 중")
	return tr("%s · %s") % [recipe_name, action]


func _order_for_id(order_id: String) -> Dictionary:
	for order: Dictionary in latest_view.orders:
		if order.id == order_id:
			return order
	return {}


func _task_for_order(order_id: String) -> Dictionary:
	for task: Dictionary in latest_view.tasks:
		if task.order_id == order_id:
			return task
	return {}


func _station_name(station_id: String) -> String:
	for station: Definitions.StationDef in definitions.stations:
		if station.id == station_id:
			return station.display_name
	return "작업대"


func _consider_chatter(event: Dictionary) -> void:
	var priority := 0
	if event.kind == "order_wait_started" and event.reason == "missing_ingredients":
		priority = 1
	elif event.kind == "prepared_stock_depleted":
		priority = 2
	elif event.kind == "order_ended" and event.reason == "deadline" and event.phase_id == "serve":
		priority = 3
	if priority == 0:
		return
	var repeat_key := "%s:%s" % [event.kind, event.get("recipe_id", "")]
	if simulation.tick - chatter_last_tick.get(repeat_key, -1000) < 50:
		return
	if not chatter_event.is_empty() and priority < chatter_event.get("priority", 0):
		return
	chatter_last_tick[repeat_key] = simulation.tick
	chatter_event = event.duplicate(true)
	chatter_event.priority = priority
	chatter_seconds_left = 2.2


func _visible_chatter() -> Dictionary:
	if chatter_event.is_empty() or chatter_seconds_left <= 0.0:
		return {}
	var result := chatter_event.duplicate(true)
	var recipe := definitions.recipe_for(result.get("recipe_id", ""))
	match result.kind:
		"order_wait_started":
			result.text = tr("으악, %s 재료가 없어!") % tr(recipe.display_name)
		"prepared_stock_depleted":
			result.text = tr("%s 프렙 다 썼다!") % tr(recipe.display_name)
		"order_ended":
			result.text = tr("으악, 다 만들었는데 가버리셨어!")
	if result.get("employee_id", "").is_empty():
		result.employee_id = _speaker_for_recipe(result.get("recipe_id", ""))
	return result


func _speaker_for_recipe(recipe_id: String) -> String:
	var recipe := definitions.recipe_for(recipe_id)
	if recipe == null:
		return ""
	for employee: Dictionary in latest_view.employees:
		if employee.duty == "all" or employee.duty == recipe.cook_role:
			return employee.id
	return ""


func _order_status(order: Dictionary) -> String:
	if order.state in ServiceSim.TERMINAL:
		return tr(STATE_TEXT[order.state])
	var description: String = tr(PHASE_TEXT[order.phase_id]) + " · " + tr(STATE_TEXT[order.state])
	if order.state == "waiting":
		description = tr(WAIT_TEXT[order.wait_detail if not order.wait_detail.is_empty() else order.wait_reason])
	return tr("%s · %.1f초 남음") % [description, maxf(0, (order.deadline_tick - simulation.tick) / 10.0)]


func _show_selected_order() -> void:
	detail_label.text = tr("주문을 선택하세요")
	for order: Dictionary in latest_view.orders:
		if order.id != selected_order_id:
			continue
		var priority := _requested_priority(order)
		var terminal: bool = order.state in ServiceSim.TERMINAL
		detail_label.text = tr("%s · 우선순위 %d\n%s") % [tr(order.name), priority, _order_status(order)]
		priority_up_button.disabled = terminal or priority >= 2
		priority_down_button.disabled = terminal or priority <= 0
		cancel_button.disabled = terminal
		return
	priority_up_button.disabled = true
	priority_down_button.disabled = true
	cancel_button.disabled = true


func _employee_wait(employee: Dictionary) -> String:
	if employee.duty == "off":
		return tr("신규 담당 없음")
	for order: Dictionary in latest_view.orders:
		var recipe := definitions.recipe_for(order.recipe_id)
		if order.state == "waiting" and (employee.duty == "all" or employee.duty == recipe.cook_role):
			return tr(WAIT_TEXT[order.wait_detail if not order.wait_detail.is_empty() else order.wait_reason])
	return tr("배정할 주문 없음")


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
