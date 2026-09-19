# 수요 예보·미장·리뷰 구현 계획 1: 생성기와 시드

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 시나리오에 예보 폭과 순수 함수 생성기를 더해 `(시나리오, 시드) → 주문 메뉴 순서`를 만들고, 시드를 영업 세션·캠페인 기록·캠페인 화면에 연결하되 모든 `.tres`의 폭은 0으로 두어 플레이어에게 보이는 동작을 바꾸지 않습니다.

**Architecture:** `ScheduleGenerator`는 `content/`의 정적 함수 모음이며 시드 0은 작성된 `order_recipe_ids`를 그대로 반환합니다. 시드는 `ScenarioDef.service_seed`라는 export 필드로 정의 객체에 실려 `PreparationPlan`의 `duplicate()`와 `ServiceSim.restore`의 일정 재계산까지 그대로 따라갑니다. 2026-09-19 headless 프로브로 `Resource.duplicate()`와 `as Definitions` 캐스트가 하위 클래스 export 값을 유지하고 스크립트가 `scenario_def.gd`로 남는 것을 확인했습니다. 세션 파일은 `service_seed`를, 캠페인 파일은 시나리오별 `attempts`를 저장하며 스키마 4로 올립니다.

**Tech Stack:** Godot `4.7.2.stable.official.ed1daf0bf`(`.godot-version`), typed GDScript, headless 검사 `bash scripts/check.sh <suite>`, `tests/harness.gd`의 `expect(condition, message)`.

**Spec:** [docs/specs/mise-forecast-reviews.md](../specs/mise-forecast-reviews.md) §4, §8, §9, §10, §12의 1단계.

## Global Constraints

- 시드 0은 작성된 `order_recipe_ids`와 바이트 단위로 같아야 합니다(명세 §4.2).
- 도착 tick은 `order_arrival_ticks` 배열 또는 `first_arrival_tick + arrival_interval_ticks × 순번`이며 생성기는 어느 쪽도 바꾸지 않습니다(§4.1).
- 총 주문 수 `order_count`는 고정입니다(§4.1).
- 인덱스 0의 시드는 0이고, 인덱스 1 이상은 `scenario_id:attempt_index` 문자열의 FNV-1a 32비트 해시입니다. 해시가 0이면 1을 씁니다(§4.3).
- 재도전(마감 화면 "다시 준비")은 같은 시드, 캠페인 화면에서 새로 시작하면 현재 `attempt_index`로 시드를 만든 뒤 인덱스를 1 올립니다(§4.3).
- `prng_state`는 계속 `null`이며 시뮬레이션 내부 추첨은 없습니다(§8).
- 기존 `Definitions.seed`는 M1·M2 fixture의 회전 오프셋이므로 건드리지 않습니다. 새 필드는 `service_seed`입니다(§4.2).
- 이번 PR에서 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있고 `service_seed`는 0입니다. 폭 작성과 시드 1~5 풀림 검사는 미장 PR 뒤의 별도 계획입니다.
- 저장 스키마는 4로 올리고, 스키마 1~3은 읽기만으로 바꾸지 않으며 다음 정상 저장에서 4로 갱신합니다. 콘텐츠 버전 4는 이번 PR에서 유지합니다(§8).
- 모든 Godot 호출은 `--headless`이며 새 검사는 잘못된 입력에서 먼저 실패하는 것을 확인한 뒤 통과시킵니다(§10).
- 문서와 사용자 문구는 한국어, 코드 식별자와 커밋 메시지는 영어입니다. 커밋에 `Co-Author`나 세션 URL을 붙이지 않습니다.
- 검사 명령: `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` 뒤에 `bash scripts/check.sh mise`, `bash scripts/check.sh m3`, `bash scripts/check.sh m4`.

---

## 파일 구조

| 파일                                                                                | 책임                                                                                                                                                                 |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `content/schedule_generator.gd` (신규)                                              | `stable_hash`, `service_seed_for`, `recipe_ids`의 순수 함수. 시뮬레이션·시계·파일을 읽지 않음                                                                        |
| `content/scenario_def.gd`                                                           | `forecast_slack`·`service_seed` export, `baseline_counts`, `forecast_ranges`, `with_service_seed`, 생성기를 쓰는 `order_schedule`, 예보 상한 기준의 `maximum_profit` |
| `persistence/service_session.gd`                                                    | 세션 6번째 필드 `service_seed`의 저장·복원, 5필드 세션은 시드 0으로 수용                                                                                             |
| `sim/campaign_progress.gd`                                                          | 시나리오별 `attempts` 검증·보관과 `next_service_seed`                                                                                                                |
| `persistence/campaign_store.gd`                                                     | 스키마 4, 문서의 `attempts` 키, 이전 스키마 읽기                                                                                                                     |
| `presentation/campaign_screen.gd`                                                   | 시작 시 시드 추첨과 즉시 저장, 이어하기 시 시드 복원, 체크포인트에 시드 포함, 브리핑 예보 범위                                                                       |
| `tests/test_schedule_generator.gd` (신규)                                           | 해시·시드·생성기 검사                                                                                                                                                |
| `tests/test_service_seed.gd` (신규)                                                 | 시나리오 필드, 세션, 기록, 저장소, 캠페인 화면 검사                                                                                                                  |
| `tests/test_mise.gd` (신규)                                                         | `mise` suite 집계                                                                                                                                                    |
| `tests/run_tests.gd`, `.github/workflows/*.yml`, `README.md`, `docs/specs/m0-m1.md` | suite 등록과 명령 계약                                                                                                                                               |

---

### Task 1: ScenarioDef 예보 필드와 범위

**Files:**

- Modify: `content/scenario_def.gd`
- Create: `tests/test_service_seed.gd`
- Create: `tests/test_mise.gd`
- Modify: `tests/run_tests.gd:6-15`

**Interfaces:**

- Produces: `ScenarioDef.forecast_slack: Dictionary[String, int]`, `ScenarioDef.service_seed: int`, `baseline_counts() -> Dictionary[String, int]`, `forecast_ranges() -> Dictionary` (값은 `{"baseline": int, "min": int, "max": int}`), `with_service_seed(seed_value: int) -> Resource`.

- [ ] **Step 1: suite 뼈대와 실패하는 검사를 씁니다**

`tests/test_mise.gd`:

```gdscript
extends "res://tests/harness.gd"

const ChildHarness := preload("res://tests/harness.gd")
const SUITES: Array[String] = ["res://tests/test_schedule_generator.gd", "res://tests/test_service_seed.gd"]


func run(tree: SceneTree) -> void:
	for script_path: String in SUITES:
		if not ResourceLoader.exists(script_path):
			expect(false, "required mise suite is missing: " + script_path)
			continue
		var suite: ChildHarness = load(script_path).new()
		await suite.run(tree)
		expect(suite.checked > 0, "mise child suite must run checks: " + script_path)
		checked += suite.checked
		failures += suite.failures
```

`tests/run_tests.gd`의 `SUITES`에 한 줄을 더합니다.

```gdscript
	"ui-regressions": "res://tests/test_ui_regressions.gd",
	"mise": "res://tests/test_mise.gd",
```

`tests/test_service_seed.gd`(첫 절만):

