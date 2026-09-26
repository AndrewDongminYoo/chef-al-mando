extends Node

## Owns the OS safe-area query so that presentation only applies the rect it receives.
## Polls at a low rate because a 180-degree rotation changes the insets without resizing the window.

signal changed(physical_safe: Rect2i)

const POLL_INTERVAL_SECONDS := 0.25

var last_physical_safe: Rect2i = Rect2i()


func _ready() -> void:
	var poll := Timer.new()
	poll.wait_time = POLL_INTERVAL_SECONDS
	poll.timeout.connect(_poll)
	add_child(poll)
	poll.start()
	last_physical_safe = current()


## Returns the safe area in physical screen pixels, or an empty rect where the OS reports none.
func current() -> Rect2i:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return DisplayServer.get_display_safe_area()
	return Rect2i()


## Returns the part of a canvas of canvas_size that lies inside the physical safe area, or the whole
## canvas when the OS reports no safe area or the safe area misses the canvas.
static func usable_area(canvas_size: Vector2, physical_safe: Rect2i, to_canvas: Transform2D) -> Rect2:
	var canvas := Rect2(Vector2.ZERO, canvas_size)
	if not physical_safe.has_area():
		return canvas
	var usable := canvas.intersection(to_canvas * Rect2(physical_safe))
	return usable if usable.has_area() else canvas


## Applies the usable area as pure offsets on a full-rect container; design padding stays on the
## container itself.
static func inset(container: Control, usable: Rect2, canvas_size: Vector2) -> void:
	container.offset_left = usable.position.x
	container.offset_top = usable.position.y
	container.offset_right = usable.end.x - canvas_size.x
	container.offset_bottom = usable.end.y - canvas_size.y


func _poll() -> void:
	var physical_safe := current()
	if physical_safe == last_physical_safe:
		return
	last_physical_safe = physical_safe
	changed.emit(physical_safe)
