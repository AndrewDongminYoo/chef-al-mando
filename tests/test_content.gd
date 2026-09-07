extends "res://tests/harness.gd"

const FIXTURE := "res://content/m1_first_service.tres"
const EXPECTED_ORDERS: Array[Array] = [
	["order_01", 10, "salad", 410],
	["order_02", 150, "soup", 750],
	["order_03", 290, "grill", 1090],
	["order_04", 430, "salad", 830],
	["order_05", 570, "soup", 1170],
	["order_06", 710, "grill", 1510],
	["order_07", 850, "salad", 1250],
	["order_08", 990, "soup", 1590],
	["order_09", 1130, "grill", 1930],
	["order_10", 1270, "salad", 1670],
	["order_11", 1410, "soup", 2010],
	["order_12", 1550, "grill", 2350],
	["order_13", 1690, "salad", 2090],
	["order_14", 1830, "soup", 2430],
	["order_15", 1970, "grill", 2770],
	["order_16", 2110, "salad", 2510],
	["order_17", 2250, "soup", 2850],
	["order_18", 2390, "grill", 3190],
	["order_19", 2530, "salad", 2930],
	["order_20", 2670, "soup", 3270],
]


func run(_tree: SceneTree) -> void:
	if not ResourceLoader.exists(FIXTURE):
		expect(false, "M1 fixture must load from a Resource")
		return
	var data := fresh()
	expect(data.call("validate").is_empty(), "the approved kitchen must load without content errors")
	expect(data.call("purchased_cost") == 6600, "the starting purchase costs 6600")
	var schedule: Array = data.call("order_schedule")
	expect(schedule.size() == 20, "the fixture must create twenty arrivals")
	for index: int in mini(schedule.size(), EXPECTED_ORDERS.size()):
		var order: Dictionary = schedule[index]
		var actual: Array = [order.id, order.arrival_tick, order.recipe_id, order.deadline_tick]
		expect(actual == EXPECTED_ORDERS[index], "fixture arrival and deadline: " + EXPECTED_ORDERS[index][0])
	var changed_seed := fresh()
	changed_seed.set("seed", 43)
	expect(changed_seed.call("order_schedule")[0].recipe_id == "soup", "seed changes the starting menu")
	_test_invalid_content()
	_test_m1_process_chain()
	_test_arrival_cutoff()


func _test_arrival_cutoff() -> void:
	var data := fresh()
	data.set("first_arrival_tick", 341)
	expect(not data.call("validate").is_empty(), "a final arrival after closing must be rejected")
	data = fresh()
	data.set("first_arrival_tick", 340)
	expect(data.call("validate").is_empty(), "a final arrival on the closing tick must remain valid")
	var sim: RefCounted = load("res://sim/service_sim.gd").new(data)
	for tick: int in range(3000):
		sim.call("step")
	var orders: Array = sim.call("snapshot").orders
	expect(orders.size() == 20 and orders[-1].terminal_reason == "service_closed", "closing records all configured arrivals, including the order arriving on that tick")


func _test_m1_process_chain() -> void:
	var data := fresh()
	for recipe: Resource in data.get("recipes"):
		var processes: Array = recipe.get("processes")
		processes[1].set("id", "chop")
		processes[0].set("next_id", "chop")
	expect(not data.call("validate").is_empty(), "an unsupported process ID must be rejected even when its references match")
	data = fresh()
	for recipe: Resource in data.get("recipes"):
		var processes: Array = recipe.get("processes")
		recipe.set("first_process_id", "cook")
		processes[1].set("next_id", "pickup")
		processes[0].set("next_id", "serve")
	expect(not data.call("validate").is_empty(), "supported process IDs in the wrong chain order must be rejected")
	data = fresh()
	for recipe: Resource in data.get("recipes"):
		var processes: Array = recipe.get("processes")
		processes[0].set("next_id", "serve")
		processes.remove_at(1)
	expect(not data.call("validate").is_empty(), "a complete chain that skips cooking must be rejected")
	data = fresh()
	var recipe: Resource = data.get("recipes")[0]
	var processes: Array = recipe.get("processes")
	processes.reverse()
	expect(data.call("validate").is_empty(), "process references determine chain order independently of the resource array")
	for phase_index: int in range(3):
		data = fresh()
		recipe = data.get("recipes")[0]
		processes = recipe.get("processes")
		processes[phase_index].set("station_role", ["cold", "hot", "storage"][phase_index])
		expect(not data.call("validate").is_empty(), "each M1 phase must use its assigned station role: " + str(phase_index))
	data = fresh()
	recipe = data.get("recipes")[0]
	recipe.set("cook_role", "storage")
	recipe.get("processes")[1].set("station_role", "storage")
	expect(not data.call("validate").is_empty(), "a recipe cannot use storage as its cooking role")


