extends "res://tests/harness.gd"

const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


class FailedStore extends "res://persistence/campaign_store.gd":
	var failure: String = ""

	func _write_text(target: String, text: String) -> Error:
		if failure == "write" and target == file_path + ".tmp":
			return ERR_CANT_CREATE
		if failure == "invalid_temp" and target == file_path + ".tmp":
			return super._write_text(target, "broken temporary file")
		return super._write_text(target, text)

	func _replace_file(source: String, target: String) -> Error:
		if (failure == "backup" and target == file_path + ".backup") \
			or (failure == "replace" and target == file_path):
			return ERR_CANT_CREATE
		return super._replace_file(source, target)


func run(_tree: SceneTree) -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var directory := "user://test_m4_store_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "M4 store fixture directory is created")
	var file_path := directory + "/campaign_records.json"
	var first: Resource = campaign.scenario_for("first_shift")
	var records := {"first_shift": {"completed": true, "best_served": first.minimum_served,
		"best_profit": first.minimum_profit}}
	var schema_one := {"schema_version": 1, "content_version": 1, "sim_version": 1, "records": records}
	_write(file_path, JSON.stringify(schema_one))
	var original_bytes := FileAccess.get_file_as_bytes(file_path)
	var loaded: Dictionary = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.has("active_session") and loaded.active_session == null,
		"schema 1 loads with no active session")
	expect(FileAccess.get_file_as_bytes(file_path) == original_bytes, "reading schema 1 leaves its bytes unchanged")
	expect(CampaignStore.new(campaign, file_path).save_records(records).accepted,
		"the next successful records write upgrades schema 1")
	var migrated: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(migrated is Dictionary and migrated.size() == 5 and migrated.schema_version == 2
		and migrated.content_version == 1 and migrated.sim_version == 1
		and migrated.has("records") and migrated.has("active_session") and migrated.active_session == null,
		"schema 1 upgrades to the exact schema 2 envelope")
	expect(CampaignStore.new(campaign, file_path).load_records().records == records,
		"schema 1 record metrics remain exact after migration")
	var session := _later_session(campaign, 1)
	var schema_two := {"schema_version": 2, "content_version": 1, "sim_version": 1,
		"records": records, "active_session": session}
	_write(file_path, JSON.stringify(schema_two))
	loaded = CampaignStore.new(campaign, file_path).load_records()
	var restored: Dictionary = ServiceSession.restore(campaign, loaded.get("active_session", {}), loaded.records)
	var expected_restore: Dictionary = ServiceSession.restore(campaign, session, records)
	expect(loaded.accepted and _same_restore(restored, expected_restore),
		"a fresh reader restores an unlocked later service from normalized JSON records")
	var improved := records.duplicate(true)
	improved.first_shift.best_served += 1
	expect(CampaignStore.new(campaign, file_path).save_records(improved).accepted,
		"a records-only write accepts a valid active session")
	loaded = CampaignStore.new(campaign, file_path).load_records()
	restored = ServiceSession.restore(campaign, loaded.get("active_session", {}), loaded.records)
	expected_restore = ServiceSession.restore(campaign, session, improved)
	expect(loaded.accepted and loaded.records == improved, "a records-only write updates only the primary records")
	expect(_same_restore(restored, expected_restore),
		"a records-only write preserves a restorable active session in the primary")
	var backup := CampaignStore.new(campaign, file_path + ".backup").load_records()
	var backup_restore: Dictionary = ServiceSession.restore(campaign, backup.get("active_session", {}), backup.records)
	expected_restore = ServiceSession.restore(campaign, session, records)
	expect(backup.accepted and backup.records == records and _same_restore(backup_restore, expected_restore),
		"a records-only write preserves the previous full envelope in the backup")
	var primary_bytes := FileAccess.get_file_as_bytes(file_path)
	expect(not CampaignStore.new(campaign, file_path).save_records({}).accepted
		and FileAccess.get_file_as_bytes(file_path) == primary_bytes,
		"a records-only write rejects records that would lock the preserved session")
	var session_store := CampaignStore.new(campaign, file_path)
	if not session_store.has_method("save_active_session") or not session_store.has_method("clear_active_session"):
		expect(false, "the campaign store exposes atomic session save and clear operations")
		_cleanup(directory)
		return
	var replacement_session := _later_session(campaign, 2)
	replacement_session.speed = 4
	var baseline_restore := ServiceSession.restore(campaign, session, records)
	var replacement_restore := ServiceSession.restore(campaign, replacement_session, records)
	expect(baseline_restore.accepted and replacement_restore.accepted
		and baseline_restore.simulation.state_hash() != replacement_restore.simulation.state_hash(),
		"baseline and replacement fixtures have different simulation states")
	var save_result: Dictionary = session_store.call("save_active_session", replacement_session, records)
	expect(save_result.accepted, "active session and records save in one operation: " + save_result.reason)
	loaded = CampaignStore.new(campaign, file_path).load_records()
	restored = _restore_loaded(campaign, loaded)
	expected_restore = ServiceSession.restore(campaign, replacement_session, records)
	expect(loaded.accepted and loaded.records == records and _same_restore(restored, expected_restore),
		"a fresh reader sees the atomically saved session and records")
	var clear_result: Dictionary = session_store.call("clear_active_session")
	expect(clear_result.accepted, "the active session can be cleared explicitly: " + clear_result.reason)
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.records == records and loaded.active_session == null,
		"clearing a session preserves valid disk records")
	expect(session_store.call("save_active_session", null, improved).accepted,
		"saving an explicit null session can update records")
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.records == improved and loaded.active_session == null,
		"a fresh reader sees the explicit null session")
	var closed_session := _closed_session(campaign)
	save_result = session_store.call("save_active_session", closed_session, {})
	expect(save_result.accepted, "a closed session is accepted for idempotent result handling: " + save_result.reason)
	loaded = CampaignStore.new(campaign, file_path).load_records()
	restored = _restore_loaded(campaign, loaded)
	expected_restore = ServiceSession.restore(campaign, closed_session, {})
	expect(loaded.accepted and _same_restore(restored, expected_restore) and restored.simulation.closed,
		"a fresh reader restores a closed session")
	_test_write_failures(campaign, directory, records, session, replacement_session)
	_test_recovery(campaign, directory, records, improved, session, replacement_session)
	_test_future_versions(campaign, directory, records, session)
	_cleanup(directory)


