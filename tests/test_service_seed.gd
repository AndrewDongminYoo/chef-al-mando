extends "res://tests/harness.gd"

const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const StoreTests := preload("res://tests/test_campaign_store.gd")
const FIXED_FORECAST: Array[String] = ["first_shift", "lunch_prep"]


func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	_test_scenario_fields(campaign)
	_test_session_seed(campaign)
	_test_attempts(campaign)
	_test_store_schema(campaign)
	await _test_campaign_screen(tree)
	await _test_replace_defers_attempts_save(tree)
	await _test_begin_rolls_back_when_save_fails(tree)


func _test_begin_rolls_back_when_save_fails(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var directory := "user://test_service_seed_rollback_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "rollback fixture directory is created")
	var file_path := directory + "/records.json"
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	var failing := StoreTests.FailedStore.new(screen.get("campaign"), file_path)
	failing.failure = "write"
	screen.set("store", failing)
	screen.get("begin_button").pressed.emit()
	expect(screen.get("active_service") == null, "a failed attempts save keeps the player on the campaign screen")
	expect(screen.get("progress").snapshot().attempts == {}, "a failed attempts save rolls the draw back")
	expect(screen.get("save_message_kind") == "storage", "a failed attempts save reports the storage problem")
	expect(not FileAccess.file_exists(file_path), "nothing was written by the failed save")
	failing.failure = ""
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	expect(service != null, "the next start succeeds once storage works")
	if service != null:
		service.set_process(false)
		await tree.process_frame
		expect(service.get("definitions").service_seed == 0, "the retried first start still uses seed 0 because the draw was rolled back")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document is Dictionary and document.attempts == {"first_shift": 1.0}, "the successful start persists the attempt count once")
	screen.queue_free()
	await tree.process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)


func _test_campaign_screen(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var directory := "user://test_service_seed_ui_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "campaign seed fixture directory is created")
	var file_path := directory + "/records.json"
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.get("briefing_label").text.contains("토마토 샐러드 12건"), "zero slack briefing shows an exact count")
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	expect(service.get("definitions").service_seed == 0, "the first start of a service uses seed 0")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.attempts == {"first_shift": 1.0}, "starting a service saves the attempt count immediately")
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	screen.call("_save_checkpoint", "test")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.active_session.service_seed == 0.0, "the checkpoint stores attempt 0's service seed")
	screen.call("return_to_menu")
	await tree.process_frame
	screen.call("select_scenario", "first_shift")
	var attempt_one_seed: int = ScheduleGenerator.service_seed_for("first_shift", 1)
	screen.get("begin_button").pressed.emit()
	expect(screen.get("active_service") == null and screen.get("replace_dialog").visible,
		"attempt 0's open checkpoint requires confirmation before attempt 1 replaces it")
	screen.get("replace_dialog").confirmed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	expect(service.get("definitions").service_seed == attempt_one_seed, "starting again draws attempt 1's pinned seed")
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	screen.call("_save_checkpoint", "test")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.active_session.service_seed == float(attempt_one_seed), "the checkpoint stores attempt 1's service seed")
	expect(document.attempts == {"first_shift": 2.0}, "the deferred attempts save lands once attempt 1's checkpoint is written")
	screen.queue_free()
	await tree.process_frame
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.call("_resume_active_session"), "the saved session resumes")
	service = screen.get("active_service")
	service.set_process(false)
	expect(service.get("definitions").service_seed == attempt_one_seed, "resume restores the stored seed")
	service.get("resume_button").pressed.emit()
	service.call("advance", 299.0)
	expect(screen.get("last_result").passed, "the resumed attempt-1 service closes with a passing result")
	screen.get("retry_service_button").pressed.emit()
	expect(service.get("definitions").service_seed == attempt_one_seed, "retry keeps the same seed")
	screen.queue_free()
	await tree.process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)


