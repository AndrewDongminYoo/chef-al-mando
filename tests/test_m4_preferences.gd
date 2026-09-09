extends "res://tests/harness.gd"

const SettingsStore := preload("res://persistence/settings_store.gd")
const AppPreferences := preload("res://presentation/app_preferences.gd")


class FailedStore extends SettingsStore:
	var failure: String = ""

	func _write_text(target: String, text: String) -> Error:
		if failure == "write" and target == file_path + ".tmp":
			return ERR_CANT_CREATE
		if failure == "invalid_temp" and target == file_path + ".tmp":
			return super._write_text(target, "broken temporary file")
		return super._write_text(target, text)

	func _replace_file(source: String, target: String) -> Error:
		if failure == "replace" and target == file_path:
			return ERR_CANT_CREATE
		return super._replace_file(source, target)


func run(tree: SceneTree) -> void:
	var directory := "user://test_m4_preferences_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "M4 preferences fixture directory is created")
	var file_path := directory + "/settings.json"
	_test_store(file_path)
	_test_failed_load_locale(file_path)
	await _test_preferences(tree, file_path)
	_test_translation()
	_cleanup(directory)


func _test_store(file_path: String) -> void:
	var defaults: Dictionary = SettingsStore.new(file_path).load_settings()
	expect(defaults.accepted and defaults.reason == "defaults"
		and defaults.values == {"locale": "ko", "sound_enabled": true, "text_size": "normal"},
		"a missing settings file returns the exact defaults")
	var values := {"locale": "en", "sound_enabled": false, "text_size": "large"}
	var saved: Dictionary = SettingsStore.new(file_path).save_settings(values)
	expect(saved.accepted and saved.values == values, "validated settings save to the primary file")
	var fresh: Dictionary = SettingsStore.new(file_path).load_settings()
	expect(fresh.accepted and fresh.reason == "loaded" and fresh.values == values,
		"a new settings store reads the saved values from disk")
	var original_bytes := FileAccess.get_file_as_bytes(file_path)
	for invalid: Dictionary in [
		{"locale": "ja", "sound_enabled": true, "text_size": "normal"},
		{"locale": "en", "sound_enabled": "false", "text_size": "normal"},
		{"locale": "ko", "sound_enabled": true, "text_size": 120},
		{"locale": &"en", "sound_enabled": true, "text_size": "normal"},
		{"locale": "ko", "sound_enabled": true, "text_size": &"large"},
		{"locale": "ko", "sound_enabled": true, "text_size": "normal", "extra": true},
	]:
		var rejected: Dictionary = SettingsStore.new(file_path).save_settings(invalid)
		expect(not rejected.accepted and rejected.reason == "invalid_settings"
			and FileAccess.get_file_as_bytes(file_path) == original_bytes,
			"invalid settings preserve the primary bytes: " + str(invalid))
	for failure: String in ["write", "invalid_temp", "replace"]:
		var target := file_path + "." + failure
		expect(SettingsStore.new(target).save_settings(values).accepted,
			"settings failure fixture writes a baseline: " + failure)
		var bytes := FileAccess.get_file_as_bytes(target)
		var failing := FailedStore.new(target)
		failing.failure = failure
		var failed: Dictionary = failing.save_settings({"locale": "ko", "sound_enabled": true, "text_size": "normal"})
		expect(not failed.accepted and FileAccess.get_file_as_bytes(target) == bytes,
			"a settings write failure preserves primary bytes: " + failure)
	_write(file_path, JSON.stringify({"schema_version": 99, "locale": "en", "sound_enabled": false, "text_size": "large"}))
	original_bytes = FileAccess.get_file_as_bytes(file_path)
	var future: Dictionary = SettingsStore.new(file_path).load_settings()
	expect(not future.accepted and future.reason == "future_version", "a future settings file is rejected")
	var protected: Dictionary = SettingsStore.new(file_path).save_settings(values)
	expect(not protected.accepted and protected.reason == "future_version"
		and FileAccess.get_file_as_bytes(file_path) == original_bytes,
		"a future settings file is never overwritten")


