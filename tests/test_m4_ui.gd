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
	screen.set("active_session", {"scenario_id": "lunch_prep"})
	screen.call("_set_save_message", "storage", "content_updated")
	screen.call("_refresh_catalog")
	expect(screen.get("continue_button").visible
		and screen.get("save_label").text == "주방 운영 규칙을 갱신했습니다. 완료 기록을 보존했고 진행 중이던 영업을 이어갈 수 있습니다.",
		"a content update explains that a preserved active service can continue")
	screen.set("active_session", null)
	screen.call("_set_save_message", "storage", "content_updated")
	screen.call("_refresh_catalog")
	expect(not screen.get("continue_button").visible
		and screen.get("save_label").text == "주방 운영 규칙을 갱신했습니다. 완료 기록은 보존하고 진행 중이던 영업은 다시 시작합니다.",
		"a content update explains when its active service was restarted")
	screen.call("_set_save_message", "storage", "new_campaign")
	expect(_find_button(screen, "설정") != null,
		"the campaign catalog provides a settings action")
	screen.get("settings_button").pressed.emit()
	var campaign_locale_popup: PopupMenu = screen.get("settings_locale").get_popup()
	var campaign_text_popup: PopupMenu = screen.get("settings_text_size").get_popup()
	expect(campaign_locale_popup.get_theme_font_size("font_size") == 26
		and campaign_text_popup.get_theme_font_size("font_size") == 26
		and _popup_row_height(campaign_locale_popup) >= 64
		and _popup_row_height(campaign_text_popup) >= 64,
		"normal campaign settings popups provide 64-pixel rows at the native 26-pixel font")
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
	screen.set("active_session", {"scenario_id": "lunch_prep"})
	screen.call("_set_save_message", "storage", "content_updated")
	expect(screen.get("save_label").text == "Kitchen rules were updated. Completion records are preserved, and the service in progress can continue.",
		"an English content update explains that a preserved active service can continue")
	screen.set("active_session", null)
	screen.call("_set_save_message", "storage", "new_campaign")
	expect(fresh_settings.accepted
		and fresh_preferences.snapshot() == {"locale": "en", "sound_enabled": false, "text_size": "large"},
		"a fresh preferences object reads all three settings from the isolated file")
	expect(screen.get("menu_title").get_theme_font_size("font_size") > base_font
		and screen.get("scenario_buttons").first_shift.get_theme_font_size("font_size") == 24
		and screen.scale == Vector2.ONE,
		"large text changes native font size without scaling the campaign control")
	expect(campaign_locale_popup.get_theme_font_size("font_size") == 32
		and campaign_text_popup.get_theme_font_size("font_size") == 32
		and _popup_row_height(campaign_locale_popup) >= 64
		and _popup_row_height(campaign_text_popup) >= 64,
		"large campaign settings popups provide 64-pixel rows at the native 32-pixel font")
	screen.get("settings_sound").toggled.emit(true)
	screen.get("settings_dialog").hide()
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	var service_settings := _find_button(service, "Settings")
	expect(service_settings != null and service.get_node("SafeArea/Layout/Controls/Start").text == "Start",
		"the service shares the active locale and provides its own settings action")
	var service_locale_popup: PopupMenu = service.get("settings_locale").get_popup()
	var service_text_popup: PopupMenu = service.get("settings_text_size").get_popup()
	expect(service_locale_popup.get_theme_font_size("font_size") == 32
		and service_text_popup.get_theme_font_size("font_size") == 32
		and _popup_row_height(service_locale_popup) >= 64
		and _popup_row_height(service_text_popup) >= 64,
		"large service settings popups provide 64-pixel rows at the native 32-pixel font")
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
	await _test_failed_checkpoint_pauses_live_service(tree, entry, directory)
	await _test_failed_checkpoint_and_replacement(tree, entry, directory)
	await _test_recovered_active_session(tree, entry, directory)
	await _test_lifecycle_audio(tree, entry, directory)
	await _test_service_locale_refresh(tree, entry, directory)
	await _test_future_settings_error(tree, entry, directory)
	await _test_invalid_campaign_settings(tree, entry, directory)
	await _test_operational_option_popups(tree, entry, directory)
	await _test_session_only_checkpoint_watermark(tree, entry, directory)
	TranslationServer.set_locale("ko")
	_cleanup(directory)


