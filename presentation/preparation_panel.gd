extends VBoxContainer

signal command_requested(kind: String, target_id: String, value: Variant)
signal station_selected(station_id: String)

const Definitions := preload("res://content/definitions.gd")
const DUTIES: Array[String] = ["all", "cold", "hot", "off"]
const DUTY_NAMES: Array[String] = ["전체 담당", "냉식 담당", "온식 담당", "담당 해제"]
const REASONS := {"insufficient_budget": "예산이 부족합니다 · 고정 인건비도 남겨 두세요",
	"insufficient_labor": "준비 노동량이 부족합니다 · 다른 프렙을 줄여 보세요",
	"missing_ingredients": "원재료가 부족합니다 · 발주를 늘리거나 프렙을 줄이세요",
	"menu_missing_ingredients": "만들 수 없는 메뉴가 있습니다 · 원재료나 프렙을 확보하세요",
	"outside_kitchen": "벽이나 주방 밖에는 놓을 수 없습니다", "station_overlap": "다른 설비나 장애물과 겹칩니다",
	"invalid_work_position": "작업 위치는 설비 옆 한 칸이어야 합니다", "blocked_work_position": "작업 위치가 막힙니다",
	"employee_start_blocked": "직원 시작 위치를 막을 수 없습니다", "no_route": "설비 사이의 이동 경로가 막힙니다",
	"work_position_overlap": "다른 설비의 작업 위치와 겹칩니다",
	"fixed_station": "고정 설비는 위치와 작업 방향을 바꿀 수 없습니다",
	"cold_hot_adjacent": "냉식대와 화구 사이에 한 칸 이상 띄우세요",
	"service_started": "영업 중에는 준비를 바꿀 수 없습니다"}

var definitions: Definitions
var current: Dictionary = {}
var tabs: Array[Button] = []
var pages: Array[ScrollContainer] = []
var purchase_labels: Dictionary[String, Label] = {}
var purchase_plus: Dictionary[String, Button] = {}
var purchase_minus: Dictionary[String, Button] = {}
var prep_labels: Dictionary[String, Label] = {}
var prep_plus: Dictionary[String, Button] = {}
var prep_minus: Dictionary[String, Button] = {}
var priority_labels: Dictionary[String, Label] = {}
var priority_plus: Dictionary[String, Button] = {}
var priority_minus: Dictionary[String, Button] = {}
var move_buttons: Dictionary[String, Button] = {}
var employee_labels: Dictionary[String, Label] = {}
var duty_buttons: Dictionary[String, OptionButton] = {}
var station_picker: OptionButton
var station_label: Label
var placement_preview: Label
var summary: Label
var reset_button: Button
var selected_station_id: String = ""
var stock_heading: Label
var prep_heading: Label
var priority_heading: Label


func setup(data: Definitions) -> void:
	definitions = data
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_row := HBoxContainer.new()
	add_child(tab_row)
	for index: int in 3:
		var tab := _button(["발주·프렙", "배치·담당", "요약"][index])
		tab.pressed.connect(show_tab.bind(index))
		tab_row.add_child(tab)
		tabs.append(tab)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		pages.append(scroll)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		scroll.add_child(column)
	_build_stock(pages[0].get_child(0))
	_build_layout(pages[1].get_child(0))
	var summary_column: VBoxContainer = pages[2].get_child(0)
	summary = _label("")
	summary_column.add_child(summary)
	reset_button = _button("기본 준비로 초기화")
	reset_button.pressed.connect(func() -> void: command_requested.emit("reset", "", null))
	summary_column.add_child(reset_button)
	show_tab(0)


func _build_stock(column: VBoxContainer) -> void:
	stock_heading = _label("원재료 발주 · 한 개씩 조절")
	column.add_child(stock_heading)
	for ingredient: Definitions.IngredientDef in definitions.ingredients:
		if not ingredient.purchasable:
			continue
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _label("")
		row.add_child(label)
		purchase_labels[ingredient.id] = label
		var minus := _button("−", false)
		minus.pressed.connect(_change_quantity.bind("set_purchase", ingredient.id, -1))
		row.add_child(minus)
		purchase_minus[ingredient.id] = minus
		var plus := _button("+", false)
		plus.pressed.connect(_change_quantity.bind("set_purchase", ingredient.id, 1))
		row.add_child(plus)
		purchase_plus[ingredient.id] = plus
	prep_heading = _label("프렙 · 영업 중 손질을 미리 준비")
	column.add_child(prep_heading)
	for recipe_id: String in definitions.menu_ids:
		var recipe := definitions.recipe_for(recipe_id)
		if recipe.prepared_ingredient_id.is_empty():
			continue
		var row := HBoxContainer.new()
		column.add_child(row)
		if recipe.icon != null:
			var icon := TextureRect.new()
			icon.texture = recipe.icon
			icon.custom_minimum_size = Vector2(36, 36)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
		var label := _label("")
		row.add_child(label)
		prep_labels[recipe.id] = label
		var minus := _button("−", false)
		minus.pressed.connect(_change_quantity.bind("set_prep", recipe.id, -1))
		row.add_child(minus)
		prep_minus[recipe.id] = minus
		var plus := _button("+", false)
		plus.pressed.connect(_change_quantity.bind("set_prep", recipe.id, 1))
		row.add_child(plus)
		prep_plus[recipe.id] = plus
	priority_heading = _label("메뉴별 기본 우선순위 · 0~2\n큰 값부터 배정 · 새 주문에 적용\n영업 중 주문별 변경 가능")
	column.add_child(priority_heading)
	for recipe_id: String in definitions.menu_ids:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _label("")
		row.add_child(label)
		priority_labels[recipe_id] = label
		var minus := _button("−", false)
		minus.pressed.connect(_change_priority.bind(recipe_id, -1))
		row.add_child(minus)
		priority_minus[recipe_id] = minus
		var plus := _button("+", false)
		plus.pressed.connect(_change_priority.bind(recipe_id, 1))
		row.add_child(plus)
		priority_plus[recipe_id] = plus


