# 수요 예보·미장·리뷰 구현 계획 2a: 미장 항목과 콘텐츠 버전 5

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메뉴별 1:1 손질 재료를 재료 단위 미장 항목으로 바꾸고, 캠페인 재료·메뉴에 실제 식재료 표시명을 붙이며, 콘텐츠 버전을 5로 올려 진행 중 영업을 재시작하되, 프렙 생략 규칙은 "레시피의 미장이 전부 재고에 있을 때만"으로 두어 시뮬레이션 스냅샷 형식을 바꾸지 않습니다.

**Architecture:** 미장 항목은 `IngredientDef`에 `inputs`(소비하는 원재료)와 `labor_units`를 더해 표현하고, 구매 불가이면서 `inputs`가 비어 있지 않은 재료가 미장입니다. 레시피는 `prepared_ingredient_id`·`prep_labor_units` 대신 `mise_ids` 집합을 참조합니다. 준비 계획·시뮬레이션·마감 분석·준비 화면은 프렙 수량을 레시피 ID가 아니라 미장 ID로 다룹니다. 엔진 전환(Task 1~3)은 기존 1:1 콘텐츠를 "항목 하나짜리 미장 집합"으로 옮겨 놓고 진행하므로 모든 기존 검사의 기대값이 그대로이며, 콘텐츠 재구성(Task 4)에서 6종 공유 미장과 실제 이름으로 바꾸고 같은 Task 안에서 시드 0 3전략 게이트를 다시 맞춥니다. 부분 프렙(비율 시간, 혼합 소비)은 계획 2b가 맡습니다.

**Tech Stack:** Godot `4.7.2.stable.official.ed1daf0bf`(`.godot-version`), typed GDScript, headless 검사 `bash scripts/check.sh <suite>`, `tests/harness.gd`의 `expect(condition, message)`, `python3 tests/test_m4_restart.py`.

**Spec:** [docs/specs/mise-forecast-reviews.md](../specs/mise-forecast-reviews.md) §5.1, §5.2, §5.4(항목별 준비·사용·폐기), §7의 준비 화면 미장 목록, §8, §10, §12의 2단계. 선행 계획은 [계획 1](mise-forecast-reviews-implementation.md)입니다.

## Global Constraints

