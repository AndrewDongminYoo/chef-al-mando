# 부분 프렙 구현 계획 (계획 2b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 레시피의 미장 집합이 일부만 재고에 있을 때 있는 항목은 미장을, 없는 항목은 원재료를 정확히 한 번씩 소비하고 `prep` 시간을 부족 비율로 줄이며, 마감 회계가 "그 항목이 비어서 원재료 경로로 간 주문 수"를 항목별로 정확히 세게 합니다.

**Architecture:** 주문 스냅샷에 `missing_mise_ids`(예약 시점에 재고에 없던 미장 ID, 레시피 `mise_ids` 순서) 한 필드를 더하고, 한 주문이 예약·소비하는 입력을 `PreparationPlan.mise_inputs_for(data, recipe, missing_mise_ids)` 한 곳에서 계산해 시뮬레이션의 예약·소비, 복원 검증의 기대 입력·재고 재구성·원가, 준비 단계의 판매 가능 검사가 모두 같은 규칙을 씁니다. `prep` 시간은 `(prep.duration_ticks × 부족 항목 수 + 전체 - 1) / 전체`의 정수 올림으로 유도하며 스냅샷에 저장하지 않습니다. Task 1은 필드와 도우미만 넣는 동작 보존 단계이고, Task 2가 혼합 소비·비율 시간으로 규칙을 바꾸면서 시드 0 3전략 게이트를 같은 Task 안에서 다시 맞춥니다. Task 3이 마감 회계의 항목별 귀속으로 2a의 권고 역전을 고치고, Task 4가 콘텐츠 버전 6으로 버전 5 이하의 진행 중 영업을 재시작시키며, Task 5가 명세·지침·검증 기록을 정정하고 전체 회귀와 준비 화면 캡처를 남깁니다.

**Tech Stack:** Godot 4.7.2 GDScript(`--headless`), 저장소 자체 harness(`tests/harness.gd`, `scripts/check.sh <suite>`), Python `unittest`(`tests/test_m4_restart.py`).

**Spec:** `docs/specs/mise-forecast-reviews.md` §5.3(영업 중 규칙)·§5.4(마감 회계)·§8(저장과 버전)·§10(검증 계약 "회계 검사" 행). 계획 2a `docs/plans/mise-items-implementation.md`의 Global Constraints·"다음 계획"·"2026-09-20 정정" 절이 이 계획의 출발점이며, 그 절이 남긴 권고 역전과 `require_stock` 정정은 이 계획이 닫습니다.

## Global Constraints

- §5.3 그대로: 미장이 **모두** 있으면 `prep`을 건너뛰고 미장을 소비한다. 하나라도 없으면 냉식대에서 `prep`을 수행하고, 소요 시간은 `레시피 prep 시간 × (부족 항목 수 / 전체 항목 수)`를 올림한 값이며, 부족한 항목은 원재료를, 있는 항목은 미장을 소비하고 각 소비는 정확히 한 번이다. 예약과 소비의 원자성, 취소 시 예약 해제와 소비 손실 처리는 기존 규칙을 따른다. 미장 재고가 0이 되는 순간 `prepared_stock_depleted`를 항목 단위로 낸다.
- 올림은 정수 산술 `(duration_ticks * missing + total - 1) / total`로만 계산합니다. 해시 경로에 float를 두지 않습니다(§9 결정론).
- 스냅샷 주문 필드는 `missing_mise_ids` 하나만 추가합니다. `uses_prepared`는 "미장 집합 전체를 재고에서 예약·소비해 `prep`을 건너뛴다"는 뜻을 유지하고, `raw_consumed`는 "원재료를 하나라도 소비했다"는 뜻이 되며 기존 불변식 `raw_consumed == input_consumed and not uses_prepared`는 그대로 성립합니다. 계획 2a "다음 계획"이 적은 `prep_duration_ticks`는 `missing_mise_ids`와 레시피에서 유도되므로 저장하지 않습니다(한 사실은 한 곳에).
- 예약 시점의 재고는 복원 시점에 다시 알 수 없으므로 `missing_mise_ids`는 스냅샷에 남겨야 합니다. 복원 검증에서 `_mise_ready`나 현재 재고로 다시 계산하려 하면 안 됩니다.
- 혼합 예약은 전부 아니면 전무입니다. 있는 미장과 부족 항목의 원재료를 합친 집합이 가용 재고(`재고 - 예약`)에 모두 있어야 예약하고, 하나라도 모자라면 아무것도 예약하지 않고 `missing_ingredients`로 기다립니다.
- 콘텐츠 버전은 6, 저장 스키마는 4 그대로입니다. 버전 5 이하 문서는 읽기만으로 바꾸지 않고 다음 정상 저장에서 6으로 갱신하며, 스냅샷 주문 형식과 소비 규칙이 달라졌으므로 버전 5 이하의 진행 중 영업은 모든 시나리오에서 재시작합니다(§8, `docs/specs/m4-mobile.md`의 버전 이력 관례). `sim_version`은 건드리지 않습니다(불일치가 `unsupported_version`으로 파일 전체를 거부하는 필드이며 이 저장소에서 한 번도 올린 적이 없음).
- 3전략·무계획 격차 게이트(`check.sh m3`)는 시드 0에서 통과해야 합니다. 목표값(`minimum_served`·`minimum_profit`), `labor_units`, `prep_labor_capacity`, 원재료 발주량, 레시피 재료 사전은 바꾸지 않습니다. 정책(`tests/fixtures/m3_policies.gd`)만 조정하고 그 근거를 `docs/notes/kitchen-pressure-verification.md`에 정정 절로 남깁니다.
- `forecast_slack` 값은 이번 계획에서 하나도 쓰지 않으며 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있고 `service_seed`는 0입니다. 시드 1~5 풀림 게이트와 폭 작성은 이 계획 뒤의 콘텐츠 계획에 두며, 폭을 쓰는 계획은 먼저 그 게이트가 풀리지 않는 fixture에서 실패하는 것을 봐야 합니다.
- 세션에 들어가는 사전은 `dict["key"] = value`로만 씁니다(`dict.key`는 `StringName` 키). 검사 fixture의 typed export(`Dictionary[String, int]`)에는 typed 지역 변수만 `set()`합니다(untyped 리터럴은 `{}`로 남음). `ResourceLoader.CACHE_MODE_IGNORE`로 읽은 fixture는 서브 리소스까지 새 사본이므로 `set()`으로 바꿔도 됩니다.
- 새 검사는 잘못된 입력에서 먼저 실패하는 것을 확인한 뒤 통과시킵니다(§10). 모든 Godot 호출은 `--headless`이며 suite는 한 번에 하나만 실행합니다(16 GB Mac mini 규칙).
- 문서와 사용자 문구는 한국어, 코드 식별자와 커밋 메시지는 영어입니다. 커밋에 `Co-Author`나 `Claude-Session` 세션 URL을 붙이지 않습니다(서브에이전트 프롬프트마다 명시). 머지는 운영자가 합니다.
- 검사 명령: `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` 뒤에 `bash scripts/check.sh mise`, `bash scripts/check.sh m2`, `bash scripts/check.sh m3`, `bash scripts/check.sh m4`, `bash scripts/check.sh ui-regressions`, `bash scripts/check-export.sh`. 각 suite의 `PASS: <suite> checks=N failures=0` 줄이 통과 증거입니다.

---

## 파일 구조

| 파일                                                                                     | 책임                                                                                                              |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `sim/preparation_plan.gd`                                                                | `mise_inputs_for()`(Task 1), `missing_mise_ids()`와 혼합 규칙의 판매 가능 검사(Task 2)                            |
| `sim/service_sim.gd`                                                                     | `OrderState.missing_mise_ids`, 스냅샷·복원·재고 재구성·원가(Task 1), 혼합 예약·소비와 `_phase_duration()`(Task 2) |
| `sim/service_analysis.gd`                                                                | `raw_orders`의 항목별 귀속(Task 3)                                                                                |
| `presentation/main.gd`, `translations/en.po`                                             | `prep_at_capacity` 문구의 "메뉴" → "항목"(Task 3)                                                                 |
| `persistence/campaign_store.gd`                                                          | 콘텐츠 버전 6, 버전 5 이하의 진행 중 영업 재시작(Task 4)                                                          |
| `tests/test_mise_items.gd`                                                               | 필드·도우미 검사(Task 1), 부분 프렙 회계 검사(Task 2), 귀속 검사(Task 3)                                          |
| `tests/test_service_feedback.gd`                                                         | 손으로 만든 마감 view에 `missing_mise_ids` 추가(Task 3)                                                           |
| `tests/fixtures/m3_policies.gd`                                                          | 필요할 때만 시드 0 정책 재조정(Task 2)                                                                            |
| `tests/test_m4_store.gd`, `tests/test_menu_priorities.gd`, `tests/test_service_seed.gd`  | 콘텐츠 버전 리터럴 5 → 6, 버전 5 재시작 fixture(Task 4)                                                           |
| `tests/test_m4_restart.py`                                                               | `M4_EXPECT_RESTART` 환경 변수로 두 PCK 재시작 기대를 강제(Task 4)                                                 |
| `tests/capture_m3.gd`                                                                    | 준비 화면 행 탭 대상과 문구 수정, 캡처 실행(Task 5)                                                               |
| `docs/specs/mise-forecast-reviews.md`, `docs/specs/m4-mobile.md`, `AGENTS.md`            | §5.1·§8 정정, 버전 6 이력, 2b 전까지의 임시 문장 삭제(Task 5)                                                     |
| `docs/notes/kitchen-pressure-verification.md`, `docs/plans/mise-items-implementation.md` | 게이트 재조정 근거(Task 2)와 2a 정정 절의 후속 한 줄(Task 5)                                                      |
| `docs/plans/partial-prep-implementation.md`                                              | 이 문서: 실행 중 갈린 지점의 정정 절과 회귀 결과(Task 5)                                                          |