func _write(target: String, text: String) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _later_session(campaign: Resource, tick_count: int = 1) -> Dictionary:
	var plan := PreparationPlan.new(campaign.scenario_for("lunch_prep"))
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the later-service store fixture starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	for _step: int in range(tick_count):
		simulation.step()
	return ServiceSession.capture("lunch_prep", started.selection, simulation, 2, 12345)


func _closed_session(campaign: Resource) -> Dictionary:
	var plan := PreparationPlan.new(campaign.scenario_for("first_shift"))
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null,
		"apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the closed-session store fixture starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while not simulation.closed:
		simulation.step()
	return ServiceSession.capture("first_shift", started.selection, simulation, 1, 0)


func _cleanup(directory: String) -> void:
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(directory) == OK, "M4 store fixtures are removed")


func _restore_loaded(campaign: Resource, loaded: Dictionary) -> Dictionary:
	if not loaded.accepted or not loaded.active_session is Dictionary:
		return {"accepted": false}
	return ServiceSession.restore(campaign, loaded.active_session, loaded.records)


func _same_restore(actual: Dictionary, expected: Dictionary) -> bool:
	return actual.get("accepted", false) and expected.get("accepted", false) \
		and actual.scenario_id == expected.scenario_id and actual.speed == expected.speed \
		and actual.accumulator_us == expected.accumulator_us and actual.selection == expected.selection \
		and actual.simulation.state_hash() == expected.simulation.state_hash()


