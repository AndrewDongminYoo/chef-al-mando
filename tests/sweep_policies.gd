extends SceneTree

## 프렙 수량 전수 스윕. 계획 2a·2b가 세션마다 다시 쓰던 임시 스크립트를 커밋한 것입니다.
## 사용법은 docs/notes/kitchen-pressure-verification.md의 스윕 절에 있습니다.

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const SeedGate := preload("res://tests/fixtures/seed_gate.gd")
const KEEP_KINDS: Array[String] = ["duties", "priorities", "placement", "purchases"]
const WITHOUT_KINDS: Array[String] = ["set_purchase", "set_duty", "move_station", "rotate_station", "priorities"]
const PURCHASE_MODES: Array[String] = ["authored", "draw"]
const GATE_ATTEMPTS: Array[int] = [0, 1, 2, 3, 4, 5]


func _init() -> void:
	var arguments := _arguments()
	if not arguments.has("scenario"):
		push_error("missing --scenario")
		quit(2)
		return
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var scenario: Resource = campaign.scenario_for(arguments.get("scenario", ""))
	if scenario == null:
		push_error("unknown scenario: " + str(arguments.get("scenario", "")))
		quit(2)
		return
	if arguments.has("gate"):
		var verdict: Dictionary = SeedGate.evaluate(campaign, scenario, GATE_ATTEMPTS)
		for row: Dictionary in verdict.rows:
			print("SEED_GATE_ROW ", scenario.id, " ", JSON.stringify(row, "", true))
		print("SEED_GATE_VERDICT ", JSON.stringify({"scenario": scenario.id, "passed": verdict.passed, "failures": verdict.failures}, "", true))
		quit(0)
		return
	var attempt_text: String = arguments.get("attempt", "0")
	if not attempt_text.is_valid_int() or int(attempt_text) < 0:
		push_error("invalid --attempt: " + attempt_text)
		quit(2)
		return
	var attempt: int = int(attempt_text)
	var seed_value: int = ScheduleGenerator.service_seed_for(scenario.id, attempt)
	var items: Array[String] = []
	var caps: Array[int] = []
	if arguments.has("items"):
		for entry: String in arguments["items"].split(","):
			var parts := entry.split(":")
			var ingredient: Resource = scenario.ingredient_for(parts[0])
			if parts.size() != 2 or not parts[1].is_valid_int() or int(parts[1]) < 0 \
				or ingredient == null or not ingredient.is_mise():
				push_error("invalid --items entry: " + entry)
				quit(2)
				return
			items.append(parts[0])
			caps.append(int(parts[1]))
	else:
		for item: Resource in scenario.mise_items():
			items.append(item.id)
			caps.append(scenario.prep_labor_capacity / item.labor_units)
	var keep: PackedStringArray = arguments.get("keep", "duties,priorities,placement,purchases").split(",")
	for token: String in keep:
		if token not in KEEP_KINDS:
			push_error("invalid --keep token: " + token)
			quit(2)
			return
	var purchase_mode: String = arguments.get("purchases", "authored")
	if purchase_mode not in PURCHASE_MODES:
		push_error("invalid --purchases: " + purchase_mode)
		quit(2)
		return
	var without: PackedStringArray = arguments["without"].split(",") if arguments.has("without") else PackedStringArray()
	for token: String in without:
		if token not in WITHOUT_KINDS:
			push_error("invalid --without token: " + token)
			quit(2)
			return
	if purchase_mode == "draw" and "set_purchase" in without:
		push_error("--purchases draw fixes the purchase commands; drop --without set_purchase")
		quit(2)
		return
	var base: Dictionary = {"preparation": [], "priorities": {}}
	var reference: Dictionary = Policies.reference_policy(scenario.id)
	for command: Dictionary in reference.preparation:
		var kind: String = command.kind
		if kind == "set_duty" and "duties" in keep or kind == "set_purchase" and "purchases" in keep \
			or kind in ["move_station", "rotate_station"] and "placement" in keep:
			base.preparation.append(command.duplicate(true))
	if "priorities" in keep:
		base.priorities = reference.priorities.duplicate(true)
	if purchase_mode == "draw":
		var drawn: Array = []
		for command: Dictionary in Policies.draw_aware_policy(scenario, seed_value).preparation:
			if command.kind == "set_purchase":
				drawn.append(command)
		var kept: Array = []
		for command: Dictionary in base.preparation:
			if command.kind != "set_purchase":
				kept.append(command)
		base.preparation = drawn + kept
	base = Policies.without_kinds(base, Array(without))
	var state := {"scenario": scenario, "seed": seed_value, "items": items, "caps": caps, "base": base,
		"combinations": 0, "passed": 0, "best": {}, "best_any": {}}
	var quantities: Array[int] = []
	quantities.resize(items.size())
	quantities.fill(0)
	_sweep(state, quantities, 0)
	print("SWEEP_SUMMARY ", JSON.stringify({"scenario": scenario.id, "attempt": attempt, "seed": seed_value,
		"combinations": state.combinations, "passed": state.passed, "best": state.best,
		"best_any": state.best_any if arguments.has("best") else {},
		"purchases": purchase_mode, "without": without}, "", true))
	quit(0)


func _sweep(state: Dictionary, quantities: Array[int], index: int) -> void:
	var items: Array[String] = state.items
	if index < items.size():
		for quantity: int in state.caps[index] + 1:
			quantities[index] = quantity
			_sweep(state, quantities, index + 1)
		return
	var scenario: Resource = state.scenario
	var policy: Dictionary = {"preparation": state.base.preparation.duplicate(true), "priorities": state.base.priorities.duplicate(true)}
	var labor: int = 0
	for position: int in items.size():
		labor += quantities[position] * scenario.ingredient_for(items[position]).labor_units
		if quantities[position] > 0:
			policy.preparation.append({"kind": "set_prep", "target_id": items[position], "value": quantities[position]})
	if labor > scenario.prep_labor_capacity:
		return
	var run: Dictionary = Policies.run_policy(scenario, policy, 1, state.seed)
	if not run.accepted:
		return
	state.combinations += 1
	var accounting: Dictionary = run.snapshot.accounting
	var row := {"quantities": _named(items, quantities), "labor": labor, "served": accounting.served,
		"profit": accounting.profit, "working": run.snapshot.metrics.orders.working}
	if _better(row, state.best_any):
		state.best_any = row
	if Policies.passes_targets(scenario, run):
		state.passed += 1
		print("SWEEP ", JSON.stringify(row, "", true))
		if _better(row, state.best):
			state.best = row


static func _better(row: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	if row.served != current.served:
		return row.served > current.served
	return row.profit > current.profit


static func _named(items: Array[String], quantities: Array[int]) -> Dictionary:
	var named: Dictionary = {}
	for position: int in items.size():
		if quantities[position] > 0:
			named[items[position]] = quantities[position]
	return named


func _arguments() -> Dictionary:
	var parsed: Dictionary = {}
	var key := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			key = argument.substr(2)
			parsed[key] = "true"
		elif not key.is_empty():
			parsed[key] = argument
			key = ""
	return parsed
