extends SceneTree


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	for scenario_path: String in ["res://content/m1_first_service.tres", "res://content/m2_first_service.tres", "res://tests/fixtures/m2_extra_menu.tres"]:
		if not FileAccess.file_exists(scenario_path + ".remap"):
			printerr("FAIL: required converted export content is missing: " + scenario_path)
			quit(1)
			return
	for scenario_path: String in ["res://content/m1_first_service.tres", "res://content/m2_first_service.tres", "res://tests/fixtures/m2_extra_menu.tres"]:
		if not await _check_scenario(scenario_path):
			quit(1)
			return
	if not await _check_campaign():
		quit(1)
		return
	print("PASS: exported M3 campaign and first served order")
	print("PASS: exported M1 content and first order")
	print("PASS: exported M2 preparation and first order")
	print("PASS: exported M2 extra menu prepared and served")
	quit(0)


func _check_scenario(scenario_path: String) -> bool:
	var data: Resource = load(scenario_path)
	if data == null or not data.call("validate").is_empty():
		printerr("FAIL: exported kitchen content is invalid")
		return false
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", scenario_path)
	root.add_child(screen)
	screen.set_process(false)
	await process_frame
	var prepared: bool = true
	if data.call("supports_preparation"):
		var recipe_id: String = data.get("menu_ids")[0]
		var recipe: Resource = data.call("recipe_for", recipe_id)
		var result: Dictionary = screen.call("submit_preparation", "set_prep", recipe_id, 1)
		prepared = result.accepted and screen.get("preparation_panel").prep_labels[recipe_id].text.contains(recipe.get("display_name"))
	var can_start: bool = not screen.get("start_button").disabled
	screen.get("start_button").pressed.emit()
	screen.call("advance", 1.0)
	var sim: RefCounted = screen.get("simulation")
	var started: bool = prepared and can_start and sim.get("tick") == 10 and sim.call("snapshot").orders.size() == 1
	if started and data.call("supports_preparation"):
		var first: Dictionary = sim.call("snapshot").orders[0]
		started = first.uses_prepared
	if started and scenario_path.contains("m2_extra_menu"):
		screen.call("advance", 19.0)
		var first: Dictionary = sim.call("snapshot").orders[0]
		started = first.recipe_id == "grain_salad" and first.name == "곡물 샐러드" and first.state == "served"
	screen.queue_free()
	await process_frame
	if not started:
		printerr("FAIL: exported preparation or first-order behavior failed: " + scenario_path)
	return started


func _check_campaign() -> bool:
	var campaign_path := "res://content/campaign/campaign.tres"
	if not FileAccess.file_exists(campaign_path + ".remap"):
		printerr("FAIL: exported campaign resource is missing")
		return false
	var campaign: Resource = load(campaign_path)
	if campaign == null or not campaign.call("validate").is_empty() or campaign.get("scenarios").size() != 8:
		printerr("FAIL: exported campaign content is invalid")
		return false
	var directory := "user://export_m3_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("FAIL: exported campaign record fixture cannot be created")
		return false
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen: Control = scene.instantiate()
	screen.set("save_path", directory + "/records.json")
	root.add_child(screen)
	await process_frame
	var valid: bool = screen.get("scenario_buttons").size() == 8
	screen.call("select_scenario", "first_shift")
	screen.call("begin_service")
	var service: Control = screen.get("active_service")
	if service == null:
		valid = false
	else:
		service.set_process(false)
		service.get("start_button").pressed.emit()
		service.call("advance", 20.0)
		var snapshot: Dictionary = service.get("simulation").call("snapshot")
		valid = valid and snapshot.tick == 200 and snapshot.orders.size() > 0 and snapshot.orders[0].state == "served"
	screen.queue_free()
	await process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
	if not valid:
		printerr("FAIL: exported campaign entry or first served order failed")
	return valid