```gdscript
extends "res://tests/harness.gd"

const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const ServiceSession := preload("res://persistence/service_session.gd")
const CampaignProgress := preload("res://sim/campaign_progress.gd")
const CampaignStore := preload("res://persistence/campaign_store.gd")
const PreparationPlan := preload("res://sim/preparation_plan.gd")
const ServiceSim := preload("res://sim/service_sim.gd")


func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	_test_scenario_fields(campaign)


func _test_scenario_fields(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		expect(scenario.forecast_slack.is_empty(), "authored slack is empty in this PR: " + scenario.id)
		expect(scenario.service_seed == 0, "authored service seed is zero: " + scenario.id)
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var counts: Dictionary = hot_queue.baseline_counts()
	expect(counts.get("grill") == 10 and counts.get("soup") == 5 and counts.get("salad") == 5, "baseline counts come from the authored order")
	var ranges: Dictionary = hot_queue.forecast_ranges()
	expect(ranges.grill == {"baseline": 10, "min": 10, "max": 10}, "zero slack collapses the range to the baseline")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	expect(slacked.validate().is_empty(), "slack on menu items validates")
	ranges = slacked.forecast_ranges()
	expect(ranges.grill == {"baseline": 10, "min": 8, "max": 12} and ranges.soup == {"baseline": 5, "min": 4, "max": 6}, "slack widens the range around the baseline")
	var wide: Resource = hot_queue.duplicate()
	var wide_slack: Dictionary[String, int] = {"soup": 9}
	wide.forecast_slack = wide_slack
	expect(wide.forecast_ranges().soup["min"] == 0, "the lower bound never goes below zero")
	var invalid: Resource = hot_queue.duplicate()
	var bad_key: Dictionary[String, int] = {"grain_salad": 1}
	invalid.forecast_slack = bad_key
	expect(not invalid.validate().is_empty(), "slack for a menu outside the service is rejected")
	invalid = hot_queue.duplicate()
	var bad_value: Dictionary[String, int] = {"grill": -1}
	invalid.forecast_slack = bad_value
	expect(not invalid.validate().is_empty(), "negative slack is rejected")
	invalid = hot_queue.duplicate()
	invalid.service_seed = -1
	expect(not invalid.validate().is_empty(), "a negative service seed is rejected")
	var seeded: Resource = hot_queue.with_service_seed(7)
	expect(seeded.service_seed == 7 and hot_queue.service_seed == 0, "with_service_seed returns a seeded copy and leaves the source untouched")
	expect(seeded.id == hot_queue.id and seeded.order_recipe_ids == hot_queue.order_recipe_ids, "the seeded copy keeps the authored content")
	expect(slacked.maximum_profit(20) == hot_queue.maximum_profit(20) + 2 * _margin(hot_queue, "grill") + _margin(hot_queue, "soup") - 3 * _margin(hot_queue, "salad"), "maximum profit uses the forecast upper bounds")


func _margin(scenario: Resource, recipe_id: String) -> int:
	var recipe: Resource = scenario.recipe_for(recipe_id)
	var margin: int = recipe.revenue
	for ingredient_id: String in recipe.ingredients:
		margin -= scenario.ingredient_for(ingredient_id).unit_cost * recipe.ingredients[ingredient_id]
	return margin
```

마지막 `maximum_profit` 검사의 산수: `hot_queue`의 마진은 구이 1500−400=1100, 수프 900−150−200=550, 샐러드 500−100=400입니다. 폭을 준 상한 다중집합은 구이 12·수프 6·샐러드 6(24건)이고 상위 20개는 구이 12·수프 6·샐러드 2이므로, 기준(구이 10·수프 5·샐러드 5) 대비 구이 +2, 수프 +1, 샐러드 −3입니다.

- [ ] **Step 2: 검사가 실패하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `FAIL: cannot load mise suite`가 아니라 `test_schedule_generator.gd` 누락과 `forecast_slack` 속성 부재로 `SCRIPT ERROR` 또는 `FAIL:` 줄이 나오고 종료 코드가 0이 아닙니다. `test_schedule_generator.gd`는 Task 2에서 만듭니다.

- [ ] **Step 3: ScenarioDef에 필드와 함수를 더합니다**

`content/scenario_def.gd`의 export 블록 뒤에 추가합니다.

```gdscript
@export var order_arrival_ticks: PackedInt32Array = PackedInt32Array()
## 메뉴별 예보 폭. 기준 건수 ± 폭이 브리핑에 보이는 범위이며, 비어 있으면 모든 메뉴가 폭 0입니다.
@export var forecast_slack: Dictionary[String, int] = {}
## 이번 영업이 쓰는 추첨. 작성된 .tres에서는 항상 0이며 with_service_seed()로만 바뀝니다.
## export여야 PreparationPlan의 duplicate()가 값을 함께 복사합니다.
@export var service_seed: int = 0
```

`validate()`의 `order_recipe_ids` 검사 뒤에 추가합니다.

```gdscript
	for recipe_id: String in forecast_slack:
		if recipe_id not in menu_ids or forecast_slack[recipe_id] < 0:
			errors.append("invalid forecast slack: " + recipe_id)
	if service_seed < 0:
		errors.append("invalid service seed")
```

`order_schedule()` 앞에 세 함수를 추가합니다.

```gdscript
func baseline_counts() -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for recipe_id: String in menu_ids:
		counts[recipe_id] = 0
	for recipe_id: String in order_recipe_ids:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	return counts


func forecast_ranges() -> Dictionary:
	var ranges: Dictionary = {}
	var counts := baseline_counts()
	for recipe_id: String in menu_ids:
		var slack: int = forecast_slack.get(recipe_id, 0)
		ranges[recipe_id] = {"baseline": counts[recipe_id], "min": maxi(counts[recipe_id] - slack, 0), "max": counts[recipe_id] + slack}
	return ranges


func with_service_seed(seed_value: int) -> Resource:
	var seeded := duplicate() as Resource
	seeded.service_seed = seed_value
	return seeded
```

`maximum_profit()`은 작성된 순서 대신 예보 상한을 씁니다. 함수 본문의 첫 반복문을 바꿉니다.

```gdscript
func maximum_profit(served_limit: int) -> int:
	var margins: Array[int] = []
	var ranges := forecast_ranges()
	for recipe_id: String in menu_ids:
		var recipe := recipe_for(recipe_id)
		if recipe == null:
			continue
		var margin: int = recipe.revenue
		for ingredient_id: String in recipe.ingredients:
			var ingredient := ingredient_for(ingredient_id)
			if ingredient != null:
				margin -= ingredient.unit_cost * recipe.ingredients[ingredient_id]
		for _index: int in ranges[recipe_id]["max"]:
			margins.append(margin)
	margins.sort()
	margins.reverse()
	var upper_bound: int = -labor_cost
	for index: int in mini(maxi(served_limit, 0), margins.size()):
		upper_bound += maxi(margins[index], 0)
	return upper_bound
```

폭이 0이면 상한 배열이 작성된 순서와 같은 다중집합이므로 기존 값과 같습니다.

- [ ] **Step 4: 기존 suite로 회귀가 없음을 확인합니다**

Run: `bash scripts/check.sh m3`
Expected: `PASS: m3 checks=... failures=0`. `test_m3_content.gd`의 `maximum_profit` 관련 검사(`a target cannot exceed revenue after required ingredient cost`)가 그대로 통과해야 합니다.

