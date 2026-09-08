extends "res://tests/harness.gd"

const CampaignStore := preload("res://persistence/campaign_store.gd")
const AppPreferences := preload("res://presentation/app_preferences.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const StoreTests := preload("res://tests/test_campaign_store.gd")


func run(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var directory := "user://test_m4_ui_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "M4 UI fixture directory is created")
	var save_path := directory + "/campaign.json"
	var screen := _boot(tree, entry, save_path, directory + "/settings.json")
	await tree.process_frame
	expect(_find_button(screen, "설정") != null,
		"the campaign catalog provides a settings action")
	screen.get("settings_button").pressed.emit()
	var base_font: int = screen.get("menu_title").get_theme_font_size("font_size")
	screen.get("settings_locale").item_selected.emit(1)
	screen.get("settings_text_size").item_selected.emit(1)
	screen.get("settings_sound").toggled.emit(false)
	var fresh_preferences := AppPreferences.new(directory + "/settings.json")
	var fresh_settings := fresh_preferences.load_settings()
	expect(TranslationServer.get_locale() == "en"
		and screen.get("settings_button").text == "Settings"
		and screen.get("begin_button").text == "Start preparation",
		"locale input immediately refreshes static and dynamic campaign text")
	expect(fresh_settings.accepted
		and fresh_preferences.snapshot() == {"locale": "en", "sound_enabled": false, "text_size": "large"},
		"a fresh preferences object reads all three settings from the isolated file")
	expect(screen.get("menu_title").get_theme_font_size("font_size") > base_font
		and screen.get("scenario_buttons").first_shift.get_theme_font_size("font_size") == 24
		and screen.scale == Vector2.ONE,
		"large text changes native font size without scaling the campaign control")
	screen.get("settings_sound").toggled.emit(true)
	screen.get("settings_dialog").hide()
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	var service_settings := _find_button(service, "Settings")
	expect(service_settings != null and service.get_node("SafeArea/Layout/Controls/Start").text == "Start",
		"the service shares the active locale and provides its own settings action")
	expect(service.get_node("SafeArea/Layout/Header/Title").text == "First service"
		and service.get("status_label").text.contains("Preparing")
		and service.get("preparation_panel").purchase_labels.vegetable.text.contains("Vegetables"),
		"English refresh includes scenario, preparation, and dynamic content names")
	var unchanged_state: String = service.get("simulation").state_hash()
	service.get("settings_locale").item_selected.emit(0)
	service.get("settings_locale").item_selected.emit(1)
	expect(service.get("simulation").state_hash() == unchanged_state
		and service.get("simulation").tick == 0,
		"changing locale twice leaves simulation state unchanged")
	var rejected_preparation: Dictionary = service.call("submit_preparation", "set_purchase", "vegetable", 999)
	expect(not rejected_preparation.accepted and service.get("feedback_label").text.contains("Budget"),
		"an English preparation rejection shows its translated reason")
	service.get("settings_locale").item_selected.emit(0)
	expect(service.get("feedback_label").text.contains("예산이 부족합니다")
		and service.get("simulation").state_hash() == unchanged_state,
		"locale refresh retains and retranslates the preparation rejection without changing simulation state")
	service.get("settings_locale").item_selected.emit(1)
	expect(service.get("feedback_label").text.contains("Budget")
		and service.get("simulation").state_hash() == unchanged_state,
		"the retained preparation rejection translates back to English")
	service.get("start_button").pressed.emit()
	var loaded: Dictionary = CampaignStore.new(screen.get("campaign"), save_path).load_records()
	expect(loaded.accepted and loaded.active_session is Dictionary
		and loaded.active_session.simulation.tick == 0,
		"committing preparation atomically saves the active service at tick zero")
	service.call("advance", 1.0)
	var arrival_player := service.get_node_or_null("AudioFeedback/ArrivalPlayer") as AudioStreamPlayer
	expect(arrival_player != null and arrival_player.playing,
		"a real order-arrival event starts the product arrival player")
	var arrived_button: Button = service.get("order_buttons").order_01
	expect(arrived_button.get_theme_font_size("font_size") == 24,
		"an order button created after large text is active uses the enlarged native font")
	service.get("settings_text_size").item_selected.emit(0)
	service.get("settings_text_size").item_selected.emit(1)
	expect(arrived_button.get_theme_font_size("font_size") == 24,
		"reapplying large text does not compound a dynamic order button font")
	if service_settings != null:
		service_settings.pressed.emit()
		expect(not service.call("is_running") and service.get("settings_dialog").visible
			and not arrival_player.playing,
			"opening settings pauses the simulation and stops an actual arrival cue")
		service.get("settings_dialog").hide()
		expect(not service.call("is_running"),
			"closing service settings does not resume the simulation")
		service.get("resume_button").pressed.emit()
	service.call("advance", 10.05)
	loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
	expect(loaded.accepted and loaded.active_session.simulation.tick == 110
		and loaded.active_session.accumulator_us == 50000,
		"the first frame boundary after one hundred game ticks saves tick and residual time")
	expect(service.call("submit_command", "set_duty", "employee_01", "all").accepted,
		"the pause checkpoint fixture queues a real command")
	expect(service.get("feedback_label").text.contains("commands queued"),
		"an accepted English command shows a translated queued state")
	service.call("advance", 0.15)
	expect(service.get("feedback_label").text == "Command applied",
		"the English queued state becomes applied after its command leaves the queue")
	service.get("pause_button").pressed.emit()
	loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
	expect(loaded.active_session.simulation.tick == 112
		and loaded.active_session.simulation.last_sequence == 1,
		"pausing saves the latest simulation and command sequence")
	service.call("_set_speed", 4)
	service.get("resume_button").pressed.emit()
	service.call("advance", 0.025)
	service.get("pause_button").pressed.emit()
	expect(service.call("submit_command", "set_duty", "employee_01", "cold").accepted,
		"the paused menu fixture queues a responsibility change")
	service.call("_set_speed", 2)
	screen.call("request_menu")
	screen.get("leave_dialog").confirmed.emit()
	await tree.process_frame
	loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
	expect(loaded.active_session.speed == 2
		and loaded.active_session.simulation.tick == 113
		and loaded.active_session.simulation.last_sequence == 2,
		"leaving from pause checkpoints queued commands and the current speed")
	expect(screen.get("active_service") == null,
		"confirming the menu action leaves the paused service in its checkpoint")
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame
	screen = _boot(tree, entry, save_path, directory + "/settings.json")
	await tree.process_frame
	var continue_button := _find_button(screen, "Continue")
	expect(continue_button != null and continue_button.visible,
		"a fresh campaign scene offers the saved service as a distinct continue action")
	if continue_button != null:
		continue_button.pressed.emit()
		await tree.process_frame
		service = screen.get("active_service")
		expect(service != null and service.get("state") == 2
			and service.get("simulation").tick == 113
			and service.get("driver").speed == 2
			and service.get("driver").accumulator_us == 0
			and service.get("command_sequence") == 2,
			"continue creates a fresh paused screen with restored timing and command sequence")
		expect(service.call("submit_command", "set_priority", "order_01", 2).accepted,
			"the paused lifecycle fixture queues a priority change")
		service.call("_set_speed", 4)
		service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
		expect(loaded.active_session.speed == 4
			and loaded.active_session.simulation.tick == 113
			and loaded.active_session.simulation.last_sequence == 3,
			"backgrounding from pause checkpoints queued commands and the current speed")
		service.get("resume_button").pressed.emit()
		service.call("advance", (3000 - service.get("simulation").tick) / 10.0)
		loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
		expect(loaded.active_session.simulation.closed
			and loaded.active_session.simulation.tick == 3000
			and loaded.records.first_shift.completed,
			"closing atomically saves the closed session with its campaign record")
		expect(screen.get("result_dialog").dialog_text.contains("Served")
			and screen.get("result_dialog").dialog_text.contains("Profit"),
			"English closing text includes the measured served and profit values")
		var closed_bytes := FileAccess.get_file_as_bytes(save_path)
		service.emit_signal("service_closed", service.get("simulation").snapshot())
		expect(FileAccess.get_file_as_bytes(save_path) == closed_bytes,
			"a duplicate closing signal preserves the saved bytes")
		screen.get("retry_service_button").pressed.emit()
		service.get("start_button").pressed.emit()
		loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
		expect(not loaded.active_session.simulation.closed,
			"retry start replaces the closed session with a new open checkpoint")
		service.call("advance", 300.0)
		loaded = CampaignStore.new(screen.get("campaign"), save_path).load_records()
		expect(loaded.active_session.simulation.closed,
			"a non-improving retry still replaces its open checkpoint with the closed session")
		service.get("audio_feedback").set_enabled(false)
		await tree.create_timer(0.3).timeout
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame
	var closed_bytes := FileAccess.get_file_as_bytes(save_path)
	screen = _boot(tree, entry, save_path, directory + "/settings.json")
	await tree.process_frame
	continue_button = _find_button(screen, "Continue")
	if continue_button != null:
		continue_button.pressed.emit()
		await tree.process_frame
		expect(screen.get("active_service").get("state") == 3
			and screen.get("result_dialog").visible
			and FileAccess.get_file_as_bytes(save_path) == closed_bytes,
			"continuing a closed checkpoint shows its idempotent result without rewriting bytes")
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame
	await _test_failed_checkpoint_and_replacement(tree, entry, directory)
	await _test_recovered_active_session(tree, entry, directory)
	await _test_lifecycle_audio(tree, entry, directory)
	await _test_future_settings_error(tree, entry, directory)
	TranslationServer.set_locale("ko")
	_cleanup(directory)


func _test_failed_checkpoint_and_replacement(tree: SceneTree, entry: String, directory: String) -> void:
	var file_path := directory + "/failed.json"
	var screen := _boot(tree, entry, file_path, directory + "/failed-settings.json")
	await tree.process_frame
	var failed_store := StoreTests.FailedStore.new(screen.get("campaign"), file_path)
	failed_store.failure = "write"
	screen.set("store", failed_store)
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	service.get("start_button").pressed.emit()
	await tree.process_frame
	var retry := _find_visible_button(screen, "저장 재시도")
	expect(screen.get("pending_save") and retry != null
		and screen.get("save_label").text.contains("다시 시도"),
		"an open-service save failure shows its reason and a visible retry action")
	screen.call("request_menu")
	expect(screen.get("active_service") == service and not screen.get("leave_dialog").visible
		and screen.get("save_error_dialog").visible,
		"a failed pause checkpoint blocks the menu confirmation behind its retry action")
	var failed_state: String = service.get("simulation").state_hash()
	screen.get("settings_locale").item_selected.emit(1)
	expect(screen.get("save_label").text.contains("another save attempt")
		and screen.get("save_error_dialog").dialog_text.contains("another save attempt")
		and service.get("simulation").state_hash() == failed_state,
		"locale refresh retains and retranslates the visible storage failure without changing simulation state")
	screen.get("settings_locale").item_selected.emit(0)
	expect(screen.get("save_label").text.contains("다시 시도"),
		"the retained storage failure translates back to Korean")
	screen.call("return_to_menu")
	expect(screen.get("active_service") == service,
		"a failed open-service save blocks direct navigation")
	failed_store.failure = ""
	if retry != null:
		retry.pressed.emit()
	expect(not screen.get("pending_save") and FileAccess.file_exists(file_path),
		"retry writes the preserved open service without changing its state")
	failed_store.failure = "write"
	screen.get("service_goal_button").pressed.emit()
	await tree.process_frame
	expect(screen.get("pending_save") and screen.get("save_error_dialog").visible
		and not screen.get("goal_dialog").visible and not screen.get("leave_dialog").visible,
		"a failed goal pause shows only the checkpoint retry dialog")
	failed_store.failure = ""
	retry.pressed.emit()
	screen.get("service_goal_button").pressed.emit()
	expect(not screen.get("pending_save") and screen.get("goal_dialog").visible
		and not service.call("is_running"),
		"a successful retry allows the goal dialog while service remains paused")
	screen.get("goal_dialog").hide()
	service.get("resume_button").pressed.emit()
	failed_store.failure = "write"
	service.get("settings_button").pressed.emit()
	await tree.process_frame
	expect(screen.get("pending_save") and screen.get("save_error_dialog").visible
		and not service.get("settings_dialog").visible and not screen.get("goal_dialog").visible,
		"a failed service-settings pause shows only the checkpoint retry dialog")
	failed_store.failure = ""
	retry.pressed.emit()
	service.get("settings_button").pressed.emit()
	expect(not screen.get("pending_save") and service.get("settings_dialog").visible
		and not service.call("is_running"),
		"a successful retry allows service settings while service remains paused")
	service.get("settings_dialog").hide()
	screen.call("request_menu")
	screen.get("leave_dialog").confirmed.emit()
	await tree.process_frame
	expect(screen.get("active_service") == null,
		"the menu action succeeds after the checkpoint retry")
	var saved_bytes := FileAccess.get_file_as_bytes(file_path)
	var saved_session: Dictionary = screen.get("active_session").duplicate(true)
	screen.get("begin_button").pressed.emit()
	var replace := _find_visible_button(screen, "새 영업으로 교체")
	expect(screen.get("active_service") == null and replace != null,
		"starting over with an open checkpoint requires an explicit replacement confirmation")
	expect(screen.get("replace_dialog").dialog_text == "새 영업에서 시작을 누르면 저장한 이어하기를 새 영업으로 교체합니다.",
		"replacement copy names Start as the checkpoint replacement point")
	screen.get("settings_locale").item_selected.emit(1)
	expect(screen.get("replace_dialog").dialog_text == "Starting the new service replaces the saved checkpoint.",
		"English replacement copy names Start as the checkpoint replacement point")
	screen.get("settings_locale").item_selected.emit(0)
	if replace != null:
		replace.pressed.emit()
	await tree.process_frame
	service = screen.get("active_service")
	expect(service != null and service.get("state") == 0
		and screen.get("active_session") == saved_session
		and FileAccess.get_file_as_bytes(file_path) == saved_bytes,
		"confirming replacement opens preparation without replacing the saved checkpoint")
	screen.call("return_to_menu")
	await tree.process_frame
	expect(screen.get("active_service") == null and screen.get("continue_button").visible
		and screen.get("active_session") == saved_session
		and FileAccess.get_file_as_bytes(file_path) == saved_bytes,
		"leaving fresh preparation keeps the previous checkpoint available")
	screen.get("begin_button").pressed.emit()
	var second_replace := _find_visible_button(screen, "새 영업으로 교체")
	if second_replace != null:
		second_replace.pressed.emit()
	await tree.process_frame
	service = screen.get("active_service")
	var replacement_purchase := int(saved_session.preparation.purchases.vegetable) + 1
	expect(service.call("submit_preparation", "set_purchase", "vegetable", replacement_purchase).accepted,
		"the replacement fixture changes its preparation")
	failed_store.failure = "write"
	service.get("start_button").pressed.emit()
	await tree.process_frame
	expect(screen.get("pending_save") and screen.get("active_session") == saved_session
		and FileAccess.get_file_as_bytes(file_path) == saved_bytes,
		"a failed replacement Start preserves the previous checkpoint")
	failed_store.failure = ""
	retry.pressed.emit()
	var replaced := CampaignStore.new(screen.get("campaign"), file_path).load_records()
	expect(not screen.get("pending_save") and replaced.accepted
		and replaced.active_session.preparation.purchases.vegetable == replacement_purchase
		and FileAccess.get_file_as_bytes(file_path) != saved_bytes,
		"a successful replacement Start writes the new checkpoint")
	if service != null:
		service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_lifecycle_audio(tree: SceneTree, entry: String, directory: String) -> void:
	var file_path := directory + "/lifecycle.json"
	var screen := _boot(tree, entry, file_path, directory + "/lifecycle-settings.json")
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	var arrival := service.get_node("AudioFeedback/ArrivalPlayer") as AudioStreamPlayer
	expect(arrival.playing, "the lifecycle fixture starts an actual arrival cue")
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not service.call("is_running") and not arrival.playing,
		"focus loss pauses service and stops active audio playback")
	var paused_tick: int = service.get("simulation").tick
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	service.call("advance", 2.0)
	expect(not service.call("is_running") and service.get("simulation").tick == paused_tick,
		"focus return does not resume service time")
	service.get("resume_button").pressed.emit()
	service.call("advance", 21.0)
	expect(arrival.playing,
		"manual resume enables only a later order-arrival cue")
	var later_arrival_tick: int = service.get("simulation").tick
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(not arrival.playing and not service.call("is_running")
		and service.get("simulation").tick == later_arrival_tick,
		"background and foreground stop a later real cue without replaying it or resuming service")
	service.get("audio_feedback").set_enabled(false)
	await tree.create_timer(0.3).timeout
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_recovered_active_session(tree: SceneTree, entry: String, directory: String) -> void:
	var file_path := directory + "/recovery.json"
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var plan := PreparationPlan.new(campaign.scenario_for("first_shift"))
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the recovery UI fixture starts a valid service")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	for _step: int in 7:
		simulation.step()
	var session := ServiceSession.capture("first_shift", started.selection, simulation, 2, 12345)
	var store := CampaignStore.new(campaign, file_path)
	expect(store.save_active_session(session, {}).accepted
		and store.save_records({}).accepted,
		"the recovery UI fixture writes an open-session backup")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var screen := _boot(tree, entry, file_path, directory + "/recovery-settings.json")
	await tree.process_frame
	expect(screen.get("recover_button").visible,
		"a corrupt primary with a valid session backup offers explicit recovery")
	screen.get("recover_button").pressed.emit()
	var continue_button := screen.get("continue_button") as Button
	expect(continue_button.visible,
		"recovering a backup exposes its open service as a continue action")
	continue_button.pressed.emit()
	await tree.process_frame
	var service: Control = screen.get("active_service")
	expect(service != null and service.get("state") == 2
		and service.get("simulation").tick == 7
		and service.get("driver").speed == 2
		and service.get("driver").accumulator_us == 12345,
		"continue restores the recovered backup session paused at its saved timing")
	if service != null:
		service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_future_settings_error(tree: SceneTree, entry: String, directory: String) -> void:
	TranslationServer.set_locale("ko")
	var settings_path := directory + "/future-settings.json"
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 99, "locale": "en", "sound_enabled": false, "text_size": "large"}))
	file.close()
	var original := FileAccess.get_file_as_bytes(settings_path)
	var screen := _boot(tree, entry, directory + "/future-campaign.json", settings_path)
	await tree.process_frame
	screen.get("settings_button").pressed.emit()
	expect(screen.get("settings_message").text.contains("지원하지 않는 설정")
		and screen.get("settings_message").is_visible_in_tree(),
		"a future settings file shows a visible protected-file reason")
	screen.get("settings_locale").item_selected.emit(1)
	expect(FileAccess.get_file_as_bytes(settings_path) == original,
		"settings input cannot overwrite future settings bytes")
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _boot(tree: SceneTree, scene_path: String, save_path: String, settings_path: String) -> Control:
	var scene: PackedScene = load(scene_path)
	var screen: Control = scene.instantiate()
	screen.set("save_path", save_path)
	screen.set("settings_path", settings_path)
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen


func _cleanup(directory: String) -> void:
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(directory) == OK, "M4 UI fixtures are removed")


func _find_button(node: Node, title: String) -> Button:
	for child: Node in node.get_children(true):
		if child is Button and child.text == title:
			return child
		var found := _find_button(child, title)
		if found != null:
			return found
	return null


func _find_visible_button(node: Node, title: String) -> Button:
	for child: Node in node.get_children(true):
		if child is Button and child.text == title and child.is_visible_in_tree():
			return child
		var found := _find_visible_button(child, title)
		if found != null:
			return found
	return null