func _test_failed_checkpoint_pauses_live_service(tree: SceneTree, entry: String, directory: String) -> void:
	var start_path := directory + "/live-start-failure.json"
	var screen := _boot(tree, entry, start_path, directory + "/live-start-settings.json")
	await tree.process_frame
	var failed_store := StoreTests.FailedStore.new(screen.get("campaign"), start_path)
	failed_store.failure = "write"
	screen.set("store", failed_store)
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	expect(service.is_processing(), "the failed Start fixture uses the real service process loop")
	service.get("start_button").pressed.emit()
	var failed_tick: int = service.get("simulation").tick
	expect(screen.get("pending_save") and screen.get("save_error_dialog").visible
		and service.get("state") == 2 and service.get("driver").paused
		and not service.call("is_running"),
		"a failed Start checkpoint pauses the service behind the retry dialog")
	await tree.create_timer(0.15).timeout
	expect(service.get("simulation").tick == failed_tick,
		"a failed Start checkpoint holds the simulation tick across real process frames")
	failed_store.failure = ""
	screen.get("retry_checkpoint_button").pressed.emit()
	var loaded := CampaignStore.new(screen.get("campaign"), start_path).load_records()
	expect(not screen.get("pending_save") and loaded.accepted
		and loaded.active_session.simulation.tick == failed_tick
		and service.get("state") == 2 and service.get("driver").paused,
		"a successful Start retry preserves the checkpoint and remains paused")
	await tree.create_timer(0.1).timeout
	expect(service.get("simulation").tick == failed_tick,
		"a successful Start retry waits for manual resume")
	service.get("resume_button").pressed.emit()
	await tree.create_timer(0.15).timeout
	expect(service.call("is_running") and service.get("simulation").tick > failed_tick,
		"manual resume restarts service time after a successful Start retry")
	service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame

	var automatic_path := directory + "/live-automatic-failure.json"
	screen = _boot(tree, entry, automatic_path, directory + "/live-automatic-settings.json")
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	expect(service.is_processing(), "the failed automatic checkpoint fixture uses the real service process loop")
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	var arrival := service.get_node("AudioFeedback/ArrivalPlayer") as AudioStreamPlayer
	expect(arrival.playing, "the automatic checkpoint fixture starts an actual arrival cue")
	failed_store = StoreTests.FailedStore.new(screen.get("campaign"), automatic_path)
	failed_store.failure = "write"
	screen.set("store", failed_store)
	service.call("advance", 9.0)
	failed_tick = service.get("simulation").tick
	expect(screen.get("pending_save") and screen.get("save_error_dialog").visible
		and service.get("state") == 2 and service.get("driver").paused
		and not service.call("is_running") and not arrival.playing,
		"a failed automatic checkpoint pauses time and stops an active arrival cue")
	await tree.create_timer(0.15).timeout
	expect(service.get("simulation").tick == failed_tick,
		"a failed automatic checkpoint holds the simulation tick across real process frames")
	failed_store.failure = ""
	screen.get("retry_checkpoint_button").pressed.emit()
	loaded = CampaignStore.new(screen.get("campaign"), automatic_path).load_records()
	expect(not screen.get("pending_save") and loaded.accepted
		and loaded.active_session.simulation.tick == failed_tick
		and service.get("state") == 2 and service.get("driver").paused,
		"a successful automatic retry preserves the checkpoint and remains paused")
	await tree.create_timer(0.1).timeout
	expect(service.get("simulation").tick == failed_tick,
		"a successful automatic retry waits for manual resume")
	service.get("resume_button").pressed.emit()
	await tree.create_timer(0.15).timeout
	expect(service.call("is_running") and service.get("simulation").tick > failed_tick,
		"manual resume restarts service time after a successful automatic retry")
	service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


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

	var closed_path := directory + "/lifecycle-closed.json"
	screen = _boot(tree, entry, closed_path, directory + "/lifecycle-closed-settings.json")
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	service.get("start_button").pressed.emit()
	service.call("advance", 300.0)
	var served := service.get_node("AudioFeedback/ServedPlayer") as AudioStreamPlayer
	expect(service.get("state") == 3 and service.get("simulation").closed
		and service.get("simulation").tick == 3000 and served.playing,
		"one real advance closes service while its drained served event plays the product cue")
	var closed_tick: int = service.get("simulation").tick
	var closed_checkpoints := {"value": 0}
	service.checkpoint_requested.connect(func(_reason: String) -> void: closed_checkpoints.value += 1)
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_PAUSED)
	expect(not served.playing and service.get("state") == 3
		and service.get("simulation").tick == closed_tick and closed_checkpoints.value == 0,
		"backgrounding a closed service stops its real served cue without changing state or checkpointing")
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_RESUMED)
	service.call("advance", 1.0)
	expect(not served.playing and service.get("state") == 3
		and service.get("simulation").tick == closed_tick and closed_checkpoints.value == 0,
		"foregrounding a closed service does not replay audio or resume time")
	service.get("audio_feedback").set_enabled(false)
	await tree.create_timer(0.3).timeout
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame

	var ready_path := directory + "/lifecycle-ready.json"
	screen = _boot(tree, entry, ready_path, directory + "/lifecycle-ready-settings.json")
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	var ready_checkpoints := {"value": 0}
	service.checkpoint_requested.connect(func(_reason: String) -> void: ready_checkpoints.value += 1)
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	service.get("lifecycle").call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(service.get("state") == 0 and service.get("simulation").tick == 0
		and ready_checkpoints.value == 0,
		"backgrounding preparation does not start time or request a checkpoint")
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	var ready_arrival := service.get_node("AudioFeedback/ArrivalPlayer") as AudioStreamPlayer
	expect(service.call("is_running") and service.get("simulation").tick == 10 and ready_arrival.playing,
		"explicit Start after a preparation background transition enables the next real cue")
	service.get("audio_feedback").set_enabled(false)
	await tree.create_timer(0.3).timeout
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_service_locale_refresh(tree: SceneTree, entry: String, directory: String) -> void:
	TranslationServer.set_locale("ko")
	var save_path := directory + "/locale-refresh.json"
	var settings_path := directory + "/locale-refresh-settings.json"
	var screen := _boot(tree, entry, save_path, settings_path)
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	var counter := service.get("counter") as Label
	var remaining := service.get("remaining_label") as Label
	var details_toggle := service.get("details_toggle") as Button
	var detail_panel := service.get("detail_panel") as Control
	var preparation_panel: Control = service.get("preparation_panel")
	preparation_panel.call("show_tab", 0)
	preparation_panel.get("prep_plus")["salad"].pressed.emit()
	preparation_panel.call("show_tab", 1)
	preparation_panel.get("duty_buttons")["employee_01"].item_selected.emit(1)
	var employee_one_label := _find_label(preparation_panel.get("pages")[1], "직원 1")
	var employee_two_label := _find_label(preparation_panel.get("pages")[1], "직원 2")
	var ready_preparation: Dictionary = service.get("preparation").snapshot()
	expect(preparation_panel.visible and preparation_panel.get("pages")[1].visible
		and employee_one_label != null and employee_one_label.is_visible_in_tree()
		and employee_two_label != null and employee_two_label.is_visible_in_tree()
		and ready_preparation.prep_quantities.salad == 1
		and ready_preparation.duties.employee_01 == "cold",
		"the locale fixture shows the real layout tab with selected prep and duty state")
	expect(service.get("state") == 0 and service.get("shown_tenths") == 0
		and service.get("simulation").tick == 0,
		"the ready locale fixture warms the displayed time cache at tick zero")
	var ready_hash: String = service.get("simulation").state_hash()
	var ready_commands: Array = service.get("simulation").snapshot().commands.duplicate(true)
	service.get("settings_locale").item_selected.emit(1)
	expect(counter.text == "000.0 s", "a ready locale change refreshes the exact English elapsed time")
	expect(remaining.text == "Time remaining 300.0 s  ·  ",
		"a ready locale change refreshes the exact English remaining time")
	expect(employee_one_label.text == "Employee 1",
		"a ready locale change refreshes the exact first employee name")
	expect(employee_two_label.text == "Employee 2",
		"a ready locale change refreshes the exact second employee name")
	expect(preparation_panel.get("pages")[1].visible
		and service.get("preparation").snapshot() == ready_preparation,
		"an English employee-name refresh preserves the visible tab and preparation state")
	expect(service.get("state") == 0 and service.get("simulation").tick == 0
		and service.get("simulation").snapshot().commands == ready_commands
		and service.get("simulation").state_hash() == ready_hash,
		"a ready locale change preserves the service state, tick, and commands")
	service.get("settings_locale").item_selected.emit(0)
	expect(counter.text == "000.0초", "a ready locale change refreshes the exact Korean elapsed time")
	expect(remaining.text == "남은 시간 300.0초  ·  ",
		"a ready locale change refreshes the exact Korean remaining time")
	expect(employee_one_label.text == "직원 1",
		"the Korean refresh restores the exact first employee name")
	expect(employee_two_label.text == "직원 2",
		"the Korean refresh restores the exact second employee name")
	expect(preparation_panel.get("pages")[1].visible
		and service.get("preparation").snapshot() == ready_preparation,
		"a Korean employee-name refresh preserves the visible tab and preparation state")
	expect(service.get("state") == 0 and service.get("simulation").tick == 0
		and service.get("simulation").snapshot().commands == ready_commands
		and service.get("simulation").state_hash() == ready_hash,
		"the Korean ready refresh preserves the service state, tick, and commands")

	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	service.call("set_compact_layout", true)
	expect(service.call("is_running") and service.get("compact_layout") and details_toggle.visible,
		"the real running service exposes the compact phone details control")
	service.get("pause_button").pressed.emit()
	expect(service.get("state") == 2 and service.get("shown_tenths") == 10
		and service.get("simulation").tick == 10 and details_toggle.visible,
		"the paused locale fixture has a warm displayed time cache and a visible compact control")
	expect(not detail_panel.visible and details_toggle.text == "주문 상세 펼치기",
		"the paused compact fixture starts collapsed with Korean text")
	var paused_hash: String = service.get("simulation").state_hash()
	var paused_commands: Array = service.get("simulation").snapshot().commands.duplicate(true)
	service.get("settings_locale").item_selected.emit(1)
	expect(counter.text == "001.0 s", "a paused locale change refreshes the exact English elapsed time")
	expect(remaining.text == "Time remaining 299.0 s  ·  ",
		"a paused locale change refreshes the exact English remaining time")
	expect(details_toggle.text == "Show order details",
		"a paused locale change refreshes the collapsed details control")
	expect(service.get("state") == 2 and service.get("simulation").tick == 10
		and service.get("simulation").snapshot().commands == paused_commands
		and service.get("simulation").state_hash() == paused_hash and not detail_panel.visible,
		"the collapsed locale change preserves the paused state, tick, commands, and panel visibility")
	service.get("settings_locale").item_selected.emit(0)
	expect(counter.text == "001.0초", "a paused locale change refreshes the exact Korean elapsed time")
	expect(remaining.text == "남은 시간 299.0초  ·  ",
		"a paused locale change refreshes the exact Korean remaining time")
	expect(details_toggle.text == "주문 상세 펼치기",
		"the Korean refresh restores the collapsed details control text")

	details_toggle.pressed.emit()
	expect(detail_panel.visible and details_toggle.text == "주문 상세 접기",
		"the paused compact fixture starts its expanded check with Korean text")
	service.get("settings_locale").item_selected.emit(1)
	expect(details_toggle.text == "Hide order details",
		"a paused locale change refreshes the expanded details control")
	expect(service.get("state") == 2 and service.get("simulation").tick == 10
		and service.get("simulation").snapshot().commands == paused_commands
		and service.get("simulation").state_hash() == paused_hash and detail_panel.visible,
		"the expanded locale change preserves the paused state, tick, commands, and panel visibility")
	service.get("settings_locale").item_selected.emit(0)
	expect(details_toggle.text == "주문 상세 접기",
		"the Korean refresh restores the expanded details control text")
	expect(service.get("state") == 2 and service.get("simulation").tick == 10
		and service.get("simulation").snapshot().commands == paused_commands
		and service.get("simulation").state_hash() == paused_hash and detail_panel.visible,
		"the Korean expanded refresh preserves the paused service and visible panel")

	service.get("resume_button").pressed.emit()
	service.call("advance", 299.0)
	expect(service.get("state") == 3 and service.get("shown_tenths") == 3000
		and service.get("simulation").tick == 3000,
		"the closed locale fixture warms the displayed time cache at the closing tick")
	var closed_hash: String = service.get("simulation").state_hash()
	var closed_commands: Array = service.get("simulation").snapshot().commands.duplicate(true)
	var closed_panel_visible: bool = detail_panel.visible
	service.get("settings_locale").item_selected.emit(1)
	expect(counter.text == "300.0 s", "a closed locale change refreshes the exact English elapsed time")
	expect(remaining.text == "Time remaining 000.0 s  ·  ",
		"a closed locale change refreshes the exact English remaining time")
	expect(service.get("state") == 3 and service.get("simulation").tick == 3000
		and service.get("simulation").snapshot().commands == closed_commands
		and service.get("simulation").state_hash() == closed_hash
		and detail_panel.visible == closed_panel_visible,
		"a closed locale change preserves the service state, tick, commands, and panel visibility")
	service.get("settings_locale").item_selected.emit(0)
	expect(counter.text == "300.0초", "a closed locale change refreshes the exact Korean elapsed time")
	expect(remaining.text == "남은 시간 000.0초  ·  ",
		"a closed locale change refreshes the exact Korean remaining time")
	expect(service.get("state") == 3 and service.get("simulation").tick == 3000
		and service.get("simulation").snapshot().commands == closed_commands
		and service.get("simulation").state_hash() == closed_hash
		and detail_panel.visible == closed_panel_visible,
		"the Korean closed refresh preserves the service state, tick, commands, and panel visibility")
	service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame

	var english_settings_path := directory + "/locale-boot-settings.json"
	var saved_preferences := AppPreferences.new(english_settings_path)
	expect(saved_preferences.update_settings({"locale": "en"}).accepted,
		"the saved-English boot fixture writes an isolated settings file")
	TranslationServer.set_locale("ko")
	screen = _boot(tree, entry, directory + "/locale-boot.json", english_settings_path)
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	preparation_panel = service.get("preparation_panel")
	preparation_panel.call("show_tab", 1)
	expect(preparation_panel.visible and preparation_panel.get("pages")[1].visible
		and _find_label(preparation_panel.get("pages")[1], "Employee 1") != null
		and _find_label(preparation_panel.get("pages")[1], "Employee 2") != null,
		"a saved-English boot renders exact employee names on the visible layout tab")
	service.get("start_button").pressed.emit()
	counter = service.get("counter") as Label
	remaining = service.get("remaining_label") as Label
	expect(TranslationServer.get_locale() == "en" and service.call("is_running")
		and service.get("simulation").tick == 0,
		"a fresh campaign loads the saved English locale before the service starts")
	expect(counter.text == "000.0 s", "a saved-English boot renders the exact elapsed time after Start")
	expect(remaining.text == "Time remaining 300.0 s  ·  ",
		"a saved-English boot renders the exact remaining time after Start")
	service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame
	TranslationServer.set_locale("ko")


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
	var primary_bytes := FileAccess.get_file_as_bytes(file_path)
	var backup_bytes := FileAccess.get_file_as_bytes(file_path + ".backup")
	var screen := _boot(tree, entry, file_path, directory + "/recovery-settings.json")
	await tree.process_frame
	var recover_button := screen.get("recover_button") as Button
	var session_only_button := screen.get("session_only_button") as Button
	expect(recover_button.visible and session_only_button.visible
		and recover_button.text == "백업에서 복구"
		and session_only_button.text == "저장 없이 새로 시작",
		"a corrupt primary with a valid backup shows both Korean recovery choices")
	expect(screen.get("storage_blocked") and screen.get("save_message_kind") == "storage"
		and screen.get("save_message_reason") == "corrupt_records"
		and screen.get("active_session") == null,
		"the recovery choices start from the actual blocked corrupt-save state")
	screen.get("settings_locale").item_selected.emit(1)
	expect(recover_button.text == "Recover from backup",
		"a locale change refreshes the exact English backup recovery action")
	expect(session_only_button.text == "Start without saving",
		"a locale change refreshes the exact English session-only action")
	expect(screen.get("save_label").text == "The save could not be read. Recover the backup or start without saving.",
		"the corrupt-save status remains visible in English")
	expect(screen.get("storage_blocked") and screen.get("save_message_reason") == "corrupt_records"
		and screen.get("active_session") == null and recover_button.visible
		and session_only_button.visible and FileAccess.get_file_as_bytes(file_path) == primary_bytes
		and FileAccess.get_file_as_bytes(file_path + ".backup") == backup_bytes,
		"the English refresh preserves failure state, bytes, choices, and the manual recovery gate")
	screen.get("settings_locale").item_selected.emit(0)
	expect(recover_button.text == "백업에서 복구",
		"the Korean refresh restores the exact backup recovery action")
	expect(session_only_button.text == "저장 없이 새로 시작",
		"the Korean refresh restores the exact session-only action")
	expect(screen.get("save_label").text == "저장 기록을 정상적으로 읽을 수 없습니다. 백업을 복구하거나 저장 없이 시작할 수 있습니다.",
		"the corrupt-save status remains visible in Korean")
	expect(screen.get("storage_blocked") and screen.get("save_message_reason") == "corrupt_records"
		and screen.get("active_session") == null and recover_button.visible
		and session_only_button.visible and FileAccess.get_file_as_bytes(file_path) == primary_bytes
		and FileAccess.get_file_as_bytes(file_path + ".backup") == backup_bytes,
		"the Korean refresh preserves failure state, bytes, choices, and the manual recovery gate")
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