func _test_write_failures(campaign: Resource, directory: String, records: Dictionary,
	baseline_session: Dictionary, replacement_session: Dictionary) -> void:
	var expected_reasons := {"write": "write_failed", "invalid_temp": "verification_failed",
		"backup": "backup_failed", "replace": "replace_failed"}
	for failure: String in expected_reasons:
		var target := directory + "/failure_%s.json" % failure
		expect(CampaignStore.new(campaign, target).save_active_session(baseline_session, records).accepted,
			"the failure fixture writes a valid baseline: " + failure)
		var original_bytes := FileAccess.get_file_as_bytes(target)
		var failing := FailedStore.new(campaign, target)
		failing.failure = failure
		var result: Dictionary = failing.save_active_session(replacement_session, records)
		expect(not result.accepted and result.reason == expected_reasons[failure],
			"the injected file operation reports its failure: " + failure)
		expect(FileAccess.get_file_as_bytes(target) == original_bytes,
			"a failed save preserves the primary bytes: " + failure)
		var loaded := CampaignStore.new(campaign, target).load_records()
		var actual_restore := _restore_loaded(campaign, loaded)
		var expected_restore := ServiceSession.restore(campaign, baseline_session, records)
		expect(loaded.accepted and _same_restore(actual_restore, expected_restore),
			"a fresh reader sees the full pre-failure session: " + failure)
		expect(not FileAccess.file_exists(target + ".tmp") and not FileAccess.file_exists(target + ".backup.tmp"),
			"a failed save removes staged temporary files: " + failure)
		failing.failure = ""
		expect(failing.save_active_session(replacement_session, records).accepted,
			"the failed file operation can be retried: " + failure)
		loaded = CampaignStore.new(campaign, target).load_records()
		actual_restore = _restore_loaded(campaign, loaded)
		expected_restore = ServiceSession.restore(campaign, replacement_session, records)
		expect(loaded.accepted and _same_restore(actual_restore, expected_restore),
			"a fresh reader sees the retried full session: " + failure)


func _test_recovery(campaign: Resource, directory: String, records: Dictionary, improved: Dictionary,
	backup_session: Dictionary, primary_session: Dictionary) -> void:
	var target := directory + "/recovery.json"
	var store := CampaignStore.new(campaign, target)
	expect(store.save_active_session(backup_session, records).accepted,
		"the recovery fixture writes the future backup envelope")
	expect(store.save_active_session(primary_session, improved).accepted,
		"the recovery fixture replaces the primary envelope")
	var backup_bytes := FileAccess.get_file_as_bytes(target + ".backup")
	_write(target, "{broken primary")
	var corrupt_bytes := FileAccess.get_file_as_bytes(target)
	var loaded := CampaignStore.new(campaign, target).load_records()
	expect(not loaded.accepted and loaded.can_recover,
		"a corrupt primary offers explicit recovery without loading its backup")
	for operation: String in ["save_records", "save_active_session", "clear_active_session"]:
		var result := _mutation(CampaignStore.new(campaign, target), operation, primary_session, improved)
		expect(not result.accepted and FileAccess.get_file_as_bytes(target) == corrupt_bytes,
			"ordinary mutation preserves a corrupt primary: " + operation)
	var failed_recovery := FailedStore.new(campaign, target)
	failed_recovery.failure = "replace"
	var recovery_result: Dictionary = failed_recovery.recover_backup()
	expect(not recovery_result.accepted and recovery_result.reason == "replace_failed"
		and FileAccess.get_file_as_bytes(target) == corrupt_bytes
		and FileAccess.get_file_as_bytes(target + ".backup") == backup_bytes,
		"a failed explicit recovery preserves corrupt primary and full backup bytes")
	failed_recovery.failure = ""
	expect(failed_recovery.recover_backup().accepted, "explicit recovery can be retried")
	loaded = CampaignStore.new(campaign, target).load_records()
	var expected_restore := ServiceSession.restore(campaign, backup_session, records)
	expect(loaded.accepted and loaded.records == records
		and _same_restore(_restore_loaded(campaign, loaded), expected_restore),
		"explicit recovery restores the full backup envelope")
	expect(FileAccess.get_file_as_bytes(target + ".backup") == backup_bytes,
		"explicit recovery leaves the backup bytes unchanged")
	expect(DirAccess.remove_absolute(target) == OK, "the missing-primary fixture removes only its primary")
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(not loaded.accepted and loaded.can_recover, "a missing primary with a valid backup requires recovery")
	var missing_result := CampaignStore.new(campaign, target).save_active_session(primary_session, improved)
	expect(not missing_result.accepted and not FileAccess.file_exists(target),
		"ordinary mutation cannot replace a missing primary that has a backup")
	expect(CampaignStore.new(campaign, target).recover_backup().accepted,
		"explicit recovery restores a missing primary")
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(loaded.accepted and _same_restore(_restore_loaded(campaign, loaded), expected_restore),
		"a fresh reader restores the full session after missing-primary recovery")
	_write(target, "{broken primary")
	_write(target + ".backup", "{broken backup")
	var corrupt_backup_bytes := FileAccess.get_file_as_bytes(target + ".backup")
	corrupt_bytes = FileAccess.get_file_as_bytes(target)
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(not loaded.accepted and not loaded.can_recover, "two corrupt files do not offer recovery")
	for operation: String in ["save_records", "save_active_session", "clear_active_session", "recover_backup"]:
		var result := _mutation(CampaignStore.new(campaign, target), operation, primary_session, records)
		expect(not result.accepted and FileAccess.get_file_as_bytes(target) == corrupt_bytes
			and FileAccess.get_file_as_bytes(target + ".backup") == corrupt_backup_bytes,
			"mutation preserves corrupt primary and backup bytes: " + operation)
	expect(DirAccess.remove_absolute(target + ".backup") == OK, "the missing-backup fixture removes only its backup")
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(not loaded.accepted and not loaded.can_recover and not CampaignStore.new(campaign, target).recover_backup().accepted
		and FileAccess.get_file_as_bytes(target) == corrupt_bytes,
		"a corrupt primary with no backup stays preserved and cannot recover")
	expect(DirAccess.remove_absolute(target) == OK, "the new-campaign fixture removes the corrupt primary")
	loaded = CampaignStore.new(campaign, target).load_records()
	expect(loaded.accepted and loaded.reason == "new_campaign" and loaded.active_session == null,
		"missing primary and backup start a new schema 2 campaign view")


