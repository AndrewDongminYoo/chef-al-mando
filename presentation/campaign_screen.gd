extends Control

const CampaignDef := preload("res://content/campaign_def.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const KitchenScreen := preload("res://presentation/main.gd")
const ServiceScene := preload("res://presentation/main.tscn")
const SafeAreaSource := preload("res://platform/safe_area.gd")

@export_file("*.tres") var campaign_path: String = "res://content/campaign/campaign.tres"
var save_path: String = "user://campaign_records.json"
var campaign: CampaignDef
var progress: CampaignProgress
var store: CampaignStore
var active_service: KitchenScreen
var selected_scenario_id: String = ""
var scenario_buttons: Dictionary[String, Button] = {}
var last_result: Dictionary = {}
var pending_save: bool = false
var session_only: bool = false
var storage_blocked: bool = false
var menu_panel: VBoxContainer
var catalog_panel: HBoxContainer
var list_scroll: ScrollContainer
var scenario_list: VBoxContainer
var briefing_title: Label
var briefing_label: Label
var begin_button: Button
var save_label: Label
var recover_button: Button
var session_only_button: Button
var ending_button: Button
var ending_panel: VBoxContainer
var result_dialog: AcceptDialog
var goal_dialog: AcceptDialog
var leave_dialog: ConfirmationDialog
var next_button: Button
var retry_service_button: Button
var retry_save_button: Button
var service_menu_button: Button
var service_goal_button: Button

@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource


func _ready() -> void:
	_build_menu()
	_build_dialogs()
	safe_area_source.changed.connect(_on_safe_area_changed)
	resized.connect(_update_safe_area)
	_update_safe_area()
	campaign = load(campaign_path) as CampaignDef
	if campaign == null or not campaign.validate().is_empty():
		save_label.text = "캠페인 데이터를 불러올 수 없습니다"
		begin_button.disabled = true
		return
	store = CampaignStore.new(campaign, save_path)
	var loaded := store.load_records()
	storage_blocked = not loaded.accepted
	progress = CampaignProgress.new(campaign, loaded.records if loaded.accepted else {})
	recover_button.visible = loaded.can_recover
	session_only_button.visible = storage_blocked
	save_label.text = _storage_message(loaded.reason)
	selected_scenario_id = campaign.scenarios[0].id
	for scenario: CampaignDef.ScenarioDef in campaign.scenarios:
		if progress.is_unlocked(scenario.id) and not progress.snapshot().records.get(scenario.id, {}).get("completed", false):
			selected_scenario_id = scenario.id
			break
	_refresh_catalog()


func _build_menu() -> void:
	menu_panel = VBoxContainer.new()
	menu_panel.add_theme_constant_override("separation", 18)
	safe_area.add_child(menu_panel)
	var heading := HBoxContainer.new()
	menu_panel.add_child(heading)
	var title := _label("Chef al Mando · 영업 목록", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	ending_button = _button("엔딩 다시 보기", _show_ending)
	ending_button.visible = false
	heading.add_child(ending_button)
	catalog_panel = HBoxContainer.new()
	catalog_panel.add_theme_constant_override("separation", 24)
	catalog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_panel.add_child(catalog_panel)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 320
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 0.8
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_panel.add_child(list_scroll)
	scenario_list = VBoxContainer.new()
	scenario_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_list.add_theme_constant_override("separation", 10)
	list_scroll.add_child(scenario_list)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio = 1.2
	details.add_theme_constant_override("separation", 14)
	catalog_panel.add_child(details)
	briefing_title = _label("영업을 선택하세요", 28)
	details.add_child(briefing_title)
	var briefing_scroll := ScrollContainer.new()
	briefing_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefing_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(briefing_scroll)
	briefing_label = _label("", 22)
	briefing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_scroll.add_child(briefing_label)
	begin_button = _button("준비 시작", begin_service)
	details.add_child(begin_button)
	ending_panel = VBoxContainer.new()
	ending_panel.visible = false
	ending_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ending_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	ending_panel.add_theme_constant_override("separation", 24)
	menu_panel.add_child(ending_panel)
	ending_panel.add_child(_label("여덟 번의 영업을 마쳤습니다", 32))
	ending_panel.add_child(_label("준비한 재료, 바꾼 동선, 나눈 담당이 하나의 주방을 완성했습니다.\n\n완료한 영업은 언제든 다시 선택할 수 있습니다.\n각 영업의 최고 제공 수와 최고 손익을 더 높여 보세요.", 26))
	ending_panel.add_child(_button("영업 목록으로", return_to_menu))
	save_label = _label("", 20)
	menu_panel.add_child(save_label)
	var recovery_actions := HBoxContainer.new()
	menu_panel.add_child(recovery_actions)
	recover_button = _button("백업에서 복구", _recover)
	recover_button.visible = false
	recovery_actions.add_child(recover_button)
	session_only_button = _button("저장 없이 새로 시작", _start_session_only)
	session_only_button.visible = false
	recovery_actions.add_child(session_only_button)


func _build_dialogs() -> void:
	result_dialog = AcceptDialog.new()
	result_dialog.title = "영업 결과"
	result_dialog.ok_button_text = "분석 보기"
	result_dialog.dialog_autowrap = true
	add_child(result_dialog)
	next_button = result_dialog.add_button("다음 영업", false, "next")
	retry_service_button = result_dialog.add_button("다시 준비", false, "retry")
	retry_save_button = result_dialog.add_button("저장 재시도", false, "save")
	for button: Button in [result_dialog.get_ok_button(), next_button, retry_service_button, retry_save_button]:
		button.custom_minimum_size.y = 64
		button.add_theme_font_size_override("font_size", 20)
	result_dialog.custom_action.connect(_result_action)
	goal_dialog = AcceptDialog.new()
	goal_dialog.title = "이번 영업의 목표"
	goal_dialog.ok_button_text = "확인"
	goal_dialog.dialog_autowrap = true
	add_child(goal_dialog)
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "영업 목록으로 돌아가기"
	leave_dialog.dialog_text = "현재 영업은 처음부터 다시 시작해야 합니다.\n이미 저장한 완료 기록과 최고 기록은 유지됩니다."
	leave_dialog.ok_button_text = "영업을 끝내고 목록으로"
	leave_dialog.cancel_button_text = "일시정지 상태로 계속"
	leave_dialog.dialog_autowrap = true
	add_child(leave_dialog)
	leave_dialog.confirmed.connect(return_to_menu)


func _refresh_catalog() -> void:
	for button: Button in scenario_buttons.values():
		scenario_list.remove_child(button)
		button.queue_free()
	scenario_buttons.clear()
	var records: Dictionary = progress.snapshot().records
	for index: int in campaign.scenarios.size():
		var scenario := campaign.scenarios[index]
		var unlocked := progress.is_unlocked(scenario.id)
		var record: Dictionary = records.get(scenario.id, {})
		var status: String = "완료" if record.get("completed", false) else "도전 가능"
		if not unlocked:
			status = "잠김 · 이전 영업 완료 필요"
		var text := "%02d · %s\n%s" % [index + 1, scenario.display_name, status]
		if not record.is_empty():
			text += "\n최고 %d건 · 손익 %s" % [record.best_served, KitchenScreen._money(record.best_profit)]
		var button := _button(text, select_scenario.bind(scenario.id))
		button.custom_minimum_size.y = 104
		button.disabled = not unlocked
		button.toggle_mode = true
		button.button_pressed = scenario.id == selected_scenario_id
		scenario_list.add_child(button)
		scenario_buttons[scenario.id] = button
	ending_button.visible = progress.snapshot().ending_unlocked
	_update_briefing()


func select_scenario(scenario_id: String) -> bool:
	if progress == null or not progress.is_unlocked(scenario_id) or active_service != null:
		return false
	selected_scenario_id = scenario_id
	for key: String in scenario_buttons:
		scenario_buttons[key].set_pressed_no_signal(key == scenario_id)
	_update_briefing()
	return true


func _update_briefing() -> void:
	var scenario := campaign.scenario_for(selected_scenario_id)
	if scenario == null:
		begin_button.disabled = true
		return
	briefing_title.text = scenario.display_name + " · " + scenario.operation_problem
	var counts: Dictionary = {}
	for recipe_id: String in scenario.order_recipe_ids:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	var menu_lines: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		menu_lines.append("%s %d건" % [scenario.recipe_for(recipe_id).display_name, counts[recipe_id]])
	briefing_label.text = "%s\n\n목표 · 제공 %d건 이상 / 손익 %s 이상\n\n예산 %s · 고정 인건비 %s\n직원 %d명 · 설비 %d개 · 준비 노동량 %d\n\n예상 주문 %d건 · 영업 300초\n%s" % [scenario.briefing,
		scenario.minimum_served, KitchenScreen._money(scenario.minimum_profit), KitchenScreen._money(scenario.starting_budget),
		KitchenScreen._money(scenario.labor_cost), scenario.employees.size(), scenario.stations.size(), scenario.prep_labor_capacity,
		scenario.order_count, "\n".join(menu_lines)]
	var record: Dictionary = progress.snapshot().records.get(scenario.id, {})
	if not record.is_empty():
		briefing_label.text += "\n\n개별 최고 기록 · 제공 %d건 / 손익 %s\n두 최고 기록은 서로 다른 시도의 결과일 수 있습니다." % [record.best_served, KitchenScreen._money(record.best_profit)]
	begin_button.disabled = storage_blocked or not progress.is_unlocked(scenario.id)


func begin_service() -> bool:
	if storage_blocked or active_service != null or progress == null or not progress.is_unlocked(selected_scenario_id):
		return false
	var scenario := campaign.scenario_for(selected_scenario_id)
	active_service = ServiceScene.instantiate() as KitchenScreen
	active_service.scenario_definition = scenario
	active_service.scenario_path = scenario.resource_path
	active_service.service_closed.connect(_on_service_closed.bind(scenario.id))
	add_child(active_service)
	active_service.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_area.visible = false
	var header: HBoxContainer = active_service.get_node("SafeArea/Layout/Header")
	active_service.get_node("SafeArea/Layout/Header/Title").text = scenario.display_name
	service_menu_button = _button("목록", request_menu)
	header.add_child(service_menu_button)
	header.move_child(service_menu_button, 0)
	service_goal_button = _button("목표", _show_goal)
	header.add_child(service_goal_button)
	header.move_child(service_goal_button, 1)
	active_service.restart_button.pressed.connect(_clear_result)
	last_result = {}
	return true


func request_menu() -> void:
	if active_service != null and active_service.state in [KitchenScreen.State.RUNNING, KitchenScreen.State.PAUSED]:
		active_service.call("_pause")
		leave_dialog.popup_centered_clamped(Vector2i(700, 260))
		return
	return_to_menu()


func return_to_menu() -> void:
	if pending_save:
		_show_result()
		return
	result_dialog.hide()
	goal_dialog.hide()
	leave_dialog.hide()
	if active_service != null:
		active_service.set_process(false)
		remove_child(active_service)
		active_service.queue_free()
		active_service = null
	safe_area.visible = true
	catalog_panel.visible = true
	ending_panel.visible = false
	if progress != null:
		_refresh_catalog()


func _on_service_closed(result: Dictionary, scenario_id: String) -> void:
	if active_service == null or active_service.definitions.id != scenario_id:
		return
	last_result = progress.record_result(scenario_id, result)
	if not last_result.accepted:
		return
	if last_result.changed:
		pending_save = not session_only
		_save_progress()
	service_goal_button.text = "결과"
	_show_result()


func _save_progress() -> void:
	if session_only:
		save_label.text = "저장 없이 플레이 중 · 이번 세션이 끝나면 새 결과는 남지 않습니다"
		return
	var result := store.save_records(progress.snapshot().records)
	pending_save = not result.accepted
	save_label.text = "기록 저장 완료" if result.accepted else _storage_message(result.reason)


func _show_result() -> void:
	if last_result.is_empty():
		return
	var final_service: bool = selected_scenario_id == campaign.scenarios[-1].id
	next_button.text = "엔딩 보기" if final_service else "다음 영업"
	next_button.disabled = pending_save or not last_result.passed
	retry_service_button.disabled = pending_save
	if active_service != null:
		active_service.restart_button.disabled = pending_save
	retry_save_button.visible = pending_save and not session_only
	result_dialog.dialog_text = "%s\n\n제공 %d건 / 목표 %d건\n손익 %s / 목표 %s\n\n%s" % ["목표 달성" if last_result.passed else "목표 미달 · 준비를 바꿔 다시 도전할 수 있습니다",
		last_result.served, last_result.minimum_served, KitchenScreen._money(last_result.profit), KitchenScreen._money(last_result.minimum_profit), save_label.text]
	result_dialog.popup_centered_clamped(Vector2i(760, 400))


func _show_goal() -> void:
	if active_service == null:
		return
	if active_service.state == KitchenScreen.State.CLOSED:
		_show_result()
		return
	active_service.call("_pause")
	var scenario := campaign.scenario_for(selected_scenario_id)
	goal_dialog.dialog_text = "%s\n\n제공 %d건 이상 · 손익 %s 이상\n\n%s\n\n확인 후 재개 버튼으로 영업을 계속하세요." % [scenario.display_name, scenario.minimum_served, KitchenScreen._money(scenario.minimum_profit), scenario.briefing]
	goal_dialog.popup_centered_clamped(Vector2i(700, 360))


func _result_action(action: String) -> void:
	if pending_save and action != "save":
		_show_result()
		return
	match action:
		"save":
			_save_progress()
			_show_result()
		"retry":
			result_dialog.hide()
			if active_service != null:
				active_service.call("_restart")
				_clear_result()
		"next":
			if last_result.is_empty() or not last_result.get("passed", false):
				return
			var index := campaign.scenarios.find(campaign.scenario_for(selected_scenario_id))
			if index == campaign.scenarios.size() - 1:
				_show_ending()
			else:
				return_to_menu()
				select_scenario(campaign.scenarios[index + 1].id)
				begin_service()


func _clear_result() -> void:
	last_result = {}
	service_goal_button.text = "목표"


func _show_ending() -> void:
	if pending_save or progress == null or not progress.snapshot().ending_unlocked:
		return
	return_to_menu()
	catalog_panel.visible = false
	ending_panel.visible = true


func _recover() -> void:
	var result := store.recover_backup()
	if not result.accepted:
		save_label.text = _storage_message(result.reason)
		return
	progress = CampaignProgress.new(campaign, result.records)
	storage_blocked = false
	recover_button.visible = false
	session_only_button.visible = false
	save_label.text = "백업에서 기록을 복구했습니다"
	_refresh_catalog()


func _start_session_only() -> void:
	session_only = true
	storage_blocked = false
	recover_button.visible = false
	session_only_button.visible = false
	save_label.text = "저장 없이 플레이 중 · 기존 파일을 보존하며 이번 세션의 결과는 저장하지 않습니다"
	_refresh_catalog()


func _storage_message(reason: String) -> String:
	match reason:
		"loaded":
			return "저장한 캠페인 기록을 불러왔습니다"
		"new_campaign":
			return "새 캠페인 · 마감 후 완료 기록과 최고 기록을 저장합니다"
		"future_version", "unsupported_version":
			return "이 앱에서 지원하지 않는 버전의 기록입니다. 기존 파일을 보존합니다."
		"corrupt_records", "missing", "recovery_required":
			return "저장 기록을 정상적으로 읽을 수 없습니다. 백업을 복구하거나 저장 없이 시작할 수 있습니다."
		_:
			return "기록을 저장하거나 읽지 못했습니다. 이번 세션의 결과는 유지되며 저장을 다시 시도할 수 있습니다."


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 64
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_safe_area_changed(physical_safe: Rect2i) -> void:
	_apply_safe_area(physical_safe, get_viewport().get_screen_transform().affine_inverse())


func _update_safe_area() -> void:
	_on_safe_area_changed(safe_area_source.current())


func _apply_safe_area(physical_safe: Rect2i, to_canvas: Transform2D) -> void:
	var canvas := Rect2(Vector2.ZERO, size)
	var usable := canvas
	if physical_safe.has_area():
		usable = canvas.intersection(to_canvas * Rect2(physical_safe))
		if not usable.has_area():
			usable = canvas
	safe_area.offset_left = usable.position.x
	safe_area.offset_top = usable.position.y
	safe_area.offset_right = usable.end.x - size.x
	safe_area.offset_bottom = usable.end.y - size.y
