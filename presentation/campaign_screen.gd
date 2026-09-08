extends Control

const CampaignDef := preload("res://content/campaign_def.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const AppPreferences := preload("res://presentation/app_preferences.gd")
const KitchenScreen := preload("res://presentation/main.gd")
const ServiceScene := preload("res://presentation/main.tscn")
const SafeAreaSource := preload("res://platform/safe_area.gd")

@export_file("*.tres") var campaign_path: String = "res://content/campaign/campaign.tres"
var save_path: String = "user://campaign_records.json"
var settings_path: String = "user://settings.json"
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
var continue_button: Button
var active_session: Variant = null
var preferences: AppPreferences
var settings_button: Button
var settings_dialog: AcceptDialog
var settings_locale: OptionButton
var settings_sound: CheckButton
var settings_text_size: OptionButton
var settings_message: Label
var settings_locale_label: Label
var settings_text_size_label: Label
var menu_title: Label
var ending_title: Label
var ending_copy: Label
var ending_return_button: Button
var save_error_dialog: AcceptDialog
var retry_checkpoint_button: Button
var replace_dialog: ConfirmationDialog
var save_message_kind: String = ""
var save_message_reason: String = ""
var settings_message_kind: String = ""
var settings_message_reason: String = ""

@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource


func _ready() -> void:
	preferences = AppPreferences.new(settings_path)
	var settings_load := preferences.load_settings()
	preferences.changed.connect(_on_preferences_changed)
	_build_menu()
	_build_dialogs()
	_build_settings()
	safe_area_source.changed.connect(_on_safe_area_changed)
	resized.connect(_update_safe_area)
	_update_safe_area()
	campaign = load(campaign_path) as CampaignDef
	if campaign == null or not campaign.validate().is_empty():
		_set_save_message("campaign_invalid")
		begin_button.disabled = true
		return
	store = CampaignStore.new(campaign, save_path)
	var loaded := store.load_records()
	storage_blocked = not loaded.accepted
	progress = CampaignProgress.new(campaign, loaded.records if loaded.accepted else {})
	active_session = loaded.get("active_session") if loaded.accepted else null
	recover_button.visible = loaded.can_recover
	session_only_button.visible = storage_blocked
	_set_save_message("storage", loaded.reason)
	if not settings_load.accepted:
		_set_settings_message("error", settings_load.reason)
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
	menu_title = _label("Chef al Mando · 영업 목록", 30)
	menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(menu_title)
	settings_button = _button("설정", _show_settings)
	heading.add_child(settings_button)
	ending_button = _button("엔딩 다시 보기", _show_ending)
	ending_button.visible = false
	heading.add_child(ending_button)
	continue_button = _button("이어하기", _resume_active_session)
	continue_button.visible = false
	heading.add_child(continue_button)
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
	ending_title = _label("여덟 번의 영업을 마쳤습니다", 32)
	ending_panel.add_child(ending_title)
	ending_copy = _label("준비한 재료, 바꾼 동선, 나눈 담당이 하나의 주방을 완성했습니다.\n\n완료한 영업은 언제든 다시 선택할 수 있습니다.\n각 영업의 최고 제공 수와 최고 손익을 더 높여 보세요.", 26)
	ending_panel.add_child(ending_copy)
	ending_return_button = _button("영업 목록으로", return_to_menu)
	ending_panel.add_child(ending_return_button)
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
	result_dialog.title = tr("영업 결과")
	result_dialog.ok_button_text = tr("분석 보기")
	result_dialog.dialog_autowrap = true
	add_child(result_dialog)
	next_button = result_dialog.add_button(tr("다음 영업"), false, "next")
	retry_service_button = result_dialog.add_button(tr("다시 준비"), false, "retry")
	retry_save_button = result_dialog.add_button(tr("저장 재시도"), false, "save")
	for button: Button in [result_dialog.get_ok_button(), next_button, retry_service_button, retry_save_button]:
		button.custom_minimum_size.y = 64
		button.add_theme_font_size_override("font_size", 20)
	result_dialog.custom_action.connect(_result_action)
	goal_dialog = AcceptDialog.new()
	goal_dialog.title = tr("이번 영업의 목표")
	goal_dialog.ok_button_text = tr("확인")
	goal_dialog.dialog_autowrap = true
	add_child(goal_dialog)
	goal_dialog.get_ok_button().custom_minimum_size.y = 64
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = tr("영업 목록으로 돌아가기")
	leave_dialog.dialog_text = tr("현재 영업을 저장하고 목록으로 돌아갑니다.\n이어하기를 누르면 일시정지한 시점부터 계속할 수 있습니다.")
	leave_dialog.ok_button_text = tr("저장하고 목록으로")
	leave_dialog.cancel_button_text = tr("일시정지 상태로 계속")
	leave_dialog.dialog_autowrap = true
	add_child(leave_dialog)
	leave_dialog.get_ok_button().custom_minimum_size.y = 64
	leave_dialog.get_cancel_button().custom_minimum_size.y = 64
	leave_dialog.confirmed.connect(return_to_menu)
	save_error_dialog = AcceptDialog.new()
	save_error_dialog.title = tr("영업을 저장하지 못했습니다")
	save_error_dialog.ok_button_text = tr("저장 재시도")
	save_error_dialog.dialog_autowrap = true
	add_child(save_error_dialog)
	retry_checkpoint_button = save_error_dialog.get_ok_button()
	retry_checkpoint_button.custom_minimum_size.y = 64
	save_error_dialog.confirmed.connect(_retry_checkpoint)
	replace_dialog = ConfirmationDialog.new()
	replace_dialog.title = tr("진행 중인 영업 교체")
	replace_dialog.dialog_text = tr("새 영업에서 시작을 누르면 저장한 이어하기를 새 영업으로 교체합니다.")
	replace_dialog.ok_button_text = tr("새 영업으로 교체")
	replace_dialog.cancel_button_text = tr("이어하기 유지")
	replace_dialog.dialog_autowrap = true
	add_child(replace_dialog)
	replace_dialog.get_ok_button().custom_minimum_size.y = 64
	replace_dialog.get_cancel_button().custom_minimum_size.y = 64
	replace_dialog.confirmed.connect(_begin_selected_service)


func _build_settings() -> void:
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = tr("설정")
	settings_dialog.ok_button_text = tr("닫기")
	settings_dialog.dialog_autowrap = true
	add_child(settings_dialog)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 12)
	settings_dialog.add_child(column)
	settings_dialog.get_ok_button().custom_minimum_size.y = 64
	settings_locale_label = _label("언어", 20)
	column.add_child(settings_locale_label)
	settings_locale = OptionButton.new()
	settings_locale.custom_minimum_size = Vector2(64, 64)
	settings_locale.add_item("한국어")
	settings_locale.add_item("English")
	settings_locale.item_selected.connect(_change_locale)
	column.add_child(settings_locale)
	settings_sound = CheckButton.new()
	settings_sound.text = tr("효과음")
	settings_sound.custom_minimum_size = Vector2(64, 64)
	settings_sound.toggled.connect(_change_sound)
	column.add_child(settings_sound)
	settings_text_size_label = _label("글자 크기", 20)
	column.add_child(settings_text_size_label)
	settings_text_size = OptionButton.new()
	settings_text_size.custom_minimum_size = Vector2(64, 64)
	settings_text_size.add_item(tr("기본"))
	settings_text_size.add_item(tr("크게"))
	settings_text_size.item_selected.connect(_change_text_size)
	column.add_child(settings_text_size)
	settings_message = _label("", 18)
	column.add_child(settings_message)
	_sync_settings_controls()
	preferences.apply_to(self)