---

### Task 1: `missing_mise_ids` 필드와 `mise_inputs_for` 도우미 (동작 보존)

**Files:**

- Modify: `sim/preparation_plan.gd` (`mise_ready` 아래에 `mise_inputs_for` 추가)
- Modify: `sim/service_sim.gd` (`OrderState` 33행 부근, `_try_assignment` 300-301행, `_begin_work` 384-388행, `snapshot()` 525행, `restore()` 620-621행, `_order_restore_error()` 833-834·902-913행, `_mise_inputs()` 1003-1007행 삭제, `_inventory_restore_error()` 1152-1168행, `_consumed_cost()` 1174-1184행)
- Test: `tests/test_mise_items.gd` (`_test_mise_definitions`, `_test_mise_set_consumption`)

**Interfaces:**

- Consumes: `RecipeDef.mise_ids: PackedStringArray`, `IngredientDef.inputs: Dictionary[String, int]`, `Definitions.ingredient_for(id)`.
- Produces: `PreparationPlan.mise_inputs_for(data: Definitions, recipe: Definitions.RecipeDef, missing_mise_ids: Array) -> Dictionary` (키 순서: 미장 집합이 없으면 `recipe.ingredients` 순서, 있으면 `recipe.mise_ids` 순서로 있는 항목은 `mise_id: 1`, 부족 항목은 그 항목의 `inputs`를 누적). `OrderState.missing_mise_ids: Array[String]`. 스냅샷·`export_state()` 주문 사전에 `missing_mise_ids` 키(문자열 배열). 복원 거부 사유 `invalid_consumption`(비정규 배열 또는 `uses_prepared` 불일치), `invalid_inventory`(배열이 실제 소비와 다름). 이 Task 뒤 시뮬레이션은 여전히 전부-미장 또는 전부-원재료만 만들므로 회계·지표는 바뀌지 않고 `state_hash()`만 바뀝니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`의 `_test_mise_definitions()` 끝(`no_labor` 사례 뒤)에 음수 노동량 사례를 추가합니다(핸드오프 triage의 `negative_labor` 항목).

```gdscript
	var negative_labor := _fixture()
	_ingredient(negative_labor, "prepped_grill").set("labor_units", -1)
	expect(_has_error(negative_labor, "mise items need inputs and labor: prepped_grill"), "a mise item rejects negative labor")
```

`_test_mise_set_consumption()`의 부분 실행 expect(170-171행) 뒤와 전체 실행의 복원 expect(184-186행) 뒤에 아래를 추가합니다. `partial`·`full`·`data` 변수는 그 함수의 기존 변수입니다.

```gdscript
	expect(view.orders[0].missing_mise_ids == ["prepped_soup_grain", "prepped_soup_vegetable"],
		"a raw-path order records every mise item of its recipe as missing")
```

(전체 실행 뒤, `view = full.snapshot()` 다음)

```gdscript
	expect(view.orders[0].missing_mise_ids == [], "a fully prepared order records no missing mise item")