- 원재료 ID `protein`·`vegetable`·`grain`·`mushroom`과 시나리오 참조는 유지하고 `display_name`과 `en.po`만 바꿉니다(§5.1). 메뉴 아이콘은 4단계 화면 계획으로 미룹니다(운영자, 2026-09-20).
- 표시명은 운영자가 2026-09-20 확정한 세트입니다: `protein` 연어, `vegetable` 토마토, `grain` 현미, `mushroom` 양송이. 메뉴 8종은 연어 구이·연어 덮밥·토마토 샐러드·현미 샐러드·양송이 샐러드·토마토 수프·양송이 수프·현미 볶음밥, 미장 6종은 손질 토마토·불린 현미·손질 양송이·토마토 베이스·해동 연어·재운 연어입니다.
- 레시피의 `ingredients` 사전은 바꾸지 않습니다. 미장 항목의 `inputs` 합이 레시피 `ingredients`와 정확히 같아야 하며 콘텐츠 검사가 이를 강제합니다. 따라서 §5.1 제안표에서 두 칸이 조정됩니다: 현미 볶음밥(`grain_grill`)은 해동 연어 대신 손질 양송이를 쓰고, 토마토 베이스는 토마토 2개로만 만듭니다. Task 6이 명세에 이 정정을 기록합니다.
- 미장 항목의 `unit_cost`는 구성 원재료 원가의 합이고, 준비 노동량은 `labor_units × 수량`이며 `prep_labor_capacity` 상한은 유지합니다(§5.1, §5.2).
- 이번 계획의 프렙 생략 규칙은 "레시피의 미장이 **전부** 재고에 있으면 생략하고 전부 소비, 하나라도 없으면 원재료 전량 소비와 전체 `prep` 시간"입니다. §5.3의 비율 시간과 혼합 소비는 계획 2b의 범위이며, 스냅샷 주문 필드(`uses_prepared`, `reserved_inputs`, `raw_consumed`)는 이번 계획에서 바뀌지 않습니다.
- `forecast_slack` 값은 이번 계획에서 하나도 쓰지 않으며 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있고 `service_seed`는 0입니다. 폭 작성은 시드 1~5 풀림 게이트가 풀리지 않는 fixture에서 먼저 실패하는 것을 본 뒤에만 시작하며, 그 게이트와 폭 작성은 계획 2b 뒤의 콘텐츠 계획에 둡니다(계획 1 "다음 계획"과 메모리 `mise-loop-state`의 합의점).
- 콘텐츠 버전은 5, 저장 스키마는 4 그대로입니다. 버전 1~4 문서는 읽기만으로 바꾸지 않고 다음 정상 저장에서 5로 갱신하며, 버전 4 이하의 진행 중 영업은 모든 시나리오에서 재시작합니다(§8). `prng_state`는 계속 `null`입니다.
- 3전략·무계획 격차 게이트(`check.sh m3`)는 시드 0에서 그대로 통과해야 합니다(§10 첫 행). 목표값(`minimum_served`·`minimum_profit`)은 낮추지 않습니다(`PLAN.md` §12).
- 캠페인은 메뉴 8종, 재료 정의 12개 이하입니다(`campaign_def.gd`). 재구성 뒤는 원재료 4 + 미장 6 = 10입니다.
- 세션에 들어가는 사전은 `dict["key"] = value`로만 씁니다. `dict.key = value`는 `StringName` 키를 만들어 `ServiceSession._normalize_json`이 거부합니다(PR #24 라운드 2).
- 검사 fixture를 변형할 때 typed export(`Dictionary[String, int]`)에는 typed 지역 변수만 `set()`합니다. untyped 사전 리터럴을 `set()`하면 Godot 4.7.2는 오류 없이 `{}`를 남깁니다(2026-09-20 headless probe: `recipe.set("ingredients", {"grain": 1})` 뒤 `get`이 `{}`, typed 변수는 값이 남음). `ResourceLoader.CACHE_MODE_IGNORE_DEEP`은 4.7.2에 있습니다(같은 probe, 값 3).
- 새 검사는 잘못된 입력에서 먼저 실패하는 것을 확인한 뒤 통과시킵니다(§10). 모든 Godot 호출은 `--headless`이며 suite는 한 번에 하나만 실행합니다(Mac mini 규칙).
- 문서와 사용자 문구는 한국어, 코드 식별자와 커밋 메시지는 영어입니다. 커밋에 `Co-Author`나 세션 URL을 붙이지 않습니다.
- 검사 명령: `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` 뒤에 `bash scripts/check.sh mise`, `bash scripts/check.sh m2`, `bash scripts/check.sh m3`, `bash scripts/check.sh m4`, `bash scripts/check.sh ui-regressions`, `bash scripts/check-export.sh`.

---

## 파일 구조

| 파일                                                                                              | 책임                                                                                                   |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `content/ingredient_def.gd`                                                                       | `inputs`·`labor_units` export와 `is_mise()`                                                            |
| `content/recipe_def.gd`                                                                           | `mise_ids` export, `prepared_ingredient_id`·`prep_labor_units` 제거(Task 3)                            |
| `content/definitions.gd`                                                                          | 미장 항목·레시피 집합 검증, `mise_items()`, `menu_count_for()`, `supports_preparation()`               |
| `content/scenario_def.gd`                                                                         | 판매 메뉴의 빈 미장 집합과 어떤 메뉴도 쓰지 않는 미장을 거부                                           |
| `content/campaign_def.gd`                                                                         | 재료·레시피 서명에 `inputs`·`labor_units`·`mise_ids` 반영                                              |
| `content/m2_first_service.tres`                                                                   | M2 fixture의 손질 재료 3종을 항목 하나짜리 미장으로 표현(이름은 그대로)                                |
| `content/campaign/ingredients/*.tres`                                                             | Task 1: `prepped_*` 8종에 `inputs`·`labor_units` 이전. Task 4: 6종 미장으로 교체, 원재료 4종 이름 변경 |
| `content/campaign/recipes/*.tres`                                                                 | Task 1: `mise_ids` 추가. Task 3: 옛 필드 삭제. Task 4: 공유 미장 집합과 새 이름                        |
| `content/campaign/scenarios/*.tres`                                                               | Task 4: 재료 배열을 미장 6종으로 교체, 브리핑 4건 수정                                                 |
| `sim/preparation_plan.gd`                                                                         | `set_prep` 대상 미장 ID, 노동량·원재료 소비를 항목 기준으로, `mise_ready()`                            |
| `sim/service_sim.gd`                                                                              | 미장 집합의 예약·소비, 항목별 `prepared_stock_depleted`, 복원 검증의 기대 입력                         |
| `sim/service_analysis.gd`                                                                         | 미장 항목별 준비·사용·폐기 행과 권고                                                                   |
| `presentation/preparation_panel.gd`, `presentation/main.gd`                                       | 미장 목록(이름·메뉴 수·원가·노동량·수량), 요약·권고·말풍선 문구                                        |
| `persistence/campaign_store.gd`                                                                   | 콘텐츠 버전 5, 버전 4 이하의 진행 중 영업 재시작                                                       |
| `tests/check_m4_restart.gd`, `tests/test_m4_restart.py`                                           | 콘텐츠가 낮은 writer PCK의 기록 보존·영업 재시작·버전 갱신                                             |
| `tests/test_mise_items.gd` (신규), `tests/test_mise.gd`                                           | 미장 콘텐츠 검사·준비·회계 검사와 mise suite 등록                                                      |
| `tests/fixtures/m3_policies.gd`, `tests/fixtures/space_experiment.gd`                             | 프렙 정책을 미장 ID로 번역, 시드 0 게이트 재조정                                                       |
| `translations/en.po`                                                                              | 새 이름·문구 msgid, 사라진 msgid 정리                                                                  |
| `docs/specs/mise-forecast-reviews.md`, `docs/notes/kitchen-pressure-verification.md`, `AGENTS.md` | 정정 기록과 게이트 재조정 값                                                                           |

---

### Task 1: 미장 항목 정의와 콘텐츠 검증

**Files:**

- Modify: `content/ingredient_def.gd`
- Modify: `content/recipe_def.gd`
- Modify: `content/definitions.gd:59-95` (레시피 준비 검증 블록), `content/definitions.gd:150-156` (`supports_preparation`)
- Modify: `content/scenario_def.gd:20-26`
- Modify: `content/campaign_def.gd:31-46`
- Modify: `content/m2_first_service.tres`, `content/campaign/ingredients/prepped_*.tres` (8개), `content/campaign/recipes/*.tres` (8개)
- Create: `tests/test_mise_items.gd`
- Modify: `tests/test_mise.gd:4`

**Interfaces:**

- Produces: `IngredientDef.inputs: Dictionary[String, int]`, `IngredientDef.labor_units: int`, `IngredientDef.is_mise() -> bool`, `RecipeDef.mise_ids: PackedStringArray`, `Definitions.mise_items() -> Array[IngredientDef]`(재료 배열 순서), `Definitions.menu_count_for(mise_id: String) -> int`.
- 이 Task에서는 `RecipeDef.prepared_ingredient_id`와 `prep_labor_units`를 남기고, 전환 검사로 두 표현이 같은지 확인합니다. Task 3이 옛 필드를 지웁니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`를 만들고 `tests/test_mise.gd`의 `SUITES`에 `"res://tests/test_mise_items.gd"`를 추가합니다.

```gdscript
extends "res://tests/harness.gd"

const FIXTURE := "res://content/m2_first_service.tres"


func run(_tree: SceneTree) -> void:
	_test_mise_definitions()


func _fixture() -> Resource:
	return ResourceLoader.load(FIXTURE, "", ResourceLoader.CACHE_MODE_IGNORE)


func _ingredient(data: Resource, ingredient_id: String) -> Resource:
	return data.call("ingredient_for", ingredient_id)


## Typed exports ignore an untyped literal passed to set(), so fixtures assign through this.
static func _typed_inputs(values: Dictionary) -> Dictionary[String, int]:
	var typed: Dictionary[String, int] = {}
	typed.assign(values)
	return typed


func _test_mise_definitions() -> void:
	var data := _fixture()
	expect(data.call("validate").is_empty(), "the M2 fixture validates as one-item mise sets")
	expect(_ingredient(data, "prepped_salad").call("is_mise") and not _ingredient(data, "vegetable").call("is_mise"),
		"a non-purchasable ingredient with inputs is a mise item and a raw ingredient is not")
	var items: Array = data.call("mise_items")
	var item_ids: Array[String] = []
	for item: Resource in items:
		item_ids.append(item.get("id"))
	expect(item_ids == ["prepped_salad", "prepped_soup", "prepped_grill"], "mise_items keeps the ingredient array order")  # content/m2_first_service.tres:237
	expect(data.call("menu_count_for", "prepped_salad") == 1 and data.call("menu_count_for", "vegetable") == 0,
		"menu_count_for counts sale menus that reference the item")

	var wrong_cost := _fixture()
	_ingredient(wrong_cost, "prepped_soup").set("unit_cost", 351)
	expect(_has_error(wrong_cost, "mise cost must equal its raw input cost: prepped_soup"), "mise cost must equal the raw input cost")

	var raw_with_inputs := _fixture()
	_ingredient(raw_with_inputs, "vegetable").set("inputs", _typed_inputs({"grain": 1}))
	expect(_ingredient(raw_with_inputs, "vegetable").get("inputs") == _typed_inputs({"grain": 1}), "the typed set lands on the fixture")
	expect(_has_error(raw_with_inputs, "raw ingredients cannot have inputs or labor: vegetable"), "raw ingredients cannot carry inputs")

	var no_labor := _fixture()
	_ingredient(no_labor, "prepped_grill").set("labor_units", 0)
	expect(_has_error(no_labor, "mise items need inputs and labor: prepped_grill"), "a mise item needs positive labor")

	var unknown_item := _fixture()
	unknown_item.call("recipe_for", "salad").set("mise_ids", PackedStringArray(["prepped_salad", "missing"]))
	expect(_has_error(unknown_item, "invalid recipe mise item: salad"), "unknown mise references are rejected")

	var duplicate_item := _fixture()
	duplicate_item.call("recipe_for", "salad").set("mise_ids", PackedStringArray(["prepped_salad", "prepped_salad"]))
	expect(_has_error(duplicate_item, "invalid recipe mise item: salad"), "duplicate mise references are rejected")

	var mismatched_inputs := _fixture()
	mismatched_inputs.call("recipe_for", "soup").set("mise_ids", PackedStringArray(["prepped_salad"]))
	expect(_has_error(mismatched_inputs, "recipe ingredients must equal the raw inputs of its mise items: soup"),
		"the mise input sum must equal the recipe ingredients")

	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	expect(campaign.call("validate").is_empty(), "the campaign validates with one-item mise sets")
	var empty_menu: Resource = campaign.call("scenario_for", "first_shift")
	empty_menu.call("recipe_for", "salad").set("mise_ids", PackedStringArray())
	empty_menu.call("recipe_for", "salad").set("prepared_ingredient_id", "")
	empty_menu.call("recipe_for", "salad").set("prep_labor_units", 0)
	expect("campaign menu needs mise items: salad" in empty_menu.call("validate"), "a campaign menu without mise items is rejected")
	expect("unused mise item: prepped_salad" in empty_menu.call("validate"), "a mise item no sale menu uses is rejected")


func _has_error(data: Resource, message: String) -> bool:
	return message in data.call("validate")
```

`first_shift`의 레시피 리소스는 다른 시나리오와 공유되는 `ext_resource`이므로, 변형하는 캠페인은 `CACHE_MODE_IGNORE_DEEP`으로 읽어 같은 프로세스의 다른 suite가 보는 캐시를 건드리지 않습니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `is_mise`·`mise_items`·`menu_count_for`가 없어 `SCRIPT ERROR` 또는 `Invalid call`이 납니다.

- [ ] **Step 3: 정의와 검증 구현**

`content/ingredient_def.gd`:

```gdscript
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var unit_cost: int = 0
@export var purchasable: bool = true
## 미장 항목 하나를 만들 때 소비하는 원재료와 수량. 원재료는 비어 있습니다.
@export var inputs: Dictionary[String, int] = {}
## 미장 항목 하나를 만드는 준비 노동량. 원재료는 0입니다.
@export var labor_units: int = 0


func is_mise() -> bool:
	return not purchasable and not inputs.is_empty()
```

`content/recipe_def.gd`의 export 목록에 `prepared_ingredient_id` 앞에 추가합니다.

```gdscript
## 이 메뉴가 쓰는 미장 항목 ID 집합. 전부 재고에 있을 때만 prep 공정을 생략합니다.
@export var mise_ids: PackedStringArray = PackedStringArray()
```

`content/definitions.gd`의 `validate()`에서 재료 루프(`ingredient_ids` 채우는 곳)를 아래로 바꿉니다.

```gdscript
	var ingredient_ids: Dictionary[String, bool] = {}
	for ingredient: IngredientDef in ingredients:
		if ingredient == null:
			continue
		ingredient_ids[ingredient.id] = true
		if ingredient.unit_cost < 0:
			errors.append("negative ingredient cost: " + ingredient.id)
	for ingredient: IngredientDef in ingredients:
		if ingredient == null:
			continue
		if ingredient.purchasable:
			if not ingredient.inputs.is_empty() or ingredient.labor_units != 0:
				errors.append("raw ingredients cannot have inputs or labor: " + ingredient.id)
			continue
		if ingredient.inputs.is_empty() or ingredient.labor_units <= 0:
			errors.append("mise items need inputs and labor: " + ingredient.id)
		var input_cost: int = 0
		for input_id: String in ingredient.inputs:
			var input := ingredient_for(input_id)
			if input == null or not input.purchasable or ingredient.inputs[input_id] <= 0:
				errors.append("mise inputs must be raw ingredients: " + ingredient.id)
			else:
				input_cost += input.unit_cost * ingredient.inputs[input_id]
		if ingredient.unit_cost != input_cost:
			errors.append("mise cost must equal its raw input cost: " + ingredient.id)
```

레시피 루프의 `var has_preparation := not recipe.prepared_ingredient_id.is_empty()`부터 `elif recipe.prep_labor_units != 0:` 블록 끝까지를 아래로 바꿉니다. 옛 필드 검사는 전환 규칙 한 줄로만 남깁니다.

```gdscript
		var has_preparation := not recipe.mise_ids.is_empty()
		var seen_mise: Dictionary[String, bool] = {}
		var mise_inputs: Dictionary[String, int] = {}
		for mise_id: String in recipe.mise_ids:
			var item := ingredient_for(mise_id)
			if item == null or not item.is_mise() or seen_mise.has(mise_id):
				errors.append("invalid recipe mise item: " + recipe.id)
				continue
			seen_mise[mise_id] = true
			for input_id: String in item.inputs:
				mise_inputs[input_id] = mise_inputs.get(input_id, 0) + item.inputs[input_id]
		if has_preparation and mise_inputs != recipe.ingredients:
			errors.append("recipe ingredients must equal the raw inputs of its mise items: " + recipe.id)
		# Transitional until Task 3 removes the legacy fields: both representations must agree.
		var legacy_ids := PackedStringArray([recipe.prepared_ingredient_id]) if not recipe.prepared_ingredient_id.is_empty() else PackedStringArray()
		var legacy_labor: int = ingredient_for(recipe.prepared_ingredient_id).labor_units if has_preparation and ingredient_for(recipe.prepared_ingredient_id) != null else 0
		if recipe.mise_ids != legacy_ids or recipe.prep_labor_units != legacy_labor:
			errors.append("legacy preparation fields disagree with mise_ids: " + recipe.id)
```

`required_phases`와 `phase_roles`의 `has_preparation` 분기는 그대로 둡니다. `supports_preparation()`은 `not recipe.mise_ids.is_empty()`를 읽게 바꾸고, `ingredient_for` 아래에 두 함수를 추가합니다.

```gdscript
func mise_items() -> Array[IngredientDef]:
	var result: Array[IngredientDef] = []
	for ingredient: IngredientDef in ingredients:
		if ingredient != null and ingredient.is_mise():
			result.append(ingredient)
	return result


func menu_count_for(mise_id: String) -> int:
	var count: int = 0
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe != null and mise_id in recipe.mise_ids:
			count += 1
	return count
```

`content/scenario_def.gd`의 `validate()`에서 `campaign service exceeds the supported limits` 검사 뒤에 추가합니다.

```gdscript
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe != null and recipe.mise_ids.is_empty():
			errors.append("campaign menu needs mise items: " + recipe_id)
	for ingredient: IngredientDef in ingredients:
		if ingredient == null or not ingredient.is_mise():
			continue
		if menu_count_for(ingredient.id) == 0:
			errors.append("unused mise item: " + ingredient.id)
```

`content/campaign_def.gd`의 서명 두 곳을 바꿉니다.

```gdscript
			var signature: Array = [ingredient.display_name, ingredient.unit_cost, ingredient.purchasable,
				ingredient.inputs, ingredient.labor_units]
```

```gdscript
			var signature: Array = [recipe.display_name, recipe.ingredients, recipe.cook_role, recipe.revenue,
				recipe.patience_ticks, Array(recipe.mise_ids), recipe.prepared_ingredient_id, recipe.prep_labor_units,
				recipe.first_process_id, processes]
```

- [ ] **Step 4: 콘텐츠를 항목 하나짜리 미장으로 옮김**

`content/m2_first_service.tres`의 손질 재료 3종과 레시피 3종을 고칩니다. 값은 레시피의 `ingredients`와 `prep_labor_units`를 그대로 옮긴 것입니다.

```plaintext
[sub_resource type="Resource" id="Ingredient_prepped_salad"]
script = ExtResource("ingredient")
id = "prepped_salad"
display_name = "손질한 샐러드 재료"
unit_cost = 100
purchasable = false
inputs = Dictionary[String, int]({"vegetable": 1})
labor_units = 1

[sub_resource type="Resource" id="Ingredient_prepped_soup"]
... unit_cost = 350, purchasable = false
inputs = Dictionary[String, int]({"vegetable": 2, "grain": 1})
labor_units = 2

[sub_resource type="Resource" id="Ingredient_prepped_grill"]
... unit_cost = 400, purchasable = false
inputs = Dictionary[String, int]({"protein": 1})
labor_units = 3
```

각 레시피에는 `prepared_ingredient_id` 줄 앞에 `mise_ids = PackedStringArray("prepped_salad")`(soup은 `"prepped_soup"`, grill은 `"prepped_grill"`)를 추가합니다.

캠페인의 `content/campaign/ingredients/prepped_*.tres` 8개에도 같은 방식으로 `inputs`와 `labor_units`를 추가합니다. 값은 해당 레시피의 현재 `ingredients`와 `prep_labor_units`입니다.

| 파일                          | inputs                                       | labor_units |
| ----------------------------- | -------------------------------------------- | ----------- |
| `prepped_salad.tres`          | `{"vegetable": 1}`                           | 1           |
| `prepped_grain_salad.tres`    | `{"grain": 1, "vegetable": 1}`               | 1           |
| `prepped_mushroom_salad.tres` | `{"mushroom": 1, "vegetable": 1}`            | 1           |
| `prepped_soup.tres`           | `{"grain": 1, "vegetable": 2}`               | 2           |
| `prepped_mushroom_soup.tres`  | `{"mushroom": 1, "vegetable": 2}`            | 2           |
| `prepped_grain_grill.tres`    | `{"grain": 1, "mushroom": 1}`                | 2           |
| `prepped_protein_bowl.tres`   | `{"grain": 1, "protein": 1, "vegetable": 1}` | 2           |
| `prepped_grill.tres`          | `{"protein": 1}`                             | 3           |

`content/campaign/recipes/*.tres` 8개에는 `prepared_ingredient_id` 줄 앞에 `mise_ids = PackedStringArray("<같은 prepped ID>")`를 추가합니다.

- [ ] **Step 5: 통과 확인**

Run: `bash scripts/check.sh mise`
Expected: `PASS: mise checks=... failures=0` (기존 173 + 새 검사 14).

Run: `bash scripts/check.sh m2`, `bash scripts/check.sh m3`
Expected: 둘 다 PASS. 시나리오의 재료 배열이 판매 메뉴의 미장과 정확히 일치하지 않으면 `unused mise item`으로 m3가 실패하며, 그때는 해당 시나리오의 재료 배열을 고칩니다.

- [ ] **Step 6: Commit**

```bash
git add content/ingredient_def.gd content/recipe_def.gd content/definitions.gd content/scenario_def.gd content/campaign_def.gd content/m2_first_service.tres content/campaign/ingredients content/campaign/recipes tests/test_mise_items.gd tests/test_mise.gd
git commit -m "feat(content): define mise items alongside the legacy prepared fields"
```

---

### Task 2: 준비 계획·마감 분석·준비 화면을 미장 ID로 전환

**Files:**

- Modify: `sim/preparation_plan.gd:38-49` (`_defaults`), `:128-132` (`set_prep`), `:255-297` (`initial_state`의 노동량·재고)
- Modify: `sim/service_analysis.gd:7-75` (`build`), `:83-106` (`_prep_recommendation`), `:109-125` (`_valid_prep_change`)
- Modify: `presentation/preparation_panel.gd:97-122`, `:230-234`
- Modify: `presentation/main.gd:757-761`, `:853-860`, `:970-972`
- Modify: `tests/check_export.gd:186-190`, `tests/capture_service_feedback.gd:38`, `tests/capture_m2.gd`, `tests/capture_m3.gd`
- Modify: `tests/test_m2_rules.gd`, `tests/test_m2_content.gd:37`, `tests/test_preparation.gd`, `tests/test_m2_ui.gd`, `tests/test_m4_determinism.gd:281,1024`, `tests/test_service_session.gd`, `tests/test_m4_ui.gd`, `tests/test_space_experiment.gd`, `tests/test_service_feedback.gd`, `tests/fixtures/m3_policies.gd`, `tests/fixtures/space_experiment.gd`
- Modify: `tests/test_mise_items.gd`
- Modify: `translations/en.po`

**Interfaces:**

- Consumes: Task 1의 `is_mise()`, `mise_items()`, `menu_count_for()`, `labor_units`, `inputs`.
- Produces: `set_prep` 명령의 `target_id`는 미장 ID. `PreparationPlan.mise_ready(inventory: Dictionary, recipe: Definitions.RecipeDef) -> bool` (static). 준비 스냅샷과 세션의 `prep_quantities`는 미장 ID를 키로 씁니다. 마감 분석 `report.prep`은 미장 ID를 키로 하고 행에 `labor_units`·`menu_count`가 있으며 `prep_labor_units`는 사라집니다. 권고 `target_id`도 미장 ID입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`에 준비 검사를 추가하고 `run()`에서 호출합니다.

```gdscript
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceAnalysis := preload("res://sim/service_analysis.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func _command(plan: PreparationPlan, kind: String, target: String, value: Variant, sequence: int) -> Dictionary:
	return plan.apply_command({"kind": kind, "target_id": target, "value": value, "apply_tick": 0, "sequence": sequence})


func _test_mise_preparation() -> void:
	var plan := PreparationPlan.new(_fixture())
	expect(plan.snapshot().prep_quantities.keys() == ["prepped_salad", "prepped_soup", "prepped_grill"],
		"preparation quantities are keyed by mise item in ingredient order")  # content/m2_first_service.tres:237
	expect(not _command(plan, "set_prep", "salad", 1, 1).accepted, "set_prep no longer accepts a recipe ID")
	expect(not _command(plan, "set_prep", "vegetable", 1, 2).accepted, "set_prep rejects a raw ingredient")
	expect(_command(plan, "set_prep", "prepped_soup", 2, 3).accepted, "two soup mise items fit the labor budget")
	var snapshot := plan.snapshot()
	expect(snapshot.labor_used == 4 and snapshot.inventory.prepped_soup == 2 and snapshot.inventory.vegetable == 18
		and snapshot.inventory.grain == 6, "mise labor and raw inputs come from the item definition")
	expect(not _command(plan, "set_prep", "prepped_grill", 1, 4).accepted, "a seventh labor unit cannot be spent")
	var inventory := {"prepped_salad": 1, "prepped_soup": 0}
	expect(PreparationPlan.mise_ready(inventory, plan.display_definition().recipe_for("salad"))
		and not PreparationPlan.mise_ready(inventory, plan.display_definition().recipe_for("soup")),
		"mise_ready requires every item of the recipe")

	var started := _command(plan, "start", "", null, 5)
	expect(started.accepted, "the prepared fixture starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while not simulation.closed:
		simulation.step()
	var report: Dictionary = ServiceAnalysis.build(started.definitions, simulation.snapshot(), started.selection)
	expect(report.prep.keys() == ["prepped_salad", "prepped_soup", "prepped_grill"], "analysis prep rows are keyed by mise item")
	var soup_row: Dictionary = report.prep.prepped_soup
	expect(soup_row.planned == 2 and soup_row.labor_units == 2 and soup_row.menu_count == 1
		and soup_row.planned == soup_row.used + soup_row.remaining, "a prep row carries planned, used, remaining, labor and menu count")
	for recommendation: Dictionary in report.recommendations:
		if recommendation.category == "prep":
			expect(started.definitions.ingredient_for(recommendation.target_id) != null, "prep recommendations target a mise item")
```

M2 fixture의 구매량은 `vegetable` 22, `grain` 8이므로(`content/m2_first_service.tres:245`) 수프 미장 2개는 토마토 4개와 곡물 2개를 소비해 18·6이 남습니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `prep_quantities.keys()`가 `["salad", "soup", "grill"]`이고 `mise_ready`가 없습니다.

- [ ] **Step 3: 준비 계획 구현**

`sim/preparation_plan.gd` `_defaults()`의 레시피 루프를 바꿉니다.

```gdscript
	for item: Definitions.IngredientDef in _source.mise_items():
		quantities[item.id] = 0
```

`apply_command`의 `"set_prep"` 분기:

```gdscript
		"set_prep":
			var item := _source.ingredient_for(target)
			if item == null or not item.is_mise() or not command.value is int or command.value < 0:
				return _rejected("invalid_preparation")
			candidate.prep_quantities[target] = command.value
```

`initial_state`의 `ordered_ids` 루프부터 `inventory[...prepared_ingredient_id] += ...` 줄까지를 바꿉니다.

```gdscript
	for mise_id: Variant in ordered_ids:
		if not mise_id is String or not quantities[mise_id] is int or quantities[mise_id] < 0:
			errors.append("invalid_preparation")
			return result
		var item := data.ingredient_for(mise_id)
		if item == null or not item.is_mise():
			errors.append("invalid_preparation")
			return result
		var quantity: int = quantities[mise_id]
		if quantity > (data.prep_labor_capacity - labor_used) / item.labor_units:
			errors.append("insufficient_labor")
			return result
		labor_used += quantity * item.labor_units
		for input_id: String in item.inputs:
			if quantity > (inventory[input_id] - required.get(input_id, 0)) / item.inputs[input_id]:
				errors.append("missing_ingredients")
				return result
			required[input_id] = required.get(input_id, 0) + quantity * item.inputs[input_id]
	for input_id: String in required:
		inventory[input_id] -= required[input_id]
	for mise_id: String in ordered_ids:
		inventory[mise_id] += quantities[mise_id]
```

`require_stock` 블록의 `if inventory.get(recipe.prepared_ingredient_id, 0) > 0:`를 `if mise_ready(inventory, recipe):`로 바꾸고, 파일 끝에 추가합니다.

```gdscript
static func mise_ready(inventory: Dictionary, recipe: Definitions.RecipeDef) -> bool:
	if recipe.mise_ids.is_empty():
		return false
	for mise_id: String in recipe.mise_ids:
		if inventory.get(mise_id, 0) <= 0:
			return false
	return true
```

- [ ] **Step 4: 마감 분석 구현**

`sim/service_analysis.gd` `build()`의 `for recipe_id: String in data.menu_ids:` 루프에서 `prep_row`와 `prep[recipe_id] = prep_row`를 걷어내 우선순위 행만 남기고, 그 루프 앞에 미장 루프를 둡니다.

```gdscript
	for item: Definitions.IngredientDef in data.mise_items():
		var planned: int = prep_quantities.get(item.id, 0)
		labor_used += planned * item.labor_units
		var remaining: int = view.inventory.get(item.id, 0)
		var prep_row := {"planned": planned, "used": maxi(0, planned - remaining),
			"remaining": remaining, "raw_orders": 0, "served": 0, "expired": 0,
			"shortage_ticks": 0, "pressure_ticks": 0, "labor_units": item.labor_units,
			"menu_count": data.menu_count_for(item.id)}
		for order: Dictionary in view.orders:
			if item.id not in data.recipe_for(order.recipe_id).mise_ids:
				continue
			if order.raw_consumed:
				prep_row.raw_orders += 1
			if order.state == "served":
				prep_row.served += 1
			elif order.state == "expired":
				prep_row.expired += 1
			prep_row.shortage_ticks += order.metrics.missing_ingredients
			prep_row.pressure_ticks += order.metrics.station_in_use + order.metrics.responsible_employee_busy
		prep[item.id] = prep_row
```

`raw_orders`는 이번 계획에서 "그 항목을 쓰는 메뉴 중 원재료 경로로 간 주문 수"이며, 어느 항목이 비어서 그랬는지는 계획 2b의 혼합 소비 기록이 정확히 셉니다.

`_prep_recommendation`의 `for recipe_id: String in data.menu_ids:`를 `for item: Definitions.IngredientDef in data.mise_items():`로, `prep[recipe_id]`를 `prep[item.id]`로, `row.prep_labor_units`를 `row.labor_units`로, `_valid_prep_change(data, selection, recipe_id, ...)`와 `"target_id": recipe_id`를 `item.id`로 바꿉니다. `_valid_prep_change`의 매개변수 이름은 `mise_id`로 바꾸고 본문은 키만 그대로 넣습니다.

- [ ] **Step 5: 준비 화면과 요약 문구**

`presentation/preparation_panel.gd`의 프렙 행 생성 루프를 바꿉니다(아이콘 없음).

```gdscript
	for item: Definitions.IngredientDef in definitions.mise_items():
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _label("")
		row.add_child(label)
		prep_labels[item.id] = label
		var minus := _button("−", false)
		minus.pressed.connect(_change_quantity.bind("set_prep", item.id, -1))
		row.add_child(minus)
		prep_minus[item.id] = minus
		var plus := _button("+", false)
		plus.pressed.connect(_change_quantity.bind("set_prep", item.id, 1))
		row.add_child(plus)
		prep_plus[item.id] = plus
```

갱신 루프:

```gdscript
	for mise_id: String in prep_labels:
		var item := definitions.ingredient_for(mise_id)
		var quantity: int = snapshot.prep_quantities.get(mise_id, 0)
		prep_labels[mise_id].text = tr("%s %d개\n메뉴 %d종 · 원가 %d · 노동 %d / 개") % [tr(item.display_name), quantity,
			definitions.menu_count_for(mise_id), item.unit_cost, item.labor_units]
		prep_minus[mise_id].disabled = quantity == 0
```

`translations/en.po`에 `msgid "%s %d개\n메뉴 %d종 · 원가 %d · 노동 %d / 개"` / `msgstr "%s × %d\n%d menus · cost %d · labor %d each"`를 추가하고, 옛 `"%s %d개\n노동 %d / 개"` 항목은 다른 곳에서 쓰지 않으면 지웁니다(`grep -rn '노동 %d / 개' presentation tests`로 확인).

`presentation/main.gd` 요약(757행 근처):

```gdscript
			for item: Definitions.IngredientDef in definitions.mise_items():
				prepared.append(tr("%s %d") % [tr(item.display_name), latest_view.inventory.get(item.id, 0)])
```

권고 문구 세 곳(`increase_prep`·`reduce_prep`·`prep_at_capacity`)의 `tr(definitions.recipe_for(target_id).display_name)`을 `tr(definitions.ingredient_for(target_id).display_name)`으로, `row.prep_labor_units`를 `row.labor_units`로 바꿉니다. 문구 자체는 바꾸지 않습니다.

- [ ] **Step 6: 테스트와 정책의 대상 ID 번역**

M2 fixture 기반 검사에서 `set_prep`의 대상과 `report.prep` 키를 레시피 ID에서 미장 ID로 바꿉니다: `salad → prepped_salad`, `soup → prepped_soup`, `grill → prepped_grill`. 대상 파일은 `tests/test_m2_rules.gd`(`{"prep_quantities": {"salad": 1}}` 꼴 16곳; `snapshot(sim).inventory.prepped_salad` 같은 재고 키는 이미 미장 ID이므로 그대로), `tests/test_m2_content.gd:37`(`grain_salad → prepped_grain_salad`), `tests/test_preparation.gd`, `tests/test_m2_ui.gd`, `tests/test_service_feedback.gd`(`{"prep_quantities": {"salad": 1}}` 포함), `tests/test_m4_determinism.gd:281,1024`, `tests/test_service_session.gd`, `tests/test_m4_ui.gd`, `tests/test_space_experiment.gd`, `tests/capture_m2.gd`, `tests/capture_service_feedback.gd`입니다. `grep -rn 'set_prep\|prep_quantities\|report.prep\|\.prep\[' tests`로 목록을 만들고 한 파일씩 고칩니다.

캠페인 정책은 이번 Task에서 1:1 대응으로만 번역합니다(경제는 Task 4·5에서 바뀝니다): `tests/fixtures/m3_policies.gd`와 `tests/fixtures/space_experiment.gd`의 `_add(policy, "set_prep", "<recipe>", n)`를 `"prepped_<recipe>"`로 바꿉니다(`grill → prepped_grill`, `soup → prepped_soup`, `salad → prepped_salad`, `grain_salad → prepped_grain_salad`, `protein_bowl → prepped_protein_bowl`, `grain_grill → prepped_grain_grill`, `mushroom_salad → prepped_mushroom_salad`). `tests/test_m3_playthrough.gd:97`의 `"grill"`도 `"prepped_grill"`로 바꿉니다.

`tests/check_export.gd:186-190`:

```gdscript
	if data.call("supports_preparation"):
		var recipe: Resource = data.call("recipe_for", data.get("menu_ids")[0])
		var mise_id: String = recipe.get("mise_ids")[0]
		var item: Resource = data.call("ingredient_for", mise_id)
		var result: Dictionary = screen.call("submit_preparation", "set_prep", mise_id, 1)
		prepared = result.accepted and screen.get("preparation_panel").prep_labels[mise_id].text.contains(item.get("display_name"))
```

- [ ] **Step 7: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS.
Run: `bash scripts/check.sh m2` → PASS (497).
Run: `bash scripts/check.sh m3` → PASS (1109). 정책 번역이 1:1이므로 결과 해시와 격차가 같아야 하며, 다르면 번역 오타입니다.
Run: `bash scripts/check.sh m4` → PASS (1191).
Run: `bash scripts/check.sh ui-regressions` → PASS (302).

- [ ] **Step 8: Commit**

```bash
git add sim/preparation_plan.gd sim/service_analysis.gd presentation/preparation_panel.gd presentation/main.gd translations/en.po tests
git commit -m "feat(prep): key preparation and closing analysis by mise item"
```

---

### Task 3: 시뮬레이션의 미장 집합 예약·소비와 옛 필드 제거

**Files:**

- Modify: `sim/service_sim.gd:301`, `:327-336` (`_available_inputs`), `:373-377` (`_begin_work`), `:891`, `:900`, `:1141-1144`, `:1154-1157`
- Modify: `content/recipe_def.gd` (`prepared_ingredient_id`·`prep_labor_units` 삭제)
- Modify: `content/definitions.gd` (전환 검사 삭제), `content/campaign_def.gd` (서명에서 옛 필드 삭제)
- Modify: `content/m2_first_service.tres`, `content/campaign/recipes/*.tres` (옛 필드 줄 삭제)
- Modify: `presentation/main.gd:945-975` (말풍선)
- Modify: `tests/test_mise_items.gd`, `tests/test_service_feedback.gd:226-228`, `tests/test_m2_content.gd`

**Interfaces:**

- Consumes: `RecipeDef.mise_ids`, `IngredientDef.is_mise()`.
- Produces: `prepared_stock_depleted` 이벤트에 `ingredient_id`(미장 ID)가 추가됩니다. 스냅샷 주문 필드는 그대로이며 `uses_prepared`는 "미장 집합 전체를 예약·소비했다"는 뜻입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`에 두 항목짜리 미장 집합 검사를 추가합니다. M2 fixture를 복제해 `soup`의 미장을 `["prepped_soup_grain", "prepped_soup_vegetable"]`로 나누고, 항목이 하나만 있을 때 원재료 경로로 가는지, 둘 다 있을 때 둘 다 소비하고 항목별 이벤트가 나는지 확인합니다.

```gdscript
func _split_soup_fixture() -> Resource:
	var data := _fixture()
	var grain_item: Resource = _ingredient(data, "prepped_soup").duplicate()
	grain_item.set("id", "prepped_soup_grain")
	grain_item.set("unit_cost", 150)
	grain_item.set("inputs", _typed_inputs({"grain": 1}))
	grain_item.set("labor_units", 1)
	var vegetable_item: Resource = _ingredient(data, "prepped_soup").duplicate()
	vegetable_item.set("id", "prepped_soup_vegetable")
	vegetable_item.set("unit_cost", 200)
	vegetable_item.set("inputs", _typed_inputs({"vegetable": 2}))
	vegetable_item.set("labor_units", 1)
	var items: Array = data.get("ingredients").duplicate()
	items.append(grain_item)
	items.append(vegetable_item)
	data.set("ingredients", items)
	data.call("recipe_for", "soup").set("mise_ids", PackedStringArray(["prepped_soup_grain", "prepped_soup_vegetable"]))
	data.set("menu_ids", PackedStringArray(["soup"]))
	data.set("order_count", 1)
	data.set("first_arrival_tick", 1)
	return data


func _run_until_consumed(simulation: ServiceSim, limit: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _step: int in limit:
		simulation.step()
		events.append_array(simulation.events())
		if simulation.snapshot().orders.size() > 0 and simulation.snapshot().orders[0].input_consumed:
			break
	return events


func _test_mise_set_consumption() -> void:
	var data := _split_soup_fixture()
	expect(_ingredient(data, "prepped_soup_grain").get("inputs") == _typed_inputs({"grain": 1}), "the split fixture keeps its typed inputs")
	expect(data.call("validate").is_empty(), "a two-item mise set whose inputs sum to the recipe validates")
	var partial := ServiceSim.new(data, null, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(partial.errors.is_empty(), "one of two mise items can be prepared")
	_run_until_consumed(partial, 40)
	var view: Dictionary = partial.snapshot()
	expect(view.orders[0].raw_consumed and not view.orders[0].uses_prepared and view.inventory.prepped_soup_grain == 1,
		"a recipe with one missing mise item takes the raw path and leaves the stocked item")
	var full := ServiceSim.new(data, null, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	var events := _run_until_consumed(full, 40)
	view = full.snapshot()
	expect(view.orders[0].uses_prepared and view.inventory.prepped_soup_grain == 0 and view.inventory.prepped_soup_vegetable == 0
		and view.orders[0].consumed_cost == 350, "a complete mise set is consumed item by item at its combined cost")
	var depleted_ids: Array[String] = []
	for event: Dictionary in events:
		if event.kind == "prepared_stock_depleted":
			depleted_ids.append(event.ingredient_id)
	expect(depleted_ids == ["prepped_soup_grain", "prepped_soup_vegetable"],
		"each mise item that reaches zero emits its own depletion event")
	var saved: Dictionary = full.export_state()
	var restored := ServiceSim.restore(data, saved, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	expect(restored.accepted and restored.simulation.state_hash() == full.state_hash(),
		"a snapshot with a consumed mise set restores to the same hash")
```

`ServiceSim.restore(data, state, preparation)`는 준비 옵션을 세 번째 인자로 받으므로(`sim/service_sim.gd:557`) 시뮬레이션을 만들 때 준 `prep_quantities`를 그대로 넘깁니다. `events()`는 직전 `step()`의 이벤트만 돌려주므로 매 step마다 모읍니다(`tests/test_service_feedback.gd:368`과 같은 꼴).

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. 시뮬레이션이 아직 `prepared_ingredient_id` 하나만 예약하므로 두 항목 소비와 이벤트 `ingredient_id`가 없습니다.

- [ ] **Step 3: 시뮬레이션 구현**

`_available_inputs`:

```gdscript
func _available_inputs(order: OrderState) -> Dictionary[String, int]:
	var inputs: Dictionary[String, int] = {}
	if _mise_ready(order.recipe):
		for mise_id: String in order.recipe.mise_ids:
			inputs[mise_id] = 1
		return inputs
	for ingredient_id: String in order.recipe.ingredients:
		if _inventory[ingredient_id] - _reserved[ingredient_id] < order.recipe.ingredients[ingredient_id]:
			return {}
	inputs.assign(order.recipe.ingredients)
	return inputs


func _mise_ready(recipe: RecipeDef) -> bool:
	if recipe.mise_ids.is_empty():
		return false
	for mise_id: String in recipe.mise_ids:
		if _inventory[mise_id] - _reserved[mise_id] <= 0:
			return false
	return true
```

`_try_assignment`의 301행: `order.uses_prepared = not order.recipe.mise_ids.is_empty() and inputs.has(order.recipe.mise_ids[0])`.

`_begin_work`의 고갈 이벤트:

```gdscript
		if order.uses_prepared:
			for mise_id: String in order.recipe.mise_ids:
				if _inventory[mise_id] == 0:
					_events.append({"kind": "prepared_stock_depleted", "order_id": order.id,
						"recipe_id": order.recipe.id, "ingredient_id": mise_id, "employee_id": task.employee_id})
```

복원 검증(`_order_restore_error`): 891행을 `if saved_order.uses_prepared and recipe.mise_ids.is_empty():`로, 900행을 아래로 바꿉니다.

```gdscript
		var expected_inputs: Dictionary = _mise_inputs(recipe) if saved_order.uses_prepared else recipe.ingredients
```

```gdscript
static func _mise_inputs(recipe: RecipeDef) -> Dictionary:
	var inputs: Dictionary = {}
	for mise_id: String in recipe.mise_ids:
		inputs[mise_id] = 1
	return inputs
```

재고 복원 검증(1141행 근처):

```gdscript
		if saved_order.uses_prepared:
			if recipe.mise_ids.is_empty():
				return "invalid_order"
			for mise_id: String in recipe.mise_ids:
				if not initial_inventory.has(mise_id):
					return "invalid_order"
				initial_inventory[mise_id] -= 1
```

`_consumed_cost`:

```gdscript
	if order.uses_prepared:
		var prepared_cost: int = 0
		for mise_id: String in order.recipe.mise_ids:
			prepared_cost += data.ingredient_for(mise_id).unit_cost
		return prepared_cost
```

`presentation/main.gd`의 말풍선: `_consider_chatter`의 `repeat_key`를 `"%s:%s" % [event.kind, event.get("ingredient_id", event.get("recipe_id", ""))]`로, `_visible_chatter`의 `"prepared_stock_depleted"` 분기를 `result.text = tr("%s 프렙 다 썼다!") % tr(definitions.ingredient_for(result.ingredient_id).display_name)`로 바꿉니다. msgid는 그대로이므로 `en.po`는 바뀌지 않습니다.

- [ ] **Step 4: 옛 필드 제거**

`content/recipe_def.gd`에서 `prepared_ingredient_id`와 `prep_labor_units` export를 지웁니다. `content/definitions.gd`의 전환 검사 4줄(`# Transitional` 주석부터 `legacy preparation fields disagree` 오류까지)을 지웁니다. `content/campaign_def.gd` 레시피 서명에서 `recipe.prepared_ingredient_id, recipe.prep_labor_units`를 지웁니다. `content/m2_first_service.tres`와 `content/campaign/recipes/*.tres`에서 `prepared_ingredient_id = ...`와 `prep_labor_units = ...` 줄을 지웁니다(`grep -rln 'prepared_ingredient_id\|prep_labor_units' content presentation sim tests`가 비어야 합니다).

`tests/test_m2_content.gd`에서 옛 규칙("prepared ingredient cost must equal", "preparation labor requires a prepared ingredient", "invalid prepared ingredient")을 검사하던 항목은 Task 1의 미장 규칙 검사로 대체됐으므로 삭제하고, `prepared_ingredient_id`를 set/get 하는 줄은 `mise_ids`로 바꿉니다. `tests/test_service_feedback.gd:226-228`의 기대에 `depleted.get("ingredient_id") == "prepped_salad"`를 추가합니다.

- [ ] **Step 5: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS.
Run: `bash scripts/check.sh m2` → PASS. `test_m2_rules.gd`의 예약·소비·취소 기대값은 모두 그대로여야 합니다.
Run: `bash scripts/check.sh m3` → PASS (해시 동일).
Run: `bash scripts/check.sh m4` → PASS.
Run: `bash scripts/check.sh ui-regressions` → PASS.

- [ ] **Step 6: Commit**

```bash
git add sim/service_sim.gd content presentation/main.gd tests
git commit -m "feat(sim): reserve and consume recipe mise sets and drop the legacy prepared fields"
```

---

### Task 4: 캠페인 콘텐츠 재구성, 실제 식재료명, 시드 0 게이트 재조정

**Files:**

- Create: `content/campaign/ingredients/prepped_vegetable.tres`, `prepped_grain.tres`, `prepped_mushroom.tres`, `soup_base.tres`, `thawed_protein.tres`, `marinated_protein.tres`
- Delete: `content/campaign/ingredients/prepped_salad.tres`, `prepped_grain_salad.tres`, `prepped_mushroom_salad.tres`, `prepped_soup.tres`, `prepped_mushroom_soup.tres`, `prepped_grain_grill.tres`, `prepped_protein_bowl.tres`, `prepped_grill.tres`
- Modify: `content/campaign/ingredients/protein.tres`, `vegetable.tres`, `grain.tres`, `mushroom.tres` (`display_name`)
- Modify: `content/campaign/recipes/*.tres` (8개: `display_name`, `mise_ids`)
- Modify: `content/campaign/scenarios/*.tres` (8개: `ext_resource`·`ingredients` 배열, 브리핑 4건)
- Modify: `translations/en.po`
- Modify: `tests/test_m3_ui.gd:23`, `tests/test_service_seed.gd:62`, `tests/test_service_feedback.gd:299`, `tests/test_mise_items.gd`
- Modify: `tests/fixtures/m3_policies.gd`, `tests/fixtures/space_experiment.gd`, `tests/test_m3_playthrough.gd:96-97`, `tests/test_m4_determinism.gd`
- Modify: `content/campaign/scenarios/*.tres` (`prep_labor_capacity`, 마지막 수단)
- Modify: `docs/notes/kitchen-pressure-verification.md`

**Interfaces:**

- Consumes: Task 1~3의 미장 모델.
- Produces: 캠페인 미장 ID `prepped_vegetable`·`prepped_grain`·`prepped_mushroom`·`soup_base`·`thawed_protein`·`marinated_protein`. Task 5의 세션 fixture가 이 ID를 씁니다. 시드 0에서 `check.sh m3`의 기준 정책·대안 정책·무계획 격차가 모두 통과하는 정책 값과 그 기록.

이 Task는 콘텐츠 교체와 게이트 재조정을 나눌 수 없습니다. 공유 미장으로 메뉴당 준비 노동량이 현미 샐러드 1→2, 양송이 샐러드 1→2, 연어 덮밥 2→3으로 바뀌므로 콘텐츠만 바꾸면 `test_m3_playthrough.gd`가 빨갛게 남고, 명세 §12는 각 단계에서 기존 검사가 계속 통과할 것을 요구합니다. 커밋은 두 번(콘텐츠, 재조정)이지만 Task의 완료 조건은 `check.sh m3` PASS입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`에 캠페인 콘텐츠 검사를 추가합니다.

```gdscript
const CAMPAIGN_MISE := {
	"prepped_vegetable": {"name": "손질 토마토", "inputs": {"vegetable": 1}, "labor": 1, "cost": 100, "menus": 4},
	"prepped_grain": {"name": "불린 현미", "inputs": {"grain": 1}, "labor": 1, "cost": 150, "menus": 4},
	"prepped_mushroom": {"name": "손질 양송이", "inputs": {"mushroom": 1}, "labor": 1, "cost": 200, "menus": 3},
	"soup_base": {"name": "토마토 베이스", "inputs": {"vegetable": 2}, "labor": 1, "cost": 200, "menus": 2},
	"thawed_protein": {"name": "해동 연어", "inputs": {"protein": 1}, "labor": 1, "cost": 400, "menus": 1},
	"marinated_protein": {"name": "재운 연어", "inputs": {"protein": 1}, "labor": 3, "cost": 400, "menus": 1},
}
const CAMPAIGN_NAMES := {"protein": "연어", "vegetable": "토마토", "grain": "현미", "mushroom": "양송이",
	"grill": "연어 구이", "protein_bowl": "연어 덮밥", "salad": "토마토 샐러드", "grain_salad": "현미 샐러드",
	"mushroom_salad": "양송이 샐러드", "soup": "토마토 수프", "mushroom_soup": "양송이 수프", "grain_grill": "현미 볶음밥"}


func _test_campaign_mise_content() -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	expect(campaign.call("validate").is_empty(), "the restructured campaign validates")
	var final_service: Resource = campaign.call("scenario_for", "final_service")
	expect(final_service.get("ingredients").size() == 10, "the final service lists four raw ingredients and six mise items")
	for mise_id: String in CAMPAIGN_MISE:
		var expected: Dictionary = CAMPAIGN_MISE[mise_id]
		var item: Resource = final_service.call("ingredient_for", mise_id)
		expect(item != null and item.get("display_name") == expected.name and item.get("inputs") == expected.inputs
			and item.get("labor_units") == expected.labor and item.get("unit_cost") == expected.cost,
			"campaign mise item matches the approved table: " + mise_id)
		expect(item != null and final_service.call("menu_count_for", mise_id) == expected.menus,
			"campaign mise item is shared by the approved number of menus: " + mise_id)
	for id: String in CAMPAIGN_NAMES:
		var definition: Resource = final_service.call("ingredient_for", id)
		if definition == null:
			definition = final_service.call("recipe_for", id)
		expect(definition != null and definition.get("display_name") == CAMPAIGN_NAMES[id], "campaign display name is a real food: " + id)
	expect(final_service.call("recipe_for", "grain_grill").get("mise_ids") == PackedStringArray(["prepped_grain", "prepped_mushroom"]),
		"the rice stir-fry uses grain and mushroom mise, not protein")
	TranslationServer.set_locale("en")
	expect(TranslationServer.translate("재운 연어") == "Marinated salmon", "the English translation covers the new mise names")
	TranslationServer.set_locale("ko")
```

`tests/test_m4_preferences.gd:87-98`이 같은 방식으로 locale을 바꾸고 `ko`로 되돌립니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `prepped_vegetable`이 없고 이름이 분류명입니다.

- [ ] **Step 3: 미장 6종 작성과 8종 삭제**

`content/campaign/ingredients/prepped_vegetable.tres`(나머지 5개도 같은 꼴):

```plaintext
[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://content/ingredient_def.gd" id="1_mise"]

[resource]
script = ExtResource("1_mise")
id = "prepped_vegetable"
display_name = "손질 토마토"
unit_cost = 100
purchasable = false
inputs = Dictionary[String, int]({
"vegetable": 1
})
labor_units = 1
```

| 파일                     | id                  | display_name  | inputs         | unit_cost | labor_units |
| ------------------------ | ------------------- | ------------- | -------------- | --------- | ----------- |
| `prepped_vegetable.tres` | `prepped_vegetable` | 손질 토마토   | `vegetable: 1` | 100       | 1           |
| `prepped_grain.tres`     | `prepped_grain`     | 불린 현미     | `grain: 1`     | 150       | 1           |
| `prepped_mushroom.tres`  | `prepped_mushroom`  | 손질 양송이   | `mushroom: 1`  | 200       | 1           |
| `soup_base.tres`         | `soup_base`         | 토마토 베이스 | `vegetable: 2` | 200       | 1           |
| `thawed_protein.tres`    | `thawed_protein`    | 해동 연어     | `protein: 1`   | 400       | 1           |
| `marinated_protein.tres` | `marinated_protein` | 재운 연어     | `protein: 1`   | 400       | 3           |

`prepped_*.tres` 8개와 짝인 `.tres.uid`가 있으면 함께 삭제합니다(`git rm`). 원재료 4종의 `display_name`을 연어·토마토·현미·양송이로 바꿉니다.

- [ ] **Step 4: 레시피와 시나리오**

레시피 `display_name`과 `mise_ids`:

| 레시피           | display_name  | mise_ids                                               |
| ---------------- | ------------- | ------------------------------------------------------ |
| `salad`          | 토마토 샐러드 | `prepped_vegetable`                                    |
| `grain_salad`    | 현미 샐러드   | `prepped_vegetable`, `prepped_grain`                   |
| `mushroom_salad` | 양송이 샐러드 | `prepped_vegetable`, `prepped_mushroom`                |
| `soup`           | 토마토 수프   | `prepped_grain`, `soup_base`                           |
| `mushroom_soup`  | 양송이 수프   | `prepped_mushroom`, `soup_base`                        |
| `grain_grill`    | 현미 볶음밥   | `prepped_grain`, `prepped_mushroom`                    |
| `protein_bowl`   | 연어 덮밥     | `prepped_vegetable`, `prepped_grain`, `thawed_protein` |
| `grill`          | 연어 구이     | `marinated_protein`                                    |

`ingredients` 사전은 그대로 두며, 콘텐츠 검사가 각 행의 `inputs` 합과 같은지 확인합니다.

시나리오 8개의 `ext_resource`와 `ingredients` 배열을 아래로 바꿉니다(원재료 먼저, 미장은 표 순서).

| 시나리오        | 원재료                              | 미장                                                                                             |
| --------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------ |
| `first_shift`   | vegetable                           | prepped_vegetable                                                                                |
| `lunch_prep`    | vegetable, grain                    | prepped_vegetable, prepped_grain, soup_base                                                      |
| `hot_queue`     | vegetable, grain, protein           | prepped_vegetable, prepped_grain, soup_base, marinated_protein                                   |
| `shared_stock`  | vegetable, grain, mushroom          | prepped_vegetable, prepped_grain, prepped_mushroom, soup_base                                    |
| `long_route`    | vegetable, grain, protein, mushroom | prepped_vegetable, prepped_grain, prepped_mushroom, soup_base, thawed_protein, marinated_protein |
| `split_duties`  | vegetable, grain, mushroom, protein | prepped_vegetable, prepped_grain, prepped_mushroom, thawed_protein                               |
| `rush_hour`     | vegetable, grain, mushroom, protein | 6종 전부                                                                                         |
| `final_service` | vegetable, grain, mushroom, protein | 6종 전부                                                                                         |

`unused mise item`·`campaign menu needs mise items` 검사가 이 표의 오류를 잡습니다.

브리핑 4건을 바꿉니다(다른 4건은 재료명을 쓰지 않으므로 그대로).

| 시나리오       | briefing                                                                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `first_shift`  | 토마토 샐러드 한 메뉴로 시작합니다. 준비를 확인하고 영업을 시작하세요. 언제든 일시정지할 수 있습니다. 마감 후 제공 수와 손익을 확인합니다.                                |
| `lunch_prep`   | 수프는 토마토 베이스와 불린 현미가 모두 있어야 손질을 건너뜁니다. 같은 노동량으로 무엇을 미리 준비하면 기다리는 주문이 줄어들지 비교하세요.                               |
| `hot_queue`    | 주문이 네 차례에 걸쳐 몰려옵니다. 재운 연어만 많이 준비하면 짧은 주문이 밀립니다. 재운 연어와 손질 토마토를 나눠 준비하고 연어 구이 우선순위를 높여 온식 병목을 넘기세요. |
| `shared_stock` | 토마토를 여러 메뉴가 나눠 쓰고 주문이 다섯 차례에 걸쳐 몰려옵니다. 고정된 재료 보관대와 출고대 사이에서 발주와 프렙을 함께 조절해 재료 부족과 남는 비용을 줄이세요.       |

- [ ] **Step 5: 번역**

`translations/en.po`에 추가합니다.

| msgid         | msgstr              |
| ------------- | ------------------- |
| 연어          | Salmon              |
| 토마토        | Tomatoes            |
| 현미          | Brown rice          |
| 양송이        | Button mushrooms    |
| 연어 구이     | Grilled salmon      |
| 연어 덮밥     | Salmon rice bowl    |
| 토마토 샐러드 | Tomato salad        |
| 현미 샐러드   | Brown rice salad    |
| 양송이 샐러드 | Mushroom salad      |
| 토마토 수프   | Tomato soup         |
| 양송이 수프   | Mushroom soup       |
| 현미 볶음밥   | Brown rice stir-fry |
| 손질 토마토   | Cut tomatoes        |
| 불린 현미     | Soaked brown rice   |
| 손질 양송이   | Sliced mushrooms    |
| 토마토 베이스 | Tomato base         |
| 해동 연어     | Thawed salmon       |
| 재운 연어     | Marinated salmon    |

브리핑 4건의 msgid도 새 문장으로 바꾸고 msgstr를 맞춥니다: `first_shift` "Start with one tomato salad menu. Review preparation and begin service. You can pause at any time. At closing, review the served count and profit."; `lunch_prep` "Soup skips prep only when both the tomato base and the soaked brown rice are ready. Compare what to prepare with the same labor so that fewer orders wait."; `hot_queue` "Orders arrive in four rushes. Marinating only salmon leaves the short orders waiting. Split prep between marinated salmon and cut tomatoes, and raise the grilled salmon priority to clear the hot-station bottleneck."; `shared_stock` "Several menus share tomatoes, and orders arrive in five rushes. Adjust purchasing and prep between the fixed storage and pass stations to reduce shortages and leftover cost."

사라진 msgid를 지웁니다: `손질한 ... 재료` 8건, 그리고 `grep -rn '<msgid>' content presentation tests`가 비는 옛 메뉴명(`버섯 수프`, `버섯 샐러드`, `곡물 샐러드`, `단백질 덮밥`, `곡물 볶음`). `채소`·`곡물`·`단백질`·`버섯`·`채소 샐러드`·`곡물 수프`·`단백질 구이`는 M2 fixture와 `tests/test_m2_ui.gd`가 아직 쓰므로 남깁니다.

- [ ] **Step 6: 이름과 캠페인 미장 ID를 읽는 검사 갱신**

Task 2가 캠페인 시나리오를 쓰는 검사와 캡처 스크립트의 `set_prep` 대상을 1:1 ID(`prepped_salad` 등)로 옮겨 두었으므로, 이 Step에서 새 미장 ID로 다시 옮깁니다. `grep -rn 'prepped_salad\|prepped_soup\|prepped_grill\|prepped_grain_salad\|prepped_mushroom_salad\|prepped_mushroom_soup\|prepped_grain_grill\|prepped_protein_bowl' tests`로 목록을 만들고, M2 fixture(`m2_first_service.tres`, `tests/fixtures/m2_extra_menu.tres`)를 쓰는 검사는 그대로 두며, 캠페인 시나리오를 쓰는 검사(`tests/test_m4_determinism.gd`, `tests/test_service_session.gd`, `tests/test_m4_ui.gd`, `tests/capture_m3.gd`, `tests/capture_m4.gd`, `tests/test_space_experiment.gd` 등 grep이 찾는 모든 파일)는 아래 표로 옮깁니다. 한 레시피의 옛 프렙 1개는 새 미장 각 1개로 늘어나므로 `set_prep` 명령은 항목 수만큼 됩니다.

| 옛 ID                    | 새 ID                                                  |
| ------------------------ | ------------------------------------------------------ |
| `prepped_salad`          | `prepped_vegetable`                                    |
| `prepped_grain_salad`    | `prepped_vegetable`, `prepped_grain`                   |
| `prepped_mushroom_salad` | `prepped_vegetable`, `prepped_mushroom`                |
| `prepped_soup`           | `prepped_grain`, `soup_base`                           |
| `prepped_mushroom_soup`  | `prepped_mushroom`, `soup_base`                        |
| `prepped_grain_grill`    | `prepped_grain`, `prepped_mushroom`                    |
| `prepped_protein_bowl`   | `prepped_vegetable`, `prepped_grain`, `thawed_protein` |
| `prepped_grill`          | `marinated_protein`                                    |

노동량이 상한을 넘게 되는 검사는 수량을 줄이고, 그 검사가 고정한 해시는 같은 명령으로 두 번 실행해 같은 값을 확인한 뒤 갱신합니다.

`tests/test_m3_ui.gd:23`의 `"채소 샐러드"`를 `"토마토 샐러드"`로, `tests/test_service_seed.gd:62`의 `"채소 샐러드 12건"`을 `"토마토 샐러드 12건"`으로, `tests/test_service_feedback.gd:299`의 `"곡물 수프의 기본 우선순위를 2로"`를 `"토마토 수프의 기본 우선순위를 2로"`로 바꿉니다. 각 파일이 캠페인 시나리오를 쓰는지 M2 fixture를 쓰는지 확인하고, M2 fixture를 쓰는 검사는 건드리지 않습니다. `tests/test_mise_items.gd`의 Task 1 검사에서 `first_shift`의 미장을 비웠을 때 기대하는 `unused mise item: prepped_salad`는 `unused mise item: prepped_vegetable`로 바꿉니다.

- [ ] **Step 7: 콘텐츠 검사 통과와 첫 커밋**

Run: `bash scripts/check.sh mise` → PASS.
Run: `bash scripts/check.sh m3`
Expected: `test_m3_content.gd`·`test_m3_ui.gd`는 PASS이고 `test_m3_playthrough.gd`는 정책이 옛 미장 ID(`prepped_soup` 등)를 가리키므로 FAIL합니다. 이 상태로 콘텐츠 커밋만 만들고, 같은 Task의 Step 8~11이 PASS로 끝나야 Task가 끝납니다.

```bash
git add content/campaign translations/en.po tests/test_mise_items.gd tests/test_m3_ui.gd tests/test_service_seed.gd tests/test_service_feedback.gd
git commit -m "feat(content): replace per-menu prep with six shared mise items and real food names"
```

- [ ] **Step 8: 정책을 미장 단위로 번역**

`reference_policy`와 `alternative_policies`의 `set_prep`를 아래 시작값으로 바꿉니다. 시작값은 옛 레시피 수량을 항목별 합으로 옮긴 뒤 `prep_labor_capacity`를 넘는 시나리오만 줄인 것입니다.

| 시나리오        | 옛 기준 정책                           | 시작 정책 (미장 ID: 수량)                                                   | 노동량 / 상한 |
| --------------- | -------------------------------------- | --------------------------------------------------------------------------- | ------------- |
| `lunch_prep`    | soup 4, grain_salad 1                  | prepped_grain 4, soup_base 4, prepped_vegetable 1                           | 9 / 9         |
| `hot_queue`     | grill 1, salad 3                       | marinated_protein 1, prepped_vegetable 3                                    | 6 / 6         |
| `shared_stock`  | soup 4, salad 1                        | prepped_grain 4, soup_base 4, prepped_vegetable 1                           | 9 / 9         |
| `long_route`    | grill 4                                | marinated_protein 4                                                         | 12 / 12       |
| `split_duties`  | protein_bowl 5, grain_grill 2, salad 1 | prepped_vegetable 4, prepped_grain 5, thawed_protein 3, prepped_mushroom 2  | 14 / 15       |
| `rush_hour`     | protein_bowl 2                         | prepped_vegetable 2, prepped_grain 2, thawed_protein 2                      | 6 / 18        |
| `final_service` | grill 4, protein_bowl 3                | marinated_protein 3, prepped_vegetable 3, prepped_grain 3, thawed_protein 3 | 18 / 18       |

대안 정책의 시작값: `first_shift` salad 2 → prepped_vegetable 2; `lunch_prep` salad 6 → prepped_vegetable 6; `hot_queue` grill 1, soup 1, salad 1 → marinated_protein 1, prepped_grain 1, soup_base 1, prepped_vegetable 1; `shared_stock` soup 4 → prepped_grain 4, soup_base 4; `long_route` grill 4 → marinated_protein 4; `split_duties` protein_bowl 3, grain_grill 4, salad 1 → prepped_vegetable 3, prepped_grain 5, thawed_protein 2, prepped_mushroom 3 (13); `split_duties` 두 번째 mushroom_salad 1 → prepped_vegetable 1, prepped_mushroom 1; `rush_hour` grill 1, protein_bowl 2 → marinated_protein 1, prepped_vegetable 2, prepped_grain 2, thawed_protein 2; `final_service` grill 6 → marinated_protein 6.

`tests/fixtures/space_experiment.gd:24-28`: grill 1, salad 3 → marinated_protein 1, prepped_vegetable 3; grill 4 → marinated_protein 4. `tests/test_m3_playthrough.gd:97`: `"prepped_grill"` → `"marinated_protein"`(4개 = 노동 12 > 6이므로 `insufficient_labor` 기대는 유지).

- [ ] **Step 9: 게이트 실행과 조정**

Run: `bash scripts/check.sh m3`
`build/check/m3.log`의 `M3_PRESSURE`·`M3_STRATEGY` 줄에서 시나리오별 제공 수·손익을 읽습니다. 실패한 기대마다 아래 순서로만 조정합니다.

1. 기준·대안 정책의 항목 수량(상한 안에서).
2. 공유 미장의 `labor_units`(1 미만 불가) 또는 `marinated_protein`의 3.
3. 시나리오 `prep_labor_capacity` (+3까지, 시나리오당 한 번).
4. 목표값은 바꾸지 않습니다.

`test_m3_playthrough.gd`의 기대는 그대로입니다: 기준 정책이 두 목표 통과, 무계획은 2주문 또는 1500 손익 이상 미달, 기준 정책의 초과가 1주문·2000 손익 이하, 대안 정책과 기준 정책의 결과가 다름, 1배·4배 해시 동일.

- [ ] **Step 10: 통과 확인**

Run: `bash scripts/check.sh m3` → PASS (1109).
Run: `bash scripts/check.sh m4` → PASS. `test_m4_determinism.gd`가 캠페인 정책 해시를 고정하고 있으면 새 해시로 갱신하되, 갱신한 값은 같은 명령으로 두 번 실행해 같은지 확인합니다.
Run: `bash scripts/check.sh m5`, `bash scripts/check.sh ui-regressions` → PASS.

- [ ] **Step 11: 검증 기록**

`docs/notes/kitchen-pressure-verification.md`의 "2026-09-19 정정: 시드 0 기준" 절 뒤에 "2026-09-XX 정정: 미장 항목 기준" 절을 추가하고, 위 표의 최종 정책 값, 조정한 `labor_units`·`prep_labor_capacity`(있다면), 시나리오별 제공 수·손익(`M3_PRESSURE` 로그 인용)을 적습니다. 위 표는 시작값이며 권위는 커밋된 `m3_policies.gd`에 있다고 명시합니다.

- [ ] **Step 12: 재조정 커밋**

```bash
git add tests/fixtures/m3_policies.gd tests/fixtures/space_experiment.gd tests/test_m3_playthrough.gd tests/test_m4_determinism.gd content/campaign/scenarios docs/notes/kitchen-pressure-verification.md
git commit -m "test(m3): retune the seed-0 strategy gates for shared mise items"
```

---

### Task 5: 콘텐츠 버전 5와 진행 중 영업 재시작

**Files:**

- Modify: `persistence/campaign_store.gd:6`, `:171`, `:233-236`
- Modify: `tests/test_m4_store.gd:168-199`
- Modify: `tests/check_m4_restart.gd:104-135` (`_reader`), `:48-60` (`_writer`의 기록)
- Modify: `tests/test_m4_restart.py:211-246`

**Interfaces:**

- Consumes: 캠페인 미장 ID(세션 fixture).
- Produces: `CampaignStore.VERSIONS.content_version == 5`. 콘텐츠 4 이하 문서는 `content_updated`로 읽히고 `active_session`은 `null`, 기록은 보존, 파일은 다음 저장까지 그대로.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_m4_store.gd`의 콘텐츠 버전 3 검사에서 "다른 시나리오의 버전 3 세션을 보존"하는 기대(178-181행)를 재시작 기대로 바꿉니다.

```gdscript
	expect(loaded.accepted and loaded.reason == "content_updated" and loaded.records == current_records
		and loaded.active_session == null,
		"the mise restructure restarts every version 3 session because prep quantities are keyed by mise item")
```

`content_version == 4`를 기대하는 두 줄(172·187행)을 `== 5`로 바꿉니다. 버전 3 hot_queue 검사 뒤에 버전 4 검사를 추가합니다.

```gdscript
	var version_four_target := directory + "/content_version_four.json"
	var version_four_session := _scenario_session(campaign, "lunch_prep")
	version_four_session["preparation"]["prep_quantities"] = {"salad": 0, "soup": 1, "grain_salad": 0}
	_write(version_four_target, JSON.stringify({"schema_version": 4, "content_version": 4, "sim_version": 1,
		"records": current_records, "attempts": {}, "active_session": version_four_session}))
	var version_four_bytes := FileAccess.get_file_as_bytes(version_four_target)
	loaded = CampaignStore.new(campaign, version_four_target).load_records()
	expect(loaded.accepted and loaded.reason == "content_updated" and loaded.records == current_records
		and loaded.active_session == null,
		"a version 4 session keyed by recipe restarts instead of failing as corrupt")
	expect(FileAccess.get_file_as_bytes(version_four_target) == version_four_bytes,
		"restarting a version 4 session leaves the old file unchanged until the next write")
	expect(CampaignStore.new(campaign, version_four_target).save_records(current_records).accepted,
		"the next write upgrades a version 4 record to content version 5")
	var version_four_migrated: Variant = JSON.parse_string(FileAccess.get_file_as_string(version_four_target))
	expect(version_four_migrated is Dictionary and version_four_migrated.content_version == 5,
		"a migrated version 4 record writes content version 5")
```

버전 4 문서의 필드 수는 6(`attempts` 포함)이어야 `corrupt_records`가 아닙니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh m4`
Expected: FAIL. 버전 4 문서가 `unsupported_version` 또는 `corrupt_records`로 거부되고 `content_version == 5` 기대가 깨집니다.

- [ ] **Step 3: 저장소 구현**

`persistence/campaign_store.gd`:

```gdscript
const VERSIONS := {"schema_version": 4, "content_version": 5, "sim_version": 1}
```

```gdscript
		if key == "content_version" and int(version) in [LEGACY_CONTENT_VERSION, 2, 3, 4]:
```

```gdscript
func _content_update_restarts_session(source_content_version: int, _active_session: Dictionary) -> bool:
	# Content 5 keys prep quantities by mise item, so no earlier session can restore.
	return source_content_version < 5
```

- [ ] **Step 4: 두 PCK 검사의 reader 분기**

`tests/check_m4_restart.gd` `_writer`에서 두 `save_active_session(..., {})`의 기록 인자를 `RECORDS`로 바꾸고 상수를 둡니다.

```gdscript
const RECORDS := {"first_shift": {"completed": true, "best_served": 11, "best_profit": 1200}}
```

`_reader`에서 `loaded`·`working_loaded`를 읽은 직후에 분기를 넣습니다.

```gdscript
	var saved_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments.save))
	var saved_content_version: int = int(saved_document.get("content_version", 0)) if saved_document is Dictionary else 0
	if saved_content_version < CampaignStore.VERSIONS.content_version:
		if not loaded.accepted or loaded.reason != "content_updated" or loaded.active_session != null \
			or loaded.records != RECORDS:
			_fail("fresh reader did not restart the older content service while keeping records")
			return
		var store := CampaignStore.new(campaign, arguments.save)
		var rewritten: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments.save)) if store.save_records(loaded.records).accepted else null
		if not rewritten is Dictionary or int(rewritten.content_version) != CampaignStore.VERSIONS.content_version:
			_fail("fresh reader did not upgrade the older content file on its next write")
			return
		print("PASS: fresh M4 reader restarts the older content service and keeps records")
		TranslationServer.set_locale("ko")
		quit(0)
		return
```

같은 콘텐츠 버전이면 기존 경로가 그대로 실행되고, 기존 검사 `loaded.records`는 `RECORDS`와 같아야 하므로 `ServiceSession.restore(campaign, loaded.active_session, loaded.records)` 호출은 바꾸지 않습니다.

`tests/test_m4_restart.py`:

```python
    RESTART_PASS = "PASS: fresh M4 reader restarts the older content service and keeps records"
    RESTORE_PASS = "PASS: fresh M4 reader preserves checkpoint and final hash"

    def test_fresh_process_restores_partial_session_and_preferences(self):
        ...
        reader = self.run_reader("reader")
        self.assertEqual(reader.returncode, 0, reader.stdout)
        expected = self.RESTART_PASS if os.environ.get("M4_WRITER_PACK") else self.RESTORE_PASS
        if os.environ.get("M4_WRITER_PACK") and self.RESTORE_PASS in reader.stdout:
            expected = self.RESTORE_PASS
        self.assertIn(expected, reader.stdout)

    def test_fresh_reader_rejects_a_wrong_saved_working_hash(self):
        ...
        reader = self.run_reader("reader")
        if self.RESTART_PASS in reader.stdout:
            self.skipTest("the writer pack carries older content; no session survives to compare hashes")
        self.assertNotEqual(reader.returncode, 0, reader.stdout)
        self.assertIn("FAIL: fresh reader hash differs immediately after restoration", reader.stdout)
```

- [ ] **Step 5: 통과 확인**

Run: `bash scripts/check.sh m4` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py` → 10 checks OK (같은 콘텐츠, 기존 경로).

두 PCK 검사. 콘텐츠 4 PCK는 `1ca2424`에서 만듭니다(세션 scratchpad 아래, 절대 경로).

```bash
git -C /Users/dongminyu/Development/01_personal/chef-al-mando archive --format=tar --prefix=content4/ 1ca2424 > <scratchpad>/content4.tar
tar -xf <scratchpad>/content4.tar -C <scratchpad>
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content4 --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content4 --export-pack Android <scratchpad>/content4.pck
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <worktree> --export-pack Android <scratchpad>/content5.pck
M4_WRITER_PACK=<scratchpad>/content4.pck M4_READER_PACK=<scratchpad>/content5.pck GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py
```

Expected: `test_fresh_process_restores_partial_session_and_preferences`가 `RESTART_PASS`로 통과하고 `test_fresh_reader_rejects_a_wrong_saved_working_hash`는 skip, 나머지는 OK. 실패를 먼저 보려면 `_content_update_restarts_session`을 잠시 `< 4`로 되돌려 reader가 `corrupt_records`로 실패하는지 확인한 뒤 되돌립니다.

- [ ] **Step 6: Commit**

```bash
git add persistence/campaign_store.gd tests/test_m4_store.gd tests/check_m4_restart.gd tests/test_m4_restart.py
git commit -m "feat(persistence): bump content to version 5 and restart every earlier session"
```

---

### Task 6: 명세 정정, 지침, export 검사

**Files:**

- Modify: `docs/specs/mise-forecast-reviews.md` §5.1, §12
- Modify: `AGENTS.md:168`
- Modify: `docs/plans/mise-items-implementation.md` (이 문서: 실행 중 갈린 지점의 정정 절)

- [ ] **Step 1: 명세 §5.1 정정**

§5.1 표 아래에 "2026-09-XX 정정" 단락을 추가합니다. 내용: 레시피 재료 사전을 유지하기 위해 현미 볶음밥은 손질 양송이를, 토마토 베이스는 토마토 2개를 쓴다; 확정 표시명(원재료 4·메뉴 8·미장 6); 미장 ID; 프렙 생략 규칙은 계획 2a에서 "전부 있을 때만"이고 §5.3의 비율 시간·혼합 소비는 계획 2b에서 구현한다; 아이콘은 4단계로 미룬다. §12의 2단계 항목에 "(2a: 항목·이름·콘텐츠 5, 2b: 부분 프렙)"을 덧붙입니다.

- [ ] **Step 2: AGENTS.md**

168행의 미장 규칙 문장 뒤에 한 문장을 추가합니다: "Until plan 2b lands, the shipped rule skips prep only when every item is stocked and otherwise consumes the raw ingredients in full."

- [ ] **Step 3: export와 전체 회귀**

Run: `bash scripts/check-export.sh` → `PASS`.
Run: `python3 tests/test_export_check.py` → OK (10). Run: `python3 tests/test_ios_export.py` → OK (2). 둘 다 `.github/workflows/check.yml:51-53`의 호출 그대로입니다.
Run: 순서대로 `check.sh m0`, `m1`, `m2`, `m3`, `m4-core`, `m4`, `m5`, `mise`, `ui-regressions` → 모두 PASS. 각 suite의 checks 수를 이 문서의 정정 절에 적습니다.

- [ ] **Step 4: Commit**

```bash
git add docs/specs/mise-forecast-reviews.md AGENTS.md docs/plans/mise-items-implementation.md
git commit -m "docs(spec): record the reconciled mise table and the 2a/2b split"
```

---

## 완료 조건

- 모든 suite와 `check-export.sh`, `test_m4_restart.py`(같은 PCK와 콘텐츠 4→5 두 PCK)가 PASS입니다.
- 캠페인 재료 정의는 원재료 4 + 미장 6이고, 모든 표시명이 Global Constraints의 확정 세트이며, `en.po`가 새 이름과 브리핑을 모두 번역합니다.
- `set_prep`은 미장 ID만 받고, 준비 화면은 항목마다 이름·메뉴 수·원가·노동량·수량을 보이며, 마감 분석은 항목별 준비·사용·폐기를 냅니다.
- 콘텐츠 4 이하 문서는 기록을 보존한 채 진행 중 영업을 재시작하고 다음 저장에서 5가 됩니다.
- 시드 0의 3전략·무계획 격차 게이트가 통과하고 그 값이 `kitchen-pressure-verification.md`에 기록돼 있습니다.
- 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있습니다.

## 다음 계획

- 계획 2b(부분 프렙): §5.3의 비율 `prep` 시간과 부족 항목만 원재료로 소비하는 혼합 소비, 스냅샷 주문 필드 확장(`missing_mise_ids`, `prep_duration_ticks`)과 복원 검증, 마감 회계의 "그 항목이 비어서 원재료 경로로 간 주문 수"의 정확한 집계. 스냅샷 형식이 바뀌므로 진행 중 영업 재시작 규칙을 한 번 더 정합니다.
- 콘텐츠 계획: 시드 1~5 풀림 게이트(먼저 실패하는 fixture 확인) 뒤 `forecast_slack` 작성, 브리핑 인내 시간 표시.
- 3단계 리뷰, 4단계 화면(메뉴 상세·리뷰 패널·메뉴 아이콘), 6단계 문서는 명세 §12 순서대로입니다.
