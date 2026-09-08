extends RefCounted

const CampaignDef := preload("res://content/campaign_def.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const VERSIONS := {"schema_version": 1, "content_version": 1, "sim_version": 1}

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
		return {"accepted": true, "reason": "new_campaign", "records": {}, "can_recover": false}
	var protected: bool = primary.reason in ["future_version", "unsupported_version", "read_failed"] or backup.reason in ["future_version", "unsupported_version"]
	var reason: String = primary.reason
	if primary.reason == "missing" and backup.reason in ["future_version", "unsupported_version"]:
		reason = backup.reason
	return {"accepted": false, "reason": reason, "records": {}, "can_recover": backup.accepted and not protected}


func save_records(records: Dictionary) -> Dictionary:
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("invalid_records")
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	if backup.reason in ["future_version", "unsupported_version"]:
		return _failure(backup.reason)
	if not primary.accepted and not (primary.reason == "missing" and backup.reason == "missing"):
		return _failure("recovery_required" if primary.reason == "missing" else primary.reason)
	var temporary := file_path + ".tmp"
	var result := _prepare_file(temporary, records)
	if not result.accepted:
		return result
	if primary.accepted:
		var staged_backup := file_path + ".backup.tmp"
		result = _prepare_file(staged_backup, primary.records)
		if result.accepted and _replace_file(staged_backup, file_path + ".backup") != OK:
			result = _failure("backup_failed")
		if not result.accepted:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(staged_backup)
			return result
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "saved", "records": records.duplicate(true)}


func recover_backup() -> Dictionary:
	var primary := _read(file_path)
	if primary.accepted:
		return _failure("recovery_not_needed")
	if primary.reason in ["future_version", "unsupported_version", "read_failed"]:
		return _failure(primary.reason)
	var backup := _read(file_path + ".backup")
	if not backup.accepted:
		return _failure(backup.reason)
	var temporary := file_path + ".tmp"
	var result := _prepare_file(temporary, backup.records)
	if not result.accepted:
		return result
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "recovered", "records": backup.records.duplicate(true)}


func _prepare_file(target: String, records: Dictionary) -> Dictionary:
	var document := VERSIONS.duplicate()
	document.records = records
	if _write_text(target, JSON.stringify(document, "\t", true)) != OK:
		DirAccess.remove_absolute(target)
		return _failure("write_failed")
	var verified := _read(target)
	if not verified.accepted or verified.records != records:
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
	for key: String in VERSIONS:
		var version: Variant = document.get(key)
		if not _is_integer(version):
			return _failure("corrupt_records")
		if version > VERSIONS[key]:
			return _failure("future_version")
		if version != VERSIONS[key]:
			return _failure("unsupported_version")
	if document.size() != 4 or not document.get("records") is Dictionary:
		return _failure("corrupt_records")
	var records: Dictionary = document.records.duplicate(true)
	for key: Variant in records:
		if not records[key] is Dictionary:
			return _failure("corrupt_records")
		for metric: String in ["best_served", "best_profit"]:
			if not _is_integer(records[key].get(metric)):
				return _failure("corrupt_records")
			records[key][metric] = int(records[key][metric])
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("corrupt_records")
	return {"accepted": true, "reason": "loaded", "records": records, "can_recover": false}


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
	return {"accepted": false, "reason": reason, "records": {}, "can_recover": false}