- [ ] **Step 5: 커밋**

```bash
git add content/scenario_def.gd tests/test_service_seed.gd tests/test_mise.gd tests/run_tests.gd
git commit -m "feat(content): add forecast slack and service seed to scenarios"
```

`mise` suite는 Task 2까지 실패 상태이므로 이 커밋 메시지 본문에 `mise suite completes in the next commit`을 적습니다.

---

### Task 2: ScheduleGenerator

**Files:**

- Create: `content/schedule_generator.gd`
- Create: `tests/test_schedule_generator.gd`
- Modify: `content/scenario_def.gd` (`order_schedule`)

**Interfaces:**

- Consumes: Task 1의 `forecast_ranges()`, `menu_ids`, `order_recipe_ids`.
- Produces: `ScheduleGenerator.stable_hash(text: String) -> int`, `ScheduleGenerator.service_seed_for(scenario_id: String, attempt_index: int) -> int`, `ScheduleGenerator.recipe_ids(scenario: Resource, service_seed: int) -> PackedStringArray`.

- [ ] **Step 1: 실패하는 검사를 씁니다**

`tests/test_schedule_generator.gd`:

```gdscript
extends "res://tests/harness.gd"

const ScheduleGenerator := preload("res://content/schedule_generator.gd")


func run(_tree: SceneTree) -> void:
	expect(ScheduleGenerator.stable_hash("a") == 3826002220, "FNV-1a 32-bit hash of a known input")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 0) == 0, "attempt 0 always uses seed 0")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 1) == 104076537, "attempt 1 seed is pinned")
	expect(ScheduleGenerator.service_seed_for("hot_queue", 2) == 53743680, "attempt 2 seed is pinned")
	expect(ScheduleGenerator.service_seed_for("first_shift", 1) == 2225007163, "seeds differ per scenario")
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	expect(ScheduleGenerator.recipe_ids(hot_queue, 0) == hot_queue.order_recipe_ids, "seed 0 returns the authored order")
	expect(ScheduleGenerator.recipe_ids(hot_queue, 104076537) == hot_queue.order_recipe_ids, "zero slack returns the authored order for any seed")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	expect(ScheduleGenerator.recipe_ids(slacked, 0) == hot_queue.order_recipe_ids, "seed 0 ignores slack")
	var drawn := ScheduleGenerator.recipe_ids(slacked, 104076537)
	expect(drawn == ScheduleGenerator.recipe_ids(slacked, 104076537), "the same seed draws the same order")
	expect(drawn.size() == hot_queue.order_count, "the draw keeps the order count")
	var counts: Dictionary = {}
	for recipe_id: String in drawn:
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	var ranges: Dictionary = slacked.forecast_ranges()
	for recipe_id: String in slacked.menu_ids:
		expect(counts.get(recipe_id, 0) >= ranges[recipe_id]["min"] and counts.get(recipe_id, 0) <= ranges[recipe_id]["max"], "drawn count stays inside the forecast range: " + recipe_id)
	expect(_differs(counts, slacked.baseline_counts()), "a seed with available slack moves at least one order")
	expect(drawn != ScheduleGenerator.recipe_ids(slacked, 53743680), "different seeds draw different orders")
	var one_sided: Resource = hot_queue.duplicate()
	var one_slack: Dictionary[String, int] = {"grill": 2}
	one_sided.forecast_slack = one_slack
	expect(ScheduleGenerator.recipe_ids(one_sided, 104076537) == hot_queue.order_recipe_ids, "slack on a single menu cannot move anything because no other menu can give or take")
	var schedule: Array = slacked.with_service_seed(104076537).order_schedule()
	expect(schedule.size() == hot_queue.order_count, "the seeded scenario schedules every order")
	for index: int in schedule.size():
		expect(schedule[index].recipe_id == drawn[index], "order_schedule uses the drawn recipe per slot")
		expect(schedule[index].arrival_tick == hot_queue.order_arrival_ticks[index], "arrival ticks never change")
	var interval: Resource = campaign.scenario_for("lunch_prep").with_service_seed(104076537)
	var interval_schedule: Array = interval.order_schedule()
	expect(interval_schedule[3].arrival_tick == interval.first_arrival_tick + interval.arrival_interval_ticks * 3, "interval arrivals stay on the formula under a seed")


func _differs(actual: Dictionary, expected: Dictionary) -> bool:
	for recipe_id: String in expected:
		if actual.get(recipe_id, 0) != expected[recipe_id]:
			return true
	return false
```

`baseline_counts()`는 typed Dictionary를 돌려주므로 untyped 사전과 `==`로 비교하지 않고 키별로 비교합니다.

`one_sided` 검사의 근거: 구이만 폭이 있으면 주는 쪽과 받는 쪽이 모두 구이뿐이므로 이동할 짝이 없습니다.

- [ ] **Step 2: 검사가 실패하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `content/schedule_generator.gd`가 없어 `SCRIPT ERROR`로 실패합니다.

- [ ] **Step 3: 생성기를 구현합니다**

`content/schedule_generator.gd`:

```gdscript
extends RefCounted

## (시나리오, 시드) → 주문 메뉴 순서의 순수 함수.
## 시드 0은 작성된 순서를 그대로 돌려주고, 그 외 시드는 예보 범위 안에서 건수를 옮긴 뒤 슬롯을 섞습니다.
## 시뮬레이션 상태, 시계, 저장 파일을 읽지 않습니다.

const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619
const MASK_32: int = 0xFFFFFFFF


static func stable_hash(text: String) -> int:
	var hash_value: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * FNV_PRIME) & MASK_32
	return hash_value


static func service_seed_for(scenario_id: String, attempt_index: int) -> int:
	if attempt_index <= 0:
		return 0
	var hash_value := stable_hash("%s:%d" % [scenario_id, attempt_index])
	return hash_value if hash_value != 0 else 1


static func recipe_ids(scenario: Resource, service_seed: int) -> PackedStringArray:
	var authored: PackedStringArray = scenario.order_recipe_ids
	if service_seed == 0:
		return authored.duplicate()
	var ranges: Dictionary = scenario.forecast_ranges()
	var counts: Dictionary[String, int] = {}
	var total_slack: int = 0
	for recipe_id: String in scenario.menu_ids:
		counts[recipe_id] = ranges[recipe_id]["baseline"]
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	var rng := RandomNumberGenerator.new()
	rng.seed = service_seed
	var moves: int = rng.randi_range(1, maxi(total_slack, 1))
	for _move: int in moves:
		var donors: PackedStringArray = []
		for recipe_id: String in scenario.menu_ids:
			if counts[recipe_id] > ranges[recipe_id]["min"] and not _receivers(scenario, counts, ranges, recipe_id).is_empty():
				donors.append(recipe_id)
		if donors.is_empty():
			break
		var donor: String = donors[rng.randi_range(0, donors.size() - 1)]
		var receivers := _receivers(scenario, counts, ranges, donor)
		var receiver: String = receivers[rng.randi_range(0, receivers.size() - 1)]
		counts[donor] -= 1
		counts[receiver] += 1
	if counts == scenario.baseline_counts():
		return authored.duplicate()
	var result: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		for _index: int in counts[recipe_id]:
			result.append(recipe_id)
	for index: int in range(result.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := result[index]
		result[index] = result[swap_index]
		result[swap_index] = held
	return result


static func _receivers(scenario: Resource, counts: Dictionary, ranges: Dictionary, donor: String) -> PackedStringArray:
	var receivers: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		if recipe_id != donor and counts[recipe_id] < ranges[recipe_id]["max"]:
			receivers.append(recipe_id)
	return receivers
```