func _build_layout(column: VBoxContainer) -> void:
	station_picker = OptionButton.new()
	station_picker.custom_minimum_size = Vector2(64, 64)
	station_picker.add_theme_font_size_override("font_size", 20)
	for station: Definitions.StationDef in definitions.stations:
		station_picker.add_item(tr(station.display_name))
	station_picker.item_selected.connect(func(index: int) -> void: select_station(definitions.stations[index].id))
	column.add_child(station_picker)
	station_label = _label("")
	column.add_child(station_label)
	var moves := HBoxContainer.new()
	column.add_child(moves)
	for direction: String in ["up", "left", "down", "right"]:
		var button := _button({"up": "↑ 위", "left": "← 왼쪽", "down": "↓ 아래", "right": "→ 오른쪽"}[direction])
		button.pressed.connect(func() -> void: command_requested.emit("move_station", selected_station_id, direction))
		moves.add_child(button)
		move_buttons[direction] = button
	var rotate := _button("작업 방향 ↻ 회전")
	rotate.pressed.connect(func() -> void: command_requested.emit("rotate_station", selected_station_id, null))
	column.add_child(rotate)
	move_buttons["rotate"] = rotate
	placement_preview = _label("")
	placement_preview.visible = false
	column.add_child(placement_preview)
	for employee: Definitions.EmployeeDef in definitions.employees:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _label(tr(employee.display_name))
		row.add_child(label)
		employee_labels[employee.id] = label
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(180, 64)
		picker.add_theme_font_size_override("font_size", 20)
		for title: String in DUTY_NAMES:
			picker.add_item(tr(title))
		picker.item_selected.connect(func(index: int) -> void: command_requested.emit("set_duty", employee.id, DUTIES[index]))
		row.add_child(picker)
		duty_buttons[employee.id] = picker
	select_station(definitions.stations[0].id)


func show_tab(index: int) -> void:
	for item: int in tabs.size():
		tabs[item].disabled = item == index
		tabs[item].theme_type_variation = &"ActiveButton" if item == index else &"Button"
		pages[item].visible = item == index


func select_station(station_id: String) -> void:
	for index: int in definitions.stations.size():
		if definitions.stations[index].id == station_id:
			selected_station_id = station_id
			station_picker.select(index)
			station_selected.emit(station_id)
			_show_station()
			return


func _show_station() -> void:
	for station: Dictionary in current.get("stations", []):
		if station.id == selected_station_id:
			station_label.text = tr("%s · 노란 테두리\n위치 (%d, %d) · 작업 위치 (%d, %d)") % [tr(station.name), station.tile[0], station.tile[1], station.work_position[0], station.work_position[1]]
			placement_preview.visible = current.get("space_rules", false)
			var lines := PackedStringArray([tr("공간 규칙 · 작업 위치 중첩 금지 / 냉식대·화구 이격")])
			var titles := {"up": "↑ 위", "left": "← 왼쪽", "down": "↓ 아래", "right": "→ 오른쪽", "rotate": "작업 방향 ↻ 회전"}
			for direction: String in move_buttons:
				var reason: String = station.get("placement_options", {}).get(direction, "")
				var blocked := not reason.is_empty()
				if move_buttons[direction].disabled != blocked:
					move_buttons[direction].disabled = blocked
				if not reason.is_empty() and not station.get("fixed", false):
					lines.append(tr("%s · %s") % [tr(titles[direction]), reason_text(reason)])
			if station.get("fixed", false):
				lines.append(reason_text("fixed_station"))
			else:
				lines.append(tr("밝은 버튼의 방향으로 배치할 수 있습니다"))
			placement_preview.text = "\n".join(lines)


