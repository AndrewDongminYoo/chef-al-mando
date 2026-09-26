extends SceneTree

## Times one CampaignStore.save_active_session call by phase (issue #31). Not a CI suite: the numbers
## depend on the machine and its load, so the script prints them and asserts nothing.
## Usage, from the repository root:
##   "$GODOT_BIN" --headless --path . --script tests/profile_save.gd
## Each value is the median of RUNS saves after one warm-up save, with min and max in parentheses.
## The session is captured after TICKS ticks, with every earlier service completed in the records.

const CampaignProgress := preload("res://sim/campaign_progress.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const ServiceSim := preload("res://sim/service_sim.gd")
const RUNS := 20
const TICKS := 200
const SCENARIOS: Array[String] = ["first_shift", "final_service"]
const PHASES: Array[String] = [
	"validate_session",
	"read_primary",
	"read_backup",
	"write_tmp",
	"verify_tmp",
	"write_backup_tmp",
	"verify_backup_tmp",
	"replace_backup",
	"replace_primary",
	"other",
	"total"
]


class ProfiledStore:
	extends "res://persistence/campaign_store.gd"
	var phases: Dictionary = {}

	func _valid_session(active_session: Variant, records: Dictionary) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._valid_session(active_session, records)
		_add("validate_session", started)
		return result

	func _read(target: String) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super._read(target)
		var names := {
			file_path: "read_primary",
			file_path + ".backup": "read_backup",
			file_path + ".tmp": "verify_tmp",
			file_path + ".backup.tmp": "verify_backup_tmp"
		}
		_add(names.get(target, "other"), started)
		return result

	func _write_text(target: String, text: String) -> Error:
		var started := Time.get_ticks_usec()
		var result := super._write_text(target, text)
		_add("write_backup_tmp" if target.ends_with(".backup.tmp") else "write_tmp", started)
		return result

	func _replace_file(source: String, target: String) -> Error:
		var started := Time.get_ticks_usec()
		var result := super._replace_file(source, target)
		_add("replace_backup" if target.ends_with(".backup") else "replace_primary", started)
		return result

	func _add(phase: String, started: int) -> void:
		phases[phase] = phases.get(phase, 0) + Time.get_ticks_usec() - started


func _init() -> void:
	var campaign: Resource = ResourceLoader.load(
		"res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
	)
	var directory := "user://profile_save_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("cannot create " + directory)
		quit(1)
		return
	print(
		"Godot %s, %d runs after one warm-up, session after %d ticks" % [Engine.get_version_info().string, RUNS, TICKS]
	)
	var columns: Dictionary = {}
	var ok := true
	for scenario_id: String in SCENARIOS:
		var records := _records_before(campaign, scenario_id)
		var session := _session(campaign, scenario_id)
		if session.is_empty():
			ok = false
			break
		columns[scenario_id] = _profile(campaign, directory + "/" + scenario_id + ".json", session, records)
		if columns[scenario_id].is_empty():
			ok = false
			break
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
	if not ok:
		quit(1)
		return
	print("| Phase (ms) | %s |" % " | ".join(PackedStringArray(SCENARIOS)))
	print("| --- |%s" % " --- |".repeat(SCENARIOS.size()))
	for phase: String in columns[SCENARIOS[0]]:
		var cells: PackedStringArray = []
		for scenario_id: String in SCENARIOS:
			cells.append(columns[scenario_id][phase])
		print("| %s | %s |" % [phase, " | ".join(cells)])
	quit(0)


func _profile(campaign: Resource, target: String, session: Dictionary, records: Dictionary) -> Dictionary:
	var samples: Dictionary = {}
	for phase: String in PHASES + ["ServiceSession.restore", "campaign.validate"]:
		samples[phase] = []
	# One store for every run, as campaign_screen.gd keeps one store for all autosaves of a session.
	var store := ProfiledStore.new(campaign, target)
	for run: int in range(RUNS + 1):
		store.phases = {}
		var started := Time.get_ticks_usec()
		var result: Dictionary = store.save_active_session(session, records)
		var total := Time.get_ticks_usec() - started
		if not result.accepted:
			push_error("save_active_session failed: " + result.reason)
			return {}
		started = Time.get_ticks_usec()
		var restored := ServiceSession.restore(campaign, session, records)
		var restore_time := Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		var errors: Array[String] = campaign.validate()
		var validate_time := Time.get_ticks_usec() - started
		if not restored.accepted or not errors.is_empty():
			push_error("the profiled session or campaign does not validate")
			return {}
		if run == 0:
			continue
		var measured := 0
		for phase: String in PHASES:
			if phase in ["other", "total"]:
				continue
			measured += store.phases.get(phase, 0)
			samples[phase].append(store.phases.get(phase, 0))
		samples.other.append(total - measured)
		samples.total.append(total)
		samples["ServiceSession.restore"].append(restore_time)
		samples["campaign.validate"].append(validate_time)
	var cells: Dictionary = {}
	for phase: String in samples:
		var values: Array = samples[phase]
		values.sort()
		var middle: int = int(RUNS / 2.0)
		var median: float = (values[middle - 1] + values[middle]) / 2.0
		cells[phase] = "%.2f (%.2f to %.2f)" % [median / 1000.0, values[0] / 1000.0, values[-1] / 1000.0]
	return cells


func _records_before(campaign: Resource, scenario_id: String) -> Dictionary:
	var records: Dictionary = {}
	for scenario: Resource in campaign.scenarios:
		if scenario.id == scenario_id:
			break
		records[scenario.id] = {
			"completed": true, "best_served": scenario.minimum_served, "best_profit": scenario.minimum_profit
		}
	return records


func _session(campaign: Resource, scenario_id: String) -> Dictionary:
	var plan := PreparationPlan.new(campaign.scenario_for(scenario_id))
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	if not started.accepted:
		push_error("the profiled scenario does not start: " + scenario_id)
		return {}
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	for _step: int in range(TICKS):
		simulation.step()
	return ServiceSession.capture(scenario_id, started.selection, simulation, 1, 0)