```

(복원 expect 뒤)

```gdscript
	var raw_state: Dictionary = partial.export_state()
	var reordered: Dictionary = raw_state.duplicate(true)
	reordered.orders[0].missing_mise_ids = ["prepped_soup_vegetable", "prepped_soup_grain"]
	var reordered_restore := ServiceSim.restore(data, reordered, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(not reordered_restore.accepted and reordered_restore.reason == "invalid_consumption",
		"restore rejects missing mise IDs that are not in recipe order")
	var unknown: Dictionary = raw_state.duplicate(true)
	unknown.orders[0].missing_mise_ids = ["prepped_soup_grain", "missing"]
	expect(not ServiceSim.restore(data, unknown, {"prep_quantities": {"prepped_soup_grain": 1}}).accepted,
		"restore rejects a missing mise ID the recipe does not use")
	var understated: Dictionary = raw_state.duplicate(true)
	understated.orders[0].missing_mise_ids = ["prepped_soup_grain"]
	var understated_restore := ServiceSim.restore(data, understated, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(not understated_restore.accepted and understated_restore.reason == "invalid_inventory",
		"restore rejects a missing list that does not explain the consumed inventory")
	var contradictory: Dictionary = full.export_state()
	contradictory.orders[0].missing_mise_ids = ["prepped_soup_grain", "prepped_soup_vegetable"]
	var contradictory_restore := ServiceSim.restore(data, contradictory, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	expect(not contradictory_restore.accepted and contradictory_restore.reason == "invalid_consumption",
		"restore rejects uses_prepared with a non-empty missing list")
```

`partial`은 `_run_until_consumed`로 원재료를 소비한 상태이므로 `raw_state`의 주문은 `input_consumed`이고 `missing_mise_ids`는 두 항목입니다. `understated`는 정규 순서의 부분집합이라 주문 규칙은 통과하지만 재고 재구성에서 `prepped_soup_vegetable`이 -1이 되어 `invalid_inventory`로 거부됩니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. 스냅샷에 `missing_mise_ids` 키가 없어 `Invalid access to property or key 'missing_mise_ids'` SCRIPT ERROR가 나거나 새 expect들이 실패합니다.

- [ ] **Step 3: `PreparationPlan.mise_inputs_for` 추가**

`sim/preparation_plan.gd` 끝의 `mise_ready` 아래에 추가합니다.

```gdscript
## 레시피 한 건이 예약·소비하는 입력. 미장 집합이 없으면 원재료 사전 그대로이고, 있으면 재고에 있는
## 항목은 그 미장 1개, missing_mise_ids에 든 항목은 그 항목의 원재료를 누적합니다. 키 순서는
## recipe.mise_ids 순서를 따르므로 같은 입력은 같은 스냅샷을 만듭니다.
static func mise_inputs_for(data: Definitions, recipe: Definitions.RecipeDef, missing_mise_ids: Array) -> Dictionary:
	var inputs: Dictionary = {}
	if recipe.mise_ids.is_empty():
		inputs.assign(recipe.ingredients)
		return inputs
	for mise_id: String in recipe.mise_ids:
		if mise_id in missing_mise_ids:
			var item := data.ingredient_for(mise_id)
			for input_id: String in item.inputs:
				inputs[input_id] = inputs.get(input_id, 0) + item.inputs[input_id]
		else:
			inputs[mise_id] = 1
	return inputs
```

- [ ] **Step 4: 시뮬레이션에 필드 추가(동작 보존)**

`sim/service_sim.gd`:

`OrderState`의 `var reserved_inputs: Dictionary[String, int] = {}` 다음 줄에:

```gdscript
	var missing_mise_ids: Array[String] = []
```

`_try_assignment`의 `order.uses_prepared = ...`(301행) 바로 뒤에:

```gdscript
				order.missing_mise_ids.clear()
				if not order.uses_prepared:
					for mise_id: String in order.recipe.mise_ids:
						order.missing_mise_ids.append(mise_id)
```

`_begin_work`의 소진 이벤트 블록(384-388행)을 아래로 바꿉니다. 원재료 경로는 `missing_mise_ids`가 집합 전체라 이벤트가 없고, 미장 경로는 집합 전체가 소비되므로 기존과 같은 이벤트가 납니다.

```gdscript
		for mise_id: String in order.recipe.mise_ids:
			if mise_id not in order.missing_mise_ids and _inventory[mise_id] == 0:
				_events.append({"kind": "prepared_stock_depleted", "order_id": order.id,
					"recipe_id": order.recipe.id, "ingredient_id": mise_id, "employee_id": task.employee_id})
```

`snapshot()`의 `"uses_prepared": order.uses_prepared,` 뒤에 `"missing_mise_ids": order.missing_mise_ids.duplicate(),`를 넣습니다. `export_state()`는 이 키를 지우지 않습니다.

`restore()`의 `order.reserved_inputs.assign(saved_order.reserved_inputs)` 다음 줄에:

```gdscript
		order.missing_mise_ids.assign(saved_order.missing_mise_ids)
```

`_order_restore_error()`의 `fields` 배열에서 `"uses_prepared"` 뒤에 `"missing_mise_ids"`를 넣습니다. `if not saved_order.reserved_inputs is Dictionary:` 검사 바로 뒤에:

```gdscript
	if not saved_order.missing_mise_ids is Array:
		return "invalid_order"
	var expected_missing: Array = []
	for mise_id: String in recipe.mise_ids:
		if mise_id in saved_order.missing_mise_ids:
			expected_missing.append(mise_id)
	if saved_order.missing_mise_ids != expected_missing:
		return "invalid_consumption"
	if (saved_order.ingredients_reserved or saved_order.input_consumed) \
		and saved_order.uses_prepared != (not recipe.mise_ids.is_empty() and saved_order.missing_mise_ids.is_empty()):
		return "invalid_consumption"
```

`expected_inputs` 줄(911행)을 바꿉니다.

```gdscript
		var expected_inputs: Dictionary = PreparationPlan.mise_inputs_for(data, recipe, saved_order.missing_mise_ids)
```

`_mise_inputs()` 정적 함수를 삭제합니다(다른 호출자 없음).

`_inventory_restore_error()`의 `if saved_order.uses_prepared:` … `else:` … 블록(1159-1168행)을 아래로 바꿉니다.

```gdscript
		if not saved_order.get("missing_mise_ids") is Array:
			return "invalid_order"
		var consumed: Dictionary = PreparationPlan.mise_inputs_for(data, recipe, saved_order.missing_mise_ids)
		for ingredient_id: String in consumed:
			if not initial_inventory.has(ingredient_id):
				return "invalid_order"
			initial_inventory[ingredient_id] -= consumed[ingredient_id]
```

`_consumed_cost()` 본문을 바꿉니다.

```gdscript
static func _consumed_cost(data: Definitions, order: OrderState) -> int:
	if not order.input_consumed:
		return 0
	var result: int = 0
	var consumed: Dictionary = PreparationPlan.mise_inputs_for(data, order.recipe, order.missing_mise_ids)
	for ingredient_id: String in consumed:
		result += data.ingredient_for(ingredient_id).unit_cost * consumed[ingredient_id]
	return result
```

- [ ] **Step 5: 통과 확인과 동작 보존 증거**

Run: `bash scripts/check.sh mise` → PASS(checks 수를 적어 둡니다).
Run: `bash scripts/check.sh m2` → PASS.
Run: `bash scripts/check.sh m4` → PASS.
Run: `bash scripts/check.sh m3` → PASS. 실행 전에 `cp build/check/m3.log <scratchpad>/m3-before-task1.log`로 origin/main 상태의 로그를 보관해 두고(Task 시작 전에 한 번 실행), 실행 뒤 `grep -E '^M3_(PRESSURE|STRATEGY|COMPARISON|PLAYTHROUGH) ' build/check/m3.log | sed -E 's/"hash": "[0-9a-f]+"/"hash": "-"/'`의 출력이 before 로그의 같은 추출과 `diff`로 동일한지 확인합니다. 회계·지표가 같으면 동작 보존이 증명된 것이고, 해시만 다릅니다.
Run: `bash scripts/check-export.sh` → PASS.

- [ ] **Step 6: Commit**

```bash
git add sim/preparation_plan.gd sim/service_sim.gd tests/test_mise_items.gd
git commit -m "feat(sim): record missing mise items per order and derive inputs from one helper"
```

---

### Task 2: 혼합 예약·소비, 비율 프렙 시간, 판매 가능 검사, 시드 0 게이트

**Files:**

- Modify: `sim/preparation_plan.gd` (`initial_state`의 `require_stock` 블록 288-300행, `missing_mise_ids()` 추가)
- Modify: `sim/service_sim.gd` (`_try_assignment` 300-301행, `_available_inputs` 322-331행, `_mise_ready` 334-340행 삭제, `_begin_work` 396행, `_order_restore_error` 994-1000행, `_phase_duration()` 추가)
- Modify: `tests/test_mise_items.gd` (`run`, `_test_mise_set_consumption`, 새 `_test_partial_prep`, `_test_shared_raw_stock`)
- Modify(필요할 때만): `tests/fixtures/m3_policies.gd`, `docs/notes/kitchen-pressure-verification.md`

**Interfaces:**

- Consumes: Task 1의 `mise_inputs_for`, `OrderState.missing_mise_ids`.
- Produces: `PreparationPlan.missing_mise_ids(available: Dictionary, recipe: Definitions.RecipeDef) -> Array[String]`(가용 재고가 0 이하인 미장 ID, 레시피 순서). `ServiceSim._phase_duration(recipe, phase, missing_mise_ids) -> int`(정적). 판매 가능 검사(`menu_missing_ingredients`)가 혼합 규칙을 따르므로 시뮬레이션 첫 주문과 준비 화면의 시작 가능 여부가 일치합니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`의 `run()`에 `_test_partial_prep()`과 `_test_shared_raw_stock()`을 `_test_mise_set_consumption()` 뒤에 추가합니다. `_test_mise_set_consumption()`에서는 부분 실행 블록(`var partial := ...`부터 Task 1이 넣은 "a raw-path order records every mise item" expect까지)과 Task 1의 `raw_state`·`reordered`·`unknown`·`understated` 검사를 삭제합니다. 그 함수에는 전체 실행(`full`) 검사, Task 1의 `missing_mise_ids == []` expect, `contradictory` 검사만 남습니다. 부분 경로의 검사는 아래 `_test_partial_prep`이 혼합 규칙 기준으로 다시 씁니다.

`_run_until_consumed` 아래에 술어 기반 도우미를 추가합니다.

```gdscript
func _run_until(simulation: ServiceSim, limit: int, done: Callable) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _step: int in limit:
		simulation.step()
		events.append_array(simulation.events())
		if done.call(simulation.snapshot()):
			break
	return events


func _three_item_soup_fixture() -> Resource:
	var data := _split_soup_fixture()
	var vegetable_item: Resource = _ingredient(data, "prepped_soup_vegetable")
	vegetable_item.set("inputs", _typed_inputs({"vegetable": 1}))
	vegetable_item.set("unit_cost", 100)
	var second_vegetable: Resource = vegetable_item.duplicate()
	second_vegetable.set("id", "prepped_soup_vegetable_2")
	var items: Array = data.get("ingredients").duplicate()
	items.append(second_vegetable)
	data.set("ingredients", items)
	var soup: Resource = data.call("recipe_for", "soup")
	soup.set("mise_ids", PackedStringArray(["prepped_soup_grain", "prepped_soup_vegetable", "prepped_soup_vegetable_2"]))
	soup.call("ordered_processes")[1].set("duration_ticks", 70)
	return data
```

새 검사:

```gdscript
func _test_partial_prep() -> void:
	var data := _split_soup_fixture()
	var options := {"prep_quantities": {"prepped_soup_grain": 1}}
	var partial := ServiceSim.new(data, null, options)
	expect(partial.errors.is_empty(), "one of two mise items can be prepared")
	_run_until(partial, 40, func(view: Dictionary) -> bool: return view.orders.size() > 0 and view.orders[0].ingredients_reserved)
	var view: Dictionary = partial.snapshot()
	expect(view.orders[0].reserved_inputs == {"prepped_soup_grain": 1, "vegetable": 2}
		and view.orders[0].missing_mise_ids == ["prepped_soup_vegetable"] and not view.orders[0].uses_prepared,
		"a recipe with one missing mise item reserves the stocked item and the raw inputs of the missing one")
	var events := _run_until(partial, 40, func(current: Dictionary) -> bool: return current.orders[0].input_consumed)
	view = partial.snapshot()
	expect(view.orders[0].raw_consumed and view.inventory.prepped_soup_grain == 0 and view.inventory.vegetable == 20
		and view.inventory.grain == 7 and view.orders[0].consumed_cost == 350,
		"mixed consumption spends the stocked item once and the missing item's raw inputs once")
	var depleted_ids: Array[String] = []
	for event: Dictionary in events:
		if event.kind == "prepared_stock_depleted":
			depleted_ids.append(event.ingredient_id)
	expect(depleted_ids == ["prepped_soup_grain"], "only the consumed mise item emits a depletion event")
	_run_until(partial, 200, func(current: Dictionary) -> bool: return current.orders[0].state == "working" and current.orders[0].phase_id == "prep")
	view = partial.snapshot()
	expect(view.orders[0].phase_id == "prep" and view.tasks.size() == 1
		and view.tasks[0].completion_tick - view.tasks[0].started_tick == 30,
		"prep for one missing item of two takes half the recipe prep time (60 × 1/2)")
	var working_restore := ServiceSim.restore(data, partial.export_state(), options)
	expect(working_restore.accepted and working_restore.simulation.state_hash() == partial.state_hash(),
		"a snapshot working on a scaled prep restores to the same hash")
	while not partial.closed:
		partial.step()
	view = partial.snapshot()
	expect(view.orders[0].state == "served", "the mixed order is served")
	var raw_state: Dictionary = partial.export_state()
	var reordered: Dictionary = raw_state.duplicate(true)
	reordered.orders[0].missing_mise_ids = ["prepped_soup_vegetable", "prepped_soup_grain"]
	expect(not ServiceSim.restore(data, reordered, options).accepted, "restore rejects missing mise IDs that are not in recipe order")
	var unknown: Dictionary = raw_state.duplicate(true)
	unknown.orders[0].missing_mise_ids = ["prepped_soup_grain", "missing"]
	expect(not ServiceSim.restore(data, unknown, options).accepted, "restore rejects a missing mise ID the recipe does not use")
	var understated: Dictionary = raw_state.duplicate(true)
	understated.orders[0].missing_mise_ids = []
	var understated_restore := ServiceSim.restore(data, understated, options)
	expect(not understated_restore.accepted and understated_restore.reason == "invalid_consumption",
		"restore rejects an empty missing list on an order that did not skip prep")
	var overstated: Dictionary = raw_state.duplicate(true)
	overstated.orders[0].missing_mise_ids = ["prepped_soup_grain", "prepped_soup_vegetable"]
	var overstated_restore := ServiceSim.restore(data, overstated, options)
	expect(not overstated_restore.accepted and overstated_restore.reason == "invalid_inventory",
		"restore rejects a missing list that claims raw grain was consumed while the grain item is gone")

	var three := _three_item_soup_fixture()
	expect(three.call("validate").is_empty(), "a three-item mise set whose inputs sum to the recipe validates")
	var two_missing := ServiceSim.new(three, null, {"prep_quantities": {"prepped_soup_grain": 1}})
	_run_until(two_missing, 200, func(current: Dictionary) -> bool: return current.orders.size() > 0 and current.orders[0].state == "working" and current.orders[0].phase_id == "prep")
	view = two_missing.snapshot()
	expect(view.orders[0].missing_mise_ids == ["prepped_soup_vegetable", "prepped_soup_vegetable_2"]
		and view.tasks[0].completion_tick - view.tasks[0].started_tick == 47,
		"two missing items of three round 70 × 2/3 up to 47 ticks")
	var one_missing := ServiceSim.new(three, null, {"prep_quantities": {"prepped_soup_grain": 1, "prepped_soup_vegetable": 1}})
	_run_until(one_missing, 200, func(current: Dictionary) -> bool: return current.orders.size() > 0 and current.orders[0].state == "working" and current.orders[0].phase_id == "prep")
	view = one_missing.snapshot()
	expect(view.orders[0].missing_mise_ids == ["prepped_soup_vegetable_2"]
		and view.tasks[0].completion_tick - view.tasks[0].started_tick == 24,
		"one missing item of three rounds 70 × 1/3 up to 24 ticks")

	var short := _split_soup_fixture()
	short.set("purchases", _typed_inputs({"vegetable": 2, "grain": 2, "protein": 0}))
	short.set("order_count", 2)
	var starved := ServiceSim.new(short, null, {"prep_quantities": {"prepped_soup_grain": 1}})
	expect(starved.errors.is_empty(), "one sellable soup lets the short fixture start")
	_run_until(starved, 400, func(current: Dictionary) -> bool: return current.orders.size() == 2 and current.orders[0].input_consumed and current.orders[1].wait_reason == "missing_ingredients")
	view = starved.snapshot()
	expect(view.orders[1].wait_reason == "missing_ingredients" and not view.orders[1].ingredients_reserved
		and view.orders[1].reserved_inputs.is_empty() and view.reserved.values().all(func(value: int) -> bool: return value == 0),
		"a mixed set that is short on raw inputs reserves nothing and waits")
```

`_split_soup_fixture`의 초기 재고는 채소 22·곡물 8이고 `prepped_soup_grain` 1개 준비가 곡물 1을 쓰므로, 혼합 소비 뒤 채소 20·곡물 7이 맞습니다. 세 항목 fixture는 `prep` 70 tick에 부족 2/3 → `(70 × 2 + 2) / 3 = 47`, 부족 1/3 → `(70 + 2) / 3 = 24`입니다. 짧은 fixture는 첫 주문이 곡물 미장 1개와 채소 2개를 다 쓰므로 두 번째 주문(첫 주문 10 tick, 간격 140 tick)은 두 항목 다 부족한데 채소가 0이라 아무것도 예약하지 않고 기다려야 합니다.

`_test_shared_raw_stock` (판매 가능 검사가 혼합 규칙을 따르는지):

```gdscript
## grain_salad는 prepped_vegetable을 salad에, prepped_grain 하나를 soup에 내주고 나면 손질 토마토는 없고
## 불린 현미만 남는 혼합 상태가 되는데, 원재료 곡물이 0이라 옛 전부-원재료 규칙으로는 팔 수 없고 혼합
## 규칙으로만 팔 수 있습니다.
func _test_shared_raw_stock() -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var scenario: Resource = campaign.call("scenario_for", "lunch_prep")
	var plan := PreparationPlan.new(scenario)
	expect(_command(plan, "set_purchase", "vegetable", 4, 1).accepted, "lunch_prep accepts a vegetable purchase of 4")
	expect(_command(plan, "set_purchase", "grain", 2, 2).accepted, "lunch_prep accepts a grain purchase of 2")
	expect(_command(plan, "set_prep", "prepped_vegetable", 1, 3).accepted, "one prepped_vegetable fits the labor budget")
	expect(_command(plan, "set_prep", "prepped_grain", 2, 4).accepted, "two prepped_grain fit the labor budget")
	expect(_command(plan, "set_prep", "soup_base", 1, 5).accepted, "one soup_base fits the labor budget")
	var snapshot: Dictionary = plan.snapshot()
	expect(snapshot.inventory.vegetable == 1 and snapshot.inventory.grain == 0,
		"the mixed-stock plan leaves one raw vegetable and no raw grain")
	expect(snapshot.can_start and snapshot.errors.is_empty(),
		"a menu whose missing item is covered by raw stock and whose other item is prepared counts as sellable")
```

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `_test_partial_prep`의 첫 expect(예약 입력이 `{"vegetable": 2, "grain": 1}`)와 `_test_shared_raw_stock`의 `can_start` expect가 실패합니다.

- [ ] **Step 3: `PreparationPlan.missing_mise_ids`와 판매 가능 검사**

`sim/preparation_plan.gd`의 `mise_ready` 위에 추가합니다.

```gdscript
## 가용 재고에서 레시피 한 건을 만들 때 재고에 없는 미장 항목. 레시피 mise_ids 순서를 지킵니다.
static func missing_mise_ids(available: Dictionary, recipe: Definitions.RecipeDef) -> Array[String]:
	var missing: Array[String] = []
	for mise_id: String in recipe.mise_ids:
		if available.get(mise_id, 0) <= 0:
			missing.append(mise_id)
	return missing
```

`initial_state`의 `require_stock` 블록을 바꿉니다.

```gdscript
	if require_stock:
		var available := inventory.duplicate()
		for recipe_id: String in data.menu_ids:
			var recipe := data.recipe_for(recipe_id)
			var inputs: Dictionary = mise_inputs_for(data, recipe, missing_mise_ids(available, recipe))
			for ingredient_id: String in inputs:
				if available[ingredient_id] < inputs[ingredient_id]:
					errors.append("menu_missing_ingredients")
					return result
			for ingredient_id: String in inputs:
				available[ingredient_id] -= inputs[ingredient_id]
```

`mise_ready`는 `test_mise_items.gd`가 쓰므로 그대로 둡니다.

- [ ] **Step 4: 시뮬레이션의 혼합 예약과 비율 시간**

`sim/service_sim.gd`:

`_available_inputs`를 바꾸고 `_mise_ready`를 삭제합니다.

```gdscript
func _available_inputs(order: OrderState) -> Dictionary[String, int]:
	var available: Dictionary[String, int] = {}
	for ingredient_id: String in _inventory:
		available[ingredient_id] = _inventory[ingredient_id] - _reserved[ingredient_id]
	var inputs: Dictionary[String, int] = {}
	inputs.assign(PreparationPlan.mise_inputs_for(_data, order.recipe, PreparationPlan.missing_mise_ids(available, order.recipe)))
	for ingredient_id: String in inputs:
		if available[ingredient_id] < inputs[ingredient_id]:
			return {}
	return inputs
```

`_try_assignment`의 `order.uses_prepared = ...`와 Task 1이 넣은 블록(300-305행)을 아래로 바꿉니다. 예약 입력에 없는 미장 ID가 곧 부족 항목입니다.

```gdscript
				order.reserved_inputs = inputs
				order.missing_mise_ids.clear()
				for mise_id: String in order.recipe.mise_ids:
					if not inputs.has(mise_id):
						order.missing_mise_ids.append(mise_id)
				order.uses_prepared = not order.recipe.mise_ids.is_empty() and order.missing_mise_ids.is_empty()
```

`_phase_duration`을 `_station_for` 위에 추가합니다.

```gdscript
## prep 공정만 부족 항목 비율로 줄어듭니다. 정수 올림이라 해시 경로에 float가 없고, 집합 전체가
## 재고에 있는 주문은 0을 돌려주지만 그 주문은 prep 자체를 건너뜁니다.
static func _phase_duration(recipe: RecipeDef, phase: ProcessDef, missing_mise_ids: Array) -> int:
	if phase.id != "prep" or recipe.mise_ids.is_empty():
		return phase.duration_ticks
	var total: int = recipe.mise_ids.size()
	@warning_ignore("integer_division")
	return (phase.duration_ticks * missing_mise_ids.size() + total - 1) / total
```

`_begin_work`의 마지막 줄을 바꿉니다.

```gdscript
	task.completion_tick = tick + _phase_duration(order.recipe, order.phases[order.phase_index], order.missing_mise_ids)
```

`_order_restore_error`의 작업 중 검사(994-1000행)를 바꿉니다.

```gdscript
			if task.completion_tick != task.started_tick + _phase_duration(recipe, phases[saved_order.phase_index], saved_order.missing_mise_ids) \
				or task.completion_tick <= state.tick:
				return "invalid_task"
			var expected_working_ticks: int = state.tick - task.started_tick + 1
			for index: int in saved_order.phase_index:
				if not saved_order.uses_prepared or phases[index].id != "prep":
					expected_working_ticks += _phase_duration(recipe, phases[index], saved_order.missing_mise_ids)
```

세 곳(`_begin_work`, 완료 tick 검사, 작업 tick 합)이 같은 함수를 써야 합니다. 하나라도 원래 `duration_ticks`를 읽으면 부분 프렙 중 스냅샷의 복원이 `invalid_task`나 `invalid_metrics`로 거부됩니다. `_complete_work`의 238행(`uses_prepared`이면 `prep` 건너뜀)은 그대로입니다. 혼합 주문은 `uses_prepared`가 false라 `prep`을 수행합니다.

- [ ] **Step 5: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS.
Run: `bash scripts/check.sh m2` → PASS.
Run: `bash scripts/check.sh m4` → PASS.
Run: `bash scripts/check.sh ui-regressions` → PASS.

- [ ] **Step 6: 시드 0 게이트 확인**

Run: `bash scripts/check.sh m3`

혼합 소비는 시나리오 결과를 바꿉니다. `lunch_prep` 기준 정책(`prepped_grain` 4, `soup_base` 4, `prepped_vegetable` 1)에서 손질 토마토 1개를 첫 샐러드가 쓰고 나면 현미 샐러드는 불린 현미만 있는 혼합 주문이 되어 2a에서는 전부 원재료였고 지금은 절반 `prep`으로 빨라집니다. 그러므로 `M3_PRESSURE`·`M3_STRATEGY` 회계는 달라지는 것이 정상이며, 게이트가 보는 것은 관계식입니다: 기준 정책은 두 목표를 통과하되 여분이 제공 1건·손익 2,000 이하, 무계획은 2건 이상 또는 1,500 이상 미달, 대체 정책 둘은 통과하고 세 최종 상태가 서로 다름, `_compare_choices`의 `prep` 변형은 `working` tick을 줄임.

PASS이면 Step 7로 갑니다. FAIL이면 `build/check/m3.log`의 실패한 expect 문장과 `M3_PRESSURE`·`M3_STRATEGY` 줄을 읽고, 아래 스윕으로 정책만 조정합니다. 목표값·`labor_units`·`prep_labor_capacity`·발주량은 바꾸지 않습니다.

scratchpad에 `sweep.gd`를 씁니다(커밋하지 않음). `<scenario_id>`와 후보 항목·상한을 실패한 시나리오에 맞게 적습니다.

```gdscript
extends SceneTree

const Policies := preload("res://tests/fixtures/m3_policies.gd")


func _init() -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var scenario: Resource = campaign.scenario_for("lunch_prep")
	var items: Array[String] = ["prepped_vegetable", "prepped_grain", "soup_base"]
	var capacity: int = scenario.prep_labor_capacity
	var quantities: Array[int] = [0, 0, 0]
	var found: int = 0
	_sweep(scenario, items, capacity, quantities, 0, found)
	quit(0)


func _sweep(scenario: Resource, items: Array[String], capacity: int, quantities: Array[int], index: int, found: int) -> void:
	if index == items.size():
		var labor: int = 0
		var policy := {"preparation": [], "priorities": {}}
		for position: int in items.size():
			labor += quantities[position] * scenario.ingredient_for(items[position]).labor_units
			if quantities[position] > 0:
				policy.preparation.append({"kind": "set_prep", "target_id": items[position], "value": quantities[position]})
		if labor > capacity:
			return
		var run := Policies.run_policy(scenario, policy)
		if not run.accepted:
			return
		var accounting: Dictionary = run.snapshot.accounting
		if accounting.served >= scenario.minimum_served and accounting.profit >= scenario.minimum_profit:
			print("SWEEP ", JSON.stringify({"quantities": quantities, "labor": labor, "served": accounting.served,
				"profit": accounting.profit, "working": run.snapshot.metrics.orders.working}))
		return
	for quantity: int in capacity + 1:
		quantities[index] = quantity
		_sweep(scenario, items, capacity, quantities, index + 1, found)
```

Run: `"$GODOT_BIN" --headless --path <worktree> --script <scratchpad>/sweep.gd > <scratchpad>/sweep-lunch_prep.log` (다른 Godot 프로세스와 동시에 돌리지 않음).

통과 조합 가운데 기준 정책은 "여분 제공 ≤ 1, 여분 손익 ≤ 2,000"을 만족하고 대체 정책과 최종 상태가 다른 것을 고릅니다. 무계획 결과는 프렙이 없어 이 Task에서 바뀌지 않으므로 `M3_PRESSURE`의 `no_plan`은 2a 표와 같아야 합니다(다르면 혼합 소비 코드에 결함이 있는 것이니 Step 4로 돌아갑니다). `tests/fixtures/m3_policies.gd`의 해당 시나리오 정책만 바꾸고 `bash scripts/check.sh m3`를 다시 돌립니다. `tests/test_m3_ui.gd`는 기준 정책 명령 수를 세므로 checks 수가 달라질 수 있습니다.

정책을 바꿨다면 `docs/notes/kitchen-pressure-verification.md`의 "2026-09-20 정정: 미장 항목 기준" 절 뒤에 "2026-09-XX 정정: 부분 프렙 기준" 절을 추가합니다. 내용: 혼합 소비·비율 시간이 결과를 바꾼 이유(한 문단), 바뀐 시나리오별 이전·이후 정책과 `M3_PRESSURE` 회계(표), 스윕한 조합 수와 로그 경로, 목표·노동량·상한·발주가 바뀌지 않았다는 문장, 권위는 커밋된 `m3_policies.gd`에 있다는 문장. 정책을 바꾸지 않았어도 같은 절에 "정책 변경 없이 통과했고 회계는 다음과 같이 움직였다"를 `M3_PRESSURE` 표로 남깁니다.

- [ ] **Step 7: Commit**

코드와 검사를 먼저, 정책 재조정과 기록을 그 다음 커밋으로 나눕니다. 첫 커밋 시점에 `m3`가 실패 상태였다면 두 번째 커밋 메시지 본문에 그 사실과 통과한 checks 수를 적습니다. 정책을 바꾸지 않았으면 두 번째 커밋은 기록 파일만 담습니다.

```bash
git add sim/preparation_plan.gd sim/service_sim.gd tests/test_mise_items.gd
git commit -m "feat(sim): consume stocked mise items and scale prep time by the missing fraction"
git add tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "test(m3): retune seed-0 policies for partial prep and record the sweep"
```

---

### Task 3: 항목별 원재료 귀속과 프렙 권고, 문구

**Files:**

- Modify: `sim/service_analysis.gd:25-26`
- Modify: `presentation/main.gd:859`, `translations/en.po:758-759`
- Modify: `tests/test_service_feedback.gd:140-142`, `:186-188`
- Test: `tests/test_mise_items.gd` (새 `_test_raw_attribution`)

**Interfaces:**

- Consumes: 스냅샷 주문의 `raw_consumed`, `missing_mise_ids`.
- Produces: 마감 분석 `prep[<mise_id>].raw_orders` = "이 항목이 비어서 원재료를 쓴 주문 수"(§5.4). `_prep_recommendation`의 점수식은 바꾸지 않습니다. 2a의 역전은 혼합 소비가 재고 항목을 실제로 쓰게 하고 귀속이 정확해지면서 사라집니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_mise_items.gd`의 `run()`에 `_test_raw_attribution()`을 추가하고 아래를 씁니다. 계획 2a 정정 절이 기록한 재현(`lunch_prep`에서 `prepped_grain` 4개만 준비)을 그대로 씁니다.

```gdscript
## 계획 2a에서는 불린 현미만 준비하면 현미 샐러드·수프가 전부 원재료 경로로 가서 현미가 남았고, 마감 조언이
## "불린 현미 1개 줄여 보세요"라고 말했습니다. 혼합 소비 뒤에는 현미가 실제로 쓰이고, 원재료 경로 주문 수는
## 비어 있던 항목에만 귀속됩니다.
func _test_raw_attribution() -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var plan := PreparationPlan.new(campaign.call("scenario_for", "lunch_prep"))
	expect(_command(plan, "set_prep", "prepped_grain", 4, 1).accepted, "lunch_prep prepares four grain items only")
	var started := _command(plan, "start", "", null, 2)
	expect(started.accepted, "the grain-only lunch_prep plan starts")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	while not simulation.closed:
		simulation.step()
	var view: Dictionary = simulation.snapshot()
	var consumed := {"salad": 0, "soup": 0, "grain_salad": 0}
	for order: Dictionary in view.orders:
		if order.input_consumed:
			consumed[order.recipe_id] += 1
	var report: Dictionary = ServiceAnalysis.build(started.definitions, view, started.selection)
	var grain_row: Dictionary = report.prep.prepped_grain
	var vegetable_row: Dictionary = report.prep.prepped_vegetable
	var base_row: Dictionary = report.prep.soup_base
	expect(consumed.soup + consumed.grain_salad >= 4 and grain_row.used == 4 and grain_row.remaining == 0,
		"mixed consumption spends every prepared grain item on the first grain orders")
	expect(grain_row.raw_orders == consumed.soup + consumed.grain_salad - 4,
		"raw orders are attributed to the grain item only once its stock is gone")
	expect(vegetable_row.raw_orders == consumed.salad + consumed.grain_salad and base_row.raw_orders == consumed.soup,
		"raw orders are attributed to each never-prepared item exactly once per consumed order")
	var prep_advice: Dictionary = {}
	for recommendation: Dictionary in report.recommendations:
		if recommendation.category == "prep":
			prep_advice = recommendation
	expect(not prep_advice.is_empty() and not (prep_advice.action == "reduce_prep" and prep_advice.target_id == "prepped_grain"),
		"the closing advice no longer tells the player to reduce the grain item that ran out")
```

`tests/test_service_feedback.gd`의 손으로 만든 두 view에 `missing_mise_ids`를 넣습니다. 141행의 grill 주문 사전에 `"missing_mise_ids": ["marinated_protein"],`을, 187행의 salad 주문 사전에 `"missing_mise_ids": ["prepped_vegetable"],`을 `"raw_consumed": true,` 바로 뒤에 추가합니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `grain_row.raw_orders`가 2a 근사(현미를 쓰는 메뉴의 원재료 경로 주문 전부)로 세어져 `consumed.soup + consumed.grain_salad - 4`보다 큽니다.

- [ ] **Step 3: 귀속 구현**

`sim/service_analysis.gd` 25-26행을 바꿉니다.

```gdscript
			if order.raw_consumed and item.id in order.missing_mise_ids:
				prep_row.raw_orders += 1
```

- [ ] **Step 4: 문구**

`presentation/main.gd` 859행의 `prep_at_capacity` 문구에서 `다른 메뉴에 프렙이 남았다면 옮기세요.`를 `다른 항목에 프렙이 남았다면 옮기세요.`로 바꿉니다. `translations/en.po` 758행의 msgid를 같은 문장으로 바꾸고 759행 msgstr의 `from another menu`를 `from another item`으로 바꿉니다. `increase_prep`의 "생재료 손질 %d건"은 이제 정확한 항목별 수를 보이므로 msgid를 유지합니다.

- [ ] **Step 5: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS.
Run: `bash scripts/check.sh m2` → PASS(`test_service_feedback.gd` 포함).
Run: `bash scripts/check.sh ui-regressions` → PASS.
Run: `grep -c '다른 메뉴에 프렙이' presentation/main.gd translations/en.po` → 각 0.

- [ ] **Step 6: Commit**

```bash
git add sim/service_analysis.gd presentation/main.gd translations/en.po tests/test_mise_items.gd tests/test_service_feedback.gd
git commit -m "feat(analysis): attribute raw-path orders to the mise item that was missing"
```

---

### Task 4: 콘텐츠 버전 6, 진행 중 영업 재시작, 두 PCK

**Files:**

- Modify: `persistence/campaign_store.gd:6`, `:171`, `:233-235`
- Modify: `tests/test_m4_store.gd` (`content_version == 5` 기대 46·171·186·214행, 문서 리터럴 53·452·489·537행, 버전 4 검사 뒤 버전 5 검사 추가)
- Modify: `tests/test_menu_priorities.gd:111`, `tests/test_service_seed.gd:341`, `:359`
- Modify: `tests/test_m4_restart.py:236-238`

**Interfaces:**

- Consumes: 계획 2a Task 5의 재시작 경로(`_content_update_restarts_session`, `content_updated`).
- Produces: `CampaignStore.VERSIONS.content_version == 6`. 콘텐츠 5 이하 문서는 `content_updated`로 읽히고 `active_session`은 `null`, 기록은 보존, 파일은 다음 저장까지 그대로. `M4_EXPECT_RESTART=1`이면 `test_m4_restart.py`가 두 PCK 실행에서 `RESTART_PASS`만 받아들입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_m4_store.gd`의 버전 4 검사 블록(199-215행) 뒤에 추가합니다. 현재 콘텐츠로 만든 세션은 `missing_mise_ids`를 가지므로 세션 자체는 정상이고, 문서의 버전만 5입니다.

```gdscript
	var version_five_target := directory + "/content_version_five.json"
	var version_five_session := _scenario_session(campaign, "lunch_prep")
	_write(version_five_target, JSON.stringify({"schema_version": 4, "content_version": 5, "sim_version": 1,
		"records": current_records, "attempts": {}, "active_session": version_five_session}))
	var version_five_bytes := FileAccess.get_file_as_bytes(version_five_target)
	loaded = CampaignStore.new(campaign, version_five_target).load_records()
	expect(loaded.accepted and loaded.reason == "content_updated" and loaded.records == current_records
		and loaded.active_session == null,
		"partial prep restarts a version 5 session because its order snapshot and consumption rules changed")
	expect(FileAccess.get_file_as_bytes(version_five_target) == version_five_bytes,
		"restarting a version 5 session leaves the old file unchanged until the next write")
	expect(CampaignStore.new(campaign, version_five_target).save_records(current_records).accepted,
		"the next write upgrades a version 5 record to content version 6")
	var version_five_migrated: Variant = JSON.parse_string(FileAccess.get_file_as_string(version_five_target))
	expect(version_five_migrated is Dictionary and version_five_migrated.content_version == 6,
		"a migrated version 5 record writes content version 6")
```

같은 파일에서 `content_version == 5`를 기대하는 46·171·186·214행을 `== 6`으로 바꿉니다. 현재 콘텐츠의 정상 세션을 담는 문서 리터럴 53·452·489·537행의 `"content_version": 5`를 `6`으로 바꿉니다(5로 두면 `content_updated`가 세션을 `null`로 만들어 그 검사들이 실패합니다). `tests/test_menu_priorities.gd:111`과 `tests/test_service_seed.gd:341`·`:359`의 `"content_version": 5`도 `6`으로 바꿉니다. `test_service_seed.gd` 308·317·323·329·353행의 `content_version: 4` 문서는 재시작·손상 검사이므로 그대로입니다.

`tests/test_m4_restart.py` 236-238행을 바꿉니다.

```python
        expected = self.RESTART_PASS if os.environ.get("M4_WRITER_PACK") else self.RESTORE_PASS
        if os.environ.get("M4_WRITER_PACK") and not os.environ.get("M4_EXPECT_RESTART") and self.RESTORE_PASS in reader.stdout:
            expected = self.RESTORE_PASS
        self.assertIn(expected, reader.stdout)
```

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh m4`
Expected: FAIL. 버전 5 문서가 `loaded`로 읽혀 `content_updated`·`null` 기대가 실패하고, `== 6` 기대가 실패합니다.

- [ ] **Step 3: 버전 6**

`persistence/campaign_store.gd`:

```gdscript
const VERSIONS := {"schema_version": 4, "content_version": 6, "sim_version": 1}
```

171행의 목록에 5를 넣습니다.

```gdscript
		if key == "content_version" and int(version) in [LEGACY_CONTENT_VERSION, 2, 3, 4, 5]:
```

`_content_update_restarts_session`을 바꿉니다.

```gdscript
func _content_update_restarts_session(source_content_version: int, _active_session: Dictionary) -> bool:
	# Content 5 keyed prep quantities by mise item and content 6 added missing_mise_ids to every order
	# snapshot with mixed consumption, so no earlier session can restore.
	return source_content_version < 6
```

- [ ] **Step 4: 통과 확인과 두 PCK**

Run: `bash scripts/check.sh m4` → PASS.
Run: `bash scripts/check.sh mise` → PASS(`test_service_seed.gd` 포함).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py` → 10 checks OK(같은 콘텐츠, 기존 경로).

두 PCK 검사. 콘텐츠 5 PCK는 `c600e27`에서 만듭니다(세션 scratchpad 아래, 절대 경로).

```bash
git -C /Users/dongminyu/Development/01_personal/chef-al-mando archive --format=tar --prefix=content5/ c600e27 --output <scratchpad>/content5.tar
tar -xf <scratchpad>/content5.tar -C <scratchpad>
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content5 --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content5 --export-pack Android <scratchpad>/content5.pck
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <worktree> --export-pack Android <scratchpad>/content6.pck
M4_EXPECT_RESTART=1 M4_WRITER_PACK=<scratchpad>/content5.pck M4_READER_PACK=<scratchpad>/content6.pck GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py
```

Expected: `test_fresh_process_restores_partial_session_and_preferences`가 `RESTART_PASS`로 통과하고 `test_fresh_reader_rejects_a_wrong_saved_working_hash`는 skip, 나머지는 OK(2a 기록: 9 OK / 1 skip). 실패를 먼저 보려면 `_content_update_restarts_session`을 잠시 `< 5`로 되돌려 reader가 `corrupt_records`로 실패하는지 확인한 뒤 되돌립니다. `M4_EXPECT_RESTART`가 없으면 같은 실행이 `RESTORE_PASS`도 받아들이므로, 강제 실패 확인은 반드시 변수를 켠 채로 합니다.

- [ ] **Step 5: Commit**

```bash
git add persistence/campaign_store.gd tests/test_m4_store.gd tests/test_menu_priorities.gd tests/test_service_seed.gd tests/test_m4_restart.py
git commit -m "feat(persistence): bump content to version 6 and restart every earlier session"
```

---

### Task 5: 명세·지침·기록 정정, 전체 회귀, 준비 화면 캡처

**Files:**

- Modify: `docs/specs/mise-forecast-reviews.md` (§5.1 정정 단락 뒤, §8 첫 항목)
- Modify: `docs/specs/m4-mobile.md:76-77` 뒤
- Modify: `AGENTS.md:168`
- Modify: `docs/plans/mise-items-implementation.md` (2026-09-20 정정 절 끝)
- Modify: `tests/capture_m3.gd:51-57`
- Modify: `docs/plans/partial-prep-implementation.md` (이 문서: 정정 절과 회귀 결과)

**Interfaces:**

- Consumes: Task 1~4의 커밋과 Task 2의 기록 절.
- Produces: 문서가 머지된 코드와 일치하고, 전체 suite의 checks 수와 준비 화면 캡처 PNG 경로가 이 문서에 남습니다.

- [ ] **Step 1: 명세 §5.1·§8 정정**

`docs/specs/mise-forecast-reviews.md` §5.1의 "2026-09-20 정정" 단락 뒤에 한 단락을 추가합니다.

```markdown
**2026-09-XX 정정:** 계획 2b(`../plans/partial-prep-implementation.md`)가 §5.3의 비율 시간과 혼합 소비, §5.4의 항목별 원재료 경로 주문 수를 구현했습니다.
스냅샷 주문에는 예약 시점에 재고에 없던 미장 ID 배열 `missing_mise_ids`만 추가하고, `prep` 시간은 그 배열과 레시피에서 정수 올림으로 유도하며 저장하지 않습니다.
준비 단계의 판매 가능 검사도 같은 혼합 규칙을 따릅니다.
```

§8 첫 항목("콘텐츠 버전 5.") 뒤에 항목을 추가합니다.

```markdown
- **콘텐츠 버전 6.** 부분 프렙이 주문 스냅샷 형식과 소비 규칙을 바꾸므로 버전 5 이하의 진행 중 영업은 모든 시나리오에서 다시 시작하고, 완료·최고 기록과 준비 기본값은 보존합니다.
```

- [ ] **Step 2: 저장 명세와 지침**

`docs/specs/m4-mobile.md` 77행("콘텐츠 버전 4는 … 버전 5로 갱신합니다.") 뒤에 두 줄을 추가합니다.

```markdown
2026-09-XX 승인된 부분 프렙은 새 쓰기의 `content_version`을 6으로 올립니다.
콘텐츠 버전 5는 완료·최고 기록을 그대로 유지하고 주문 스냅샷 형식과 소비 규칙이 달라졌으므로 모든 시나리오의 진행 중 영업을 `null`로 해석하며, 다음 정상 쓰기에서 버전 6으로 갱신합니다.
```

`AGENTS.md` 168행에서 `Until plan 2b lands, the shipped rule skips prep only when every item is stocked and otherwise consumes the raw ingredients in full.` 문장을 삭제합니다(수정이 아니라 삭제). 남는 문장이 구현된 규칙 그대로입니다.

`docs/plans/mise-items-implementation.md`의 "2026-09-20 정정" 절 마지막 항목 뒤에 항목 하나를 추가합니다.

```markdown
- 이 문서 "다음 계획"이 적은 스냅샷 필드 `prep_duration_ticks`는 계획 2b(`partial-prep-implementation.md`)에서 저장하지 않고 `missing_mise_ids`와 레시피에서 유도하기로 했습니다.
  `_prep_recommendation` 역전과 `require_stock` 근사는 계획 2b가 닫았습니다.
```

Run: `grep -rn 'Until plan 2b\|2b에서 구현\|계획 2b가 맡' AGENTS.md docs/specs README.md docs/plans/PLAN.md` → 남는 줄이 있으면 각각 읽고, 미래형으로 2b를 가리키는 문장만 과거형 정정으로 바꿉니다(§5.1 2026-09-20 정정 단락의 두 문장은 그날의 기록이므로 그대로 둡니다).

- [ ] **Step 3: 준비 화면 캡처와 행 탭 수정**

`tests/capture_m3.gd` 52-57행에서 `thawed_protein` 세 곳을 `marinated_protein`으로, expect 문구 `"the eighth-menu preparation row accepts an actual coordinate tap"`을 `"the last mise row accepts an actual coordinate tap"`으로, 파일명 `m3-eight-menu-preparation.png`를 `m3-last-mise-row-preparation.png`로 바꿉니다. `final_service`의 미장 6종 가운데 `marinated_protein`이 재료 배열의 마지막이라 스크롤 끝의 행을 검증합니다(`content/campaign/scenarios/final_service.tres`의 `ingredients` 배열 순서를 읽어 확인하고, 다르면 실제 마지막 미장 ID를 씁니다).

Run: `"$GODOT_BIN" --path <worktree> --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd` → `PASS`.
Run: `"$GODOT_BIN" --path <worktree> --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd -- --phone-wide` → `PASS`.

`build/check/m3-first-preparation.png`와 `build/check/m3-last-mise-row-preparation.png`를 Read 도구로 열어 봅니다. 확인할 것: 미장 여섯 행이 모두 보이거나 스크롤로 닿는가, 긴 이름(`재운 연어`, `토마토 베이스`)이 수량·원가 열과 겹치지 않는가, 마지막 행의 `+`가 안전 영역 안에 있는가. 문제가 보이면 고치지 말고 이 문서의 정정 절에 "화면 계획(§12 4단계)으로 넘김"과 함께 적습니다.

- [ ] **Step 4: 전체 회귀**

Run(순서대로, 한 번에 하나): `bash scripts/check-export.sh`, `python3 tests/test_export_check.py`, `python3 tests/test_ios_export.py`, `bash scripts/check.sh m0`, `m1`, `m2`, `m3`, `m4-core`, `m4`, `m5`, `mise`, `ui-regressions` → 모두 PASS.

이 문서 끝에 "## 2026-09-XX 정정" 절(Task 1~4 실행 중 이 계획과 실제 커밋이 갈린 지점, 게이트 재조정 여부, 캡처 관찰)과 "### Task 5 회귀 결과" 절(위 명령과 checks 수를 `log` 블록으로)을 추가합니다. 두 PCK 결과는 Task 4의 값을 인용합니다.

- [ ] **Step 5: Commit**

```bash
git add docs/specs/mise-forecast-reviews.md docs/specs/m4-mobile.md AGENTS.md docs/plans/mise-items-implementation.md docs/plans/partial-prep-implementation.md tests/capture_m3.gd
git commit -m "docs: record partial prep in the spec, storage history and plans"
```

---

## 완료 조건

- 모든 suite와 `check-export.sh`, `test_m4_restart.py`(같은 PCK와 콘텐츠 5→6 두 PCK, `M4_EXPECT_RESTART=1`)가 PASS입니다.
- 미장이 일부만 있는 주문은 있는 항목의 미장과 부족 항목의 원재료를 정확히 한 번씩 소비하고, `prep` 시간이 부족 비율의 정수 올림이며, 그 상태의 스냅샷이 같은 해시로 복원됩니다.
- 마감 분석의 `raw_orders`는 항목이 비어서 원재료를 쓴 주문 수이고, `lunch_prep`의 `prepped_grain` 4개 fixture에서 마감 조언이 현미를 줄이라고 말하지 않습니다.
- 콘텐츠 5 이하 문서는 기록을 보존한 채 진행 중 영업을 재시작하고 다음 저장에서 6이 됩니다.
- 시드 0의 3전략·무계획 격차 게이트가 통과하고, 정책을 바꿨든 아니든 그 회계가 `kitchen-pressure-verification.md`에 기록돼 있습니다.
- `AGENTS.md`에 "Until plan 2b lands" 문장이 없고, 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있습니다.

## 알려진 한계 (이 계획이 손대지 않는 것)

- `presentation/main.gd` 899·909행의 직원 행동 문구는 `uses_prepared`로 "프렙 재료"와 "원재료"만 가르므로 혼합 주문은 "원재료 받으러"로 보입니다. 세 번째 문구는 msgid 추가가 필요하므로 §12 4단계 화면 계획에 둡니다.
- `_prep_recommendation`의 `planned > 0` 가산점(10000)은 그대로입니다. 남은 항목을 줄이라는 조언이 부족 항목을 늘리라는 조언보다 앞서는 순위 자체는 2a의 역전과 별개의 설계이며, 플레이테스트가 조언을 읽는 방식을 보기 전에는 바꾸지 않습니다.

## 다음 계획

- 콘텐츠 계획: 시드 1~5 풀림 게이트(먼저 실패하는 fixture 확인) 뒤 `forecast_slack` 작성, 브리핑 인내 시간 표시.
- 3단계 리뷰, 4단계 화면(메뉴 상세·리뷰 패널·메뉴 아이콘·혼합 주문 문구), 6단계 문서는 명세 §12 순서대로입니다.

## 2026-09-21 정정

아래 항목은 Task 1~5 실행 중 이 계획의 서술과 실제로 머지된 코드가 갈린 지점입니다.
이 절 위의 단계 서술은 고치지 않으며, 권위는 인용한 커밋의 코드와 테스트에 있습니다.

- Task 1(커밋 `42b76b5`)은 동작 보존이었고, 이 Task 뒤 `mise` checks 수는 254였습니다(계획은 수치를 예측하지 않았습니다).
  계획 Step 5의 sed 패턴 `"hash": "[0-9a-f]+"`(콜론 뒤 공백)는 Godot의 압축 JSON과 맞지 않아, 구현자는 `"hash":"[0-9a-f]+"`를 썼습니다.
  건드리지 않은 트리 대비 `M3_*` 정규화 diff는 비어 있었습니다.
- Task 2(코드 커밋 `e735f9a`, 재조정 커밋 `89d59c2`)에서 `check.sh m3`는 `e735f9a` 시점에 붉었습니다(1,113개 중 64개 실패).
  `shared_stock`·`split_duties`·`rush_hour`·`final_service`의 기준 정책과 대체 정책 넷이 혼합 소비 아래서 목표를 놓쳤고, `no_plan` 행은 모두 2026-09-20 표와 같았습니다.
  재조정한 정책(권위는 커밋된 `tests/fixtures/m3_policies.gd`; 근거는 `docs/notes/kitchen-pressure-verification.md`의 "2026-09-21 정정: 부분 프렙 기준"): `shared_stock` 기준 `1+6+2`(9/9), `split_duties` 기준은 기존 담당 배정에 `prepped_vegetable 6·prepped_grain 3·prepped_mushroom 4·thawed_protein 2`, `rush_hour`는 기준과 대체 A, `final_service` 기준은 우선순위 없이 `marinated_protein 5·prepped_grain 3`, 대체 B는 발주 `7→6`.
  이 Task 뒤 `m3` checks 수는 1,108이었습니다(`test_m3_ui.gd`가 기준 정책 명령 수를 세기 때문).
  범위 밖 수정: `tests/test_service_feedback.gd`의 shared-stock fixture를 `pv 1/2`에서 `pv 3/4`로 바꿨습니다.
  옛 fixture가 "전부 아니면 무" 규칙을 인코딩하고 있었기 때문이며, 리뷰어가 최소한의 적응이고 가드가 여전히 공허하지 않음을 확인했습니다.
- Task 2의 설계에 드러난 결과가 있습니다(컨트롤러 판정: 수용).
  게이트의 관계는 유지되고, 계획은 목표·발주량 변경을 금지합니다.
  둘 다 콘텐츠 계획 후보입니다.
  `PLAN.md` §12는 목표를 낮추는 것은 금지하지만, 올리는 것은 금지하지 않습니다.
  (1) `split_duties`는 이제 담당 배정 없이 `thawed_protein 1`만으로도 통과해, 담당 분리가 더 이상 필수 조건이 아닙니다.
  (2) `final_service`의 기준은 구이 우선순위 레버를 잃었습니다.
  구이 우선순위 2를 고정한 모든 스윕 조합(15,807가지 + 화구 2 배치를 더한 6,160가지)이 목표에 못 미쳤고, 우선순위 없는 스윕 범위(6,160가지)에서 통과하는 프렙-전용 조합이 정확히 하나뿐이라 이 스테이지는 knife edge 위에 있습니다.
  노트의 2026-09-20 산문이 마지막 스테이지를 "프렙·우선순위"로 묘사한 서술은 2026-09-21 절이 대체합니다.
- Task 3(커밋 `e030ac4`)의 곡물 전용 `lunch_prep`(`prepped_grain` 4개) fixture: salad 6·soup 6·grain_salad 6을 소비했고, `prepped_grain` 사용 4·잔여 0·`raw_orders` 8, `prepped_vegetable`의 `raw_orders` 12, `soup_base`의 `raw_orders` 6이었습니다.
  마감 조언은 이제 `increase_prep prepped_grain 1`입니다(계획 2a는 "불린 현미 1개 줄여 보세요"였습니다).
  이 Task 뒤 `mise` checks 수는 277이었습니다.
- Task 4(커밋 `312c969`)에서 콘텐츠 버전은 6이 됐고, 이 Task 뒤 `m4` checks 수는 1,201이었습니다.
  같은-PCK python 검사는 10개 OK, 두-PCK 교차(`c600e27`의 content5.pck 대 이 브랜치의 content6.pck, `M4_EXPECT_RESTART=1`)는 9개 OK·1개 skip(`RESTART_PASS`)이었고, 강제 `< 5` 프로브는 예상대로 실패했습니다.
  편차: 계획이 지정한 `git -C <메인 체크아웃> archive`는 워크트리 가드가 거부해 워크트리 안에서 아카이브를 실행했습니다(같은 오브젝트 데이터베이스라 결과는 동일합니다).
  `tests/test_m4_store.gd`의 expect 문구 두 곳을 "version 6"으로 올렸고, 같은 파일의 손상·미래 문서 fixture는 콘텐츠 4로 남겨 뒀습니다.
- Task 5(이 작업)의 Step 3에서 `tests/capture_m3.gd`의 준비 화면 캡처가 처음 FAIL했습니다: `index == 6` 분기가 실제로 여는 시나리오는 `rush_hour`입니다(브리프 산문은 `final_service`라고 적었지만, `final_service.tres`와 `rush_hour.tres` 둘 다 `ingredients` 배열의 마지막이 `marinated_protein`이라 미장 ID 선택 자체는 맞았습니다).
  이 분기의 수동 좌표 탭은 계획 2a 때는 `thawed_protein`을 눌러 `prep_quantities.thawed_protein`을 1로 만들었고, 바로 뒤 `rush_hour` 기준 정책의 `set_prep thawed_protein 1` 명령이 같은 값으로 덮어써 순 효과가 0이었습니다.
  Task 2의 재조정(`89d59c2`)이 그 명령을 빼고 `prepped_mushroom`을 1에서 3으로 올리면서(위 Task 2 표), 탭이 남긴 수량을 되돌리는 명령이 사라졌습니다.
  그 결과 이 캡처는 원본(`thawed_protein`) 그대로도, 이 작업이 지시받은 `marinated_protein` 치환도 `rush_hour`의 (이미 목표보다 딱 1건 여유인) 기준 정책 위에 여분의 노동·원재료를 얹어 목표(23건·8,500원)를 놓쳤습니다(재현: 기준 정책 자체는 24건·9,200원까지만 통과합니다).
  `tests/capture_m3.gd`의 좌표 탭·스크린샷 직후에 `service.submit_preparation("set_prep", "marinated_protein", 0)` 한 줄을 추가해 기준 정책 루프가 실행되기 전에 탭의 수량을 되돌렸습니다(`tests/fixtures/m3_policies.gd`는 건드리지 않았습니다).
  이 한 줄 뒤 기본 캡처와 `--phone-wide` 캡처 모두 `M3 rendered input checks=186 failures=0`으로 통과했습니다.
- `grep -rn 'Until plan 2b\|2b에서 구현\|계획 2b가 맡' AGENTS.md docs/specs README.md docs/plans/PLAN.md`는 2개의 줄만 남겼고(`docs/specs/mise-forecast-reviews.md:133`·`:134`), 둘 다 §5.1의 "2026-09-20 정정" 단락 안에 있어 브리프가 예외로 둔 그날의 기록이므로 고치지 않고 그대로 뒀습니다.
  `AGENTS.md`의 "Until plan 2b lands" 문장은 삭제했습니다.
- 준비 화면 캡처 관찰: `build/check/m3-first-preparation.png`(첫 영업)는 미장 1종(손질 토마토)만 있는 짧은 패널이라 겹침이나 스크롤 문제가 없습니다.
  `build/check/m3-last-mise-row-preparation.png`(`rush_hour`, "몰려오는 주문")는 패널이 마지막 행(재운 연어, `+` 버튼이 방금 눌려 강조된 상태)까지 스크롤돼 있고, 6개 미장 행 전부가 이 스크롤로 닿으며, 긴 표시명("재운 연어", "토마토 베이스")이 수량·원가 열과 겹치지 않고, 마지막 행의 `+`가 세이프 에어리어 안에 있습니다.
  §12 4단계 화면 계획으로 넘길 문제는 보이지 않았습니다.
- 다음 네 가지는 고치지 않고 최종 전체-브랜치 리뷰로 미룹니다.
  (1) `docs/notes/kitchen-pressure-verification.md`의 2026-09-21 절은 기준·무계획 회계를 표와 `log` 블록에 중복 기록하고(파일 관례), 세션 스코프의 스윕 로그 경로를 인용합니다.
  (2) `_phase_duration`은 미장 집합이 전부 재고에 있는 prep 단계에서도 0을 돌려주며, `uses_prepared`가 그런 경우 prep 자체를 건너뛰기 때문에만 안전합니다.
  (3) `_release_ingredients`는 해제된 대기 주문의 `missing_mise_ids`를 갱신하지 않고 그대로 남겨 두며, 다음 예약에서 다시 계산되고 복원은 예약되었거나 소비된 상태에서만 그 배열을 제한합니다.
  (4) `unknown` ID 복원 테스트는 계획이 지시한 대로 `not accepted`만 검사합니다.

### Task 5 회귀 결과 (2026-09-21)

두 PCK 결과(같은 PCK python 10 OK, 콘텐츠 5→6 두 PCK `M4_EXPECT_RESTART=1` 9 OK·1 skip)는 위 Task 4 항목이 인용하는 `312c969`의 값입니다.
`test_m4_restart.py`는 이 Task에서 다시 실행하지 않았습니다.

```log
$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check-export.sh
PASS: exported M3 campaign and first served order
PASS: exported M1 content and first order
PASS: exported M2 preparation and first order
PASS: exported M2 extra menu prepared and served
PASS: exported M4 storage core
PASS: exported M4 resume and localization
PASS: exported M5 campaign ending and licenses

$ python3 tests/test_export_check.py
Ran 10 tests in 0.830s
OK

$ python3 tests/test_ios_export.py
Ran 2 tests in 0.104s
OK

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m0
PASS: m0 checks=25 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m1
PASS: m1 checks=192 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m2
PASS: m2 checks=489 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3
PASS: m3 checks=1108 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4-core
PASS: m4-core checks=897 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4
PASS: m4 checks=1201 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m5
PASS: m5 checks=583 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise
PASS: mise checks=277 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh ui-regressions
PASS: ui-regressions checks=302 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot "$GODOT_BIN" --path <worktree> --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd
M3 rendered input checks=186 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot "$GODOT_BIN" --path <worktree> --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd -- --phone-wide
M3 rendered input checks=186 failures=0
```