건수가 기준과 같으면 섞지 않고 작성된 순서를 돌려주므로, 폭이 0인 시나리오는 어떤 시드에서도 항등입니다(명세 §4.2).

`content/scenario_def.gd` 상단에 preload를 더하고 `order_schedule()`을 생성기 기반으로 바꿉니다.

```gdscript
extends "res://content/definitions.gd"

const ScheduleGenerator := preload("res://content/schedule_generator.gd")
```

```gdscript
func order_schedule() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipe_ids := ScheduleGenerator.recipe_ids(self, service_seed)
	for index: int in recipe_ids.size():
		var recipe := recipe_for(recipe_ids[index])
		if recipe == null:
			return []
		var arrival_tick := order_arrival_ticks[index] if not order_arrival_ticks.is_empty() else first_arrival_tick + arrival_interval_ticks * index
		result.append({"id": "order_%02d" % (index + 1), "arrival_tick": arrival_tick,
			"recipe_id": recipe.id, "deadline_tick": arrival_tick + recipe.patience_ticks})
	return result
```

- [ ] **Step 4: 검사가 통과하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `PASS: mise checks=... failures=0`.

Run: `bash scripts/check.sh m3`
Expected: `PASS`. 모든 `.tres`의 시드가 0이므로 3전략·무계획·결정론 검사의 입력이 바뀌지 않아야 합니다.

- [ ] **Step 5: 커밋**

```bash
git add content/schedule_generator.gd content/scenario_def.gd tests/test_schedule_generator.gd
git commit -m "feat(content): generate order recipes from forecast slack and a seed"
```

---

### Task 3: 세션의 `service_seed`

**Files:**

- Modify: `persistence/service_session.gd:12-49`
- Modify: `tests/test_service_seed.gd`

**Interfaces:**

- Consumes: Task 1의 `with_service_seed()`.
- Produces: `ServiceSession.capture(scenario_id, selection, simulation, speed := 1, accumulator_us := 0, service_seed := 0) -> Dictionary`에 `"service_seed"` 키, `ServiceSession.restore(...)` 결과에 `"service_seed": int`.

- [ ] **Step 1: 실패하는 검사를 씁니다**

`tests/test_service_seed.gd`의 `run()`에 호출을 더하고 함수를 추가합니다.

```gdscript
func run(tree: SceneTree) -> void:
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	_test_scenario_fields(campaign)
	_test_session_seed(campaign)


func _test_session_seed(campaign: Resource) -> void:
	var records: Dictionary = {}
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var unlocked: Dictionary = {}
	for scenario: Resource in campaign.scenarios:
		if scenario.id == "hot_queue":
			break
		unlocked[scenario.id] = {"completed": true, "best_served": scenario.minimum_served, "best_profit": scenario.minimum_profit}
	records = unlocked
	var seeded: Resource = hot_queue.with_service_seed(104076537)
	var plan := PreparationPlan.new(seeded)
	var started := plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(started.accepted, "seeded preparation starts")
	expect(started.definitions.service_seed == 104076537, "the started definition carries the service seed through duplicate()")
	var simulation := ServiceSim.new(started.definitions, null, started.options)
	expect(simulation.errors.is_empty(), "seeded simulation builds")
	var session := ServiceSession.capture("hot_queue", started.selection, simulation, 1, 0, 104076537)
	expect(session.size() == 6 and session.service_seed == 104076537, "capture stores the service seed as the sixth field")
	var restored := ServiceSession.restore(campaign, session, records)
	expect(restored.accepted and restored.service_seed == 104076537, "restore returns the service seed")
	expect(restored.definitions.order_schedule()[0].recipe_id == seeded.order_schedule()[0].recipe_id, "restore rebuilds the seeded schedule")
	var legacy := session.duplicate(true)
	legacy.erase("service_seed")
	var legacy_restored := ServiceSession.restore(campaign, legacy, records)
	expect(legacy_restored.accepted and legacy_restored.service_seed == 0, "a five-field session restores with seed 0")
	var forged := session.duplicate(true)
	forged.service_seed = "7"
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a non-integer seed is rejected")
	forged = session.duplicate(true)
	forged.service_seed = -1
	expect(not ServiceSession.restore(campaign, forged, records).accepted, "a negative seed is rejected")
	var modified: Resource = campaign.duplicate(true)
	var slacked: Resource = modified.scenario_for("hot_queue")
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	var drawn_scenario: Resource = slacked.with_service_seed(104076537)
	var drawn_plan := PreparationPlan.new(drawn_scenario)
	var drawn_started := drawn_plan.apply_command({"kind": "start", "target_id": "", "value": null, "apply_tick": 0, "sequence": 1})
	expect(drawn_started.accepted, "a slack-bearing seeded preparation starts")
	var drawn_sim := ServiceSim.new(drawn_started.definitions, null, drawn_started.options)
	while not drawn_sim.closed:
		drawn_sim.step()
	var drawn_session := ServiceSession.capture("hot_queue", drawn_started.selection, drawn_sim, 1, 0, 104076537)
	expect(ServiceSession.restore(modified, drawn_session, records).accepted, "a closed session restores under the seed that produced it")
	var wrong_seed := drawn_session.duplicate(true)
	wrong_seed.service_seed = 0
	var rejected := ServiceSession.restore(modified, wrong_seed, records)
	expect(not rejected.accepted and rejected.reason == "invalid_schedule", "the same orders cannot restore under a seed whose draw differs")
```

폭이 0인 `.tres`에서는 시드가 달라도 일정이 같으므로 앞부분은 시드의 왕복과 잘못된 값의 거부만 검사하고, 뒷부분은 폭을 준 캠페인 복제본으로 마감까지 진행한 세션을 만들어 같은 시드에서는 복원되고 다른 시드에서는 `sim/service_sim.gd`의 `_order_restore_error`가 `invalid_schedule`로 거부하는지 확인합니다.
`campaign.duplicate(true)`는 `tests/test_m3_content.gd`가 쓰는 것과 같은 깊은 복제이므로 로드된 캠페인 리소스를 오염시키지 않습니다.

- [ ] **Step 2: 검사가 실패하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `capture`가 여섯 번째 인자를 받지 않아 `SCRIPT ERROR`, 또는 `capture stores the service seed` 검사가 `FAIL:`로 나옵니다.

- [ ] **Step 3: 세션에 시드를 더합니다**

`persistence/service_session.gd`의 `capture`와 `restore`를 바꿉니다.

```gdscript
static func capture(scenario_id: String, selection: Dictionary, simulation: ServiceSim, speed: int = 1,
	accumulator_us: int = 0, service_seed: int = 0) -> Dictionary:
	return {"scenario_id": scenario_id, "preparation": selection.duplicate(true),
		"simulation": simulation.export_state(), "speed": speed, "accumulator_us": accumulator_us,
		"service_seed": service_seed}
```

`restore`에서 필드 수 검사와 시나리오 조회를 바꿉니다.

