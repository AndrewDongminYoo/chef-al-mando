extends Node

## Emitted once per transition into the background, and on every window close or back request.
## Focus loss (notification shade, permission dialog, call banner) counts as a background transition
## on purpose: the counter must stop whenever the player cannot see it, and a later PAUSED for the
## same transition must not emit again.
## Close and back requests always emit and leave `in_background` alone: the engine notifies nodes
## before it sets its quit flag, so the listener's synchronous pause checkpoint lands before the
## app quits, and a repeated checkpoint costs less than a skipped one.
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
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			backgrounded.emit()
