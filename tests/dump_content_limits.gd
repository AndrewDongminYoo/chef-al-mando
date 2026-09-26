extends SceneTree

## Prints this tree's save-compatibility limits as one row for tests/fixtures/content_limits.gd.
## After a content version bump, run it from the repository root and append the printed row (without
## its line marker) to ROWS; a tree that was never imported (a fresh clone) needs the first line:
##   "$GODOT_BIN" --headless --path . --import
##   "$GODOT_BIN" --headless --path . --script res://tests/dump_content_limits.gd | sed -n 's/^CONTENT_LIMITS_ROW //p'
## It also runs unchanged against an older tree (--path <extracted commit> --script <absolute path>,
## after the same --import), so it only reads what every shipped content version had: no preloads, no
## typed content classes. The row keeps the campaign's service order, which validate_records checks.

const CAMPAIGN_PATH := "res://content/campaign/campaign.tres"
const STORE_PATH := "res://persistence/campaign_store.gd"
const ROW_MARKER := "CONTENT_LIMITS_ROW "


func _initialize() -> void:
	var store: GDScript = load(STORE_PATH)
	var campaign: Resource = load(CAMPAIGN_PATH)
	if store == null or campaign == null:
		push_error("dump_content_limits: cannot load the campaign or the store; run --import on this tree first")
		quit(1)
		return
	var row := limits_row(campaign, store.get_script_constant_map().VERSIONS.content_version)
	for line: String in format_row(row).split("\n"):
		print(ROW_MARKER + line)
	quit(0)


## The per-service limits CampaignProgress.validate_records reads: order_count, starting_budget,
## the target pair, and maximum_profit(served) for every served count from 0 to order_count.
static func limits_row(campaign: Resource, content_version: int) -> Dictionary:
	var scenarios := {}
	for scenario: Resource in campaign.scenarios:
		var caps: Array = []
		for served: int in scenario.order_count + 1:
			caps.append(scenario.maximum_profit(served))
		scenarios[scenario.id] = {
			"order_count": scenario.order_count,
			"starting_budget": scenario.starting_budget,
			"minimum_served": scenario.minimum_served,
			"minimum_profit": scenario.minimum_profit,
			"maximum_profit": caps
		}
	return {"content_version": content_version, "scenarios": scenarios}


static func format_row(row: Dictionary) -> String:
	var lines: PackedStringArray = ['\t{"content_version": %d, "scenarios": {' % row.content_version]
	for scenario_id: String in row.scenarios:
		lines.append('\t\t"%s": %s,' % [scenario_id, str(row.scenarios[scenario_id])])
	lines.append("\t}},")
	return "\n".join(lines)
