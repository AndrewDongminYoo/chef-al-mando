extends SceneTree

const AppPreferences := preload("res://presentation/app_preferences.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


class ReplaceBoundaryStore extends CampaignStore:
	var marker_path: String = ""

	func _replace_file(source: String, target: String) -> Error:
		if source == file_path + ".tmp" and target == file_path:
			var marker := FileAccess.open(marker_path, FileAccess.WRITE)
			if marker != null:
				marker.store_string(JSON.stringify({"kind": "replace_boundary"}))
				marker.flush()
				marker.close()
			while true:
				OS.delay_msec(20)
		return super._replace_file(source, target)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := _arguments()
	for required: String in ["mode", "save", "settings", "status", "marker"]:
		if not arguments.has(required) or not arguments[required] is String or arguments[required].is_empty():
			_fail("missing required argument: " + required)
			return
	match arguments.mode:
		"writer":
			_writer(arguments)
		"reader":
			_reader(arguments)
		"interrupt_writer":
			_interrupt_writer(arguments)
		"interrupt_reader":
			_interrupt_reader(arguments)
		_:
			_fail("unknown mode: " + arguments.mode)


func _writer(arguments: Dictionary) -> void:
	var fixture := _fixture()
	if not fixture.accepted:
		_fail(fixture.reason)
		return
	var preferences := AppPreferences.new(arguments.settings)
	var saved_settings := preferences.update_settings({"locale": "en", "sound_enabled": false, "text_size": "large"})
	if not saved_settings.accepted or preferences.snapshot() != {"locale": "en", "sound_enabled": false, "text_size": "large"} \
		or TranslationServer.get_locale() != "en":
		_fail("writer settings fixture did not save and apply English preferences")
		return
	var partial_session := ServiceSession.capture("first_shift", fixture.selection, fixture.partial, 4, 43210)
	var working_session := ServiceSession.capture("first_shift", fixture.selection, fixture.working, 2, 12345)
	var store := CampaignStore.new(fixture.campaign, arguments.save)
	var saved_partial := store.save_active_session(partial_session, {})
	var working_store := CampaignStore.new(fixture.campaign, str(arguments.save) + ".working")
	var saved_working := working_store.save_active_session(working_session, {})
	if not saved_partial.accepted or not saved_working.accepted:
		_fail("writer did not save both real simulation fixtures")
		return
	var restored_partial := ServiceSession.restore(fixture.campaign, store.load_records().active_session, {})
	var restored_working := ServiceSession.restore(fixture.campaign, working_store.load_records().active_session, {})
	var partial_hash: String = fixture.partial.state_hash()
	var working_hash: String = fixture.working.state_hash()
	if not restored_partial.accepted or not restored_working.accepted \
		or restored_partial.simulation.state_hash() != partial_hash or restored_working.simulation.state_hash() != working_hash:
		_fail("writer could not read back both saved simulation fixtures")
		return
	var partial_tick: int = fixture.partial.tick
	var working_tick: int = fixture.working.tick
	var immediate_hash: String = partial_hash
	var final_hash := _finish_hash(fixture.partial)
	var working_final_hash := _finish_hash(fixture.working)
	if final_hash.is_empty():
		_fail("writer fixture did not close after partial movement")
		return
	var status := {"immediate_hash": immediate_hash, "final_hash": final_hash,
		"working_hash": working_hash, "working_final_hash": working_final_hash,
		"partial_movement": fixture.partial_movement, "active_work": fixture.active_work}
	if not _write_json(arguments.status, status) or not _write_json(arguments.marker,
		{"kind": "writer_ready", "partial_movement": fixture.partial_movement, "active_work": fixture.active_work,
			"partial_tick": partial_tick, "working_tick": working_tick,
			"partial_hash": partial_hash, "working_hash": working_hash,
			"saved_partial_hash": restored_partial.simulation.state_hash(), "saved_working_hash": restored_working.simulation.state_hash()}):
		_fail("writer could not write its completion evidence")
		return
	print("M4 writer reached its saved partial checkpoint")
	while true:
		OS.delay_msec(20)


func _reader(arguments: Dictionary) -> void:
	var expected := _read_json(arguments.status)
	var campaign := _campaign()
	var preferences := AppPreferences.new(arguments.settings)
	var loaded_settings := preferences.load_settings()
	if expected.is_empty() or campaign == null or not loaded_settings.accepted \
		or preferences.snapshot() != {"locale": "en", "sound_enabled": false, "text_size": "large"} \
		or TranslationServer.get_locale() != "en":
		_fail("fresh reader did not load the independent English settings fixture")
		return
	var loaded := CampaignStore.new(campaign, arguments.save).load_records()
	var working_loaded := CampaignStore.new(campaign, str(arguments.save) + ".working").load_records()
	if not loaded.accepted or not working_loaded.accepted or not loaded.active_session is Dictionary \
		or not working_loaded.active_session is Dictionary:
		_fail("fresh reader did not load the saved campaign session")
		return
	var restored := ServiceSession.restore(campaign, loaded.active_session, loaded.records)
	var restored_working := ServiceSession.restore(campaign, working_loaded.active_session, working_loaded.records)
	if not restored.accepted or not restored_working.accepted or restored.simulation.state_hash() != expected.immediate_hash \
		or restored_working.simulation.state_hash() != expected.working_hash:
		_fail("fresh reader hash differs immediately after restoration")
		return
	var final_hash := _finish_hash(restored.simulation)
	var working_final_hash := _finish_hash(restored_working.simulation)
	if final_hash != expected.final_hash or working_final_hash != expected.working_final_hash:
		_fail("fresh reader hash differs after the restored service closes")
		return
	print("PASS: fresh M4 reader preserves checkpoint and final hash")
	TranslationServer.set_locale("ko")
	quit(0)


func _interrupt_writer(arguments: Dictionary) -> void:
	var fixture := _fixture()
	if not fixture.accepted:
		_fail(fixture.reason)
		return
	var baseline := ServiceSim.new(fixture.definitions, null, fixture.options)
	var baseline_session := ServiceSession.capture("first_shift", fixture.selection, baseline, 1, 0)
	var initial := CampaignStore.new(fixture.campaign, arguments.save)
	if not initial.save_active_session(baseline_session, {}).accepted:
		_fail("interruption fixture could not write its valid primary")
		return
	var replacement := ServiceSession.capture("first_shift", fixture.selection, fixture.partial, 2, 0)
	if not _write_json(arguments.status, {"baseline_hash": baseline.state_hash()}):
		_fail("interruption fixture could not write its expected primary hash")
		return
	var interrupted := ReplaceBoundaryStore.new(fixture.campaign, arguments.save)
	interrupted.marker_path = arguments.marker
	var ignored := interrupted.save_active_session(replacement, {})
	_fail("interruption writer returned after the primary replacement boundary: " + str(ignored))


func _interrupt_reader(arguments: Dictionary) -> void:
	var expected := _read_json(arguments.status)
	var campaign := _campaign()
	if expected.is_empty() or campaign == null:
		_fail("interruption reader is missing its expected recovery fixture")
		return
	var primary := CampaignStore.new(campaign, arguments.save).load_records()
	var backup := CampaignStore.new(campaign, arguments.save + ".backup").load_records()
	if not primary.accepted or not backup.accepted or not primary.active_session is Dictionary \
		or not backup.active_session is Dictionary:
		_fail("interrupted primary or backup is not independently valid")
		return
	var primary_restored := ServiceSession.restore(campaign, primary.active_session, primary.records)
	var backup_restored := ServiceSession.restore(campaign, backup.active_session, backup.records)
	if not primary_restored.accepted or not backup_restored.accepted \
		or primary_restored.simulation.state_hash() != expected.baseline_hash \
		or backup_restored.simulation.state_hash() != expected.baseline_hash:
		_fail("interrupted save changed the recoverable primary or backup session")
		return
	var incomplete: String = str(arguments.save) + ".incomplete"
	if not _copy_file(arguments.save + ".backup", incomplete + ".backup") \
		or not _write_text(incomplete + ".tmp", "{incomplete temporary file"):
		_fail("incomplete temporary-file fixture could not be created")
		return
	var blocked := CampaignStore.new(campaign, incomplete).load_records()
	if blocked.accepted or not blocked.can_recover:
		_fail("an incomplete temporary file was adopted as a saved campaign")
		return
	var recovered := CampaignStore.new(campaign, incomplete).recover_backup()
	var restored_recovery := CampaignStore.new(campaign, incomplete).load_records()
	if not recovered.accepted or not restored_recovery.accepted or not restored_recovery.active_session is Dictionary:
		_fail("backup recovery could not replace an incomplete temporary-file fixture")
		return
	var recovered_session := ServiceSession.restore(campaign, restored_recovery.active_session, restored_recovery.records)
	if not recovered_session.accepted or recovered_session.simulation.state_hash() != expected.baseline_hash:
		_fail("backup recovery did not restore the original valid session")
		return
	print("PASS: interrupted save keeps only valid primary or backup recovery")
	quit(0)


func _fixture() -> Dictionary:
	var campaign := _campaign()
	if campaign == null:
		return {"accepted": false, "reason": "campaign fixture is invalid"}
	var scenario = campaign.scenario_for("first_shift")
	var plan := PreparationPlan.new(scenario)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	if not started.accepted:
		return {"accepted": false, "reason": "first-shift preparation did not start"}
	var partial := ServiceSim.new(started.definitions, null, started.options)
	var partial_movement := false
	while partial.tick < 300:
		partial.step()
		var view: Dictionary = partial.snapshot()
		if not view.tasks.is_empty() and view.employees[0].progress in [1, 2, 3, 4]:
			partial_movement = true
			break
	var active := ServiceSim.new(started.definitions, null, started.options)
	var active_work := false
	while active.tick < 300:
		active.step()
		var view: Dictionary = active.snapshot()
		if not view.orders.is_empty() and view.orders[0].state == "working":
			active_work = true
			break
	if not partial_movement or not active_work:
		return {"accepted": false, "reason": "real first-shift fixture lacks partial movement or active work"}
	return {"accepted": true, "campaign": campaign, "selection": started.selection,
		"definitions": started.definitions, "options": started.options, "partial": partial, "working": active,
		"partial_movement": partial_movement, "active_work": active_work}


func _campaign() -> Resource:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	if campaign == null or not campaign.validate().is_empty():
		return null
	return campaign


func _finish_hash(simulation: ServiceSim) -> String:
	while not simulation.closed:
		simulation.step()
	return simulation.state_hash() if simulation.closed else ""


func _arguments() -> Dictionary:
	var values: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var pair := argument.substr(2).split("=", false, 1)
		if pair.size() == 2:
			values[pair[0]] = pair[1]
	return values


func _write_json(target: String, value: Dictionary) -> bool:
	return _write_text(target, JSON.stringify(value))


func _write_text(target: String, text: String) -> bool:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	return result == OK


func _read_json(target: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	return parsed if parsed is Dictionary else {}


func _copy_file(source: String, target: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false
	var bytes := input.get_buffer(input.get_length())
	input.close()
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return false
	output.store_buffer(bytes)
	output.flush()
	var result := output.get_error()
	output.close()
	return result == OK


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	TranslationServer.set_locale("ko")
	quit(1)