func _test_invalid_campaign_settings(tree: SceneTree, entry: String, directory: String) -> void:
	var empty_campaign: Resource = load("res://content/campaign_def.gd").new()
	var invalid_campaign: Resource = load("res://content/campaign/campaign.tres").duplicate(true)
	invalid_campaign.id = ""
	var fixtures: Array[Resource] = [Resource.new(), empty_campaign, invalid_campaign]
	for index: int in fixtures.size():
		TranslationServer.set_locale("ko")
		var campaign_path := directory + "/invalid-campaign-%d.tres" % index
		var settings_path := directory + "/invalid-campaign-%d-settings.json" % index
		var records_path := directory + "/invalid-campaign-%d-records.json" % index
		expect(ResourceSaver.save(fixtures[index], campaign_path) == OK,
			"invalid campaign fixture saves a readable resource")
		var scene: PackedScene = load(entry)
		var screen: Control = scene.instantiate()
		screen.set("campaign_path", campaign_path)
		screen.set("save_path", records_path)
		screen.set("settings_path", settings_path)
		tree.root.add_child(screen)
		screen.set_process(false)
		await tree.process_frame
		expect(screen.get("progress") == null and screen.get("store") == null
			and screen.get("save_label").text == "캠페인 데이터를 불러올 수 없습니다"
			and screen.get("begin_button").disabled,
			"invalid campaign stops initialization and shows its error before settings input")
		expect((screen.get("campaign") == null) == (index == 0),
			"fixtures cover both a failed campaign cast and failed campaign validation")
		screen.get("settings_button").pressed.emit()
		expect(screen.get("settings_dialog").visible,
			"settings remain accessible after campaign initialization fails")
		screen.get("settings_locale").item_selected.emit(1)
		expect(screen.get("save_label").text == "Could not load campaign data",
			"locale input refreshes the campaign error without campaign data")
		screen.get("settings_sound").toggled.emit(false)
		screen.get("settings_text_size").item_selected.emit(1)
		expect(screen.get("save_label").text == "Could not load campaign data"
			and screen.get("menu_title").get_theme_font_size("font_size") == 36,
			"sound and large text inputs preserve the translated campaign error")
		var fresh_preferences := AppPreferences.new(settings_path)
		expect(fresh_preferences.load_settings().accepted
			and fresh_preferences.snapshot() == {"locale": "en", "sound_enabled": false, "text_size": "large"},
			"a new settings reader loads inputs made on the campaign error screen")
		screen.get("settings_locale").item_selected.emit(0)
		expect(screen.get("save_label").text == "캠페인 데이터를 불러올 수 없습니다"
			and screen.get("scenario_buttons").is_empty() and screen.get("begin_button").disabled
			and not screen.call("begin_service") and not FileAccess.file_exists(records_path),
			"returning to Korean keeps invalid campaign actions blocked and records absent")
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