func _show_settings() -> void:
	_sync_settings_controls()
	settings_dialog.popup_centered_clamped(Vector2i(620, 520))
	_ensure_dialog_tap_sizes()
	_ensure_dialog_tap_sizes.call_deferred()


func _change_locale(index: int) -> void:
	_update_settings({"locale": "ko" if index == 0 else "en"})


func _change_sound(enabled: bool) -> void:
	_update_settings({"sound_enabled": enabled})


func _change_text_size(index: int) -> void:
	_update_settings({"text_size": "normal" if index == 0 else "large"})


func _update_settings(changes: Dictionary) -> void:
	var result := preferences.update_settings(changes)
	_set_settings_message("saved" if result.accepted else "error", result.reason)
	_sync_settings_controls()


func _sync_settings_controls() -> void:
	var values := preferences.snapshot()
	settings_locale.select(0 if values.locale == "ko" else 1)
	settings_sound.set_pressed_no_signal(values.sound_enabled)
	settings_text_size.select(0 if values.text_size == "normal" else 1)
	var popup_font_size := 32 if values.text_size == "large" else 26
	for picker: OptionButton in [settings_locale, settings_text_size]:
		picker.get_popup().add_theme_font_size_override("font_size", popup_font_size)
		picker.get_popup().add_theme_constant_override("v_separation", 32)


