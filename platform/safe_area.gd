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


func _poll() -> void:
	var physical_safe := current()
	if physical_safe == last_physical_safe:
		return
	last_physical_safe = physical_safe
	changed.emit(physical_safe)