```gdscript
	var saved: Dictionary = normalized.value
	if saved.size() != 5 and saved.size() != 6:
		return _failure("invalid_session")
	for field: String in ["scenario_id", "preparation", "simulation", "speed", "accumulator_us"]:
		if not saved.has(field):
			return _failure("invalid_session")
	var service_seed: int = 0
	if saved.size() == 6:
		if not saved.has("service_seed") or not saved.service_seed is int or saved.service_seed < 0:
			return _failure("invalid_session")
		service_seed = saved.service_seed
```

```gdscript
	var scenario = campaign.scenario_for(saved.scenario_id)
	if scenario == null:
		return _failure("unknown_service")
	scenario = scenario.with_service_seed(service_seed)
```

반환 사전에 시드를 더합니다.

```gdscript
	return {"accepted": true, "reason": "", "simulation": restored.simulation,
		"definitions": started.definitions, "selection": started.selection.duplicate(true),
		"scenario_id": saved.scenario_id, "speed": saved.speed, "accumulator_us": saved.accumulator_us,
		"service_seed": service_seed}
```

- [ ] **Step 4: 검사가 통과하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `PASS`.

Run: `bash scripts/check.sh m4-core` 와 `bash scripts/check.sh m4`
Expected: `PASS`. 기존 5필드 세션 fixture는 시드 0으로 복원되어야 합니다.

- [ ] **Step 5: 커밋**

```bash
git add persistence/service_session.gd tests/test_service_seed.gd
git commit -m "feat(persistence): carry the service seed through the active session"
```

---

### Task 4: 캠페인 기록의 `attempts`와 저장 스키마 4

**Files:**

- Modify: `sim/campaign_progress.gd`
- Modify: `persistence/campaign_store.gd`
- Modify: `tests/test_service_seed.gd`
- Modify: `tests/test_m4_store.gd:45`
- Modify: `tests/test_menu_priorities.gd:123`

**Interfaces:**

- Consumes: Task 2의 `ScheduleGenerator.service_seed_for`.
- Produces: `CampaignProgress.new(campaign, records := {}, attempts := {})`, `CampaignProgress.validate_attempts(campaign, attempts) -> Array[String]`, `next_service_seed(scenario_id) -> Dictionary` (`{"accepted": bool, "reason": String, "service_seed": int, "attempt_index": int}`), `snapshot().attempts`, `CampaignStore.load_records().attempts`, `save_records(records, attempts := null)`, `save_active_session(session, records, attempts := null)`.

- [ ] **Step 1: 실패하는 검사를 씁니다**

`tests/test_service_seed.gd`의 `run()`에 호출을 더하고 함수를 추가합니다.

```gdscript
	_test_attempts(campaign)
	_test_store_schema(campaign)


func _test_attempts(campaign: Resource) -> void:
	var progress := CampaignProgress.new(campaign)
	expect(progress.snapshot().attempts == {}, "a new campaign has no attempts")
	var first := progress.next_service_seed("first_shift")
	expect(first.accepted and first.service_seed == 0 and first.attempt_index == 0, "the first start of a service uses seed 0")
	var second := progress.next_service_seed("first_shift")
	expect(second.accepted and second.service_seed == ScheduleGenerator.service_seed_for("first_shift", 1) and second.attempt_index == 1, "the second start draws attempt 1")
	expect(progress.snapshot().attempts == {"first_shift": 2}, "attempts count the starts")
	expect(not progress.next_service_seed("hot_queue").accepted, "a locked service cannot draw a seed")
	expect(not progress.next_service_seed("missing").accepted, "an unknown service cannot draw a seed")
	expect(CampaignProgress.validate_attempts(campaign, {"first_shift": 2}).is_empty(), "valid attempts pass")
	expect(not CampaignProgress.validate_attempts(campaign, {"missing": 1}).is_empty(), "attempts for an unknown service fail")
	expect(not CampaignProgress.validate_attempts(campaign, {"first_shift": -1}).is_empty(), "negative attempts fail")
	expect(not CampaignProgress.validate_attempts(campaign, {"first_shift": 1.5}).is_empty(), "non-integer attempts fail")
	var restored := CampaignProgress.new(campaign, {}, {"first_shift": 2})
	expect(restored.next_service_seed("first_shift").attempt_index == 2, "restored attempts continue the count")


func _test_store_schema(campaign: Resource) -> void:
	var directory := "user://test_service_seed_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "store fixture directory is created")
	var file_path := directory + "/records.json"
	var store := CampaignStore.new(campaign, file_path)
	expect(store.save_records({}, {"first_shift": 3}).accepted, "attempts save with empty records")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.size() == 6 and int(document.schema_version) == 4 and document.attempts == {"first_shift": 3.0}, "new writes use schema 4 with an attempts key")
	var loaded := CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.attempts == {"first_shift": 3}, "attempts load as integers")
	expect(store.save_records({}).accepted, "saving without attempts keeps the stored attempts")
	expect(CampaignStore.new(campaign, file_path).load_records().attempts == {"first_shift": 3}, "a null attempts argument preserves the primary attempts")
	var legacy := {"schema_version": 3, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null}
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(loaded.accepted and loaded.attempts == {}, "a schema 3 document loads with empty attempts")
	expect(store.save_records({}, {"first_shift": 1}).accepted, "the next save upgrades the document")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(int(document.schema_version) == 4 and document.attempts == {"first_shift": 1.0}, "the upgraded document carries schema 4 and attempts")
	var corrupt := {"schema_version": 4, "content_version": 4, "sim_version": 1, "records": {}, "active_session": null, "attempts": {"missing": 1}}
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	loaded = CampaignStore.new(campaign, file_path).load_records()
	expect(not loaded.accepted and loaded.reason == "corrupt_records", "attempts for an unknown service are rejected as corrupt")
```

`tests/test_m4_store.gd:45`의 기대값을 바꿉니다.

```gdscript
	expect(migrated is Dictionary and migrated.size() == 6 and migrated.schema_version == 4
```

`tests/test_menu_priorities.gd:123`의 기대값을 바꿉니다.

```gdscript
	expect(new_document.schema_version == 4, "new writes use schema 4 for older-app future-version protection")
```

- [ ] **Step 2: 검사가 실패하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `next_service_seed`가 없어 `SCRIPT ERROR`.

Run: `bash scripts/check.sh m4`
Expected: `test_m4_store.gd`와 `test_menu_priorities.gd`의 바뀐 기대값이 `FAIL:`로 나옵니다.

- [ ] **Step 3: CampaignProgress에 attempts를 더합니다**

`sim/campaign_progress.gd`에 preload와 필드를 더합니다.

```gdscript
const CampaignDef := preload("res://content/campaign_def.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
```