func _on_preferences_changed() -> void:
	preferences.apply_to(self)
	_refresh_strings()
	if active_service != null:
		active_service.apply_preferences()


func _refresh_strings() -> void:
	menu_title.text = tr("Chef al Mando · 영업 목록")
	settings_button.text = tr("설정")
	ending_button.text = tr("엔딩 다시 보기")
	continue_button.text = tr("이어하기")
	ending_title.text = tr("여덟 번의 영업을 마쳤습니다")
	ending_copy.text = tr("준비한 재료, 바꾼 동선, 나눈 담당이 하나의 주방을 완성했습니다.\n\n완료한 영업은 언제든 다시 선택할 수 있습니다.\n각 영업의 최고 제공 수와 최고 손익을 더 높여 보세요.")
	ending_return_button.text = tr("영업 목록으로")
	begin_button.text = tr("준비 시작")
	settings_dialog.title = tr("설정")
	settings_dialog.ok_button_text = tr("닫기")
	settings_locale_label.text = tr("언어")
	settings_sound.text = tr("효과음")
	settings_text_size_label.text = tr("글자 크기")
	settings_text_size.set_item_text(0, tr("기본"))
	settings_text_size.set_item_text(1, tr("크게"))
	save_error_dialog.title = tr("영업을 저장하지 못했습니다")
	retry_checkpoint_button.text = tr("저장 재시도")
	replace_dialog.title = tr("진행 중인 영업 교체")
	replace_dialog.dialog_text = tr("새 영업에서 시작을 누르면 저장한 이어하기를 새 영업으로 교체합니다.")
	replace_dialog.ok_button_text = tr("새 영업으로 교체")
	replace_dialog.cancel_button_text = tr("이어하기 유지")
	result_dialog.title = tr("영업 결과")
	result_dialog.ok_button_text = tr("분석 보기")
	next_button.text = tr("다음 영업")
	retry_service_button.text = tr("다시 준비")
	retry_save_button.text = tr("저장 재시도")
	goal_dialog.title = tr("이번 영업의 목표")
	goal_dialog.ok_button_text = tr("확인")
	leave_dialog.title = tr("영업 목록으로 돌아가기")
	leave_dialog.dialog_text = tr("현재 영업을 저장하고 목록으로 돌아갑니다.\n이어하기를 누르면 일시정지한 시점부터 계속할 수 있습니다.")
	leave_dialog.ok_button_text = tr("저장하고 목록으로")
	leave_dialog.cancel_button_text = tr("일시정지 상태로 계속")
	if service_menu_button != null:
		service_menu_button.text = tr("목록")
		service_goal_button.text = tr("결과") if not last_result.is_empty() else tr("목표")
	_refresh_save_message()
	_refresh_settings_message()
	if save_error_dialog.visible:
		save_error_dialog.dialog_text = save_label.text
	if not last_result.is_empty():
		_refresh_result_text()
	_ensure_dialog_tap_sizes()
	_ensure_dialog_tap_sizes.call_deferred()
	_refresh_catalog()


func _ensure_dialog_tap_sizes() -> void:
	for dialog: AcceptDialog in [settings_dialog, result_dialog, goal_dialog, leave_dialog,
		save_error_dialog, replace_dialog]:
		dialog.add_theme_constant_override("buttons_min_height", 64)
		dialog.add_theme_constant_override("buttons_min_width", 64)
	for button: Button in [settings_dialog.get_ok_button(), result_dialog.get_ok_button(), next_button,
		retry_service_button, retry_save_button, goal_dialog.get_ok_button(), leave_dialog.get_ok_button(),
		leave_dialog.get_cancel_button(), retry_checkpoint_button, replace_dialog.get_ok_button(),
		replace_dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, 64.0), 64.0)


