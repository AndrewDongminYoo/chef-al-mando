extends RefCounted

const SettingsStore := preload("res://persistence/settings_store.gd")

signal changed

var store: SettingsStore
var current: Dictionary = SettingsStore.DEFAULTS.duplicate()


func _init(target: String = "user://settings.json") -> void:
	store = SettingsStore.new(target)


func load_settings() -> Dictionary:
	var loaded := store.load_settings()
	if loaded.accepted:
		current = loaded.values.duplicate()
	TranslationServer.set_locale(current.locale)
	return loaded


func update_settings(changes: Dictionary) -> Dictionary:
	var next := current.duplicate()
	for key: Variant in changes:
		if not next.has(key):
			return {"accepted": false, "reason": "invalid_settings", "values": current.duplicate()}
		next[key] = changes[key]
	var saved := store.save_settings(next)
	if not saved.accepted:
		return saved
	current = saved.values.duplicate()
	TranslationServer.set_locale(current.locale)
	changed.emit()
	return saved


func snapshot() -> Dictionary:
	return current.duplicate()


func font_size(base: int) -> int:
	return ceili(float(base) * 1.2) if current.text_size == "large" else base


func apply_to(root: Control) -> void:
	TranslationServer.set_locale(current.locale)
	_apply_node(root)


func _apply_node(node: Node) -> void:
	if node is Control:
		_apply_font_size(node)
	for child: Node in node.get_children(true):
		_apply_node(child)


func _apply_font_size(control: Control) -> void:
	var base_key := &"m4_base_font_size"
	var override_key := &"m4_had_font_size_override"
	if not control.has_meta(base_key):
		var base := control.get_theme_font_size("font_size")
		control.set_meta(base_key, base)
		control.set_meta(override_key, control.has_theme_font_size_override("font_size"))
	var base_size := int(control.get_meta(base_key))
	if current.text_size == "large":
		control.add_theme_font_size_override("font_size", font_size(base_size))
	elif bool(control.get_meta(override_key)):
		control.add_theme_font_size_override("font_size", base_size)
	else:
		control.remove_theme_font_size_override("font_size")