func _test_failed_load_locale(file_path: String) -> void:
	for fixture: Dictionary in [
		{"label": "corrupt", "text": "not valid json", "reason": "corrupt_settings"},
		{"label": "future", "text": "{\"schema_version\":99,\"locale\":\"en\",\"sound_enabled\":false,\"text_size\":\"large\"}",
			"reason": "future_version"},
	]:
		var target: String = file_path + "." + fixture.label + "-load"
		_write(target, fixture.text)
		var original_bytes := FileAccess.get_file_as_bytes(target)
		TranslationServer.set_locale("en")
		var preferences := AppPreferences.new(target)
		var loaded: Dictionary = preferences.load_settings()
		expect(not loaded.accepted and loaded.reason == fixture.reason,
			"a failed preference load returns its original failure: " + fixture.label)
		expect(preferences.snapshot() == {"locale": "ko", "sound_enabled": true, "text_size": "normal"},
			"a failed preference load publishes the literal default snapshot: " + fixture.label)
		expect(TranslationServer.get_locale() == "ko",
			"a failed preference load applies the default Korean locale: " + fixture.label)
		expect(FileAccess.get_file_as_bytes(target) == original_bytes,
			"a failed preference load preserves the original file bytes: " + fixture.label)
	TranslationServer.set_locale("ko")


