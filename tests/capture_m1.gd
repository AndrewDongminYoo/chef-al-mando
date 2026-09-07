extends "res://tests/capture_m0.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: M1 capture requires a rendered window")
		quit(1)
		return
	var screen := Harness.boot_main(self) as KitchenScreen
	if screen == null:
		printerr("FAIL: main scene must exist")
		quit(1)
		return
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/check")
	await save_frame("res://build/check/m1-ready.png")
	await click(screen.start_button)
	screen.advance(30.0)
	await click(screen.pause_button)
	await click(screen.order_buttons["order_03"])
	await click(screen.priority_up_button)
	checks.expect(screen.simulation.snapshot().commands.size() == 1, "rendered priority hit target queues one command")
	await save_frame("res://build/check/m1-paused.png")
	await click(screen.cancel_button)
	await click(screen.resume_button)
	screen.advance(0.1)
	checks.expect(screen.simulation.snapshot().orders[2].state == "cancelled", "rendered cancellation applies after resume")
	await click(screen.speed_buttons[2])
	checks.expect(screen.driver.speed == 4, "rendered four-speed hit target changes the driver")
	screen.advance(68.0)
	checks.expect(screen.simulation.closed, "the rendered service reaches closing")
	await save_frame("res://build/check/m1-closed.png")
	await click(screen.restart_button)
	checks.expect(screen.simulation.tick == 0 and screen.state == KitchenScreen.State.READY, "rendered restart returns to preparation")
	await process_frame
	var safe := screen.safe_area.get_global_rect()
	if "--negative-layout" in OS.get_cmdline_user_args():
		screen.start_button.position.x = screen.size.x + 100
	for button: Button in [screen.start_button, screen.pause_button, screen.resume_button, screen.speed_buttons[0], screen.details_toggle]:
		if button.is_visible_in_tree():
			checks.expect(safe.encloses(button.get_global_rect()), "rendered control must remain in the safe area: " + str(button.name))
	print("M1 rendered input failures=%d" % checks.failures)
	screen.queue_free()
	await process_frame
	quit(1 if checks.failures > 0 else 0)