func _settings_message(reason: String) -> String:
	if reason in ["future_version", "unsupported_version"]:
		return tr("이 앱에서 지원하지 않는 설정 파일입니다. 기존 파일을 보존합니다.")
	return tr("설정을 저장하거나 읽지 못했습니다. 기존 설정을 유지합니다.")


func _set_settings_message(kind: String, reason: String = "") -> void:
	settings_message_kind = kind
	settings_message_reason = reason
	_refresh_settings_message()


func _refresh_settings_message() -> void:
	match settings_message_kind:
		"saved":
			settings_message.text = tr("설정 저장 완료")
		"error":
			settings_message.text = _settings_message(settings_message_reason)
		_:
			settings_message.text = ""


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
		var status: String = tr("완료") if record.get("completed", false) else tr("도전 가능")
		if not unlocked:
			status = tr("잠김 · 이전 영업 완료 필요")
		var text := tr("%02d · %s\n%s") % [index + 1, tr(scenario.display_name), status]
		if not record.is_empty():
			text += tr("\n최고 %d건 · 손익 %s") % [record.best_served, KitchenScreen._money(record.best_profit)]
		var button := _button(text, select_scenario.bind(scenario.id))
		button.custom_minimum_size.y = 104
		button.disabled = not unlocked
		button.toggle_mode = true
		button.button_pressed = scenario.id == selected_scenario_id
		scenario_list.add_child(button)
		preferences.apply_to(button)
		scenario_buttons[scenario.id] = button
	ending_button.visible = progress.snapshot().ending_unlocked
	continue_button.visible = active_session is Dictionary and active_service == null
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
	briefing_title.text = tr("%s · %s") % [tr(scenario.display_name), tr(scenario.operation_problem)]
	var counts: Dictionary = {}
	for recipe_id: String in scenario.order_recipe_ids:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	var menu_lines: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		menu_lines.append(tr("%s %d건") % [tr(scenario.recipe_for(recipe_id).display_name), counts[recipe_id]])
	briefing_label.text = tr("%s\n\n목표 · 제공 %d건 이상 / 손익 %s 이상\n\n예산 %s · 고정 인건비 %s\n직원 %d명 · 설비 %d개 · 준비 노동량 %d\n\n예상 주문 %d건 · 영업 300초\n%s") % [tr(scenario.briefing),
		scenario.minimum_served, KitchenScreen._money(scenario.minimum_profit), KitchenScreen._money(scenario.starting_budget),
		KitchenScreen._money(scenario.labor_cost), scenario.employees.size(), scenario.stations.size(), scenario.prep_labor_capacity,
		scenario.order_count, "\n".join(menu_lines)]
	var record: Dictionary = progress.snapshot().records.get(scenario.id, {})
	if not record.is_empty():
		briefing_label.text += tr("\n\n개별 최고 기록 · 제공 %d건 / 손익 %s\n두 최고 기록은 서로 다른 시도의 결과일 수 있습니다.") % [record.best_served, KitchenScreen._money(record.best_profit)]
	begin_button.disabled = storage_blocked or not progress.is_unlocked(scenario.id)


func begin_service() -> bool:
	if storage_blocked or active_service != null or progress == null or not progress.is_unlocked(selected_scenario_id):
		return false
	if active_session is Dictionary and not active_session.simulation.closed:
		replace_dialog.popup_centered_clamped(Vector2i(700, 300))
		_ensure_dialog_tap_sizes()
		return false
	return _begin_selected_service()


func _begin_selected_service() -> bool:
	if storage_blocked or active_service != null or progress == null or not progress.is_unlocked(selected_scenario_id):
		return false
	var scenario := campaign.scenario_for(selected_scenario_id)
	_mount_service(scenario)
	return true


