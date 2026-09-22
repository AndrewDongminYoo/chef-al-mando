extends RefCounted

const CampaignDef := preload("res://content/campaign_def.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const VERSIONS := {"schema_version": 4, "content_version": 7, "sim_version": 1}
const LEGACY_SCHEMA_VERSION := 1
const LEGACY_CONTENT_VERSION := 1
const READABLE_SCHEMA_VERSIONS: Array[int] = [1, 2, 3, 4]

var file_path: String
var _campaign: CampaignDef


func _init(campaign: CampaignDef, target: String = "user://campaign_records.json") -> void:
	_campaign = campaign
	file_path = target


func load_records() -> Dictionary:
	var primary := _read(file_path)
	if primary.accepted:
		return primary
	var backup := _read(file_path + ".backup")
	if primary.reason == "missing" and backup.reason == "missing":
		return {"accepted": true, "reason": "new_campaign", "records": {}, "attempts": {}, "active_session": null, "can_recover": false}
	var protected: bool = primary.reason in ["future_version", "unsupported_version", "read_failed"] or backup.reason in ["future_version", "unsupported_version"]
	var reason: String = primary.reason
	if primary.reason == "missing" and backup.reason in ["future_version", "unsupported_version"]:
		reason = backup.reason
	return {"accepted": false, "reason": reason, "records": {}, "attempts": {}, "can_recover": backup.accepted and not protected}


func save_records(records: Dictionary, attempts: Variant = null) -> Dictionary:
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("invalid_records")
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	if backup.reason in ["future_version", "unsupported_version"]:
		return _failure(backup.reason)
	if not primary.accepted and not (primary.reason == "missing" and backup.reason == "missing"):
		return _failure("recovery_required" if primary.reason == "missing" else primary.reason)
	var active_session: Variant = primary.active_session if primary.accepted else null
	if not _valid_session(active_session, records):
		return _failure("invalid_session")
	var resolved := _resolve_attempts(attempts, primary)
	if not resolved.accepted:
		return _failure("invalid_attempts")
	return _commit(records, active_session, resolved.attempts, primary)


func save_active_session(active_session: Variant, records: Dictionary, attempts: Variant = null) -> Dictionary:
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("invalid_records")
	if not _valid_session(active_session, records):
		return _failure("invalid_session")
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	if backup.reason in ["future_version", "unsupported_version"]:
		return _failure(backup.reason)
	if not primary.accepted and not (primary.reason == "missing" and backup.reason == "missing"):
		return _failure("recovery_required" if primary.reason == "missing" else primary.reason)
	var resolved := _resolve_attempts(attempts, primary)
	if not resolved.accepted:
		return _failure("invalid_attempts")
	return _commit(records, active_session, resolved.attempts, primary)


func _resolve_attempts(attempts: Variant, primary: Dictionary) -> Dictionary:
	if attempts == null:
		return {"accepted": true, "attempts": primary.attempts.duplicate(true) if primary.accepted else {}}
	if not attempts is Dictionary or not CampaignProgress.validate_attempts(_campaign, attempts).is_empty():
		return {"accepted": false, "attempts": {}}
	return {"accepted": true, "attempts": attempts.duplicate(true)}


func clear_active_session() -> Dictionary:
	var loaded := load_records()
	if not loaded.accepted:
		return loaded
	return save_active_session(null, loaded.records, loaded.attempts)


func _commit(records: Dictionary, active_session: Variant, attempts: Dictionary, primary: Dictionary) -> Dictionary:
	var temporary := file_path + ".tmp"
	var result := _prepare_file(temporary, records, active_session, attempts)
	if not result.accepted:
		return result
	if primary.accepted:
		var staged_backup := file_path + ".backup.tmp"
		result = _prepare_file(staged_backup, primary.records, primary.active_session, primary.attempts)
		if result.accepted and _replace_file(staged_backup, file_path + ".backup") != OK:
			result = _failure("backup_failed")
		if not result.accepted:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(staged_backup)
			return result
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "saved", "records": records.duplicate(true), "attempts": attempts.duplicate(true),
		"active_session": active_session.duplicate(true) if active_session is Dictionary else null}


func recover_backup() -> Dictionary:
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	for candidate: Dictionary in [primary, backup]:
		if candidate.reason in ["future_version", "unsupported_version"]:
			return _failure(candidate.reason)
	if primary.accepted:
		return _failure("recovery_not_needed")
	if primary.reason == "read_failed":
		return _failure(primary.reason)
	if not backup.accepted:
		return _failure(backup.reason)
	var temporary := file_path + ".tmp"
	var result := _prepare_file(temporary, backup.records, backup.active_session, backup.attempts)
	if not result.accepted:
		return result
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "recovered", "records": backup.records.duplicate(true), "attempts": backup.attempts.duplicate(true),
		"active_session": backup.active_session.duplicate(true) if backup.active_session is Dictionary else null}