func _test_replace_defers_attempts_save(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var directory := "user://test_service_seed_replace_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "replace fixture directory is created")
	var file_path := directory + "/records.json"
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	screen.call("_save_checkpoint", "test")
	var pre_replace_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(pre_replace_document.attempts == {"first_shift": 1.0} and not pre_replace_document.active_session.simulation.closed,
		"an open checkpoint with an unclosed simulation is on disk before any replacement")
	var pre_replace_bytes := FileAccess.get_file_as_bytes(file_path)
	screen.queue_free()
	await tree.process_frame
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.call("select_scenario", "first_shift"), "the same scenario can be reselected")
	expect(not screen.call("begin_service"), "an open checkpoint requires an explicit replacement confirmation")
	expect(screen.get("replace_dialog").visible and screen.get("active_service") == null,
		"the replace dialog opens instead of mounting a new service directly")
	screen.get("replace_dialog").confirmed.emit()
	await tree.process_frame
	service = screen.get("active_service")
	expect(service != null, "confirming replacement mounts a fresh service")
	service.set_process(false)
	expect(service.get("definitions").service_seed == ScheduleGenerator.service_seed_for("first_shift", 1),
		"confirming replacement draws attempt 1's seed even though the checkpoint being replaced held attempt 0")
	var confirmed_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(FileAccess.get_file_as_bytes(file_path) != pre_replace_bytes and confirmed_document.attempts == {"first_shift": 2.0},
		"confirming replacement persists attempt count 2 immediately so a quit before Start cannot redraw the same seed")
	expect(confirmed_document.active_session == pre_replace_document.active_session,
		"confirming replacement keeps the open checkpoint on disk until Start replaces it")
	service.get("start_button").pressed.emit()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.attempts == {"first_shift": 2.0},
		"the replacement's preparation checkpoint keeps attempt count 2")
	expect(document.active_session.service_seed == float(ScheduleGenerator.service_seed_for("first_shift", 1)),
		"the landed checkpoint stores the newly drawn seed")
	screen.queue_free()
	await tree.process_frame
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)


func _boot(tree: SceneTree, scene_path: String, file_path: String) -> Control:
	var scene: PackedScene = load(scene_path)
	var screen: Control = scene.instantiate()
	screen.set("save_path", file_path)
	var settings_path := file_path + ".settings.json"
	var settings := {"locale": "ko", "sound_enabled": false, "text_size": "normal"}
	if not HarnessSettingsStore.new(settings_path).save_settings(settings).accepted:
		return null
	screen.set("settings_path", settings_path)
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(settings_path))
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen


func _test_scenario_fields(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		if scenario.id in FIXED_FORECAST:
			expect(scenario.forecast_slack.is_empty(), "the first two services keep a fixed forecast: " + scenario.id)
		elif not scenario.forecast_slack.is_empty():
			var total: int = 0
			for recipe_id: String in scenario.menu_ids:
				var slack: int = scenario.forecast_slack.get(recipe_id, 0)
				total += slack
				expect(slack >= 0 and slack <= maxi(1, scenario.baseline_counts()[recipe_id] / 5),
					"authored slack stays within a fifth of the baseline: %s %s" % [scenario.id, recipe_id])
			expect(total > 0, "authored slack is not all zeros: " + scenario.id)
			for attempt: int in [1, 2, 3, 4, 5]:
				expect(ScheduleGenerator.recipe_ids(scenario, ScheduleGenerator.service_seed_for(scenario.id, attempt)) != scenario.order_recipe_ids,
					"authored slack moves at least one order on attempt %d: %s" % [attempt, scenario.id])
		expect(scenario.service_seed == 0, "authored service seed is zero: " + scenario.id)
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var counts: Dictionary = hot_queue.baseline_counts()
	expect(counts.get("grill") == 8 and counts.get("soup") == 4 and counts.get("salad") == 8, "baseline counts come from the authored order")
	# hot_queue.tres는 2026-09-22 재조율부터 작성 slack을 가지므로 slack 0 fixture는 복사본에 만듭니다.
	var fixed: Resource = hot_queue.duplicate()
	var no_slack: Dictionary[String, int] = {}
	fixed.forecast_slack = no_slack
	var ranges: Dictionary = fixed.forecast_ranges()
	expect(ranges.grill == {"baseline": 8, "min": 8, "max": 8}, "zero slack collapses the range to the baseline")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	expect(slacked.validate().is_empty(), "slack on menu items validates")
	ranges = slacked.forecast_ranges()
	expect(ranges.grill == {"baseline": 8, "min": 6, "max": 10} and ranges.soup == {"baseline": 4, "min": 3, "max": 5}, "slack widens the range around the baseline")
	var wide: Resource = hot_queue.duplicate()
	var wide_slack: Dictionary[String, int] = {"soup": 9}
	wide.forecast_slack = wide_slack
	expect(wide.forecast_ranges().soup["min"] == 0, "the lower bound never goes below zero")
	var invalid: Resource = hot_queue.duplicate()
	var bad_key: Dictionary[String, int] = {"grain_salad": 1}
	invalid.forecast_slack = bad_key
	expect(not invalid.validate().is_empty(), "slack for a menu outside the service is rejected")
	invalid = hot_queue.duplicate()
	var bad_value: Dictionary[String, int] = {"grill": -1}
	invalid.forecast_slack = bad_value
	expect(not invalid.validate().is_empty(), "negative slack is rejected")
	invalid = hot_queue.duplicate()
	invalid.service_seed = -1
	expect(not invalid.validate().is_empty(), "a negative service seed is rejected")
	var seeded: Resource = hot_queue.with_service_seed(7)
	expect(seeded.service_seed == 7 and hot_queue.service_seed == 0, "with_service_seed returns a seeded copy and leaves the source untouched")
	expect(seeded.id == hot_queue.id and seeded.order_recipe_ids == hot_queue.order_recipe_ids, "the seeded copy keeps the authored content")
	expect(slacked.maximum_profit(20) == fixed.maximum_profit(20) + 2 * _margin(hot_queue, "grill") + _margin(hot_queue, "soup") - 3 * _margin(hot_queue, "salad"), "maximum profit uses the forecast upper bounds")


func _test_session_seed(campaign: Resource) -> void:
	var records: Dictionary = {}
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var unlocked: Dictionary = {}
	for scenario: Resource in campaign.scenarios:
		if scenario.id == "hot_queue":
			break
		unlocked[scenario.id] = {"completed": true, "best_served": scenario.minimum_served, "best_profit": scenario.minimum_profit}
	records = unlocked
	var seeded: Resource = hot_queue.with_service_seed(104076537)
	var plan := PreparationPlan.new(seeded)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(started.accepted, "seeded preparation starts")
	expect(started.definitions.service_seed == 104076537, "the started definition carries the service seed through duplicate()")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	expect(simulation.errors.is_empty(), "seeded simulation builds")
	var session := ServiceSession.capture("hot_queue", started.selection, simulation, 1, 0, 104076537)
	expect(session.size() == 6 and session.service_seed == 104076537, "capture stores the service seed as the sixth field")
	var restored := ServiceSession.restore(campaign, session, records)
	expect(restored.accepted and restored.service_seed == 104076537, "restore returns the service seed")
	expect(restored.definitions.order_schedule()[0].recipe_id == seeded.order_schedule()[0].recipe_id, "restore rebuilds the seeded schedule")
	var legacy := session.duplicate(true)
	legacy.erase("service_seed")
	var legacy_restored := ServiceSession.restore(campaign, legacy, records)
	expect(legacy_restored.accepted and legacy_restored.service_seed == 0, "a five-field session restores with seed 0")
	var forged := session.duplicate(true)
	forged.service_seed = "7"
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a non-integer seed is rejected")
	forged = session.duplicate(true)
	forged.service_seed = -1
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a negative seed is rejected")
	# Array.duplicate(true) does not copy Resource elements, so a deep campaign copy still shares the
	# cached hot_queue; duplicate the scenario itself and swap the copy into a shallow campaign copy.
	var modified: Resource = campaign.duplicate()
	modified.scenarios = campaign.scenarios.duplicate()
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	modified.scenarios[campaign.scenarios.find(hot_queue)] = slacked
	expect(modified.scenario_for("hot_queue") == slacked and campaign.scenario_for("hot_queue") == hot_queue,
		"the slack-bearing copy replaces hot_queue only in the modified campaign")
	var drawn_scenario: Resource = slacked.with_service_seed(104076537)
	var drawn_plan := PreparationPlan.new(drawn_scenario)
	var drawn_started := drawn_plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(drawn_started.accepted, "a slack-bearing seeded preparation starts")
	var drawn_sim := ServiceSim.new(drawn_started.definitions, null, drawn_started.options)
	while not drawn_sim.closed:
		drawn_sim.step()
	var drawn_session := ServiceSession.capture("hot_queue", drawn_started.selection, drawn_sim, 1, 0, 104076537)
	expect(ServiceSession.restore(modified, drawn_session, records).accepted, "a closed session restores under the seed that produced it")
	var wrong_seed := drawn_session.duplicate(true)
	wrong_seed.service_seed = 0
	var rejected := ServiceSession.restore(modified, wrong_seed, records)
	expect(not rejected.accepted and rejected.reason == "invalid_schedule", "the same orders cannot restore under a seed whose draw differs")


func _margin(scenario: Resource, recipe_id: String) -> int:
	var recipe: Resource = scenario.recipe_for(recipe_id)
	var margin: int = recipe.revenue
	for ingredient_id: String in recipe.ingredients:
		margin -= scenario.ingredient_for(ingredient_id).unit_cost * recipe.ingredients[ingredient_id]
	return margin


func _test_attempts(campaign: Resource) -> void:
	var progress := CampaignProgress.new(campaign)
	expect(progress.snapshot().attempts == {}, "a new campaign has no attempts")
	var first := progress.next_service_seed("first_shift")
	expect(first.accepted and first.service_seed == 0 and first.attempt_index == 0, "the first start of a service uses seed 0")
	var second := progress.next_service_seed("first_shift")
	expect(second.accepted and second.service_seed == ScheduleGenerator.service_seed_for("first_shift", 1) and second.attempt_index == 1, "the second start draws attempt 1")
	expect(progress.snapshot().attempts == {"first_shift": 2}, "attempts count the starts")
	expect(not progress.revert_service_seed("first_shift", 0), "only the most recent draw can be reverted")
	expect(progress.revert_service_seed("first_shift", 1) and progress.snapshot().attempts == {"first_shift": 1}, "reverting the last draw restores the previous count")
	expect(progress.revert_service_seed("first_shift", 0) and progress.snapshot().attempts == {}, "reverting the first draw removes the entry")
	expect(progress.next_service_seed("first_shift").service_seed == 0, "the next draw after a full revert is attempt 0 again")
	expect(progress.next_service_seed("first_shift").attempt_index == 1, "the count resumes after the reverted draws")
	expect(not progress.next_service_seed("hot_queue").accepted, "a locked service cannot draw a seed")
	expect(not progress.next_service_seed("missing").accepted, "an unknown service cannot draw a seed")
	expect(CampaignProgress.validate_attempts(campaign, {"first_shift": 2}).is_empty(), "valid attempts pass")
	expect(not CampaignProgress.validate_attempts(campaign, {"missing": 1}).is_empty(), "attempts for an unknown service fail")
	expect(not CampaignProgress.validate_attempts(campaign, {"first_shift": -1}).is_empty(), "negative attempts fail")
	expect(not CampaignProgress.validate_attempts(campaign, {"first_shift": 1.5}).is_empty(), "non-integer attempts fail")
	var restored := CampaignProgress.new(campaign, {}, {"first_shift": 2})
	expect(restored.next_service_seed("first_shift").attempt_index == 2, "restored attempts continue the count")


func _test_store_schema(campaign: Resource) -> void:
	var directory := "user://test_service_seed_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "store fixture directory is created")
	var file_path := directory + "/records.json"
	var store := CampaignStore.new(campaign, file_path)
	expect(store.save_records({}, {"first_shift": 3}).accepted, "attempts save with empty records")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.size() == 6 and int(document.schema_version) == 4 and document.attempts == {"first_shift": 3.0}, "new writes use schema 4 with an attempts key")
	var loaded := CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.attempts == {"first_shift": 3}, "attempts load as integers")
	expect(store.save_records({}).accepted, "saving without attempts keeps the stored attempts")
	expect(CampaignStore.new(campaign, file_path).load_records().attempts == {"first_shift": 3}, "a null attempts argument preserves the primary attempts")
	var legacy := {"schema_version": 3, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null}
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.attempts == {}, "a schema 3 document loads with empty attempts")
	expect(store.save_records({}, {"first_shift": 1}).accepted, "the next save upgrades the document")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(int(document.schema_version) == 4 and document.attempts == {"first_shift": 1.0}, "the upgraded document carries schema 4 and attempts")
	var corrupt := {"schema_version": 4, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null, "attempts": {"missing": 1}}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records", "attempts for an unknown service are rejected as corrupt")
	var missing_attempts := {"schema_version": 4, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(missing_attempts))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records", "a schema 4 document without an attempts key is rejected as corrupt")
	var non_dictionary_attempts := {"schema_version": 4, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null, "attempts": 3}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(non_dictionary_attempts))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records", "a schema 4 document whose attempts is not a Dictionary is rejected as corrupt")
	var session_plan := PreparationPlan.new(campaign.scenario_for("first_shift"))
	var session_started := session_plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	var session_sim := ServiceSim.new(session_started.definitions, null, session_started.options)
	var six_field_session := ServiceSession.capture("first_shift", session_started.selection, session_sim, 1, 0, 0)
	var five_field_session := six_field_session.duplicate(true)
	five_field_session.erase("service_seed")
	var legacy_session_document := {"schema_version": 3, "content_version": 7, "sim_version": 1, "records": {}, "active_session": five_field_session}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_session_document))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.active_session is Dictionary and loaded.active_session.service_seed == 0, "a schema 3 document still restores a five-field session, normalized to seed 0")
	var upgrading_store := CampaignStore.new(campaign, file_path)
	expect(upgrading_store.save_records({}).accepted, "a records save on top of a legacy five-field session succeeds")
	var staged_backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path + ".backup"))
	expect(int(staged_backup.schema_version) == 4 and staged_backup.active_session is Dictionary and staged_backup.active_session.service_seed == 0, "the staged backup re-encodes the legacy session with service_seed 0")
	expect(upgrading_store.clear_active_session().accepted, "clearing a normalized legacy session succeeds")
	expect(CampaignStore.new(campaign, file_path).load_records().active_session == null, "the legacy session is cleared on disk")
	var truncated_session_document := {"schema_version": 4, "content_version": 4, "sim_version": 1, "records": {}, "active_session": five_field_session, "attempts": {}}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(truncated_session_document))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records", "a schema 4 document whose session lacks service_seed is rejected as corrupt")
	var seeded_session_document := {"schema_version": 4, "content_version": 7, "sim_version": 1, "records": {}, "active_session": six_field_session, "attempts": {}}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(seeded_session_document))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.active_session is Dictionary and loaded.active_session.service_seed == 0, "a schema 4 document with a six-field session restores")
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