func _mount_service(scenario: Resource) -> void:
	active_service = ServiceScene.instantiate() as KitchenScreen
	active_service.scenario_definition = scenario
	active_service.scenario_path = scenario.resource_path
	active_service.settings_path = settings_path
	active_service.app_preferences = preferences
	active_service.modal_open_allowed = func() -> bool: return not pending_save
	active_service.service_closed.connect(_on_service_closed.bind(scenario.id))
	active_service.checkpoint_requested.connect(_save_checkpoint)
	add_child(active_service)
	active_service.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_area.visible = false
	var header: HBoxContainer = active_service.get_node("SafeArea/Layout/Header")
	active_service.get_node("SafeArea/Layout/Header/Title").text = tr(scenario.display_name)
	service_menu_button = _button("목록", request_menu)
	header.add_child(service_menu_button)
	preferences.apply_to(service_menu_button)
	header.move_child(service_menu_button, 0)
	service_goal_button = _button("목표", _show_goal)
	header.add_child(service_goal_button)
	preferences.apply_to(service_goal_button)
	header.move_child(service_goal_button, 1)
	active_service.restart_button.pressed.connect(_clear_result)
	last_result = {}


func _resume_active_session() -> bool:
	if not active_session is Dictionary or active_service != null:
		return false
	var restored := ServiceSession.restore(campaign, active_session, progress.snapshot().records)
	if not restored.accepted:
		_set_save_message("storage", restored.reason)
		return false
	selected_scenario_id = restored.scenario_id
	var scenario := campaign.scenario_for(selected_scenario_id)
	_mount_service(scenario)
	if not active_service.restore_service(restored):
		return false
	if active_service.state == KitchenScreen.State.CLOSED:
		last_result = progress.record_result(selected_scenario_id, active_service.simulation.snapshot())
		service_goal_button.text = tr("결과")
		_show_result()
	return true


func _save_checkpoint(_reason: String = "checkpoint") -> bool:
	if session_only or active_service == null or active_service.last_preparation.is_empty():
		return session_only
	var session := ServiceSession.capture(active_service.definitions.id, active_service.last_preparation,
		active_service.simulation, active_service.driver.speed, active_service.driver.accumulator_us)
	var result := store.save_active_session(session, progress.snapshot().records)
	pending_save = not result.accepted
	_set_save_message("service_saved" if result.accepted else "storage", result.reason)
	if result.accepted:
		active_session = result.active_session
		active_service.checkpoint_saved()
		save_error_dialog.hide()
	elif active_service.state != KitchenScreen.State.CLOSED:
		active_service.pause_after_save_failure()
		save_error_dialog.dialog_text = save_label.text
		save_error_dialog.popup_centered_clamped(Vector2i(680, 300))
		_ensure_dialog_tap_sizes()
	return result.accepted


func _retry_checkpoint() -> void:
	_save_checkpoint("retry")


func request_menu() -> void:
	if active_service != null and active_service.state in [KitchenScreen.State.RUNNING, KitchenScreen.State.PAUSED]:
		active_service.call("_pause")
		if pending_save:
			return
		leave_dialog.popup_centered_clamped(Vector2i(700, 260))
		_ensure_dialog_tap_sizes()
		return
	return_to_menu()


func return_to_menu() -> void:
	if pending_save:
		if last_result.is_empty():
			leave_dialog.hide()
			save_error_dialog.dialog_text = save_label.text
			save_error_dialog.popup_centered_clamped(Vector2i(680, 300))
			_ensure_dialog_tap_sizes()
		else:
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
	if not last_result.is_empty():
		return
	last_result = progress.record_result(scenario_id, result)
	if not last_result.accepted:
		return
	pending_save = not session_only
	_save_progress()
	service_goal_button.text = tr("결과")
	_show_result()


func _save_progress() -> void:
	if session_only:
		_set_save_message("session_only_result")
		pending_save = false
		return
	_save_checkpoint("closing")


