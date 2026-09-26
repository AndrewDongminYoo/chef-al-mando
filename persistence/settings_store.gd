extends "res://persistence/file_store.gd"

const DEFAULTS := {"locale": "ko", "sound_enabled": true, "text_size": "normal"}
const SCHEMA_VERSION := 1

var file_path: String


func _init(target: String = "user://settings.json") -> void:
	file_path = target


func load_settings() -> Dictionary:
	var loaded := _read(file_path)
	if loaded.reason == "missing":
		return {"accepted": true, "reason": "defaults", "values": DEFAULTS.duplicate()}
	return loaded


func save_settings(values: Dictionary) -> Dictionary:
	if not _valid_values(values):
		return _failure("invalid_settings")
	var existing := _read(file_path)
	if existing.reason not in ["missing", "corrupt_settings"] and not existing.accepted:
		return _failure(existing.reason)
	var temporary := file_path + ".tmp"
	var document := {
		"schema_version": SCHEMA_VERSION,
		"locale": values.locale,
		"sound_enabled": values.sound_enabled,
		"text_size": values.text_size
	}
	if _write_text(temporary, JSON.stringify(document, "\t", true)) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("write_failed")
	var verified := _read(temporary)
	if not verified.accepted or verified.values != values:
		DirAccess.remove_absolute(temporary)
		return _failure("verification_failed")
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "saved", "values": values.duplicate()}


func _read(target: String) -> Dictionary:
	var raw := _read_text(target)
	if not raw.reason.is_empty():
		return _failure(raw.reason)
	var parser := JSON.new()
	if parser.parse(raw.text) != OK or not parser.data is Dictionary:
		return _failure("corrupt_settings")
	var document: Dictionary = parser.data
	if not _is_integer(document.get("schema_version")):
		return _failure("corrupt_settings")
	var version := int(document.schema_version)
	if version > SCHEMA_VERSION:
		return _failure("future_version")
	# No app version ever wrote a schema below 1, so such a file is corrupt, not protected.
	if version != SCHEMA_VERSION or document.size() != 4:
		return _failure("corrupt_settings")
	var values := {
		"locale": document.get("locale"),
		"sound_enabled": document.get("sound_enabled"),
		"text_size": document.get("text_size")
	}
	if not _valid_values(values):
		return _failure("corrupt_settings")
	return {"accepted": true, "reason": "loaded", "values": values}


func _valid_values(values: Variant) -> bool:
	if not values is Dictionary or values.size() != DEFAULTS.size():
		return false
	var locale: Variant = values.get("locale")
	var sound_enabled: Variant = values.get("sound_enabled")
	var text_size: Variant = values.get("text_size")
	return (
		locale is String
		and locale in ["ko", "en"]
		and sound_enabled is bool
		and text_size is String
		and text_size in ["normal", "large"]
	)


func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "values": {}}
