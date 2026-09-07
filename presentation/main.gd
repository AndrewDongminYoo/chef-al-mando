extends Control

## M0 kitchen screen: a lifecycle counter with start, pause, and resume.

enum State { READY, RUNNING, PAUSED }

const AppLifecycle := preload("res://platform/app_lifecycle.gd")
const SafeAreaSource := preload("res://platform/safe_area.gd")
const STATUS_TEXT := {
	State.READY: "준비 완료 · 시작을 눌러 주방을 확인하세요",
	State.RUNNING: "진행 중 · 언제든지 일시정지할 수 있습니다",
	State.PAUSED: "일시정지 · 재개를 눌러 계속하세요",
}

var state: State = State.READY
var input_actions: int = 0
var elapsed_seconds: float = 0.0
var shown_tenths: int = -1
var last_usable_area: Rect2 = Rect2()
var last_canvas_size: Vector2 = Vector2.ZERO

@onready var start_button: Button = $SafeArea/Layout/Controls/Start
@onready var pause_button: Button = $SafeArea/Layout/Controls/Pause
@onready var resume_button: Button = $SafeArea/Layout/Controls/Resume
@onready var counter: Label = $SafeArea/Layout/Header/Counter
@onready var status_label: Label = $SafeArea/Layout/Status
@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource
@onready var lifecycle: AppLifecycle = $Lifecycle


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
	_update_safe_area()
	_refresh()


func _record_input(action: String) -> void:
	input_actions += 1
	if OS.is_debug_build():
		print("M0_INPUT action=%s total=%d" % [action, input_actions])


func _process(delta: float) -> void:
	advance(delta)


## Advances the counter by `delta` seconds while running; a no-op in every other state.
func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed_seconds += delta
	_show_counter()


func is_running() -> bool:
	return state == State.RUNNING


func _start() -> void:
	if state == State.READY:
		_set_state(State.RUNNING)


func _pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)


func _resume() -> void:
	if state == State.PAUSED:
		_set_state(State.RUNNING)


func _set_state(next: State) -> void:
	state = next
	_refresh()


func _refresh() -> void:
	start_button.disabled = state != State.READY
	pause_button.disabled = state != State.RUNNING
	resume_button.disabled = state != State.PAUSED
	status_label.text = STATUS_TEXT[state]
	_show_counter()


func _show_counter() -> void:
	var tenths := int(elapsed_seconds * 10.0)
	if tenths == shown_tenths:
		return
	shown_tenths = tenths
	counter.text = "%05.1f초" % elapsed_seconds


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
