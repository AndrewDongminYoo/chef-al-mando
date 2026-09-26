extends Control

## The settings dialog that the campaign and service screens share: the locale, sound and text-size
## controls, the save message, and optionally the open-source licenses button and dialog.
## A screen adds the panel to its root, where it takes no space, and opens the dialog with open().
## The screen refreshes the panel's strings when the preferences change.

const AppPreferences := preload("res://presentation/app_preferences.gd")
const LicenseNotices := preload("res://presentation/license_notices.gd")

const DIALOG_SIZE := Vector2i(620, 520)
const LICENSES_DIALOG_SIZE := Vector2i(900, 520)
const LABEL_FONT_SIZE := 20
const TAP_SIZE := 64

var preferences: AppPreferences
var settings_dialog: AcceptDialog
var settings_locale: OptionButton
var settings_sound: CheckButton
var settings_text_size: OptionButton
var settings_message: Label
var settings_locale_label: Label
var settings_text_size_label: Label
## The licenses controls exist only on a panel built with licenses; they are null otherwise.
var licenses_button: Button
var licenses_dialog: AcceptDialog
var licenses_body: RichTextLabel
var message_kind: String = ""
var message_reason: String = ""


func _init(app_preferences: AppPreferences, with_licenses: bool = false) -> void:
	preferences = app_preferences
	name = "SettingsPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = tr("설정")
	settings_dialog.ok_button_text = tr("닫기")
	settings_dialog.dialog_autowrap = true
	add_child(settings_dialog)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 12)
	settings_dialog.add_child(column)
	settings_locale_label = _label("언어")
	column.add_child(settings_locale_label)
	settings_locale = OptionButton.new()
	settings_locale.custom_minimum_size = Vector2(TAP_SIZE, TAP_SIZE)
	settings_locale.add_item("한국어")
	settings_locale.add_item("English")
	settings_locale.item_selected.connect(_change_locale)
	column.add_child(settings_locale)
	settings_sound = CheckButton.new()
	settings_sound.text = tr("효과음")
	settings_sound.custom_minimum_size = Vector2(TAP_SIZE, TAP_SIZE)
	settings_sound.toggled.connect(_change_sound)
	column.add_child(settings_sound)
	settings_text_size_label = _label("글자 크기")
	column.add_child(settings_text_size_label)
	settings_text_size = OptionButton.new()
	settings_text_size.custom_minimum_size = Vector2(TAP_SIZE, TAP_SIZE)
	settings_text_size.add_item(tr("기본"))
	settings_text_size.add_item(tr("크게"))
	settings_text_size.item_selected.connect(_change_text_size)
	column.add_child(settings_text_size)
	settings_message = _label("")
	column.add_child(settings_message)
	if with_licenses:
		_build_licenses(column)
	_ensure_tap_sizes()
	sync_controls()


func _build_licenses(column: VBoxContainer) -> void:
	licenses_button = Button.new()
	licenses_button.text = tr("오픈 소스 라이선스")
	licenses_button.custom_minimum_size.y = TAP_SIZE
	licenses_button.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	licenses_button.pressed.connect(_show_licenses)
	column.add_child(licenses_button)
	licenses_dialog = AcceptDialog.new()
	licenses_dialog.title = tr("오픈 소스 라이선스")
	licenses_dialog.ok_button_text = tr("닫기")
	add_child(licenses_dialog)
	licenses_body = RichTextLabel.new()
	licenses_body.custom_minimum_size = Vector2(0, 200)
	licenses_body.bbcode_enabled = false
	licenses_body.selection_enabled = true
	licenses_dialog.add_child(licenses_body)


## Opens the settings dialog. Callers do not await it: the second frame only re-centers the dialog
## once its contents have their size.
func open() -> void:
	sync_controls()
	settings_dialog.popup_centered_clamped(DIALOG_SIZE)
	_ensure_tap_sizes()
	_ensure_tap_sizes.call_deferred()
	await get_tree().process_frame
	if settings_dialog.visible:
		settings_dialog.size = DIALOG_SIZE
		settings_dialog.popup_centered_clamped(DIALOG_SIZE)


func set_message(kind: String, reason: String = "") -> void:
	message_kind = kind
	message_reason = reason
	_refresh_message()


func refresh_strings() -> void:
	settings_dialog.title = tr("설정")
	settings_dialog.ok_button_text = tr("닫기")
	settings_locale_label.text = tr("언어")
	settings_sound.text = tr("효과음")
	settings_text_size_label.text = tr("글자 크기")
	settings_text_size.set_item_text(0, tr("기본"))
	settings_text_size.set_item_text(1, tr("크게"))
	if licenses_dialog != null:
		licenses_button.text = tr("오픈 소스 라이선스")
		licenses_dialog.title = tr("오픈 소스 라이선스")
		licenses_dialog.ok_button_text = tr("닫기")
		licenses_body.add_theme_font_size_override("normal_font_size", preferences.font_size(LABEL_FONT_SIZE))
		if licenses_dialog.visible:
			licenses_body.text = LicenseNotices.text()
	_refresh_message()
	_ensure_tap_sizes()
	_ensure_tap_sizes.call_deferred()


func sync_controls() -> void:
	var values := preferences.snapshot()
	settings_locale.select(0 if values.locale == "ko" else 1)
	settings_sound.set_pressed_no_signal(values.sound_enabled)
	settings_text_size.select(0 if values.text_size == "normal" else 1)
	var popup_font_size := 32 if values.text_size == "large" else 26
	for picker: OptionButton in [settings_locale, settings_text_size]:
		picker.get_popup().add_theme_font_size_override("font_size", popup_font_size)
		picker.get_popup().add_theme_constant_override("v_separation", 32)


func _show_licenses() -> void:
	settings_dialog.hide()
	licenses_body.text = LicenseNotices.text()
	licenses_body.add_theme_font_size_override("normal_font_size", preferences.font_size(LABEL_FONT_SIZE))
	licenses_body.scroll_to_line(0)
	licenses_dialog.popup_centered_clamped(LICENSES_DIALOG_SIZE)
	_ensure_tap_sizes()
	_ensure_tap_sizes.call_deferred()


func _change_locale(index: int) -> void:
	_update_settings({"locale": "ko" if index == 0 else "en"})


func _change_sound(enabled: bool) -> void:
	_update_settings({"sound_enabled": enabled})


func _change_text_size(index: int) -> void:
	_update_settings({"text_size": "normal" if index == 0 else "large"})


func _update_settings(changes: Dictionary) -> void:
	var result := preferences.update_settings(changes)
	set_message("saved" if result.accepted else "error", result.reason)
	sync_controls()


func _refresh_message() -> void:
	match message_kind:
		"saved":
			settings_message.text = tr("설정 저장 완료")
		"error":
			settings_message.text = _error_text(message_reason)
		_:
			settings_message.text = ""


func _error_text(reason: String) -> String:
	if reason in ["future_version", "unsupported_version"]:
		return tr("이 앱에서 지원하지 않는 설정 파일입니다. 기존 파일을 보존합니다.")
	return tr("설정을 저장하거나 읽지 못했습니다. 기존 설정을 유지합니다.")


func _ensure_tap_sizes() -> void:
	for dialog: AcceptDialog in [settings_dialog, licenses_dialog]:
		if dialog == null:
			continue
		dialog.add_theme_constant_override("buttons_min_height", TAP_SIZE)
		dialog.add_theme_constant_override("buttons_min_width", TAP_SIZE)
		var button := dialog.get_ok_button()
		button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, TAP_SIZE), TAP_SIZE)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	return label