func _prepare_file(target: String, records: Dictionary, active_session: Variant, attempts: Dictionary) -> Dictionary:
	var document := VERSIONS.duplicate()
	document.records = records
	document.active_session = active_session
	document.attempts = attempts
	if _write_text(target, JSON.stringify(document, "\t", true)) != OK:
		DirAccess.remove_absolute(target)
		return _failure("write_failed")
	var verified := _read(target)
	var expected_session: Variant = null
	if active_session is Dictionary:
		expected_session = JSON.parse_string(JSON.stringify(active_session))
	if not verified.accepted or verified.records != records or verified.active_session != expected_session or verified.attempts != attempts:
		DirAccess.remove_absolute(target)
		return _failure("verification_failed")
	return {"accepted": true}


func _read(target: String) -> Dictionary:
	if not FileAccess.file_exists(target):
		return _failure("missing")
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return _failure("read_failed")
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return _failure("read_failed")
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _failure("corrupt_records")
	var document: Dictionary = parser.data
	var content_updated := false
	for key: String in VERSIONS:
		var version: Variant = document.get(key)
		if not _is_integer(version):
			return _failure("corrupt_records")
		if version > VERSIONS[key]:
			return _failure("future_version")
		if key == "schema_version" and int(version) in READABLE_SCHEMA_VERSIONS:
			continue
		if key == "content_version" and int(version) in [LEGACY_CONTENT_VERSION, 2, 3, 4, 5, 6]:
			content_updated = true
			continue
		if version != VERSIONS[key]:
			return _failure("unsupported_version")
	var schema_version := int(document.schema_version)
	var expected_size := 4
	if schema_version in [2, 3]:
		expected_size = 5
	elif schema_version == 4:
		expected_size = 6
	if document.size() != expected_size or not document.get("records") is Dictionary:
		return _failure("corrupt_records")
	var attempts: Dictionary = {}
	if schema_version == 4:
		if not document.get("attempts") is Dictionary:
			return _failure("corrupt_records")
		for key: Variant in document.attempts:
			if not _is_integer(document.attempts[key]):
				return _failure("corrupt_records")
			attempts[key] = int(document.attempts[key])
		if not CampaignProgress.validate_attempts(_campaign, attempts).is_empty():
			return _failure("corrupt_records")
	var records: Dictionary = document.records.duplicate(true)
	for key: Variant in records:
		if not records[key] is Dictionary:
			return _failure("corrupt_records")
		for metric: String in ["best_served", "best_profit"]:
			if not _is_integer(records[key].get(metric)):
				return _failure("corrupt_records")
			records[key][metric] = int(records[key][metric])
		var scenario: CampaignDef.ScenarioDef = null
		if key is String:
			scenario = _campaign.scenario_for(key)
		if content_updated and scenario != null:
			var record: Dictionary = records[key]
			# An earlier content version may have allowed a higher best profit than the current
			# composition can pay (content 7 lowered hot_queue's maximum_profit), so the old best is
			# clamped to the current cap; validate_records keeps its upper bound strict.
			if record.best_served >= 0 and record.best_served <= scenario.order_count:
				record.best_profit = mini(record.best_profit, scenario.maximum_profit(record.best_served))
			# A completion earned under an earlier content version's targets stays completed while it
			# clears the lowest targets any shipped version had; anything lower is corrupt.
			if record.get("completed") == true \
				and (record.best_served < scenario.minimum_served or record.best_profit < scenario.minimum_profit):
				if not CampaignProgress.meets_legacy_completion_targets(key, record):
					return _failure("corrupt_records")
				record.legacy_completed = true
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("corrupt_records")
	var active_session: Variant = null
	if schema_version >= 2:
		active_session = document.get("active_session", "missing")
		if active_session != null:
			if not active_session is Dictionary:
				return _failure("corrupt_records")
			# Five-field sessions are legacy shapes from schema 1-3 writers; a schema 4 writer always
			# records service_seed, so its absence means the session was edited or truncated.
			if schema_version >= 4 and not active_session.has("service_seed"):
				return _failure("corrupt_records")
			if content_updated and _content_update_restarts_session(int(document.content_version), active_session):
				active_session = null
			elif not ServiceSession.restore(_campaign, active_session, records).accepted:
				return _failure("corrupt_records")
			else:
				active_session = active_session.duplicate(true)
				# A schema 1-3 session predates service_seed; normalize it so that every later write
				# (primary, staged backup, recovery) produces a schema 4 session the guard above accepts.
				if not active_session.has("service_seed"):
					active_session["service_seed"] = 0
	return {"accepted": true, "reason": "content_updated" if content_updated else "loaded", "records": records,
		"attempts": attempts, "active_session": active_session, "can_recover": false}


func _content_update_restarts_session(source_content_version: int, _active_session: Dictionary) -> bool:
	# Content 5 keyed prep quantities by mise item, content 6 added missing_mise_ids with mixed
	# consumption, and content 7 authored forecast_slack so a seeded session's schedule no longer
	# matches its snapshot; no earlier session can restore.
	return source_content_version < 7


func _valid_session(active_session: Variant, records: Dictionary) -> bool:
	return active_session == null or (active_session is Dictionary
		and ServiceSession.restore(_campaign, active_session, records).accepted)


func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0


func _write_text(target: String, text: String) -> Error:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	return result


func _replace_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(source, target)


func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "records": {}, "attempts": {}, "active_session": null, "can_recover": false}
