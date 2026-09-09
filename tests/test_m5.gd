extends "res://tests/harness.gd"


func run(tree: SceneTree) -> void:
	var directory := "user://m5_licenses_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "license fixture directory is created")
	var screen: Control = load("res://presentation/campaign.tscn").instantiate()
	screen.set("save_path", directory + "/records.json")
	screen.set("settings_path", directory + "/settings.json")
	tree.root.add_child(screen)
	await tree.process_frame
	var button: Button = screen.get("licenses_button")
	expect(button != null, "settings provides an offline licenses button")
	if button != null:
		screen.get("settings_button").pressed.emit()
		button.pressed.emit()
		await tree.process_frame
		var dialog: AcceptDialog = screen.get("licenses_dialog")
		var body: RichTextLabel = screen.get("licenses_body")
		expect(dialog.visible and body.is_visible_in_tree(), "settings opens the readable license body")
		expect(not body.bbcode_enabled, "license text is displayed without markup interpretation")
		expect(body.text.contains(Engine.get_license_text()), "the complete engine license is displayed")
		for component: Dictionary in Engine.get_copyright_info():
			expect(body.text.contains(component.name), "component name is displayed: " + component.name)
			for part: Dictionary in component.parts:
				for source_file: String in part.files:
					expect(body.text.contains(source_file), "component source file is displayed")
				for owner: String in part.copyright:
					expect(body.text.contains(owner), "component copyright is displayed")
				expect(body.text.contains(part.license), "component license reference is displayed")
		for license_text: String in Engine.get_license_info().values():
			expect(body.text.contains(license_text), "each complete third-party license is displayed")
		expect(body.text.contains("https://github.com/godotengine/godot"), "engine source location is displayed")
		var original_text := body.text
		var scroll := body.get_v_scroll_bar()
		expect(scroll.visible and scroll.max_value > scroll.page, "the full notices exceed the viewport and provide a scrollbar")
		body.scroll_to_line(body.get_line_count() - 1)
		await tree.process_frame
		expect(scroll.value > 0 and scroll.value >= scroll.max_value - scroll.page - 1, "the last license line can be reached by scrolling")
		screen.preferences.update_settings({"locale": "en", "text_size": "large"})
		expect(button.text == "Open source licenses" and dialog.title == "Open source licenses", "license controls update to English")
		expect(body.text == original_text, "localization preserves verbatim license text")
		dialog.get_ok_button().pressed.emit()
		await tree.process_frame
		expect(not dialog.visible, "the license dialog can be closed")
	screen.queue_free()
	await tree.process_frame
	TranslationServer.set_locale("ko")
	for owned_file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory + "/" + owned_file)
	DirAccess.remove_absolute(directory)
