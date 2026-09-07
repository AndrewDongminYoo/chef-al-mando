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
	data = fresh()
	var obstacles: Array[Vector2i] = [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 3)]
	data.set("extra_obstacles", obstacles)
	expect(not data.call("validate").is_empty(), "a station unreachable from every employee must be rejected")
	expect(fresh().call("validate").is_empty(), "invalid fixtures must not mutate the saved kitchen")


func fresh() -> Resource:
	return ResourceLoader.load(FIXTURE, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