```gdscript
var errors: Array[String] = []
var _campaign: CampaignDef
var _records: Dictionary = {}
var _attempts: Dictionary = {}


func _init(campaign: CampaignDef, records: Dictionary = {}, attempts: Dictionary = {}) -> void:
	_campaign = campaign
	errors = campaign.validate()
	errors.append_array(validate_records(campaign, records))
	errors.append_array(validate_attempts(campaign, attempts))
	if errors.is_empty():
		_records = records.duplicate(true)
		_attempts = attempts.duplicate(true)


static func validate_attempts(campaign: CampaignDef, attempts: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for scenario_id: Variant in attempts:
		if not scenario_id is String or campaign.scenario_for(scenario_id) == null:
			problems.append("attempts contain an unknown service")
		elif not attempts[scenario_id] is int or attempts[scenario_id] < 0:
			problems.append("invalid attempt count")
	return problems


func next_service_seed(scenario_id: String) -> Dictionary:
	if not is_unlocked(scenario_id):
		return {"accepted": false, "reason": "locked_service", "service_seed": 0, "attempt_index": 0}
	var attempt_index: int = _attempts.get(scenario_id, 0)
	_attempts[scenario_id] = attempt_index + 1
	return {"accepted": true, "reason": "", "service_seed": ScheduleGenerator.service_seed_for(scenario_id, attempt_index),
		"attempt_index": attempt_index}
```

`snapshot()`의 반환에 attempts를 더합니다.

```gdscript
	return {"records": _records.duplicate(true), "attempts": _attempts.duplicate(true), "unlocked": unlocked,
		"ending_unlocked": ending, "errors": errors.duplicate()}
```

`is_unlocked`는 알 수 없는 시나리오에 `false`를 돌려주므로 `missing`도 거부됩니다.

- [ ] **Step 4: CampaignStore를 스키마 4로 올립니다**

`persistence/campaign_store.gd`의 상수를 바꿉니다.

```gdscript
const VERSIONS := {"schema_version": 4, "content_version": 4, "sim_version": 1}
const LEGACY_SCHEMA_VERSION := 1
const LEGACY_CONTENT_VERSION := 1
const READABLE_SCHEMA_VERSIONS: Array[int] = [1, 2, 3, 4]
```

`load_records`의 새 캠페인 반환과 `_failure`에 `attempts`를 더합니다.

```gdscript
		return {"accepted": true, "reason": "new_campaign", "records": {}, "attempts": {}, "active_session": null, "can_recover": false}
```

```gdscript
func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "records": {}, "attempts": {}, "active_session": null, "can_recover": false}
```

`load_records`의 실패 반환도 `"attempts": {}`를 포함하도록 같은 줄에 키를 더합니다.

```gdscript
	return {"accepted": false, "reason": reason, "records": {}, "attempts": {}, "can_recover": backup.accepted and not protected}
```

`save_records`와 `save_active_session`은 `attempts` 인자를 받고, `null`이면 기본 파일의 값을 유지합니다.

```gdscript
func save_records(records: Dictionary, attempts: Variant = null) -> Dictionary:
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("invalid_records")
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	if backup.reason in ["future_version", "unsupported_version"]:
		return _failure(backup.reason)
	if not primary.accepted and not (primary.reason == "missing" and backup.reason == "missing"):
		return _failure("recovery_required" if primary.reason == "missing" else primary.reason)
	var active_session: Variant = primary.active_session if primary.accepted else null
	if not _valid_session(active_session, records):
		return _failure("invalid_session")
	var resolved := _resolve_attempts(attempts, primary)
	if not resolved.accepted:
		return _failure("invalid_attempts")
	return _commit(records, active_session, resolved.attempts, primary)


func save_active_session(active_session: Variant, records: Dictionary, attempts: Variant = null) -> Dictionary:
	if not CampaignProgress.validate_records(_campaign, records).is_empty():
		return _failure("invalid_records")
	if not _valid_session(active_session, records):
		return _failure("invalid_session")
	var primary := _read(file_path)
	var backup := _read(file_path + ".backup")
	if backup.reason in ["future_version", "unsupported_version"]:
		return _failure(backup.reason)
	if not primary.accepted and not (primary.reason == "missing" and backup.reason == "missing"):
		return _failure("recovery_required" if primary.reason == "missing" else primary.reason)
	var resolved := _resolve_attempts(attempts, primary)
	if not resolved.accepted:
		return _failure("invalid_attempts")
	return _commit(records, active_session, resolved.attempts, primary)


func _resolve_attempts(attempts: Variant, primary: Dictionary) -> Dictionary:
	if attempts == null:
		return {"accepted": true, "attempts": primary.attempts.duplicate(true) if primary.accepted else {}}
	if not attempts is Dictionary or not CampaignProgress.validate_attempts(_campaign, attempts).is_empty():
		return {"accepted": false, "attempts": {}}
	return {"accepted": true, "attempts": attempts.duplicate(true)}
```

`clear_active_session`은 읽은 attempts를 넘깁니다.

```gdscript
func clear_active_session() -> Dictionary:
	var loaded := load_records()
	if not loaded.accepted:
		return loaded
	return save_active_session(null, loaded.records, loaded.attempts)
```

`_commit`, `recover_backup`, `_prepare_file`은 attempts를 함께 쓰고 검증합니다.

```gdscript
func _commit(records: Dictionary, active_session: Variant, attempts: Dictionary, primary: Dictionary) -> Dictionary:
	var temporary := file_path + ".tmp"
	var result := _prepare_file(temporary, records, active_session, attempts)
	if not result.accepted:
		return result
	if primary.accepted:
		var staged_backup := file_path + ".backup.tmp"
		result = _prepare_file(staged_backup, primary.records, primary.active_session, primary.attempts)
		if result.accepted and _replace_file(staged_backup, file_path + ".backup") != OK:
			result = _failure("backup_failed")
		if not result.accepted:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(staged_backup)
			return result
	if _replace_file(temporary, file_path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("replace_failed")
	return {"accepted": true, "reason": "saved", "records": records.duplicate(true), "attempts": attempts.duplicate(true),
		"active_session": active_session.duplicate(true) if active_session is Dictionary else null}
```

`recover_backup`에서 `_prepare_file(temporary, backup.records, backup.active_session)`을 `_prepare_file(temporary, backup.records, backup.active_session, backup.attempts)`로 바꾸고, 성공 반환에 `"attempts": backup.attempts.duplicate(true)`를 더합니다.

```gdscript
func _prepare_file(target: String, records: Dictionary, active_session: Variant, attempts: Dictionary) -> Dictionary:
	var document := VERSIONS.duplicate()
	document.records = records
	document.active_session = active_session
	document.attempts = attempts
	if _write_text(target, JSON.stringify(document, "\t", true)) != OK:
		DirAccess.remove_absolute(target)
		return _failure("write_failed")
	var verified := _read(target)
	var expected_session: Variant = null
	if active_session is Dictionary:
		expected_session = JSON.parse_string(JSON.stringify(active_session))
	if not verified.accepted or verified.records != records or verified.active_session != expected_session or verified.attempts != attempts:
		DirAccess.remove_absolute(target)
		return _failure("verification_failed")
	return {"accepted": true}
```

`_read`의 버전·크기 검사와 attempts 파싱을 바꿉니다.

