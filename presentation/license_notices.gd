extends RefCounted


static func text() -> String:
	var sections: PackedStringArray = ["Godot Engine", Engine.get_license_text(),
		TranslationServer.translate("Godot 엔진 소스: %s") % "https://github.com/godotengine/godot",
		TranslationServer.translate("Godot 라이선스: %s") % "https://godotengine.org/license/",
		TranslationServer.translate("제삼자 구성요소")]
	for component: Dictionary in Engine.get_copyright_info():
		sections.append(component.name)
		for part: Dictionary in component.parts:
			sections.append("\n".join(PackedStringArray(part.files)))
			sections.append("\n".join(PackedStringArray(part.copyright)))
			sections.append(part.license)
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for license_name: String in names:
		sections.append(license_name + "\n" + str(licenses[license_name]))
	return "\n\n".join(sections)