func _test_future_versions(campaign: Resource, directory: String, records: Dictionary,
	active_session: Dictionary) -> void:
	var valid_document := {"schema_version": 2, "content_version": 1, "sim_version": 1,
		"records": records, "active_session": active_session}
	var future_document := valid_document.duplicate(true)
	future_document.schema_version = 99
	var target := directory + "/future_primary.json"
	_write(target, JSON.stringify(future_document))
	_write(target + ".backup", JSON.stringify(valid_document))
	_assert_protected_files(campaign, target, active_session, records, "future primary")
	target = directory + "/future_backup.json"
	_write(target, JSON.stringify(valid_document))
	_write(target + ".backup", JSON.stringify(future_document))
	_assert_protected_files(campaign, target, active_session, records, "future backup")


func _assert_protected_files(campaign: Resource, target: String, active_session: Dictionary,
	records: Dictionary, label: String) -> void:
	var primary_bytes := FileAccess.get_file_as_bytes(target)
	var backup_bytes := FileAccess.get_file_as_bytes(target + ".backup")
	for operation: String in ["save_records", "save_active_session", "clear_active_session", "recover_backup"]:
		var result := _mutation(CampaignStore.new(campaign, target), operation, active_session, records)
		expect(not result.accepted and result.reason == "future_version",
			"every mutation rejects an unknown %s: %s" % [label, operation])
		expect(FileAccess.get_file_as_bytes(target) == primary_bytes
			and FileAccess.get_file_as_bytes(target + ".backup") == backup_bytes,
			"every rejected mutation preserves %s bytes: %s" % [label, operation])


func _mutation(store: RefCounted, operation: String, active_session: Dictionary, records: Dictionary) -> Dictionary:
	match operation:
		"save_records":
			return store.call("save_records", records)
		"save_active_session":
			return store.call("save_active_session", active_session, records)
		"clear_active_session":
			return store.call("clear_active_session")
		"recover_backup":
			return store.call("recover_backup")
	return {"accepted": false, "reason": "unknown_test_operation"}
