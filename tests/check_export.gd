extends SceneTree

const AppPreferences := preload("res://presentation/app_preferences.gd")

func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var directory := "user://export_m4_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("FAIL: exported M4 fixture directory cannot be created")
		quit(1)
		return
	var settings_path := directory + "/settings.json"
	if not _save_settings(settings_path, "ko"):
		printerr("FAIL: exported fixture settings cannot be saved")
		_cleanup(directory)
		quit(1)
		return
	var valid := true
	for scenario_path: String in ["res://content/m1_first_service.tres", "res://content/m2_first_service.tres", "res://tests/fixtures/m2_extra_menu.tres"]:
		if not FileAccess.file_exists(scenario_path + ".remap"):
			printerr("FAIL: required converted export content is missing: " + scenario_path)
			valid = false
	for scenario_path: String in ["res://content/m1_first_service.tres", "res://content/m2_first_service.tres", "res://tests/fixtures/m2_extra_menu.tres"]:
		if valid and not await _check_scenario(scenario_path, settings_path):
			valid = false
	if valid and not await _check_campaign(directory):
		valid = false
	if valid and not _check_storage_core():
		printerr("FAIL: exported M4 storage core behavior failed")
		valid = false
	if valid and not await _check_m4_resume(directory):
		valid = false
	_cleanup(directory)
	TranslationServer.set_locale("ko")
	if not valid:
		quit(1)
		return
	print("PASS: exported M3 campaign and first served order")
	print("PASS: exported M1 content and first order")
	print("PASS: exported M2 preparation and first order")
	print("PASS: exported M2 extra menu prepared and served")
	print("PASS: exported M4 storage core")
	print("PASS: exported M4 resume and localization")
	quit(0)


func _check_storage_core() -> bool:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var plan: RefCounted = load("res://sim/preparation_plan.gd").new(campaign.scenario_for("first_shift"))
	var started: Dictionary = plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	if not started.accepted:
		return false
	var simulation: RefCounted = load("res://sim/service_sim.gd").new(started.definitions, null, started.options)
	for _tick: int in range(10):
		simulation.step()
	var session_script: GDScript = load("res://persistence/service_session.gd")
	var session: Dictionary = session_script.capture("first_shift", started.selection, simulation)
	if session.simulation.orders.size() != 1 or session.simulation.last_sequence != 0 \
		or session.simulation.orders[0].priority != 1:
		return false
	var corrupted := session.duplicate(true)
	corrupted.simulation.orders[0].priority = 2
	var rejected: Dictionary = session_script.restore(campaign, corrupted, {})
	var restored: Dictionary = session_script.restore(campaign, session, {})
	if rejected.accepted or rejected.reason != "invalid_order" or not restored.accepted \
		or restored.simulation.state_hash() != simulation.state_hash():
		return false
	while not simulation.closed:
		simulation.step()
		restored.simulation.step()
	return restored.simulation.state_hash() == simulation.state_hash()


func _check_scenario(scenario_path: String, settings_path: String) -> bool:
	var data: Resource = load(scenario_path)
	if data == null or not data.call("validate").is_empty():
		printerr("FAIL: exported kitchen content is invalid")
		return false
	var scene: PackedScene = load("res://presentation/main.tscn")
	var screen: Control = scene.instantiate()
	screen.set("scenario_path", scenario_path)
	screen.set("settings_path", settings_path)
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


func _check_campaign(directory: String) -> bool:
	var campaign_path := "res://content/campaign/campaign.tres"
	if not FileAccess.file_exists(campaign_path + ".remap"):
		printerr("FAIL: exported campaign resource is missing")
		return false
	var campaign: Resource = load(campaign_path)
	if campaign == null or not campaign.call("validate").is_empty() or campaign.get("scenarios").size() != 8:
		printerr("FAIL: exported campaign content is invalid")
		return false
	var settings_path := directory + "/settings.json"
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen: Control = scene.instantiate()
	screen.set("save_path", directory + "/records.json")
	screen.set("settings_path", settings_path)
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
	if not valid:
		printerr("FAIL: exported campaign entry or first served order failed")
	return valid


func _check_m4_resume(directory: String) -> bool:
	var settings_path := directory + "/m4-settings.json"
	if not _save_settings(settings_path, "en"):
		printerr("FAIL: exported M4 English settings cannot be saved")
		return false
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var screen: Control = scene.instantiate()
	screen.set("save_path", directory + "/m4-records.json")
	screen.set("settings_path", settings_path)
	root.add_child(screen)
	await process_frame
	var valid: bool = TranslationServer.get_locale() == "en" and screen.get("menu_title").text == "Chef al Mando · Service list"
	screen.call("select_scenario", "first_shift")
	valid = valid and screen.call("begin_service")
	var service: Control = screen.get("active_service")
	if service == null:
		valid = false
	else:
		service.set_process(false)
		service.get("start_button").pressed.emit()
		service.call("advance", 10.0)
		var checkpoint: Dictionary = screen.get("store").load_records()
		valid = valid and checkpoint.accepted and checkpoint.active_session is Dictionary \
			and checkpoint.active_session.simulation.tick == 100
		screen.call("return_to_menu")
		await process_frame
		valid = valid and screen.get("continue_button").visible and screen.get("continue_button").text == "Continue"
		screen.get("continue_button").pressed.emit()
		await process_frame
		service = screen.get("active_service")
		valid = valid and service != null and service.get("state") == 2 \
			and service.get("simulation").tick == 100 and service.get("status_label").text.contains("Paused")
	screen.queue_free()
	await process_frame
	if not valid:
		printerr("FAIL: exported M4 session resume or English UI behavior failed")
	return valid


func _save_settings(settings_path: String, locale: String) -> bool:
	var preferences := AppPreferences.new(settings_path)
	var result := preferences.update_settings({"locale": locale, "sound_enabled": false, "text_size": "normal"})
	return result.accepted and preferences.snapshot().locale == locale and not preferences.snapshot().sound_enabled


func _cleanup(directory: String) -> void:
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
