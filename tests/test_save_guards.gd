extends "res://tests/harness.gd"

## Pins the reason code that save_records and save_active_session return for each guard, and for
## pairs of faults whose reason depends on the order in which the guards run.

const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ServiceSim := preload("res://sim/service_sim.gd")

const BAD_ATTEMPTS := {"first_shift": -1}

var _campaign: Resource
var _directory: String
var _records: Dictionary
var _session: Dictionary


func run(_tree: SceneTree) -> void:
	_campaign = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_directory = "user://test_save_guards_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(_directory) == OK, "save guard fixture directory is created")
	var first: Resource = _campaign.scenario_for("first_shift")
	_records = {
		"first_shift": {"completed": true, "best_served": first.minimum_served, "best_profit": first.minimum_profit}
	}
	# lunch_prep is unlocked by the first_shift completion, so the same session is locked under {}.
	_session = _lunch_session()
	expect(
		(
			ServiceSession.restore(_campaign, _session, _records).accepted
			and not ServiceSession.restore(_campaign, _session, {}).accepted
		),
		"the session fixture restores under the records and is locked without them"
	)
	_test_single_guards()
	_test_guard_order()
	_cleanup()


func _test_single_guards() -> void:
	var target := _valid_files("valid")
	_expect_both(target, "invalid_records", {"unknown_service": {}}, _session, null, "unknown records")
	_expect_reason(
		_save_session(target, "not a session", _records),
		"invalid_session",
		"save_active_session rejects a session that is not a dictionary"
	)
	_expect_reason(
		_save_session(target, _session, {}),
		"invalid_session",
		"save_active_session rejects a session that the records lock"
	)
	_expect_reason(
		_save_records(target, {}), "invalid_session", "save_records rejects records that lock the stored session"
	)
	_expect_both(target, "invalid_attempts", _records, _session, BAD_ATTEMPTS, "negative attempts")
	_expect_both(target, "invalid_attempts", _records, _session, "not attempts", "attempts that are not a dictionary")

	target = _valid_files("corrupt_primary")
	_write(target, "{broken primary")
	_expect_both(target, "corrupt_records", _records, _session, null, "corrupt primary with a valid backup")

	target = _valid_files("missing_primary")
	expect(DirAccess.remove_absolute(target) == OK, "the missing-primary fixture removes only its primary")
	_expect_both(target, "recovery_required", _records, _session, null, "missing primary with a valid backup")

	for version: Array in [
		["future", "schema_version", 99, "future_version"], ["unsupported", "sim_version", 0, "unsupported_version"]
	]:
		target = _valid_files("%s_backup" % version[0])
		_write(target + ".backup", JSON.stringify(_document(version[1], version[2])))
		_expect_both(target, version[3], _records, _session, null, "%s backup with a valid primary" % version[0])
		target = _valid_files("%s_primary" % version[0])
		_write(target, JSON.stringify(_document(version[1], version[2])))
		_expect_both(target, version[3], _records, _session, null, "%s primary with a valid backup" % version[0])


func _test_guard_order() -> void:
	var target := _valid_files("order_corrupt_primary")
	_write(target, "{broken primary")
	_expect_both(
		target, "invalid_records", {"unknown_service": {}}, _session, null, "records are checked before the files"
	)
	_expect_reason(
		_save_session(target, _session, {}),
		"invalid_session",
		"save_active_session checks the new session before it reads the files"
	)
	_expect_reason(
		_save_records(target, {}), "corrupt_records", "save_records reads the files before it checks the stored session"
	)
	_expect_both(target, "corrupt_records", _records, _session, BAD_ATTEMPTS, "attempts are checked after the files")

	target = _valid_files("order_future_backup")
	_write(target, "{broken primary")
	_write(target + ".backup", JSON.stringify(_document("schema_version", 99)))
	_expect_both(
		target, "future_version", _records, _session, null, "a protected backup is reported before a corrupt primary"
	)

	target = _valid_files("order_locked_session")
	_expect_reason(
		_save_records(target, {}, BAD_ATTEMPTS),
		"invalid_session",
		"save_records checks the stored session before the attempts"
	)
	_expect_reason(
		_save_session(target, _session, {}, BAD_ATTEMPTS),
		"invalid_session",
		"save_active_session checks the new session before the attempts"
	)


## Asserts one reason for both save functions; every rejected save is also checked to leave the files.
func _expect_both(
	target: String, reason: String, records: Dictionary, session: Variant, attempts: Variant, label: String
) -> void:
	_expect_reason(_save_records(target, records, attempts), reason, "save_records: " + label)
	_expect_reason(_save_session(target, session, records, attempts), reason, "save_active_session: " + label)


func _expect_reason(result: Dictionary, reason: String, label: String) -> void:
	expect(not result.accepted and result.reason == reason, "%s (expected %s, got %s)" % [label, reason, result.reason])


func _save_records(target: String, records: Dictionary, attempts: Variant = null) -> Dictionary:
	var before := _bytes(target)
	return _unchanged(target, before, CampaignStore.new(_campaign, target).save_records(records, attempts))


func _save_session(target: String, session: Variant, records: Dictionary, attempts: Variant = null) -> Dictionary:
	var before := _bytes(target)
	return _unchanged(
		target, before, CampaignStore.new(_campaign, target).save_active_session(session, records, attempts)
	)


func _unchanged(target: String, before: Array, result: Dictionary) -> Dictionary:
	if not result.accepted:
		expect(
			_bytes(target) == before,
			"a rejected save (%s) leaves the primary and backup bytes unchanged: %s" % [result.reason, target]
		)
	return result


func _bytes(target: String) -> Array:
	var files: Array = []
	for path: String in [target, target + ".backup"]:
		files.append(FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null)
	return files


## Writes a valid primary that holds the session and a valid backup through the store itself.
func _valid_files(name: String) -> String:
	var target := _directory + "/%s.json" % name
	var store := CampaignStore.new(_campaign, target)
	expect(
		store.save_active_session(null, _records).accepted and store.save_active_session(_session, _records).accepted,
		"the %s fixture writes a primary and a backup" % name
	)
	return target


func _document(key: String, value: int) -> Dictionary:
	var document := CampaignStore.VERSIONS.duplicate()
	document.records = _records
	document.active_session = null
	document.attempts = {}
	document[key] = value
	return document


func _write(target: String, text: String) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _lunch_session() -> Dictionary:
	var plan := PreparationPlan.new(_campaign.scenario_for("lunch_prep"))
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(started.accepted, "the save guard session fixture starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	simulation.step()
	return ServiceSession.capture("lunch_prep", started.selection, simulation, 1, 0)


func _cleanup() -> void:
	for owned_file: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(_directory) == OK, "save guard fixtures are removed")
