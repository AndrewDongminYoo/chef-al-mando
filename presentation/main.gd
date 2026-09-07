extends Control

var elapsed_seconds: float = 0.0
var started: bool = false
var running: bool = false
var last_usable_area: Rect2 = Rect2()

@onready var start_button: Button = $SafeArea/Layout/Controls/Start
@onready var pause_button: Button = $SafeArea/Layout/Controls/Pause
@onready var resume_button: Button = $SafeArea/Layout/Controls/Resume
@onready var counter: Label = $SafeArea/Layout/Header/Counter
@onready var status_label: Label = $SafeArea/Layout/Status


func _ready() -> void:
	start_button.pressed.connect(_start)
	pause_button.pressed.connect(_pause)
	resume_button.pressed.connect(_resume)
	$Lifecycle.backgrounded.connect(_pause)
	resized.connect(_update_safe_area)
	_update_safe_area()
	_refresh()


func _process(delta: float) -> void:
	_update_safe_area()
	if running:
		elapsed_seconds += delta
		counter.text = "%05.1f초" % elapsed_seconds


func _start() -> void:
	if started:
		return
	started = true
	running = true
	_refresh()


func _pause() -> void:
	running = false
	_refresh()


func _resume() -> void:
	if started:
		running = true
		_refresh()


func _refresh() -> void:
	start_button.disabled = started
	pause_button.disabled = not running
	resume_button.disabled = not started or running
	status_label.text = "준비 완료 · 시작을 눌러 주방을 확인하세요"
	if started:
		status_label.text = "진행 중 · 언제든지 일시정지할 수 있습니다" if running else "일시정지 · 재개를 눌러 계속하세요"


func _update_safe_area() -> void:
	var physical_safe := Rect2i()
	if OS.has_feature("android") or OS.has_feature("ios"):
		physical_safe = DisplayServer.get_display_safe_area()
	_apply_safe_area(physical_safe, get_viewport().get_screen_transform().affine_inverse())


func _apply_safe_area(physical_safe: Rect2i, to_canvas: Transform2D) -> void:
	var usable := Rect2(Vector2.ZERO, size)
	if physical_safe.has_area():
		usable = usable.intersection(to_canvas * Rect2(physical_safe))
	if usable == last_usable_area:
		return
	last_usable_area = usable
	$SafeArea.offset_left = usable.position.x + 24.0
	$SafeArea.offset_top = usable.position.y + 24.0
	$SafeArea.offset_right = -(size.x - usable.end.x) - 24.0
	$SafeArea.offset_bottom = -(size.y - usable.end.y) - 24.0