func _show_result() -> void:
	if last_result.is_empty():
		return
	save_error_dialog.hide()
	var final_service: bool = selected_scenario_id == campaign.scenarios[-1].id
	next_button.text = tr("엔딩 보기") if final_service else tr("다음 영업")
	next_button.disabled = pending_save or not last_result.passed
	retry_service_button.disabled = pending_save
	if active_service != null:
		active_service.restart_button.disabled = pending_save
	retry_save_button.visible = pending_save and not session_only
	_refresh_result_text()
	result_dialog.popup_centered_clamped(Vector2i(760, 400))
	_ensure_dialog_tap_sizes()


func _refresh_result_text() -> void:
	result_dialog.dialog_text = tr("%s\n\n제공 %d건 / 목표 %d건\n손익 %s / 목표 %s\n\n%s") % [tr("목표 달성") if last_result.passed else tr("목표 미달 · 준비를 바꿔 다시 도전할 수 있습니다"),
		last_result.served, last_result.minimum_served, KitchenScreen._money(last_result.profit), KitchenScreen._money(last_result.minimum_profit), save_label.text]


func _show_goal() -> void:
	if active_service == null:
		return
	if active_service.state == KitchenScreen.State.CLOSED:
		_show_result()
		return
	active_service.call("_pause")
	if pending_save:
		return
	var scenario := campaign.scenario_for(selected_scenario_id)
	goal_dialog.dialog_text = tr("%s\n\n제공 %d건 이상 · 손익 %s 이상\n\n%s\n\n확인 후 재개 버튼으로 영업을 계속하세요.") % [tr(scenario.display_name), scenario.minimum_served, KitchenScreen._money(scenario.minimum_profit), tr(scenario.briefing)]
	goal_dialog.popup_centered_clamped(Vector2i(700, 360))
	_ensure_dialog_tap_sizes()


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
	service_goal_button.text = tr("목표")


func _show_ending() -> void:
	if pending_save or progress == null or not progress.snapshot().ending_unlocked:
		return
	return_to_menu()
	catalog_panel.visible = false
	ending_panel.visible = true


func _recover() -> void:
	var result := store.recover_backup()
	if not result.accepted:
		_set_save_message("storage", result.reason)
		return
	progress = CampaignProgress.new(campaign, result.records)
	active_session = result.active_session
	storage_blocked = false
	recover_button.visible = false
	session_only_button.visible = false
	_set_save_message("recovered")
	_refresh_catalog()


func _start_session_only() -> void:
	session_only = true
	storage_blocked = false
	recover_button.visible = false
	session_only_button.visible = false
	_set_save_message("session_only_active")
	_refresh_catalog()


func _set_save_message(kind: String, reason: String = "") -> void:
	save_message_kind = kind
	save_message_reason = reason
	_refresh_save_message()


func _refresh_save_message() -> void:
	match save_message_kind:
		"campaign_invalid":
			save_label.text = tr("캠페인 데이터를 불러올 수 없습니다")
		"storage":
			save_label.text = _storage_message(save_message_reason)
		"service_saved":
			save_label.text = tr("영업 저장 완료")
		"recovered":
			save_label.text = tr("백업에서 기록을 복구했습니다")
		"session_only_result":
			save_label.text = tr("저장 없이 플레이 중 · 이번 세션이 끝나면 새 결과는 남지 않습니다")
		"session_only_active":
			save_label.text = tr("저장 없이 플레이 중 · 기존 파일을 보존하며 이번 세션의 결과는 저장하지 않습니다")
		_:
			save_label.text = ""


func _storage_message(reason: String) -> String:
	match reason:
		"loaded":
			return tr("저장한 캠페인 기록을 불러왔습니다")
		"new_campaign":
			return tr("새 캠페인 · 마감 후 완료 기록과 최고 기록을 저장합니다")
		"future_version", "unsupported_version":
			return tr("이 앱에서 지원하지 않는 버전의 기록입니다. 기존 파일을 보존합니다.")
		"corrupt_records", "missing", "recovery_required":
			return tr("저장 기록을 정상적으로 읽을 수 없습니다. 백업을 복구하거나 저장 없이 시작할 수 있습니다.")
		_:
			return tr("기록을 저장하거나 읽지 못했습니다. 이번 세션의 결과는 유지되며 저장을 다시 시도할 수 있습니다.")


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(text)
	button.custom_minimum_size.y = 64
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = tr(text)
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