func _test_invalid_content() -> void:
	var data := fresh()
	var items: Array = data.get("ingredients")
	items.append(items[0])
	expect(not data.call("validate").is_empty(), "duplicate ingredient IDs must be rejected")
	data = fresh()
	var recipes: Array = data.get("recipes")
	var requirements: Dictionary[String, int] = recipes[0].get("ingredients")
	requirements["unknown"] = 1
	expect(not data.call("validate").is_empty(), "unknown recipe ingredients must be rejected")
	data = fresh()
	var purchases: Dictionary[String, int] = data.get("purchases")
	purchases["vegetable"] = -1
	expect(not data.call("validate").is_empty(), "negative purchases must be rejected")
	data = fresh()
	recipes = data.get("recipes")
	requirements = recipes[0].get("ingredients")
	requirements["vegetable"] = -1
	expect(not data.call("validate").is_empty(), "negative recipe quantities must be rejected")
	data = fresh()
	recipes = data.get("recipes")
	var processes: Array = recipes[0].get("processes")
	processes[1].set("duration_ticks", 0)
	expect(not data.call("validate").is_empty(), "zero process duration must be rejected")
	data = fresh()
	recipes = data.get("recipes")
	processes = recipes[0].get("processes")
	processes[2].set("next_id", "pickup")
	expect(not data.call("validate").is_empty(), "a process cycle must be rejected")
	data = fresh()
	recipes = data.get("recipes")
	processes = recipes[0].get("processes")
	processes[1].set("next_id", "missing")
	expect(not data.call("validate").is_empty(), "missing process references must be rejected")
	data = fresh()
	recipes = data.get("recipes")
	processes = recipes[0].get("processes")
	processes[1].set("station_role", "missing")
	expect(not data.call("validate").is_empty(), "an unavailable station role must be rejected")
	for invalid_role: String in ["", "unknown_role"]:
		data = fresh()
		var changed_stations: Array = data.get("stations")
		changed_stations[0].set("role", invalid_role)
		recipes = data.get("recipes")
		for recipe: Resource in recipes:
			processes = recipe.get("processes")
			processes[0].set("station_role", invalid_role)
		expect(not data.call("validate").is_empty(), "matching station and process roles must still reject an unsupported role: " + invalid_role)
	data = fresh()
	data.set("menu_ids", PackedStringArray(["missing"]))
	expect(not data.call("validate").is_empty(), "an unknown menu must be rejected")
	data = fresh()
	purchases = data.get("purchases")
	purchases["vegetable"] = 0
	expect(not data.call("validate").is_empty(), "the scenario must be able to sell each configured menu")
	data = fresh()
	var stations: Array = data.get("stations")
	stations[0].set("work_position", Vector2i(0, 0))
	expect(not data.call("validate").is_empty(), "a work position on a wall must be rejected")
	for outside_tile: Vector2i in [Vector2i(-1, 1), Vector2i(12, 1), Vector2i(1, -1), Vector2i(1, 8)]:
		data = fresh()
		data.get("stations")[0].set("tile", outside_tile)
		expect(not data.call("validate").is_empty(), "a station outside the kitchen grid must be rejected: " + str(outside_tile))
	data = fresh()
	var obstacles: Array[Vector2i] = [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 3)]
	data.set("extra_obstacles", obstacles)
	expect(not data.call("validate").is_empty(), "a station unreachable from every employee must be rejected")
	data = fresh()
	var employees: Array = data.get("employees")
	employees[1].set("starting_tile", Vector2i(6, 4))
	obstacles = []
	for y: int in range(1, 7):
		obstacles.append(Vector2i(4, y))
	data.set("extra_obstacles", obstacles)
	expect(not data.call("validate").is_empty(), "stations reached by separate employees must still form a connected kitchen")
	expect(fresh().call("validate").is_empty(), "invalid fixtures must not mutate the saved kitchen")


func fresh() -> Resource:
	return ResourceLoader.load(FIXTURE, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
