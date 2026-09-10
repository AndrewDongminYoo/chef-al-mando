extends "res://tests/harness.gd"

const PreparationPlan := preload("res://sim/preparation_plan.gd")
const PreparationPanel := preload("res://presentation/preparation_panel.gd")


func run(tree: SceneTree) -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ko")
	var data = load("res://content/m2_first_service.tres").duplicate(true)
	data.space_rules = true
	data.stations[3].fixed = true
	var plan := PreparationPlan.new(data)
	var panel := PreparationPanel.new()
	tree.root.add_child(panel)
	panel.setup(data)
	panel.refresh(plan.snapshot())
	panel.select_station("pass_01")
	var preview: Variant = panel.get("placement_preview")
	expect(preview is Label, "spatial preparation shows placement rules before a tap")
	if preview is Label:
		expect(preview.text.contains("작업 위치") and preview.text.contains("냉식대"), "placement preview explains shared work positions and cold-hot clearance")
		expect(preview.text.contains("고정"), "fixed-station preview explains why movement is unavailable")
	expect(panel.move_buttons.left.disabled and panel.move_buttons.rotate.disabled, "fixed station controls reflect the preview before input")
	plan.apply_command({"kind": "move_station", "target_id": "hot_01", "value": "left", "apply_tick": 0, "sequence": 1})
	panel.refresh(plan.snapshot())
	panel.select_station("hot_01")
	expect(panel.move_buttons.left.disabled and not panel.move_buttons.right.disabled, "only the direction that breaks clearance is disabled")
	if preview is Label:
		expect(preview.text.contains("냉식대와 화구 사이"), "the invalid direction names its clearance rule")
	panel.queue_free()
	await tree.process_frame
	TranslationServer.set_locale(previous_locale)