func _test_operational_option_popups(tree: SceneTree, entry: String, directory: String) -> void:
	var screen := _boot(tree, entry, directory + "/operational-popups.json", directory + "/operational-popups-settings.json")
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	var preparation: Control = service.get("preparation_panel")
	var preparation_pickers: Array[OptionButton] = [preparation.get("station_picker")]
	for picker: OptionButton in preparation.get("duty_buttons").values():
		preparation_pickers.append(picker)
	var live_pickers: Array[OptionButton] = []
	for picker: OptionButton in service.get("duty_buttons"):
		live_pickers.append(picker)
	expect(_operational_popups_match(preparation_pickers, 26) and _operational_popups_match(live_pickers, 26),
		"normal text styles preparation and live duty popup rows at 26 pixels")
	service.get("settings_text_size").item_selected.emit(1)
	expect(_operational_popups_match(preparation_pickers, 32) and _operational_popups_match(live_pickers, 32),
		"large text styles preparation and live duty popup rows at 32 pixels")
	service.get("settings_text_size").item_selected.emit(0)
	expect(_operational_popups_match(preparation_pickers, 26) and _operational_popups_match(live_pickers, 26),
		"normal text restores preparation and live duty popup rows at 26 pixels")
	service.get("start_button").pressed.emit()
	expect(service.call("is_running") and _operational_popups_match(live_pickers, 26),
		"live service keeps normal duty popup rows after preparation starts")
	service.call("_process", 300.0)
	service.get("restart_button").pressed.emit()
	expect(service.get("state") == 0 and _operational_popups_match(preparation_pickers, 26),
		"preparation regeneration keeps normal station and duty popup rows")
	service.get("audio_feedback").set_enabled(false)
	screen.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_session_only_checkpoint_watermark(tree: SceneTree, entry: String, directory: String) -> void:
	var file_path := directory + "/session-only-watermark.json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var original_bytes := FileAccess.get_file_as_bytes(file_path)
	var screen := _boot(tree, entry, file_path, directory + "/session-only-watermark-settings.json")
	await tree.process_frame
	screen.get("session_only_button").pressed.emit()
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	var automatic_ticks: Array[int] = []
	service.checkpoint_requested.connect(func(reason: String) -> void:
		if reason == "automatic":
			automatic_ticks.append(service.get("simulation").tick))
	service.get("start_button").pressed.emit()
	expect(screen.get("session_only") and service.get("last_saved_tick") == 0
		and FileAccess.get_file_as_bytes(file_path) == original_bytes,
		"starting without saving advances the preparation checkpoint watermark without changing corrupt bytes")
	for _tick: int in 200:
		service.call("_process", 0.1)
	expect(automatic_ticks == [100, 200] and service.get("last_saved_tick") == 200
		and FileAccess.get_file_as_bytes(file_path) == original_bytes,
		"session-only automatic checkpoints run at ticks 100 and 200 without writing bytes")
	for _tick: int in 50:
		service.call("_process", 0.1)
	service.get("pause_button").pressed.emit()
	service.get("resume_button").pressed.emit()
	for _tick: int in 99:
		service.call("_process", 0.1)
	expect(automatic_ticks == [100, 200] and service.get("last_saved_tick") == 250,
		"a session-only pause preserves the automatic checkpoint cadence")
	service.call("_process", 0.1)
	expect(automatic_ticks == [100, 200, 350] and service.get("last_saved_tick") == 350
		and FileAccess.get_file_as_bytes(file_path) == original_bytes,
		"the next session-only automatic checkpoint waits for tick 350 without writing bytes")
	service.get("audio_feedback").set_enabled(false)
	for _tick: int in 2650:
		service.call("_process", 0.1)
	var automatic_count_before_restart := automatic_ticks.size()
	expect(automatic_count_before_restart == 29 and automatic_ticks[-1] == 2950,
		"single-tick frames keep session-only automatic checkpoints on 100-tick boundaries before restart")
	screen.get("result_dialog").hide()
	service.get("restart_button").pressed.emit()
	service.get("start_button").pressed.emit()
	for _tick: int in 100:
		service.call("_process", 0.1)
	expect(automatic_ticks.size() == automatic_count_before_restart + 1 and automatic_ticks[-1] == 100
		and service.get("last_saved_tick") == 100
		and FileAccess.get_file_as_bytes(file_path) == original_bytes,
		"a session-only restart resets the watermark and keeps the corrupt bytes")
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


func _find_label(node: Node, title: String) -> Label:
	for child: Node in node.get_children(true):
		if child is Label and child.text == title:
			return child
		var found := _find_label(child, title)
		if found != null:
			return found
	return null


func _popup_row_height(popup: PopupMenu) -> int:
	var font_size := popup.get_theme_font_size("font_size")
	var text_height := ceili(popup.get_theme_font("font").get_height(font_size))
	var radio_height := maxi(popup.get_theme_icon("radio_checked").get_height(),
		popup.get_theme_icon("radio_unchecked").get_height())
	return maxi(text_height, radio_height) + popup.get_theme_constant("v_separation")


func _operational_popups_match(pickers: Array[OptionButton], font_size: int) -> bool:
	if pickers.is_empty():
		return false
	for picker: OptionButton in pickers:
		var popup := picker.get_popup()
		if popup.get_theme_font_size("font_size") != font_size \
				or popup.get_theme_constant("v_separation") != 32 \
				or _popup_row_height(popup) < 64:
			return false
	return true
