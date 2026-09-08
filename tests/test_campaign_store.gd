extends "res://tests/harness.gd"

const CampaignStore := preload("res://persistence/campaign_store.gd")


class FailedStore extends "res://persistence/campaign_store.gd":
	var failure: String = ""

	func _write_text(target: String, text: String) -> Error:
		if failure == "write":
			return ERR_CANT_CREATE
		if failure == "invalid_temp" and target == file_path + ".tmp":
			return super._write_text(target, "broken temporary file")
		return super._write_text(target, text)

	func _replace_file(source: String, target: String) -> Error:
		if (failure == "backup" and target == file_path + ".backup") or (failure == "replace" and target == file_path):
			return ERR_CANT_CREATE
		return super._replace_file(source, target)


func run(_tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var directory := "user://test_campaign_store_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "record fixture directory is created")
	var file_path := directory + "/records.json"
	var scenario: Resource = campaign.scenarios[0]
	var records: Dictionary = {scenario.id: {"completed": true, "best_served": scenario.minimum_served, "best_profit": scenario.minimum_profit}}
	var improved: Dictionary = records.duplicate(true)
	improved[scenario.id].best_served += 1
	var store := CampaignStore.new(campaign, file_path)
	var loaded := store.load_records()
	expect(loaded.accepted and loaded.records.is_empty() and loaded.reason == "new_campaign", "missing primary and backup start a new campaign")
	expect(store.save_records(records).accepted, "valid records save to disk")
	var reopened := CampaignStore.new(campaign, file_path)
	expect(reopened.load_records().records == records, "a new store reads the saved bytes")
	expect(store.save_records(improved).accepted, "an improved record replaces the primary")
	var backup_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path + ".backup"))
	expect(int(backup_document.records[scenario.id].best_served) == scenario.minimum_served, "backup contains the previous valid record")
	expect(CampaignStore.new(campaign, file_path).load_records().records == improved, "new primary contains the improved record")
	var primary_bytes := FileAccess.get_file_as_bytes(file_path)
	var backup_bytes := FileAccess.get_file_as_bytes(file_path + ".backup")
	for failure: String in ["write", "invalid_temp", "backup", "replace"]:
		var failing := FailedStore.new(campaign, file_path)
		failing.failure = failure
		expect(not failing.save_records(records).accepted, "injected save failure is reported: " + failure)
		expect(FileAccess.get_file_as_bytes(file_path) == primary_bytes, "failed save preserves the primary bytes: " + failure)
		expect(CampaignStore.new(campaign, file_path).load_records().records == improved, "failed save remains readable from a new store: " + failure)
		failing.failure = ""
		if failure == "replace":
			expect(failing.save_records(improved).accepted, "a failed primary replacement can be retried")
	var valid_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	var future := valid_document.duplicate(true)
	future.schema_version = 99
	_write(file_path, JSON.stringify(future))
	var future_bytes := FileAccess.get_file_as_bytes(file_path)
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "future_version" and not loaded.can_recover, "future primary versions block recovery")
	expect(not store.save_records(records).accepted and not store.recover_backup().accepted, "save and backup recovery cannot overwrite future data")
	expect(FileAccess.get_file_as_bytes(file_path) == future_bytes, "future primary bytes remain unchanged")
	_write(file_path, JSON.stringify(valid_document))
	_write(file_path + ".backup", JSON.stringify(future))
	future_bytes = FileAccess.get_file_as_bytes(file_path + ".backup")
	expect(not store.save_records(records).accepted, "saving cannot overwrite an unknown future backup")
	expect(FileAccess.get_file_as_bytes(file_path + ".backup") == future_bytes, "future backup bytes remain unchanged")
	_write_bytes(file_path + ".backup", backup_bytes)
	_write(file_path, "{broken")
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.can_recover and loaded.records.is_empty(), "corruption offers recovery without silently loading the backup")
	expect(not store.save_records(records).accepted, "ordinary saves cannot silently replace corrupt data")
	var failed_recovery := FailedStore.new(campaign, file_path)
	failed_recovery.failure = "replace"
	expect(not failed_recovery.recover_backup().accepted and FileAccess.get_file_as_string(file_path) == "{broken", "failed explicit recovery preserves the corrupt primary")
	expect(store.recover_backup().accepted, "explicit recovery restores a valid backup")
	expect(CampaignStore.new(campaign, file_path).load_records().records == records, "a new store reads the explicitly recovered record")
	expect(FileAccess.get_file_as_bytes(file_path + ".backup") == backup_bytes, "recovery preserves the valid backup")
	DirAccess.remove_absolute(file_path)
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.can_recover, "missing primary with a backup requires explicit recovery")
	expect(store.recover_backup().accepted, "a missing primary can be recovered")
	for invalid_kind: String in ["unknown_id", "fraction", "wrong_bool", "skipped", "extra_field", "served_limit", "profit_limit", "profit_served"]:
		var invalid := valid_document.duplicate(true)
		match invalid_kind:
			"unknown_id":
				invalid.records = {"unknown": records[scenario.id]}
			"fraction":
				invalid.records[scenario.id].best_served = 1.5
			"wrong_bool":
				invalid.records[scenario.id].completed = "true"
			"skipped":
				var second: Resource = campaign.scenarios[1]
				invalid.records = {second.id: {"completed": true, "best_served": second.minimum_served, "best_profit": second.minimum_profit}}
			"extra_field":
				invalid.records[scenario.id].unlocked = 8
			"profit_limit":
				invalid.records[scenario.id].best_profit = 4000
			"profit_served":
				invalid.records[scenario.id] = {"completed": false, "best_served": 1, "best_profit": 1000}
			"served_limit":
				invalid.records[scenario.id].best_served = 999
		_write(file_path, JSON.stringify(invalid))
		loaded = CampaignStore.new(campaign, file_path).load_records()
		expect(not loaded.accepted, "invalid record data is rejected: " + invalid_kind)
		var original := FileAccess.get_file_as_bytes(file_path)
		expect(not store.save_records(records).accepted and FileAccess.get_file_as_bytes(file_path) == original, "invalid records are not silently reset: " + invalid_kind)
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(directory) == OK, "record fixtures are removed")


func _write(file_path: String, text: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_bytes(file_path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
