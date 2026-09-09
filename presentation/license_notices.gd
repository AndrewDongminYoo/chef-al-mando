extends RefCounted


static func text() -> String:
	var sections: PackedStringArray = ["Godot Engine", Engine.get_license_text(),
		"Godot Engine source: https://github.com/godotengine/godot\nGodot licenses: https://godotengine.org/license/\nThe application icon is derived from the Godot icon.",
		"Third-party components"]
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