func _test_preferences(tree: SceneTree, file_path: String) -> void:
	var preferences := AppPreferences.new(file_path + ".preferences")
	var change_count := {"value": 0}
	preferences.changed.connect(func() -> void: change_count.value += 1)
	TranslationServer.set_locale("en")
	var loaded: Dictionary = preferences.load_settings()
	expect(loaded.accepted and preferences.snapshot().locale == "ko" and TranslationServer.get_locale() == "ko",
		"preferences load applies the stored locale")
	TranslationServer.set_locale("ko")
	var changed: Dictionary = preferences.update_settings({"locale": "en", "text_size": "large"})
	expect(changed.accepted and change_count.value == 1 and TranslationServer.get_locale() == "en"
		and preferences.snapshot() == {"locale": "en", "sound_enabled": true, "text_size": "large"},
		"a persisted preference update changes the snapshot and emits once")
	TranslationServer.set_locale("ko")
	var restored := AppPreferences.new(file_path + ".preferences")
	var restored_load: Dictionary = restored.load_settings()
	expect(restored_load.accepted and restored.snapshot().locale == "en" and TranslationServer.get_locale() == "en",
		"a fresh preferences object restores the saved locale")
	expect(preferences.font_size(25) == 30, "large text uses a 120 percent font size")
	var root := Control.new()
	root.add_theme_font_size_override("font_size", 20)
	var static_label := Label.new()
	static_label.add_theme_font_size_override("font_size", 15)
	root.add_child(static_label)
	tree.root.add_child(root)
	preferences.apply_to(root)
	expect(root.get_theme_font_size("font_size") == 24 and static_label.get_theme_font_size("font_size") == 18
		and root.scale == Vector2.ONE and static_label.scale == Vector2.ONE,
		"large text changes static font sizes without scaling controls")
	preferences.apply_to(root)
	expect(root.get_theme_font_size("font_size") == 24 and static_label.get_theme_font_size("font_size") == 18,
		"repeated font application does not compound font sizes")
	var dynamic_label := Label.new()
	root.add_child(dynamic_label)
	var dynamic_base := dynamic_label.get_theme_font_size("font_size")
	var label_theme := Theme.new()
	label_theme.set_font_size(&"font_size", &"Label", 13)
	var themed_label := Label.new()
	themed_label.theme = label_theme
	root.add_child(themed_label)
	var themed_base := themed_label.get_theme_font_size("font_size")
	expect(themed_base == 13, "the label theme fixture resolves its independent baseline")
	var button_theme := Theme.new()
	button_theme.set_font_size(&"font_size", &"Button", 17)
	var themed_button := Button.new()
	themed_button.theme = button_theme
	root.add_child(themed_button)
	var themed_button_base := themed_button.get_theme_font_size("font_size")
	expect(themed_button_base == 17, "the button theme fixture resolves its independent baseline")
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "실제 대화 상자 본문"
	var dialog_label := Label.new()
	dialog.add_child(dialog_label)
	root.add_child(dialog)
	var dialog_label_base := dialog_label.get_theme_font_size("font_size")
	var dialog_button_base := dialog.get_ok_button().get_theme_font_size("font_size")
	var dialog_body := _find_text_label(dialog, dialog.dialog_text)
	expect(dialog_body != null, "the dialog fixture exposes its native body label")
	var dialog_body_base := dialog_body.get_theme_font_size("font_size") if dialog_body != null else 0
	var confirmation := ConfirmationDialog.new()
	confirmation.dialog_text = "확인 대화 상자 본문"
	root.add_child(confirmation)
	var confirmation_body := _find_text_label(confirmation, confirmation.dialog_text)
	expect(confirmation_body != null, "the confirmation fixture exposes its native body label")
	var confirmation_body_base := confirmation_body.get_theme_font_size("font_size") if confirmation_body != null else 0
	var cancel_button_base := confirmation.get_cancel_button().get_theme_font_size("font_size")
	preferences.apply_to(root)
	expect(dynamic_label.get_theme_font_size("font_size") == preferences.font_size(dynamic_base)
		and themed_label.get_theme_font_size("font_size") == 16
		and themed_button.get_theme_font_size("font_size") == 21
		and dialog_label.get_theme_font_size("font_size") == preferences.font_size(dialog_label_base)
		and dialog.get_ok_button().get_theme_font_size("font_size") == preferences.font_size(dialog_button_base),
		"font application uses each runtime control baseline and includes dialog buttons")
	expect(dialog_body != null and dialog_body.get_theme_font_size("font_size") == preferences.font_size(dialog_body_base)
		and confirmation_body != null and confirmation_body.get_theme_font_size("font_size") == preferences.font_size(confirmation_body_base)
		and confirmation.get_cancel_button().get_theme_font_size("font_size") == preferences.font_size(cancel_button_base),
		"font application includes native dialog text and confirmation cancel buttons")
	var normalized: Dictionary = preferences.update_settings({"text_size": "normal"})
	preferences.apply_to(root)
	expect(normalized.accepted
		and root.get_theme_font_size("font_size") == 20 and static_label.get_theme_font_size("font_size") == 15
		and dynamic_label.get_theme_font_size("font_size") == dynamic_base and not dynamic_label.has_theme_font_size_override("font_size")
		and themed_label.get_theme_font_size("font_size") == 13 and themed_button.get_theme_font_size("font_size") == 17
		and confirmation_body != null and confirmation_body.get_theme_font_size("font_size") == confirmation_body_base
		and confirmation.get_cancel_button().get_theme_font_size("font_size") == cancel_button_base
		and not themed_label.has_theme_font_size_override("font_size") and not themed_button.has_theme_font_size_override("font_size"),
		"normal text restores dynamic and overridden font sizes")
	var failing := FailedStore.new(file_path + ".preferences")
	failing.failure = "write"
	preferences.store = failing
	var rejected: Dictionary = preferences.update_settings({"sound_enabled": false})
	expect(not rejected.accepted and change_count.value == 2 and preferences.snapshot().sound_enabled,
		"a failed preference write leaves current settings and emits no change")
	root.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_translation() -> void:
	TranslationServer.set_locale("en")
	expect(TranslationServer.translate("Chef al Mando · 영업 목록") == "Chef al Mando · Service list"
		and TranslationServer.translate("준비 시작") == "Start preparation"
		and TranslationServer.translate("주문을 선택하세요") == "Select an order",
		"native English translation returns independent expected phrases")
	TranslationServer.set_locale("ko")
	expect(TranslationServer.translate("준비 시작") == "준비 시작", "translation tests restore Korean locale")


func _write(target: String, text: String) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_text_label(node: Node, text: String) -> Label:
	for child: Node in node.get_children(true):
		if child is Label and child.text == text:
			return child
		var found := _find_text_label(child, text)
		if found != null:
			return found
	return null


func _cleanup(directory: String) -> void:
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	expect(DirAccess.remove_absolute(directory) == OK, "M4 preferences fixtures are removed")
