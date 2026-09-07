extends "res://tests/harness.gd"

const KitchenScreen := preload("res://presentation/main.gd")

var backgrounded_count: int = 0


func run(tree: SceneTree) -> void:
	var screen := boot_main(tree) as KitchenScreen
	if screen == null:
		expect(false, "main scene must exist")
		return
	await tree.process_frame
	expect(screen.elapsed_seconds == 0.0, "counter starts at zero")
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 0.0, "ready screen must not advance")
	screen.start_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 1.0, "start advances the counter")
	screen.pause_button.pressed.emit()
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 1.0, "pause freezes the counter")
	screen.resume_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 2.0, "resume continues without resetting")
	screen.lifecycle.backgrounded.connect(_count_backgrounded)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	expect(backgrounded_count == 1, "focus loss followed by pause is one background transition")
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 2.0, "background transition freezes the counter")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 2.0, "foreground must not resume automatically")
	expect(not screen.resume_button.disabled, "resume remains usable")
	screen.resume_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 3.0, "manual resume excludes background time")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(backgrounded_count == 2, "a later focus loss is a new background transition")
	expect(not screen.is_running(), "focus loss alone pauses the counter")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(screen.status_label.text == KitchenScreen.STATUS_TEXT[KitchenScreen.State.PAUSED], "status text follows the state")
	expect(screen.counter.text == "003.0초", "counter text shows tenths of a second")
	screen.resized.disconnect(screen._update_safe_area)
	screen.size = Vector2(1280, 720)
	var to_canvas := Transform2D.IDENTITY.scaled(Vector2(0.5, 0.5))
	screen._apply_safe_area(Rect2i(100, 0, 2460, 1440), to_canvas)
	expect(screen.safe_area.offset_left == 50.0, "physical left inset converts to logical units")
	expect(screen.safe_area.offset_right == 0.0, "unobscured right edge has no inset")
	screen._apply_safe_area(Rect2i(0, 0, 2460, 1400), to_canvas)
	expect(screen.safe_area.offset_left == 0.0, "rotation releases the old left inset")
	expect(screen.safe_area.offset_right == -50.0 and screen.safe_area.offset_bottom == -20.0, "rotation applies the new insets without resizing")
	screen.size = Vector2(1400, 800)
	screen._apply_safe_area(Rect2i(0, 0, 2460, 1400), to_canvas)
	expect(screen.safe_area.offset_right == -170.0 and screen.safe_area.offset_bottom == -100.0, "a resize with an unchanged safe rect recomputes the far edges")
	screen._apply_safe_area(Rect2i(5000, 5000, 100, 100), to_canvas)
	expect(screen.safe_area.offset_left == 0.0 and screen.safe_area.offset_right == 0.0 and screen.safe_area.offset_bottom == 0.0, "a safe rect outside the canvas falls back to the full canvas")
	screen.queue_free()
	await tree.process_frame


func _count_backgrounded() -> void:
	backgrounded_count += 1