func refresh(snapshot: Dictionary) -> void:
	current = snapshot
	if not snapshot.has("purchases"):
		return
	for ingredient: Definitions.IngredientDef in definitions.ingredients:
		if not ingredient.purchasable:
			continue
		var quantity: int = snapshot.purchases.get(ingredient.id, 0)
		purchase_labels[ingredient.id].text = tr("%s %d개\n개당 %d") % [tr(ingredient.display_name), quantity, ingredient.unit_cost]
		purchase_minus[ingredient.id].disabled = quantity == 0
	for recipe_id: String in prep_labels:
		var recipe := definitions.recipe_for(recipe_id)
		var quantity: int = snapshot.prep_quantities.get(recipe_id, 0)
		prep_labels[recipe_id].text = tr("%s %d개\n노동 %d / 개") % [tr(recipe.display_name), quantity, recipe.prep_labor_units]
		prep_minus[recipe_id].disabled = quantity == 0
	for employee_id: String in duty_buttons:
		duty_buttons[employee_id].select(DUTIES.find(snapshot.duties[employee_id]))
	for recipe_id: String in priority_labels:
		var priority: int = snapshot.menu_priorities[recipe_id]
		priority_labels[recipe_id].text = tr("%s · 우선순위 %d") % [tr(definitions.recipe_for(recipe_id).display_name), priority]
		priority_minus[recipe_id].disabled = priority == 0
		priority_plus[recipe_id].disabled = priority == 2
	var lines: PackedStringArray = [tr("준비 확정 후 영업이 시작됩니다."), tr("원재료와 프렙은 이번 영업에만 사용합니다."), "", tr("시작 재고")]
	for ingredient: Definitions.IngredientDef in definitions.ingredients:
		lines.append(tr("%s · %d개") % [tr(ingredient.display_name), snapshot.inventory[ingredient.id]])
	lines.append(tr("\n메뉴별 기본 우선순위"))
	for recipe_id: String in definitions.menu_ids:
		lines.append(tr("%s · 우선순위 %d") % [tr(definitions.recipe_for(recipe_id).display_name), snapshot.menu_priorities[recipe_id]])
	if snapshot.get("space_rules", false):
		lines.append(tr("\n고정 설비와 작업 위치를 확인하세요.\n배치와 담당의 효과는 마감 지표로 비교하세요."))
	else:
		lines.append(tr("\n설비를 가까이 두면 이동이 줄어듭니다.\n프렙과 우선순위의 효과는 마감 지표로 비교하세요."))
	summary.text = "\n".join(lines)
	_show_station()


func _change_quantity(kind: String, target: String, amount: int) -> void:
	var quantities: Dictionary = current.purchases if kind == "set_purchase" else current.prep_quantities
	command_requested.emit(kind, target, quantities.get(target, 0) + amount)


func _change_priority(recipe_id: String, amount: int) -> void:
	command_requested.emit("set_menu_priority", recipe_id, current.menu_priorities[recipe_id] + amount)


static func reason_text(reason: String) -> String:
	return TranslationServer.translate(REASONS.get(reason, "준비를 적용할 수 없습니다 · 선택과 데이터를 확인하세요"))


func refresh_translations() -> void:
	for index: int in tabs.size():
		tabs[index].text = tr(["발주·프렙", "배치·담당", "요약"][index])
	stock_heading.text = tr("원재료 발주 · 한 개씩 조절")
	prep_heading.text = tr("프렙 · 영업 중 손질을 미리 준비")
	priority_heading.text = tr("메뉴별 기본 우선순위 · 0~2\n큰 값부터 배정 · 새 주문에 적용\n영업 중 주문별 변경 가능")
	reset_button.text = tr("기본 준비로 초기화")
	for index: int in definitions.stations.size():
		station_picker.set_item_text(index, tr(definitions.stations[index].display_name))
	for employee: Definitions.EmployeeDef in definitions.employees:
		employee_labels[employee.id].text = tr(employee.display_name)
	for employee_id: String in duty_buttons:
		for index: int in DUTY_NAMES.size():
			duty_buttons[employee_id].set_item_text(index, tr(DUTY_NAMES[index]))
	for direction: String in ["up", "left", "down", "right"]:
		move_buttons[direction].text = tr({"up": "↑ 위", "left": "← 왼쪽", "down": "↓ 아래", "right": "→ 오른쪽"}[direction])
	move_buttons.rotate.text = tr("작업 방향 ↻ 회전")
	refresh(current)


static func _button(title: String, expand: bool = true) -> Button:
	var button := Button.new()
	button.text = TranslationServer.translate(title)
	button.custom_minimum_size = Vector2(64, 64)
	button.add_theme_font_size_override("font_size", 20)
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


static func _label(title: String) -> Label:
	var label := Label.new()
	label.text = TranslationServer.translate(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 20)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