```gdscript
	for key: String in VERSIONS:
		var version: Variant = document.get(key)
		if not _is_integer(version):
			return _failure("corrupt_records")
		if version > VERSIONS[key]:
			return _failure("future_version")
		if key == "schema_version" and int(version) in READABLE_SCHEMA_VERSIONS:
			continue
		if key == "content_version" and int(version) in [LEGACY_CONTENT_VERSION, 2, 3]:
			content_updated = true
			legacy_targets_updated = int(version) == LEGACY_CONTENT_VERSION
			continue
		if version != VERSIONS[key]:
			return _failure("unsupported_version")
	var schema_version := int(document.schema_version)
	var expected_size := 4
	if schema_version in [2, 3]:
		expected_size = 5
	elif schema_version == 4:
		expected_size = 6
	if document.size() != expected_size or not document.get("records") is Dictionary:
		return _failure("corrupt_records")
	var attempts: Dictionary = {}
	if schema_version == 4:
		if not document.get("attempts") is Dictionary:
			return _failure("corrupt_records")
		for key: Variant in document.attempts:
			if not _is_integer(document.attempts[key]):
				return _failure("corrupt_records")
			attempts[key] = int(document.attempts[key])
		if not CampaignProgress.validate_attempts(_campaign, attempts).is_empty():
			return _failure("corrupt_records")
```

`_read`의 성공 반환에 attempts를 더합니다.

```gdscript
	return {"accepted": true, "reason": "content_updated" if content_updated else "loaded", "records": records,
		"attempts": attempts, "active_session": active_session, "can_recover": false}
```

- [ ] **Step 5: 검사가 통과하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `PASS`.

Run: `bash scripts/check.sh m3` 와 `bash scripts/check.sh m4` 와 `bash scripts/check.sh m5`
Expected: 모두 `PASS`. 스키마 2·3 fixture는 attempts 없이 읽히고, 새 쓰기는 6개 키를 가집니다.

Run: `python3 tests/test_m4_restart.py`
Expected: `10개 검사 통과`에 해당하는 종료 코드 0. 이 검사는 별도 프로세스가 쓴 저장을 다시 읽으므로 스키마 4 문서를 새 프로세스가 수용하는지 확인합니다.

- [ ] **Step 6: 커밋**

```bash
git add sim/campaign_progress.gd persistence/campaign_store.gd tests/test_service_seed.gd tests/test_m4_store.gd tests/test_menu_priorities.gd
git commit -m "feat(persistence): record service attempts and bump the save schema to 4"
```

---

### Task 5: 캠페인 화면 연결과 브리핑 예보

**Files:**

- Modify: `presentation/campaign_screen.gd:481-500` (`_update_briefing`), `:513-519` (`_begin_selected_service`), `:521-545` (`_mount_service`), `:547-564` (`_resume_active_session`), `:566-588` (`_save_checkpoint`), `:93-96` (`_ready`의 progress 생성), `:726-737` (`_recover`)
- Modify: `tests/test_service_seed.gd`

**Interfaces:**

- Consumes: Task 1의 `with_service_seed`, `forecast_ranges`; Task 3의 `capture(..., service_seed)`와 `restore().service_seed`; Task 4의 `next_service_seed`, `snapshot().attempts`, `save_records(records, attempts)`, `save_active_session(session, records, attempts)`, `load_records().attempts`.

- [ ] **Step 1: 실패하는 검사를 씁니다**

`tests/test_service_seed.gd`의 `run()`에 호출을 더하고 함수를 추가합니다. 화면 부팅은 `tests/test_m3_ui.gd`의 `_boot`와 같은 방식입니다.

```gdscript
	await _test_campaign_screen(tree)


func _test_campaign_screen(tree: SceneTree) -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var directory := "user://test_service_seed_ui_%d" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "campaign seed fixture directory is created")
	var file_path := directory + "/records.json"
	var screen := _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.get("briefing_label").text.contains("채소 샐러드 12건"), "zero slack briefing shows an exact count")
	screen.get("begin_button").pressed.emit()
	var service: Control = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	expect(service.get("definitions").service_seed == 0, "the first start of a service uses seed 0")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.attempts == {"first_shift": 1.0}, "starting a service saves the attempt count immediately")
	service.get("start_button").pressed.emit()
	service.call("advance", 1.0)
	screen.call("_save_checkpoint", "test")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.active_session.service_seed == 0.0, "the checkpoint stores the service seed")
	screen.queue_free()
	await tree.process_frame
	screen = _boot(tree, entry, file_path)
	await tree.process_frame
	expect(screen.call("_resume_active_session"), "the saved session resumes")
	service = screen.get("active_service")
	service.set_process(false)
	expect(service.get("definitions").service_seed == 0, "resume restores the stored seed")
	service.call("advance", 299.0)
	expect(screen.get("last_result").passed, "the resumed first service closes with a passing result")
	screen.get("retry_service_button").pressed.emit()
	expect(service.get("definitions").service_seed == 0, "retry keeps the same seed")
	screen.call("return_to_menu")
	await tree.process_frame
	screen.call("select_scenario", "first_shift")
	screen.get("begin_button").pressed.emit()
	service = screen.get("active_service")
	service.set_process(false)
	await tree.process_frame
	expect(service.get("definitions").service_seed == ScheduleGenerator.service_seed_for("first_shift", 1), "a restart from the campaign screen draws attempt 1")
	document = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	expect(document.attempts == {"first_shift": 2.0}, "the second start increments the attempt count")
	screen.queue_free()
	await tree.process_frame


func _boot(tree: SceneTree, scene_path: String, file_path: String) -> Control:
	var scene: PackedScene = load(scene_path)
	var screen: Control = scene.instantiate()
	screen.set("save_path", file_path)
	var settings_path := file_path + ".settings.json"
	var settings := {"locale": "ko", "sound_enabled": false, "text_size": "normal"}
	if not HarnessSettingsStore.new(settings_path).save_settings(settings).accepted:
		return null
	screen.set("settings_path", settings_path)
	screen.tree_exited.connect(func() -> void: DirAccess.remove_absolute(settings_path))
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen
```

`first_shift`의 기본 운영이 목표를 통과한다는 사실은 `test_m3_ui.gd`의 "actual closing displays a passing result" 검사가 이미 보장합니다. 재도전 뒤 `return_to_menu`가 결과 대화상자를 닫는지는 기존 화면 흐름을 따르며, 막히면 `screen.get("result_dialog").hide()`를 먼저 호출합니다.

- [ ] **Step 2: 검사가 실패하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `starting a service saves the attempt count immediately`와 `a restart from the campaign screen draws attempt 1`이 `FAIL:`로 나옵니다.

- [ ] **Step 3: 캠페인 화면을 연결합니다**

`_ready`에서 progress를 attempts와 함께 만듭니다.

```gdscript
	progress = CampaignProgress.new(campaign, loaded.records if loaded.accepted else {}, loaded.attempts if loaded.accepted else {})
```

`_recover`는 백업에서 읽은 attempts를 함께 되살립니다.

```gdscript
	progress = CampaignProgress.new(campaign, result.records, result.attempts)
```

`_begin_selected_service`는 시드를 뽑고 즉시 저장합니다.

```gdscript
func _begin_selected_service() -> bool:
	if storage_blocked or active_service != null or progress == null or not progress.is_unlocked(selected_scenario_id):
		return false
	var scenario := campaign.scenario_for(selected_scenario_id)
	var draw := progress.next_service_seed(selected_scenario_id)
	if not draw.accepted:
		return false
	if not session_only:
		var saved := store.save_records(progress.snapshot().records, progress.snapshot().attempts)
		if not saved.accepted:
			_set_save_message("storage", saved.reason)
	_mount_service(scenario.with_service_seed(draw.service_seed))
	return true
```

`_mount_service`는 복제본의 빈 `resource_path` 대신 원본 경로를 씁니다.

