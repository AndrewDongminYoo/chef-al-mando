extends Node

## Emitted once per transition into the background.
## Focus loss (notification shade, permission dialog, call banner) counts as a background transition
## on purpose: the counter must stop whenever the player cannot see it, and a later PAUSED for the
## same transition must not emit again.
signal backgrounded

var in_background: bool = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if in_background:
				return
			in_background = true
			backgrounded.emit()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			in_background = false