```gdscript
func _mount_service(scenario: Resource) -> void:
	active_service = ServiceScene.instantiate() as KitchenScreen
	active_service.scenario_definition = scenario
	active_service.scenario_path = campaign.scenario_for(scenario.id).resource_path
```

나머지 본문은 그대로 둡니다.
`presentation/main.gd:287`은 `scenario_definition`이 `null`일 때만 `scenario_path`를 다시 로드하므로, 캠페인 경로에서는 항상 시드가 실린 정의가 먼저 설정되어야 합니다. 이 순서를 바꾸는 리팩터링은 시드 없는 일정을 조용히 되살립니다.

`_resume_active_session`은 복원된 시드로 장착합니다.

```gdscript
	selected_scenario_id = restored.scenario_id
	var scenario := campaign.scenario_for(selected_scenario_id)
	_mount_service(scenario.with_service_seed(restored.service_seed))
```

`_save_checkpoint`는 시드와 attempts를 함께 저장합니다.

```gdscript
	var session := ServiceSession.capture(active_service.definitions.id, active_service.last_preparation,
		active_service.simulation, active_service.driver.speed, active_service.driver.accumulator_us,
		int(active_service.definitions.get("service_seed")))
	var result := store.save_active_session(session, progress.snapshot().records, progress.snapshot().attempts)
```

`definitions`는 `Definitions`로 정적 타입이 붙어 있어 `.service_seed`를 직접 쓰면 컴파일 오류이므로 `get()`으로 읽습니다. 캠페인이 아닌 정의에서는 `null`이 나와 0이 됩니다.

```gdscript

```

`_update_briefing`은 폭이 있으면 범위를, 없으면 지금처럼 건수를 보여 줍니다.

```gdscript
	var ranges: Dictionary = scenario.forecast_ranges()
	var menu_lines: PackedStringArray = []
	for recipe_id: String in scenario.menu_ids:
		var range_values: Dictionary = ranges[recipe_id]
		var menu_name: String = tr(scenario.recipe_for(recipe_id).display_name)
		if range_values["min"] == range_values["max"]:
			menu_lines.append(tr("%s %d건") % [menu_name, range_values["baseline"]])
		else:
			menu_lines.append(tr("%s %d–%d건") % [menu_name, range_values["min"], range_values["max"]])
```

기존 `counts` 사전과 그 반복문은 지웁니다. `"%s %d–%d건"`은 새 번역 키이므로 `translations/en.po`에 `"%s %d–%d orders"`를 더합니다.

- [ ] **Step 4: 검사가 통과하는 것을 확인합니다**

Run: `bash scripts/check.sh mise`
Expected: `PASS`.

Run: `bash scripts/check.sh m3` 와 `bash scripts/check.sh m4` 와 `bash scripts/check.sh ui-regressions`
Expected: `PASS`. `test_m3_ui.gd`의 "briefing shows the actual first menu"는 `채소 샐러드`를 포함하는지만 보므로 그대로 통과합니다.

Run: `bash scripts/check-export.sh`
Expected: 완료 표시 7개 확인. 내보낸 PCK의 캠페인 완주가 시드 0에서 그대로 통과해야 합니다.

- [ ] **Step 5: 커밋**

```bash
git add presentation/campaign_screen.gd translations/en.po tests/test_service_seed.gd
git commit -m "feat(campaign): draw a service seed per start and keep it across resume and retry"
```

---

### Task 6: CI와 명령 계약 문서

**Files:**

- Modify: `.github/workflows/*.yml` (`check.sh m5` 단계 뒤)
- Modify: `README.md` "로컬 실행과 검사" 절
- Modify: `docs/specs/m0-m1.md` §7 검증 명령 계약
- Modify: `docs/notes/kitchen-pressure-verification.md` "스테이지별 세 전략 검증" 절

- [ ] **Step 1: CI에 suite를 더합니다**

`check.sh m5` 단계 바로 뒤에 같은 형식의 단계를 더합니다.

```yaml
- name: mise
  run: bash scripts/check.sh mise
```

단계 이름과 들여쓰기는 파일의 이웃 단계와 같게 맞춥니다.

- [ ] **Step 2: README와 명령 계약을 갱신합니다**

`README.md`의 `check.sh m4` 설명 뒤에 한 문장을 더합니다.

```markdown
`check.sh mise`는 예보 폭·시드 생성기·세션과 기록의 시드 보존을 검사하며, 폭이 0인 현재 콘텐츠에서는 작성된 일정과의 항등을 확인합니다.
```

`docs/specs/m0-m1.md` §7의 명령 목록에 다음 줄을 더합니다.

```markdown
`bash scripts/check.sh mise`는 예보 폭 검증, 시드 해시 고정값, 생성기의 시드 0 항등·범위·결정론, 세션·기록·저장소의 `service_seed`와 `attempts` 보존, 캠페인 화면의 시드 추첨을 검사합니다.
```

- [ ] **Step 3: 3전략 표에 정정 절을 덧붙입니다**

`docs/notes/kitchen-pressure-verification.md`의 "스테이지별 세 전략 검증" 절 끝에 추가합니다.

```markdown
### 2026-09-XX 정정: 시드 0 기준

[수요 예보·미장·리뷰 명세](../specs/mise-forecast-reviews.md)에 따라 주문 구성은 시드로 정해집니다.
위 표와 `check.sh m3`의 3전략·무계획 격차는 시드 0, 곧 작성된 일정에 대한 결과이며 다른 시드로 넓히지 않습니다.
```

`XX`는 커밋하는 날짜로 채웁니다.

- [ ] **Step 4: 문서 검사와 전체 회귀**

Run: `trunk check README.md docs/specs/m0-m1.md docs/notes/kitchen-pressure-verification.md .github/workflows`
Expected: `✔ No issues`.

Run: `bash scripts/check.sh m0` 부터 `m5`, `mise`, `ui-regressions`까지 차례로, 그리고 `python3 tests/test_m4_restart.py`, `python3 tests/test_export_check.py`, `bash scripts/check-export.sh`
Expected: 모두 `PASS`.

- [ ] **Step 5: 커밋**

```bash
git add .github/workflows README.md docs/specs/m0-m1.md docs/notes/kitchen-pressure-verification.md
git commit -m "docs(checks): register the mise suite and record the seed-0 baseline"
```

---

## 완료 조건

- `bash scripts/check.sh mise`가 `PASS`이고 CI에 등록되어 있습니다.
- 기존 모든 suite와 export 검사가 `PASS`이며, 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있고 `service_seed`는 0입니다.
- 새 저장 문서는 스키마 4에 `attempts`를 가지며, 스키마 1~3 문서와 5필드 세션은 그대로 읽힙니다.
- 캠페인 화면에서 같은 시나리오를 두 번 시작하면 두 번째 `definitions.service_seed`가 `service_seed_for(id, 1)`이고, 이어하기와 재도전은 시드를 유지합니다.
- 플레이어에게 보이는 주문 구성은 이 PR에서 바뀌지 않습니다.

## 다음 계획

2단계(미장 재구성)는 이 PR이 머지된 코드 위에서 별도 계획으로 씁니다.
폭 작성과 시드 1~5 풀림 검사, 브리핑 인내 시간 표시는 미장 PR 뒤의 콘텐츠 계획에 둡니다.
