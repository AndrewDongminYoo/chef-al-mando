# 수요 예보 콘텐츠 구현 계획 (계획 3: 시드 게이트, `forecast_slack`, 압력 영업 목표)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 시드 1~5 풀림 게이트를 먼저 실패하는 fixture에서 세운 뒤 캠페인 시나리오의 `forecast_slack`을 작성해 두 번째 시작부터 주문 구성이 달라지게 하고, 부분 프렙 뒤 지렛대를 잃은 `split_duties`·`final_service`의 목표와 여유를 측정 근거로 다시 정합니다.

**Architecture:** 게이트는 `tests/fixtures/m3_policies.gd`의 시드 0 기준 정책에 "실제 추첨이 필요로 하는 원재료 발주"만 더한 **추첨 인지 정책**(`draw_aware_policy`)을 시나리오별 시도 1~5의 시드로 실행해 두 목표 통과와 무계획 미달을 확인하는 순수 함수이며, `tests/test_seed_gate.gd`가 실제 콘텐츠와 두 합성 fixture(반드시 실패해야 하는 것)로 그 함수를 검사합니다. `forecast_slack`은 시나리오 `.tres`에만 쓰며 실패한 시나리오는 `PLAN.md` §12대로 폭을 줄이고 목표를 낮추지 않습니다. slack이 생기면 시드≠0 세션의 일정이 달라져 복원이 거부되므로 콘텐츠 버전을 7로 올리고 버전 6 이하의 진행 중 영업을 재시작합니다. 정책 스윕은 세션마다 다시 쓰던 임시 스크립트 대신 `tests/sweep_policies.gd`로 커밋해 목표·여유 결정을 재현 가능하게 합니다.

**Tech Stack:** Godot 4.7.2 GDScript(`--headless`), 저장소 harness(`scripts/check.sh <suite>`), Python `unittest`(`tests/test_m4_restart.py`).

**Spec:** `docs/specs/mise-forecast-reviews.md` §4(예보와 시드)·§8(저장과 버전)·§10(검증 계약 "생성기 검사"·"풀림 검사" 행), `docs/plans/PLAN.md` §12 위험 표의 "예보 폭이 넓어 풀리지 않는 시드" 행. 선행 계획의 정정 절: `docs/plans/mise-forecast-reviews-implementation.md`(계획 1, "다음 계획"이 이 계획의 범위를 정함), `docs/plans/partial-prep-implementation.md`(계획 2b, `split_duties`·`final_service` 판정), `docs/notes/kitchen-pressure-verification.md` 2026-09-21 절(스윕 수치).

## Global Constraints

- §4.1 그대로: `forecast_slack`의 키는 판매 메뉴 ID, 값은 기준 건수에서 위아래로 허용하는 폭이고 없는 메뉴는 0이다. 총 주문 수와 도착 tick은 바뀌지 않는다. `first_shift`·`lunch_prep`의 slack은 0이고 변동은 `hot_queue`부터 시작한다.
- §10 풀림 검사 그대로: 시드마다 실제 추첨을 아는 기준 정책이 두 목표를 통과하고 무계획은 미달한다. 이 계획에서 "시드 1–5"는 시도 인덱스 1–5가 만드는 시드 `ScheduleGenerator.service_seed_for(scenario_id, n)`이며 플레이어가 두 번째부터 여섯 번째 시작에서 실제로 받는 값이다. "무계획 미달"은 `check.sh m3`와 같이 캠페인 세 번째 영업(`hot_queue`)부터 검사한다.
- 추첨 인지 정책은 시드 0 기준 정책(프렙·담당·배치·우선순위)에 원재료별 `max(작성 purchases, 추첨된 구성의 필요량)`을 `set_purchase`로 맞춘 것이다(작성 발주에 둔 여유는 유지하고 추첨이 더 필요로 하는 만큼만 늘림; `shared_stock`은 작성 발주가 기준 구성의 필요량보다 크다). 발주가 예산을 넘어 거부되면 그 시드는 실패다. 시드 0에서는 이 발주가 작성된 `purchases`와 같아야 하며 Task 1이 이를 검사한다.
- `PLAN.md` §12: 게이트에 실패한 시나리오는 `forecast_slack`을 줄이며 `minimum_served`·`minimum_profit`을 낮추지 않는다. slack 폭과 목표 상향은 같은 여유를 나눠 쓰므로 **현재 목표에서 slack을 먼저 확정한 뒤**(Task 4) 남은 여유로 목표를 정한다(Task 5). 두 Task의 순서를 바꾸지 않는다.
- 목표는 낮추지 않는다. `split_duties`는 담당 없는 정책이 시드 0에서 이미 최대치(26건·12,350원)에 닿으므로 목표값으로는 담당 유무를 가를 수 없다는 것이 측정된 사실이며(2026-09-21 절), Task 5는 이를 전제로 시드 1~5까지 측정한 뒤 승인된 규칙대로만 움직인다. 승인되지 않은 콘텐츠 값(`prep_labor_capacity`, `purchases`, `order_count`, 레시피)은 바꾸지 않는다.
- 콘텐츠 버전은 7, 저장 스키마는 4 그대로다. 버전 6 이하 문서는 읽기만으로 바꾸지 않고 다음 정상 저장에서 7로 갱신하며, 진행 중 영업은 모든 시나리오에서 재시작한다(§8과 `docs/specs/m4-mobile.md`의 버전 이력 관례; `service_seed != 0`인 세션만 골라 재시작하는 안은 두 PCK 검사가 시드 0 writer만 쓰므로 검증할 수 없어 택하지 않는다). `sim_version`은 건드리지 않는다.
- 3전략·무계획 격차 게이트(`check.sh m3`)는 시드 0에서 계속 통과해야 하고, 시드 게이트(`check.sh mise`의 `test_seed_gate.gd`)는 시도 1~5에서 통과해야 한다. 스윕 도구의 출력과 결정 근거는 `docs/notes/kitchen-pressure-verification.md`에 남긴다.
- 범위 밖: §12 3단계 리뷰, 4단계 화면(메뉴 상세·리뷰 패널·메뉴 아이콘·혼합 주문 직원 문구). 브리핑은 §4.4 예보 범위를 이미 보이고, "메뉴별 손님 인내 시간(초)" 한 줄(§7)은 모든 레시피의 `patience_ticks`가 500이라 정보가 없으므로 운영자가 승인 시점에 포함 여부를 정한다(Task 7은 조건부).
- 세션에 들어가는 사전은 `dict["key"] = value`로만 쓴다. fixture의 typed export에는 typed 지역 변수만 `set()`한다. 새 검사는 잘못된 입력에서 먼저 실패하는 것을 확인한 뒤 통과시킨다(§10). Godot 호출은 `--headless`, suite와 스윕은 한 번에 하나만 실행한다(16 GB Mac mini).
- 문서와 사용자 문구는 한국어, 코드 식별자와 커밋 메시지는 영어다. 커밋에 `Co-Author`나 `Claude-Session` 세션 URL을 붙이지 않는다. 머지는 운영자가 한다.
- 검사 명령: `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` 뒤에 `bash scripts/check.sh mise`, `bash scripts/check.sh m3`, `bash scripts/check.sh m4`, `bash scripts/check.sh ui-regressions`, `bash scripts/check-export.sh`. 스윕: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- <인자>`.

---

## 파일 구조

| 파일                                                                                                                     | 책임                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `tests/fixtures/m3_policies.gd`                                                                                          | `run_policy`의 시드 인자, `draw_aware_policy()`, `passes_targets()`(Task 1); 재조정된 정책(Task 5) |
| `tests/test_seed_gate.gd` (신규), `tests/test_mise.gd`                                                                   | 풀림 게이트 함수와 검사(실제 콘텐츠 + 합성 실패 fixture 2종), mise suite 등록(Task 1)              |
| `tests/sweep_policies.gd` (신규)                                                                                         | 시나리오·시드·항목 상한·고정 명령을 인자로 받는 프렙 수량 전수 스윕(Task 2)                        |
| `content/campaign/scenarios/*.tres`                                                                                      | `forecast_slack`(Task 4), 승인된 규칙에 따른 목표값(Task 5)                                        |
| `persistence/campaign_store.gd`, `tests/test_m4_store.gd`, `tests/test_menu_priorities.gd`, `tests/test_service_seed.gd` | 콘텐츠 버전 7과 재시작, 리터럴 6 → 7, 작성된 slack 검사(Task 4)                                    |
| `docs/notes/kitchen-pressure-verification.md`                                                                            | 시드 게이트 절(시도별 회계 표), 지렛대 측정과 목표 결정 절(Task 4·5)                               |
| `docs/specs/mise-forecast-reviews.md`, `docs/specs/m4-mobile.md`, `docs/plans/PLAN.md`                                   | §4.1 작성값 정정, §10 행 현행화, 버전 7 이력(Task 6)                                               |
| `presentation/campaign_screen.gd`, `translations/en.po`                                                                  | 조건부 Task 7: 브리핑 인내 시간 한 줄                                                              |
| `docs/plans/forecast-content-implementation.md`                                                                          | 이 문서: 실행 중 갈린 지점의 정정 절과 회귀 결과(Task 6)                                           |

---

### Task 1: 시드 풀림 게이트와 추첨 인지 정책 (실제 콘텐츠에서는 항등, 합성 fixture에서 실패)

**Files:**

- Modify: `tests/fixtures/m3_policies.gd` (`run_policy` 122-150행, 새 정적 함수 두 개)
- Create: `tests/test_seed_gate.gd`
- Modify: `tests/test_mise.gd:4` (`SUITES`에 추가)

**Interfaces:**

- Consumes: `ScheduleGenerator.service_seed_for(scenario_id, attempt_index)`, `ScenarioDef.with_service_seed(seed)`, `order_schedule()`, `Definitions.recipe_for/ingredient_for`, `minimum_served`, `minimum_profit`, `starting_budget`, `labor_cost`.
- Produces: `Policies.run_policy(scenario, policy = {}, speed = 1, seed_value = 0) -> Dictionary`(시드 0이면 지금과 같음). `Policies.draw_aware_policy(scenario, seed_value) -> Dictionary`(기준 정책 앞에 원재료별 `set_purchase`, `data.ingredients` 순서). `Policies.passes_targets(scenario, run) -> bool`. `SeedGate.evaluate(campaign, scenario, attempts: Array[int]) -> Dictionary`(`{"passed": bool, "failures": Array[String], "rows": Array[Dictionary]}`; `rows`는 시도별 `{"attempt", "seed", "served", "profit", "no_plan_served", "no_plan_profit"}`). 모든 캠페인 slack이 비어 있으므로 이 Task 뒤 실제 콘텐츠의 게이트는 시드 0 결과와 같은 값으로 통과합니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_seed_gate.gd`를 만듭니다.

```gdscript
extends "res://tests/harness.gd"

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const ATTEMPTS: Array[int] = [1, 2, 3, 4, 5]


func run(_tree: SceneTree) -> void:
	var campaign: Resource = ResourceLoader.load("res://content/campaign/campaign.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_test_draw_aware_policy(campaign)
	_test_synthetic_failures(campaign)
	_test_campaign_gate(campaign)


## 시드 0의 추첨은 작성된 순서이므로 추첨 인지 발주는 작성된 purchases와 같아야 하고, 시드가 있으면 그
## 시드의 구성이 필요로 하는 양이어야 합니다.
func _test_draw_aware_policy(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		var policy: Dictionary = Policies.draw_aware_policy(scenario, 0)
		var purchases: Dictionary = {}
		for command: Dictionary in policy.preparation:
			if command.kind == "set_purchase":
				purchases[command.target_id] = command.value
		expect(purchases == scenario.purchases, "seed 0 draw-aware purchases equal the authored purchases: " + scenario.id)
		expect(policy.preparation.slice(purchases.size()) == Policies.reference_policy(scenario.id).preparation
			and policy.priorities == Policies.reference_policy(scenario.id).priorities,
			"the draw-aware policy is the reference policy behind its purchases: " + scenario.id)
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var slacked: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	slacked.forecast_slack = slack
	var seed_value: int = ScheduleGenerator.service_seed_for("hot_queue", 1)
	var drawn: Dictionary = {}
	for arrival: Dictionary in slacked.with_service_seed(seed_value).order_schedule():
		var recipe: Resource = slacked.recipe_for(arrival.recipe_id)
		for ingredient_id: String in recipe.ingredients:
			drawn[ingredient_id] = drawn.get(ingredient_id, 0) + recipe.ingredients[ingredient_id]
	var expected_purchases: Dictionary = {}
	for ingredient_id: String in hot_queue.purchases:
		expected_purchases[ingredient_id] = maxi(hot_queue.purchases[ingredient_id], drawn.get(ingredient_id, 0))
	for ingredient_id: String in drawn:
		if not expected_purchases.has(ingredient_id):
			expected_purchases[ingredient_id] = drawn[ingredient_id]
	var seeded_policy: Dictionary = Policies.draw_aware_policy(slacked, seed_value)
	var seeded_purchases: Dictionary = {}
	for command: Dictionary in seeded_policy.preparation:
		if command.kind == "set_purchase":
			seeded_purchases[command.target_id] = command.value
	var seeded_ids: PackedStringArray = []
	for arrival: Dictionary in slacked.with_service_seed(seed_value).order_schedule():
		seeded_ids.append(arrival.recipe_id)
	expect(seeded_ids != hot_queue.order_recipe_ids, "the seeded fixture draws a different order than the authored one")
	expect(seeded_purchases == expected_purchases,
		"a seeded draw-aware policy raises each purchase to what the drawn composition needs and keeps the authored surplus")
	var run: Dictionary = Policies.run_policy(slacked, seeded_policy, 1, seed_value)
	expect(run.accepted and run.snapshot.orders.size() == slacked.order_count, "run_policy executes a seeded schedule")
	var repeat: Dictionary = Policies.run_policy(slacked, seeded_policy, 1, seed_value)
	expect(repeat.accepted and repeat.hash == run.hash, "a seeded run repeats its final state hash")


## 게이트는 풀리지 않는 fixture에서 실패해야 합니다(§10). 첫째: 손익 목표를 예보 상한의 최대 손익과 같게
## 두면 어떤 실제 영업도 닿지 못합니다. 둘째: 목표가 없다시피 하면 무계획이 통과해 게이트가 실패합니다.
func _test_synthetic_failures(campaign: Resource) -> void:
	var hot_queue: Resource = campaign.scenario_for("hot_queue")
	var unsolvable: Resource = hot_queue.duplicate()
	var slack: Dictionary[String, int] = {"grill": 2, "soup": 1, "salad": 1}
	unsolvable.forecast_slack = slack
	unsolvable.minimum_profit = unsolvable.maximum_profit(unsolvable.order_count)
	expect(unsolvable.validate().is_empty(), "the unsolvable fixture is still valid content")
	var verdict: Dictionary = SeedGate.evaluate(campaign, unsolvable, ATTEMPTS)
	expect(not verdict.passed and verdict.failures.size() == ATTEMPTS.size()
		and verdict.failures[0].begins_with("attempt 1:"),
		"a profit target equal to the forecast maximum fails the gate on every attempt")
	var trivial: Resource = hot_queue.duplicate()
	trivial.forecast_slack = slack
	trivial.minimum_served = 1
	trivial.minimum_profit = -trivial.starting_budget
	verdict = SeedGate.evaluate(campaign, trivial, ATTEMPTS)
	expect(not verdict.passed and verdict.failures.size() == ATTEMPTS.size()
		and verdict.failures[0].contains("no plan passes"),
		"targets the no-plan service reaches fail the gate on every attempt")


func _test_campaign_gate(campaign: Resource) -> void:
	for scenario: Resource in campaign.scenarios:
		var verdict: Dictionary = SeedGate.evaluate(campaign, scenario, ATTEMPTS)
		expect(verdict.passed, "attempts 1-5 are solvable and pressured: %s %s" % [scenario.id, ", ".join(verdict.failures)])
		for row: Dictionary in verdict.rows:
			print("SEED_GATE ", scenario.id, " ", JSON.stringify(row, "", true))
```

같은 파일 끝에 게이트를 내부 클래스로 둡니다(별도 fixture 파일을 만들지 않습니다: 이 검사만 씁니다).

```gdscript
class SeedGate:
	## 시도 인덱스마다 그 시드의 추첨 인지 정책이 두 목표를 통과하고, 캠페인 세 번째 영업부터는 무계획이
	## 미달해야 합니다. 실패 문장은 "attempt N: <이유>" 꼴입니다.
	static func evaluate(campaign: Resource, scenario: Resource, attempts: Array[int]) -> Dictionary:
		var failures: Array[String] = []
		var rows: Array[Dictionary] = []
		var pressured: bool = campaign.scenarios.find(campaign.scenario_for(scenario.id)) >= 2
		for attempt: int in attempts:
			var seed_value: int = ScheduleGenerator.service_seed_for(scenario.id, attempt)
			var run: Dictionary = Policies.run_policy(scenario, Policies.draw_aware_policy(scenario, seed_value), 1, seed_value)
			var row: Dictionary = {"attempt": attempt, "seed": seed_value, "served": -1, "profit": 0, "no_plan_served": -1, "no_plan_profit": 0}
			if not run.accepted:
				failures.append("attempt %d: draw-aware policy rejected (%s)" % [attempt, run.reason])
			else:
				row["served"] = run.snapshot.accounting.served
				row["profit"] = run.snapshot.accounting.profit
				if not Policies.passes_targets(scenario, run):
					failures.append("attempt %d: draw-aware policy misses the targets (%d served, %d profit)" % [attempt, row["served"], row["profit"]])
			if pressured:
				var no_plan: Dictionary = Policies.run_policy(scenario, {}, 1, seed_value)
				if no_plan.accepted:
					row["no_plan_served"] = no_plan.snapshot.accounting.served
					row["no_plan_profit"] = no_plan.snapshot.accounting.profit
					if Policies.passes_targets(scenario, no_plan):
						failures.append("attempt %d: no plan passes (%d served, %d profit)" % [attempt, row["no_plan_served"], row["no_plan_profit"]])
			rows.append(row)
		return {"passed": failures.is_empty(), "failures": failures, "rows": rows}
```

`pressured`는 시나리오 ID로 캠페인 원본을 찾아 그 위치를 봅니다. 합성 fixture는 캠페인 배열에 없는 사본이라 `find(scenario)`는 -1이지만 `scenario_for("hot_queue")`는 원본(세 번째, 인덱스 2)을 돌려주므로 사본도 압력 영업으로 다뤄집니다.

`tests/test_mise.gd`의 `SUITES`에 `"res://tests/test_seed_gate.gd"`를 마지막에 추가합니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. `Policies.draw_aware_policy`·`passes_targets`가 없어 SCRIPT ERROR가 나거나, `run_policy`가 시드 인자를 받지 않아 파싱에 실패합니다.

- [ ] **Step 3: `run_policy` 시드 인자와 새 정적 함수**

`tests/fixtures/m3_policies.gd`의 `run_policy` 서명과 본문을 바꿉니다. 시드가 있으면 시나리오 사본에 시드를 심어 준비·시뮬레이션·우선순위 루프가 모두 그 사본의 일정을 읽게 합니다.

```gdscript
static func run_policy(scenario: Definitions, policy: Dictionary = {}, speed: int = 1, seed_value: int = 0) -> Dictionary:
	var seeded: Definitions = scenario if seed_value == 0 else scenario.with_service_seed(seed_value)
	var plan := PreparationPlan.new(seeded)
```

같은 함수 안의 `for arrival: Dictionary in scenario.order_schedule():`을 `seeded.order_schedule()`로, `_drive_to(driver, sim, scenario.closing_tick, speed)`는 그대로 둡니다(`closing_tick`은 같음). 나머지 본문은 바뀌지 않습니다.

`reference_policy` 아래에 추가합니다.

```gdscript
## §10 풀림 검사의 "실제 추첨을 아는 기준 정책": 시드 0 기준 정책 앞에, 원재료마다 작성 발주와 그 시드의
## 구성이 필요로 하는 양 가운데 큰 값을 set_purchase로 맞춥니다. 시드 0에서는 작성된 purchases와 같습니다.
static func draw_aware_policy(scenario: Definitions, seed_value: int) -> Dictionary:
	var seeded: Definitions = scenario if seed_value == 0 else scenario.with_service_seed(seed_value)
	var needs: Dictionary[String, int] = {}
	for arrival: Dictionary in seeded.order_schedule():
		var recipe := scenario.recipe_for(arrival.recipe_id)
		for ingredient_id: String in recipe.ingredients:
			needs[ingredient_id] = needs.get(ingredient_id, 0) + recipe.ingredients[ingredient_id]
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	for ingredient: Definitions.IngredientDef in scenario.ingredients:
		if not ingredient.purchasable:
			continue
		var quantity: int = maxi(scenario.purchases.get(ingredient.id, 0), needs.get(ingredient.id, 0))
		if quantity > 0:
			_add(policy, "set_purchase", ingredient.id, quantity)
	var reference := reference_policy(scenario.id)
	policy.preparation.append_array(reference.preparation)
	policy.priorities = reference.priorities.duplicate(true)
	return policy


static func passes_targets(scenario: Definitions, run: Dictionary) -> bool:
	return run.accepted and run.snapshot.accounting.served >= scenario.minimum_served \
		and run.snapshot.accounting.profit >= scenario.minimum_profit
```

`set_purchase`가 프렙 명령보다 앞에 오는 이유: 프렙은 원재료 재고를 소비하므로 발주가 먼저 확정돼야 `set_prep`이 거부되지 않습니다. 수량 0인 원재료는 명령을 내지 않으므로 시드 0의 발주 사전은 작성 `purchases`와 키까지 같습니다. Step 4의 "seed 0 draw-aware purchases equal the authored purchases" 검사가 어느 시나리오에서 실패하면 그 시나리오의 작성 발주가 자기 기준 구성의 필요량보다 작다는 뜻이며(작성된 일정으로도 모든 주문을 팔 수 없음), 그것은 고칠 대상이 아니라 보고할 발견입니다: 검사를 완화하지 말고 멈춰서 시나리오 ID와 두 사전을 보고합니다.

- [ ] **Step 4: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS. `build/check/mise.log`의 `SEED_GATE` 줄 40개(시나리오 8 × 시도 5)에서 `served`·`profit`이 시나리오마다 시도와 무관하게 같은지 확인합니다(slack이 비어 있으면 모든 시드가 작성된 순서를 돌려주므로 같아야 하며, 다르면 `run_policy`의 시드 처리에 결함이 있는 것입니다).
Run: `bash scripts/check.sh m3` → PASS(`run_policy`의 기본 인자 경로가 그대로임을 증명).

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/m3_policies.gd tests/test_seed_gate.gd tests/test_mise.gd
git commit -m "test(seed): add the attempt 1-5 solvability gate with a draw-aware reference policy"
```

---

### Task 2: 정책 스윕 도구

**Files:**

- Create: `tests/sweep_policies.gd`
- Modify: `docs/notes/kitchen-pressure-verification.md` (스윕 절에 도구 사용법 한 문단)

**Interfaces:**

- Consumes: `Policies.run_policy(scenario, policy, 1, seed)`, `Policies.passes_targets`, `Policies.reference_policy`.
- Produces: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario <id> [--attempt N] [--items id:cap,id:cap,...] [--keep prep|duties|priorities|placement|purchases,...] [--best]`. 출력은 조합마다 `SWEEP {"quantities": {...}, "labor": L, "served": S, "profit": P, "working": W}`(통과 조합만), 끝에 `SWEEP_SUMMARY {"scenario", "attempt", "seed", "combinations", "passed", "best": {...}}`. `--keep`은 기준 정책에서 그대로 둘 명령 종류이며, 스윕 대상인 `set_prep`은 항상 기준 정책에서 지우고 `--items`로 순회합니다. `--items`를 생략하면 그 시나리오의 미장 전부를 상한 `prep_labor_capacity / labor_units`로 순회합니다. `--best`는 통과 여부와 무관하게 제공·손익 사전순 최댓값도 요약에 넣습니다.

- [ ] **Step 1: 스크립트 작성**

```gdscript
extends SceneTree

## 프렙 수량 전수 스윕. 계획 2a·2b가 세션마다 다시 쓰던 임시 스크립트를 커밋한 것입니다.
## 사용법은 docs/notes/kitchen-pressure-verification.md의 스윕 절에 있습니다.

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")


func _init() -> void:
	var arguments := _arguments()
	var campaign: Resource = load("res://content/campaign/campaign.tres")
	var scenario: Resource = campaign.scenario_for(arguments.get("scenario", ""))
	if scenario == null:
		push_error("unknown scenario: " + str(arguments.get("scenario", "")))
		quit(2)
		return
	var attempt: int = int(arguments.get("attempt", "0"))
	var seed_value: int = ScheduleGenerator.service_seed_for(scenario.id, attempt)
	var items: Array[String] = []
	var caps: Array[int] = []
	if arguments.has("items"):
		for entry: String in arguments["items"].split(","):
			var parts := entry.split(":")
			items.append(parts[0])
			caps.append(int(parts[1]))
	else:
		for item: Resource in scenario.mise_items():
			items.append(item.id)
			caps.append(scenario.prep_labor_capacity / item.labor_units)
	var keep: PackedStringArray = arguments.get("keep", "duties,priorities,placement,purchases").split(",")
	var base: Dictionary = {"preparation": [], "priorities": {}}
	var reference: Dictionary = Policies.reference_policy(scenario.id)
	for command: Dictionary in reference.preparation:
		var kind: String = command.kind
		if kind == "set_duty" and "duties" in keep or kind == "set_purchase" and "purchases" in keep \
			or kind in ["move_station", "rotate_station"] and "placement" in keep:
			base.preparation.append(command.duplicate(true))
	if "priorities" in keep:
		base.priorities = reference.priorities.duplicate(true)
	var state := {"scenario": scenario, "seed": seed_value, "items": items, "caps": caps, "base": base,
		"combinations": 0, "passed": 0, "best": {}, "best_any": {}}
	var quantities: Array[int] = []
	quantities.resize(items.size())
	quantities.fill(0)
	_sweep(state, quantities, 0)
	print("SWEEP_SUMMARY ", JSON.stringify({"scenario": scenario.id, "attempt": attempt, "seed": seed_value,
		"combinations": state.combinations, "passed": state.passed, "best": state.best,
		"best_any": state.best_any if arguments.has("best") else {}}, "", true))
	quit(0)


func _sweep(state: Dictionary, quantities: Array[int], index: int) -> void:
	var items: Array[String] = state.items
	if index < items.size():
		for quantity: int in state.caps[index] + 1:
			quantities[index] = quantity
			_sweep(state, quantities, index + 1)
		return
	var scenario: Resource = state.scenario
	var policy: Dictionary = {"preparation": state.base.preparation.duplicate(true), "priorities": state.base.priorities.duplicate(true)}
	var labor: int = 0
	for position: int in items.size():
		labor += quantities[position] * scenario.ingredient_for(items[position]).labor_units
		if quantities[position] > 0:
			policy.preparation.append({"kind": "set_prep", "target_id": items[position], "value": quantities[position]})
	if labor > scenario.prep_labor_capacity:
		return
	var run: Dictionary = Policies.run_policy(scenario, policy, 1, state.seed)
	if not run.accepted:
		return
	state.combinations += 1
	var accounting: Dictionary = run.snapshot.accounting
	var row := {"quantities": _named(items, quantities), "labor": labor, "served": accounting.served,
		"profit": accounting.profit, "working": run.snapshot.metrics.orders.working}
	if _better(row, state.best_any):
		state.best_any = row
	if Policies.passes_targets(scenario, run):
		state.passed += 1
		print("SWEEP ", JSON.stringify(row, "", true))
		if _better(row, state.best):
			state.best = row


static func _better(row: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	if row.served != current.served:
		return row.served > current.served
	return row.profit > current.profit


static func _named(items: Array[String], quantities: Array[int]) -> Dictionary:
	var named: Dictionary = {}
	for position: int in items.size():
		if quantities[position] > 0:
			named[items[position]] = quantities[position]
	return named


func _arguments() -> Dictionary:
	var parsed: Dictionary = {}
	var key := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			key = argument.substr(2)
			parsed[key] = "true"
		elif not key.is_empty():
			parsed[key] = argument
			key = ""
	return parsed
```

`scenario.mise_items()`와 `ingredient_for`는 `Definitions`의 메서드입니다(계획 2a Task 1). `run_policy`는 발주가 예산을 넘거나 재료가 모자라면 `accepted=false`를 돌려주므로 그 조합은 세지 않습니다(계획 2b 절의 "`PreparationPlan.initial_state`가 받아들이는 조합만"과 같은 규칙).

- [ ] **Step 2: 실행 확인(작은 시나리오)**

Run: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario first_shift --items prepped_vegetable:6 --best`
Expected: `SWEEP_SUMMARY`에 `combinations` 7(0~6), `passed` ≥ 1, `best`에 `served` 12(주문 12건 전부)와 손익. 결과를 아무 파일에도 기록하지 않습니다(도구 확인일 뿐).

Run: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario split_duties --keep duties --items thawed_protein:1`
Expected: 2026-09-21 절의 수치대로 `thawed_protein 1`(담당 없음이 아니라 담당 유지) 조합이 통과하고 `best.served == 26`, `best.profit == 12350`. 여기서 `--keep duties`를 빼면 담당 없는 실행이며 같은 26·12,350이 나와야 합니다(그 절이 기록한 사실의 재현). 두 값이 다르면 도구나 그 절 가운데 하나가 틀린 것이니 멈추고 보고합니다.

- [ ] **Step 3: 사용법 기록**

`docs/notes/kitchen-pressure-verification.md`의 2026-09-21 절 마지막 문단(스윕 로그가 남아 있지 않다는 문장) 뒤에 한 문단을 추가합니다: 이후의 스윕은 `tests/sweep_policies.gd`로 돌리며 인자와 출력 형식(위 Interfaces의 한 줄), 같은 인자는 같은 조합 수와 같은 `best`를 낸다는 문장. 숫자는 적지 않습니다.

- [ ] **Step 4: Commit**

```bash
git add tests/sweep_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "test(m3): commit the prep-quantity sweep as a reusable headless script"
```

---

### Task 3: 생성기 자리바꿈 (명세 §4.2 3단계 정정, 운영자 결정 2026-09-21)

**배경:** Task 4의 첫 실행이 BLOCKED로 끝났습니다. 생성기는 §4.2대로 slack이 하나라도 있으면 건수 이동과 무관하게 전체 슬롯을 섞는데, 작성된 일정은 화구·냉식대 부하를 교대로 배치한 파동 구조라 섞이면 구이가 연속으로 몰립니다. `hot_queue`에 `{salad: 1}`만 두면(이동 불가, 순수 섞기만 발생) 시도 1~5가 전부 실패했고, 프렙 수량 104가지 조합 전부, 우선순위를 빼도 통과 조합이 0이었습니다. 여섯 시나리오의 30개 시도 행 중 29개가 실패했습니다. `PLAN.md` §12의 "폭을 줄인다"는 완화는 폭이 0이 아닌 한 섞기를 막지 못합니다. 운영자는 "자리바꿈만, 섞기 없음"을 골랐습니다.

**Files:**

- Modify: `content/schedule_generator.gd` (`recipe_ids`, 파일 머리 주석)
- Modify: `tests/test_schedule_generator.gd`
- Modify: `docs/specs/mise-forecast-reviews.md` §4.2 (정정 단락)

**Interfaces:**

- Consumes: `forecast_ranges()`, `menu_ids`, `order_recipe_ids`, `break_identity()`.
- Produces: `ScheduleGenerator.recipe_ids(scenario, seed)`가 시드 0이나 slack 합 0이면 작성 순서를, 그 외에는 **작성 순서에서 이동 횟수만큼의 슬롯만 바뀐 배열**을 돌려줍니다. 한 이동은 기증 메뉴가 든 슬롯 하나를 RNG로 골라 수신 메뉴로 바꾸는 것입니다. 이동이 하나도 불가능할 때만 결과가 작성 순서와 같아지며 그때 `break_identity`가 서로 다른 메뉴의 첫 인접 쌍을 맞바꿉니다. RNG 소비 순서: 이동 횟수 → (기증 → 수신 → 슬롯) × 이동 횟수. 같은 시드는 같은 배열입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_schedule_generator.gd`의 `expect(drawn != ScheduleGenerator.recipe_ids(slacked, 53743680), ...)` 뒤에 추가합니다.

```gdscript
	var changed: int = 0
	for index: int in drawn.size():
		if drawn[index] != hot_queue.order_recipe_ids[index]:
			changed += 1
	var total_slack: int = 0
	for recipe_id: String in slacked.menu_ids:
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	expect(changed >= 1 and changed <= total_slack,
		"a seeded draw changes between one slot and the total slack (changed %d of %d)" % [changed, total_slack])
	var authored_runs: Dictionary = _longest_runs(hot_queue.order_recipe_ids)
	var drawn_runs: Dictionary = _longest_runs(drawn)
	for recipe_id: String in slacked.menu_ids:
		expect(drawn_runs.get(recipe_id, 0) <= authored_runs.get(recipe_id, 0) + 1,
			"slot replacement keeps the authored wave structure within one extra consecutive order: " + recipe_id)
```

파일 끝에 도우미를 추가합니다.

```gdscript
func _longest_runs(recipe_ids: PackedStringArray) -> Dictionary:
	var longest: Dictionary = {}
	var current: String = ""
	var length: int = 0
	for recipe_id: String in recipe_ids:
		length = length + 1 if recipe_id == current else 1
		current = recipe_id
		longest[recipe_id] = maxi(longest.get(recipe_id, 0), length)
	return longest
```

`hot_queue`는 `grill, soup, grill, salad, …` 교대라 작성 연속 길이가 모두 1이고, 이동 4회 이하의 자리바꿈은 한 메뉴의 연속을 최대 2까지만 만듭니다(두 이동이 인접 슬롯을 같은 수신 메뉴로 바꾸면 3도 가능하지만 시드 104076537의 결과가 그런지는 실행이 정합니다; 그 경우 `+ 1`을 `+ 2`로 고치고 이 문서 정정 절에 적습니다). 기존 검사 가운데 "no seed in 1..50 reproduces the authored order"와 `one_sided`(이동 불가 → 건수 불변)는 새 규칙에서도 그대로 성립합니다.

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise`
Expected: FAIL. 전체 섞기는 `changed`가 `total_slack`을 훨씬 넘고 연속 길이도 넘습니다. (작업 트리에 Task 4의 미커밋 slack이 있으면 `test_seed_gate.gd`의 여섯 캠페인 줄도 실패합니다; 그것은 이 Task의 RED가 아니라 Task 4의 상태입니다.)

- [ ] **Step 3: 생성기**

`content/schedule_generator.gd`의 `recipe_ids`를 바꿉니다. 이동 결정 루프는 그대로 두고 결과를 만드는 방식만 바뀝니다.

```gdscript
static func recipe_ids(scenario: Resource, service_seed: int) -> PackedStringArray:
	var authored: PackedStringArray = scenario.order_recipe_ids
	var ranges: Dictionary = scenario.forecast_ranges()
	var counts: Dictionary[String, int] = {}
	var total_slack: int = 0
	for recipe_id: String in scenario.menu_ids:
		counts[recipe_id] = ranges[recipe_id]["baseline"]
		total_slack += ranges[recipe_id]["max"] - ranges[recipe_id]["baseline"]
	if service_seed == 0 or total_slack == 0:
		return authored.duplicate()
	var result: PackedStringArray = authored.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = service_seed
	var moves: int = rng.randi_range(1, total_slack)
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
		var slots: PackedInt32Array = []
		for index: int in result.size():
			if result[index] == donor:
				slots.append(index)
		result[slots[rng.randi_range(0, slots.size() - 1)]] = receiver
		counts[donor] -= 1
		counts[receiver] += 1
	return break_identity(result, authored)
```

`counts[donor] > min ≥ 0`이므로 `slots`는 비지 않습니다. 파일 머리 주석을 새 규칙으로 바꿉니다: "시드 0이거나 모든 메뉴의 slack 합이 0이면 작성된 순서를 그대로 돌려줍니다. 그 외에는 예보 범위 안에서 건수를 옮기되, 한 이동은 기증 메뉴가 든 슬롯 하나를 수신 메뉴로 바꾸는 것이고 슬롯을 섞지 않으므로 작성된 파동 구조가 유지됩니다." `break_identity`의 주석 첫 문장("A shuffle can land on the authored order …")은 "이동이 하나도 불가능하면 결과가 작성 순서와 같다"로 고칩니다.

- [ ] **Step 4: 통과 확인**

Run: `bash scripts/check.sh mise` → `test_schedule_generator.gd`의 검사가 모두 통과합니다. 작업 트리에 Task 4의 미커밋 시작 slack이 있으면 `SEED_GATE` 줄을 읽어 `hot_queue`의 시도 1~5가 통과하는지 봅니다(직전에 0/104였던 사례). 다른 시나리오가 아직 실패하면 그 문장을 보고서에 적고 Task 4에 넘깁니다. 이 Task의 통과 조건은 생성기 검사이며, 시드 게이트는 Task 4가 닫습니다.
Run: `bash scripts/check.sh m3` → PASS(시드 0 경로는 바뀌지 않음).

- [ ] **Step 5: 명세 정정**

`docs/specs/mise-forecast-reviews.md` §4.2의 마지막 단락("섞은 결과가 우연히 …") 뒤에 단락을 추가합니다.

```markdown
**2026-09-21 정정:** 3단계의 전체 섞기는 작성된 파동 구조(화구·냉식대 부하의 교대)를 무너뜨려 `hot_queue`에서 어떤 프렙 조합도 목표에 닿지 못했으므로(계획 3 `../plans/forecast-content-implementation.md` Task 3), 자리바꿈으로 바꿉니다.
한 이동은 기증 메뉴가 든 슬롯 하나를 같은 RNG로 골라 수신 메뉴로 바꾸는 것이고 슬롯을 섞지 않습니다.
따라서 건수가 기준과 같은 시드는 없고(이동이 가능하면 최소 한 번 이동), 이동이 하나도 불가능한 시나리오만 작성 순서와 같아지며 그때 서로 다른 메뉴가 인접한 첫 두 슬롯을 맞바꿔 구분합니다.
```

- [ ] **Step 6: Commit**

Task 4의 미커밋 파일(`content/campaign/scenarios/*.tres`, `persistence/campaign_store.gd`, `tests/test_m4_store.gd`, `tests/test_menu_priorities.gd`, `tests/test_service_seed.gd`)은 이 커밋에 넣지 않습니다. `git add`에 아래 세 파일만 적습니다.

```bash
git add content/schedule_generator.gd tests/test_schedule_generator.gd docs/specs/mise-forecast-reviews.md
git commit -m "feat(content): replace slots instead of shuffling the seeded schedule"
```

---

### Task 4: `forecast_slack` 작성, 콘텐츠 버전 7, 시드 게이트 통과 — **취소 (운영자 결정 2026-09-21)**

**취소 사유:** Task 3의 자리바꿈 생성기로도 시작 slack(메뉴별 1–2)에서 시도 1–5의 게이트가 여섯 압력 영업 30행 가운데 24행 실패했습니다(`hot_queue` 1/5, `shared_stock` 1/5, `long_route` 2/5, `split_duties` 1/5, `rush_hour` 1/5, `final_service` 0/5). 원인은 조율 방식입니다: `check.sh m3`의 "기준 정책 여분 ≤ 제공 1건·손익 2,000" 규칙이 압력 영업을 여분 1건 이내로 맞춰 놓아(`hot_queue` 시드 0은 수프 5건 전부와 구이 3건이 만료된 채 12건·4,750원으로 통과), ±1건의 구성 변화도 흡수할 여유가 없습니다. `hot_queue` 시도 2(교체 3슬롯, 구이 3연속)는 프렙 조합 104가지 전부에서 우선순위 유무와 무관하게(작성 발주·배치 기준) 통과가 없었습니다(최고 9건). `PLAN.md` §12의 "폭을 줄인다"는 완화는 자리바꿈 생성기에서는 실행하지 않았고, 이전의 전체 섞기에서만 메뉴 하나짜리 폭까지 줄여도 실패했으므로, 자리바꿈에서 0이 아닌 다른 폭이 풀리는지는 재지 않았습니다. 운영자는 "여기서 멈추고 발견 기록"을 골랐습니다: `forecast_slack`은 비운 채로 두고 콘텐츠 버전은 6 그대로이며, 변동을 살리는 **압력 영업 재조율 명세**(m3 게이트 규칙 완화, 노동량·예산 여유, 시드별 정책)는 플레이테스트와 함께 별도로 결정합니다. 첫 실행이 남긴 시작 slack·콘텐츠 7 작업은 되돌렸고 그 diff는 세션 scratchpad에만 있었습니다. 아래 단계 서술은 기록으로 남기며 실행하지 않습니다.

재현 절차는 세 줄입니다.
압력 영업 여섯 개의 `forecast_slack`을 아래 Step 4 표의 값으로 둡니다(`.tres` 표기는 `hot_queue`가 `forecast_slack = Dictionary[String, int]({"grill": 2, "soup": 1, "salad": 1})`, 나머지는 메뉴마다 1).
`bash scripts/check.sh mise`를 돌려 `SEED_GATE` 줄을 읽습니다.
`"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario hot_queue --attempt 2 --keep priorities --best`를 돌리고, 같은 명령을 `--keep placement`로 한 번 더 돌립니다.

**Files:**

- Modify: `content/campaign/scenarios/hot_queue.tres`, `shared_stock.tres`, `long_route.tres`, `split_duties.tres`, `rush_hour.tres`, `final_service.tres` (`forecast_slack`)
- Modify: `tests/test_service_seed.gd:180-181`
- Modify: `persistence/campaign_store.gd:6`, `:171`, `:233-236`
- Modify: `tests/test_m4_store.gd`(46·171·186·214·230행의 `== 6` → `== 7`, 53·468·505·553행 리터럴 6 → 7, 버전 5 검사 뒤 버전 6 검사 추가), `tests/test_menu_priorities.gd:111`, `tests/test_service_seed.gd:341`·`:359`
- Modify: `docs/notes/kitchen-pressure-verification.md` (새 절 "2026-09-XX 시드 게이트: 작성된 forecast_slack")

**Interfaces:**

- Consumes: Task 1의 게이트, Task 2의 스윕(실패 원인을 볼 때).
- Produces: 여섯 시나리오의 `forecast_slack`(작성값은 아래 규칙으로 정하고 최종값은 `.tres`가 권위). `CampaignStore.VERSIONS.content_version == 7`; 버전 6 이하 문서는 `content_updated`로 읽히고 `active_session`은 `null`. 브리핑은 `campaign_screen.gd`가 이미 `forecast_ranges()`를 읽으므로 코드 변경 없이 범위를 보입니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_service_seed.gd:180`의 `expect(scenario.forecast_slack.is_empty(), ...)`를 작성 규칙의 검사로 바꿉니다.

파일 상단 상수에 `const FIXED_FORECAST: Array[String] = ["first_shift", "lunch_prep"]`를 추가하고 루프를 바꿉니다.

```gdscript
	for scenario: Resource in campaign.scenarios:
		if scenario.id in FIXED_FORECAST:
			expect(scenario.forecast_slack.is_empty(), "the first two services keep a fixed forecast: " + scenario.id)
		else:
			expect(not scenario.forecast_slack.is_empty(), "every pressure service varies from the second attempt: " + scenario.id)
			for recipe_id: String in scenario.menu_ids:
				expect(scenario.forecast_slack.get(recipe_id, 0) <= maxi(1, scenario.baseline_counts()[recipe_id] / 5) and scenario.forecast_slack.get(recipe_id, 0) >= 0,
					"authored slack stays within a fifth of the baseline: %s %s" % [scenario.id, recipe_id])
		expect(scenario.service_seed == 0, "authored service seed is zero: " + scenario.id)
```

이 검사는 Step 3 뒤에 통과하며, 상한 규칙 `max(1, 기준 / 5)`가 §4.4의 예시("단백질 구이 8–12, 곡물 수프 4–6, 채소 샐러드 4–6" = `hot_queue` 기준 10·5·5에 2·1·1)와 같습니다.

`tests/test_m4_store.gd`의 버전 5 검사 블록(216-231행) 뒤에 버전 6 검사를 추가합니다(계획 2b Task 5와 같은 꼴, 세션은 현재 코드로 만든 `lunch_prep` 세션).

```gdscript
	var version_six_target := directory + "/content_version_six.json"
	var version_six_session := _scenario_session(campaign, "lunch_prep")
	_write(version_six_target, JSON.stringify({"schema_version": 4, "content_version": 6, "sim_version": 1,
		"records": current_records, "attempts": {}, "active_session": version_six_session}))
	var version_six_bytes := FileAccess.get_file_as_bytes(version_six_target)
	loaded = CampaignStore.new(campaign, version_six_target).load_records()
	expect(loaded.accepted and loaded.reason == "content_updated" and loaded.records == current_records
		and loaded.active_session == null,
		"authored forecast slack restarts a version 6 session because a seeded schedule no longer matches its snapshot")
	expect(FileAccess.get_file_as_bytes(version_six_target) == version_six_bytes,
		"restarting a version 6 session leaves the old file unchanged until the next write")
	expect(CampaignStore.new(campaign, version_six_target).save_records(current_records).accepted,
		"the next write upgrades a version 6 record to content version 7")
	var version_six_migrated: Variant = JSON.parse_string(FileAccess.get_file_as_string(version_six_target))
	expect(version_six_migrated is Dictionary and version_six_migrated.content_version == 7,
		"a migrated version 6 record writes content version 7")
```

같은 파일의 `content_version == 6` 기대(46·171·186·214·230행)를 `== 7`로, 현재 세션을 담는 문서 리터럴(53·468·505·553행)의 6을 7로 바꿉니다. `tests/test_menu_priorities.gd:111`, `tests/test_service_seed.gd:341`·`:359`의 6도 7로 바꿉니다. 버전 5 검사 블록의 입력 리터럴 5와 그 아래 `== 7` 기대는 그대로 두되 문구의 "content version 6"은 "content version 7"로 맞춥니다(계획 2b Task 5에서 같은 이유로 문구를 바꾼 선례).

- [ ] **Step 2: 실패 확인**

Run: `bash scripts/check.sh mise` → FAIL(`test_service_seed.gd`의 "every pressure service varies" 기대).
Run: `bash scripts/check.sh m4` → FAIL(버전 6 문서가 `loaded`로 읽힘, `== 7` 기대).

- [ ] **Step 3: 콘텐츠 버전 7**

`persistence/campaign_store.gd`:

```gdscript
const VERSIONS := {"schema_version": 4, "content_version": 7, "sim_version": 1}
```

171행의 목록에 6을 넣습니다: `in [LEGACY_CONTENT_VERSION, 2, 3, 4, 5, 6]`.

```gdscript
func _content_update_restarts_session(source_content_version: int, _active_session: Dictionary) -> bool:
	# Content 5 keyed prep quantities by mise item, content 6 added missing_mise_ids with mixed
	# consumption, and content 7 authored forecast_slack so a seeded session's schedule no longer
	# matches its snapshot; no earlier session can restore.
	return source_content_version < 7
```

- [ ] **Step 4: slack 작성과 게이트**

여섯 시나리오의 `.tres`에 `forecast_slack`을 씁니다. 시작값은 메뉴마다 `max(1, 기준 건수 / 5)`(정수 나눗셈)입니다.

| 시나리오        | 기준 건수(메뉴 순서)                                                                                      | 시작 slack               |
| --------------- | --------------------------------------------------------------------------------------------------------- | ------------------------ |
| `hot_queue`     | grill 10, soup 5, salad 5                                                                                 | grill 2, soup 1, salad 1 |
| `shared_stock`  | salad 5, soup 9, grain_salad 4, mushroom_salad 4                                                          | 1, 1, 1, 1               |
| `long_route`    | grill 6, mushroom_soup 6, protein_bowl 6, grain_salad 6                                                   | 1, 1, 1, 1               |
| `split_duties`  | salad 7, mushroom_salad 7, grain_grill 6, protein_bowl 6                                                  | 1, 1, 1, 1               |
| `rush_hour`     | salad 4, soup 4, grill 4, grain_salad 4, mushroom_salad 4, mushroom_soup 4, grain_grill 3, protein_bowl 3 | 1 × 8                    |
| `final_service` | 8종 각 4                                                                                                  | 1 × 8                    |

`.tres`의 표기는 `forecast_slack = Dictionary[String, int]({"grill": 2, "soup": 1, "salad": 1})` 꼴이며 `scenario_def.gd`의 typed export와 같아야 합니다(`hot_queue.tres`의 `purchases` 줄이 같은 표기입니다).

Run: `bash scripts/check.sh mise` → 실제 콘텐츠의 게이트 결과를 `SEED_GATE` 줄에서 읽습니다. 실패한 시나리오는 실패 문장(발주 거부 = 예산 초과, 목표 미달, 무계획 통과)을 보고 아래 규칙으로 그 시나리오의 slack만 줄인 뒤 다시 돌립니다(한 번에 한 시나리오, suite는 한 번에 하나).

1. 예산 초과(`draw-aware policy rejected`): 가장 비싼 원재료를 쓰는 메뉴(연어 > 양송이 > 현미 > 토마토)의 slack을 1 줄입니다. 그 시나리오의 발주 여유는 `starting_budget − labor_cost − 작성 purchases 원가`이며, 추첨이 이 여유를 넘는 구성을 만들면 실패합니다.
2. 목표 미달: 가장 큰 slack 값을 1 줄입니다(같으면 `menu_ids` 앞쪽). 필요하면 `tests/sweep_policies.gd --attempt N`으로 그 시드에서 통과 조합이 있는지 봅니다. 통과 조합이 있는데 기준 정책만 실패하면 이 계획에서는 정책을 바꾸지 않고 slack을 줄입니다(§12: 정책은 시드 0 기준이며 폭이 정책의 강건성을 넘지 않게 정함).
3. 무계획 통과: 가장 큰 slack 값을 1 줄입니다.
4. 어떤 시나리오의 slack이 전부 0이 되면 멈추고 보고합니다(§4.1의 취지에 어긋남).

`bash scripts/check.sh m3` → PASS(시드 0 결과는 slack과 무관하므로 바뀌지 않아야 합니다).

- [ ] **Step 5: 기록**

`docs/notes/kitchen-pressure-verification.md`에 "2026-09-XX 시드 게이트: 작성된 `forecast_slack`" 절을 추가합니다. 내용: 작성 규칙과 시작값, 줄인 시나리오와 그 이유(위 규칙 번호), 확정값(권위는 `.tres`), 시나리오·시도별 추첨 인지 정책과 무계획의 제공·손익 표(`SEED_GATE` 줄 인용), 발주 여유가 좁아 폭을 제한한 시나리오. 시드 0 표는 위 절이 소유하므로 다시 적지 않습니다.

- [ ] **Step 6: 통과 확인**

Run: `bash scripts/check.sh mise` → PASS. `bash scripts/check.sh m4` → PASS. `bash scripts/check.sh m3` → PASS. `bash scripts/check.sh ui-regressions` → PASS(브리핑이 범위를 보이는 검사 포함).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py` → 10 OK.
두 PCK: 콘텐츠 6 PCK를 `ab239fa`에서 만들고(계획 2b Task 5의 명령에서 `c600e27`·`content5`·`content6`을 `ab239fa`·`content6`·`content7`로 바꿈) `M4_EXPECT_RESTART=1`로 실행 → 9 OK / 1 skip. 강제 실패 확인은 `< 6`으로 되돌려 두 reader 검사가 실패하는 것을 본 뒤 `< 7`로 되돌립니다.

- [ ] **Step 7: Commit**

콘텐츠와 게이트 기록을 먼저, 버전 7을 다음 커밋으로 나눕니다.

```bash
git add content/campaign/scenarios tests/test_service_seed.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): author forecast slack from the third service and record the seed gate"
git add persistence/campaign_store.gd tests/test_m4_store.gd tests/test_menu_priorities.gd tests/test_service_seed.gd
git commit -m "feat(persistence): bump content to version 7 and restart every earlier session"
```

---

### Task 5: 지렛대 필요성 측정과 압력 영업 목표

**Files:**

- Modify(승인된 규칙에 따라): `content/campaign/scenarios/split_duties.tres`, `final_service.tres`
- Modify: `tests/fixtures/m3_policies.gd`(목표가 바뀌어 대체 정책이 미달하면 그 정책만)
- Modify: `docs/notes/kitchen-pressure-verification.md` (새 절 "2026-09-XX 지렛대 측정과 목표")

**Interfaces:**

- Consumes: Task 4의 확정 slack, Task 2의 스윕.
- Produces: 두 시나리오의 측정 표와, 승인된 규칙이 허용하는 범위의 목표값. 목표가 바뀌면 `check.sh m3`(시드 0 관계식: 기준 여분 ≤ 제공 1·손익 2,000, 무계획 ≥ 2건 또는 1,500 미달, 대체 둘 통과)와 시드 게이트가 모두 통과해야 합니다.

승인 시점의 답이 이 Task의 규칙입니다. 아래는 승인 질문에 대응하는 세 갈래이며, 답에 맞는 갈래만 실행합니다.

**운영자 답(2026-09-21):** `split_duties`는 "준비 노동량 상한 스윕 허용"(Step 2-A 뒤 Step 2-B 실행), `final_service`는 "올리지 않고 여유 측정"(Step 2-C의 "여유 측정" 갈래), 브리핑 인내 시간은 "4단계 화면 계획으로 미룸"(Task 7 실행 안 함).

**Task 4 취소에 따른 범위 조정(2026-09-21):** slack이 비어 있으므로 시도 1–5의 시드는 모두 작성 순서를 돌려줍니다. 아래 "시도 0–5"는 **시도 0만** 실행하며, 표의 시드 열은 0 하나입니다. Step 2-A의 "시드 변동으로 담당이 필요해지는지"는 측정할 수 없으므로 곧바로 Step 2-B를 실행합니다.

- [ ] **Step 1: 측정(모든 갈래 공통)**

시도 0~5(시드 0 포함 여섯 시드)마다 다음을 스윕합니다. 한 번에 하나의 Godot 프로세스만.

`split_duties`: `--keep duties,priorities,placement` (담당 유지)와 `--keep priorities,placement` (담당 없음) 두 조건에서 `--items prepped_vegetable:7,prepped_grain:6,prepped_mushroom:6,thawed_protein:3,marinated_protein:2 --best`. 표에 조건·시도별 `passed`, `best`(제공·손익)를 적습니다.

`final_service`: `--keep priorities,placement` (구이 우선순위 2 유지)와 `--keep placement` (우선순위 없음) 두 조건에서 `--items marinated_protein:6,prepped_vegetable:6,prepped_grain:4,prepped_mushroom:3,soup_base:2,thawed_protein:3 --best`. `--keep`에 `purchases`가 없으므로 발주는 작성값입니다. 추첨 인지 발주(시드별 필요량)로도 같은 스윕을 돌리려면 그 시드의 `draw_aware_policy`가 만드는 `set_purchase` 값을 `--items`와 별도로 고정해야 하는데, 이 도구는 발주를 인자로 받지 않으므로 이 Task에서는 작성 발주 기준으로만 측정하고 그 사실을 표 위에 적습니다.

- [ ] **Step 2-A: `split_duties` — 목표값으로 가를 수 있는지**

담당 없는 조건의 여섯 시드 `best`가 모두 담당 유지 조건의 `best` 이상이면 목표값은 담당 유무를 가르지 못합니다(시드 0은 이미 그렇습니다: 둘 다 26·12,350). 이 경우 목표를 바꾸지 않고 표와 결론만 기록하고, 승인 답이 "상한 스윕 허용"이면 Step 2-B로, 아니면 Task 6로 갑니다.
담당 없는 조건이 어느 시드에서든 목표에 미달하고 담당 유지 조건은 여섯 시드 모두 통과하면, 지렛대는 시드 변동으로 이미 필요해진 것이므로 목표를 바꾸지 않고 그 시드와 수치를 기록합니다.

- [ ] **Step 2-B: `split_duties` — 준비 노동량 상한 스윕(승인된 경우에만)**

`prep_labor_capacity`를 15에서 1씩 내리며(`.tres`를 바꾸고 저장) Step 1의 두 조건을 다시 스윕해, 담당 유지 조건이 여섯 시드 모두 통과하고 담당 없는 조건이 한 시드 이상 미달하는 가장 큰 상한을 찾습니다. 찾으면 그 값으로 `.tres`를 확정하고 기준·대체 정책의 프렙 합이 새 상한을 넘으면 `m3_policies.gd`의 그 정책만 조정합니다(2026-09-21 절의 방식). 상한 9 아래까지 내려도 가르지 못하면 15로 되돌리고 보고합니다.

- [ ] **Step 2-C: `final_service` — 목표 상향 또는 여유 측정(승인 답에 따라)**

"상향" 답: 시도 0~5에서 추첨 인지 정책(Task 1의 `run_policy` + `draw_aware_policy`)의 손익 최솟값을 구해, `minimum_profit`을 그 값 이하이면서 50 단위로 내림한 값으로 올립니다(현재 10,000, 시드 0 기준 10,300이므로 최대 10,300). `minimum_served`는 올리지 않습니다(기준 25 = 목표). 올린 뒤 `check.sh m3`의 "여분 손익 ≤ 2,000"과 대체 정책 통과, 시드 게이트를 확인합니다.
"여유 측정" 답: 목표를 그대로 두고 Step 1의 표에 "우선순위 유지 조건에서 통과 조합 0인 시드"와 "우선순위 없는 조건의 통과 조합 수"를 적어, 어떤 콘텐츠 값(상한 18 → 21, 또는 연어 발주 8 → 9)이 구이 우선순위 지렛대를 되살리는지 스윕으로 봅니다. 값은 바꾸지 않고 표만 남깁니다(별도 승인 대상).

- [ ] **Step 3: 통과 확인과 기록**

목표나 상한을 바꿨다면 `bash scripts/check.sh m3` → PASS, `bash scripts/check.sh mise` → PASS(시드 게이트). 새 절에 측정 표, 적용한 갈래, 바뀐 값과 이전 값, 스윕 인자를 적습니다.

- [ ] **Step 4: Commit**

```bash
git add content/campaign/scenarios tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): set pressure-service targets from the lever measurement"
```

값을 바꾸지 않았으면 메시지는 `docs(notes): record the lever measurement for split_duties and final_service`입니다.

---

### Task 6: 명세·지침·기록 정정과 전체 회귀

**Files:**

- Modify: `docs/specs/mise-forecast-reviews.md` (§4.1 마지막 항목 뒤, §10 표의 "풀림 검사" 행)
- Modify: `docs/notes/kitchen-pressure-verification.md` (`## 저장 호환성` 절 한 문장)
- Modify: `docs/plans/PLAN.md` (§12 위험 표의 행에 "시드 1~5 게이트 구현됨" 정정 한 줄이 필요한지 읽고 결정)
- Modify: `docs/plans/forecast-content-implementation.md` (이 문서: 정정 절과 회귀 결과)

- [ ] **Step 1: 명세 정정**

**Task 4 취소에 따른 조정(2026-09-21):** 아래 단락은 작성된 slack이 아니라 그 발견을 기록합니다. §8의 콘텐츠 버전 7 항목과 `docs/specs/m4-mobile.md`의 버전 7 두 줄은 쓰지 않습니다(버전은 6 그대로).

§4.1의 "첫 두 영업의 slack은 0으로 둡니다(제안)" 항목 뒤에 단락을 추가합니다.

```markdown
**2026-09-21 정정:** 계획 3(`../plans/forecast-content-implementation.md`)은 시도 1~5의 풀림 게이트(`tests/test_seed_gate.gd`)와 자리바꿈 생성기(§4.2 정정)를 넣었지만 `forecast_slack`은 작성하지 않았습니다.
메뉴별 `max(1, 기준 건수 / 5)`의 폭에서 여섯 압력 영업의 시도 30행 가운데 24행이 실패했고, `hot_queue` 시도 2는 프렙 조합 104가지 전부에서 최고 9건(목표 12)이라 어떤 정책으로도 풀리지 않았습니다.
원인은 `check.sh m3`의 "기준 정책 여분 ≤ 제공 1건·손익 2,000" 규칙이 압력 영업을 목표에 정확히 맞춰 놓아 ±1건의 구성 변화도 흡수하지 못하는 조율이며, §12의 "폭을 줄인다"는 완화는 0에서만 통과합니다.
변동을 살리려면 압력 영업의 재조율(그 규칙의 완화, 노동량·예산 여유, 시드별 기준 정책)이 먼저 필요하고, 그것은 [플레이테스트 명세](playtest-price-validation.md)와 함께 정하는 별도 명세입니다.
게이트의 "실제 추첨을 아는 기준 정책"은 시드 0 기준 정책에 원재료별 `max(작성 발주, 추첨된 구성의 필요량)`을 발주로 맞춘 것이며, 모든 slack이 비어 있는 동안은 시드 0 결과와 같은 값으로 통과합니다.
```

§10 표의 "새 `check.sh mise` 풀림 검사" 행 앞의 문장("아래 검사는 아직 구현되지 않았으므로 …")이 이제 이 행과 생성기 검사 행에는 맞지 않으므로, 그 문장을 "아래 검사 가운데 회계·리뷰 검사는 아직 구현되지 않았습니다"로 좁힙니다(생성기·풀림 검사는 구현됨을 표 아래 한 줄로 적습니다).

`docs/plans/PLAN.md` §12 위험 표의 "예보 폭이 넓어 풀리지 않는 시드" 행 뒤(또는 표 아래)에 한 줄을 더합니다: 2026-09-21 측정에서 현재 조율은 어떤 0이 아닌 폭도 풀리지 않았으며 재조율 명세가 선행한다는 문장(수치는 명세 §4.1 정정 단락이 소유하므로 다시 적지 않음).

`docs/notes/kitchen-pressure-verification.md`의 `## 저장 호환성` 절이 콘텐츠 버전 4를 현재 버전처럼 말하면, 현재 버전은 `persistence/campaign_store.gd`의 `VERSIONS`가, 이력은 `docs/specs/m4-mobile.md`가 소유한다는 한 문장으로 바꿉니다(숫자를 적지 않음).

- [ ] **Step 2: 전체 회귀**

Run(순서대로): `bash scripts/check-export.sh`, `python3 tests/test_export_check.py`, `python3 tests/test_ios_export.py`, `bash scripts/check.sh m0`, `m1`, `m2`, `m3`, `m4-core`, `m4`, `m5`, `mise`, `ui-regressions` → 모두 PASS. 이 문서 끝에 "## 2026-09-21 정정"(갈린 지점: Task 2 브리프의 `--keep` 문구 오류, `shared_stock` 수프 기준 9, Task 4 첫 실행의 BLOCKED와 취소, Task 3 삽입, Task 5의 갈래와 결과)과 "### Task 6 회귀 결과"(`log` 블록)를 추가합니다. `test_m4_restart.py`는 같은 PCK로 한 번 실행합니다(콘텐츠 버전이 바뀌지 않았으므로 두 PCK 검사는 없음).

- [ ] **Step 3: Commit**

```bash
git add docs/specs/mise-forecast-reviews.md docs/plans/PLAN.md docs/notes/kitchen-pressure-verification.md docs/plans/forecast-content-implementation.md
git commit -m "docs: record the authored forecast slack, the seed gate and content version 7"
```

---

### Task 7 (조건부): 브리핑의 메뉴별 손님 인내 시간

승인 답이 "포함"일 때만 실행합니다. `presentation/campaign_screen.gd:487-496`의 메뉴 줄에 인내 시간을 붙입니다: `menu_lines.append(tr("%s %d–%d건 · 인내 %d초") % [menu_name, min, max, recipe.patience_ticks / 10])`(고정 건수 분기도 같은 꼴, tick 10 = 1초는 브리핑의 "영업 300초" = `closing_tick` 3000과 같은 환산). 기존 msgid `"%s %d건"`·`"%s %d–%d건"`은 사라지므로 `translations/en.po`에서 새 msgid로 바꾸고, `tests/test_ui_regressions.gd`의 브리핑 검사가 "건"을 찾는 방식이면 그대로 통과하는지 확인합니다. 커밋: `feat(ui): show each menu's patience in the briefing`.

---

## 완료 조건

(2026-09-21 Task 4 취소 반영)

- `tests/test_seed_gate.gd`가 실제 캠페인 8종의 시도 1~5를 통과하고(모든 slack이 비어 있어 시드 0과 같은 값), 두 합성 fixture에서는 실패를 보고합니다.
- 생성기는 자리바꿈만 하며(`tests/test_schedule_generator.gd`의 변경 슬롯 수·연속 길이 검사), 명세 §4.2에 정정이 있습니다.
- 모든 캠페인 `.tres`의 `forecast_slack`은 비어 있고, 그 이유(현재 조율에서는 0이 아닌 폭이 풀리지 않음)와 수치가 명세 §4.1 정정 단락과 이 문서의 정정 절에 있으며 콘텐츠 버전은 6 그대로입니다.
- `tests/sweep_policies.gd`가 커밋돼 있고 2026-09-21 절의 `split_duties` 수치를 재현합니다.
- `split_duties`·`final_service`의 지렛대 측정 표가 있고, 승인된 갈래대로 `split_duties`의 상한이 정해졌거나 "바꾸지 않음"의 근거가, `final_service`는 여유 측정 표가 적혀 있습니다.
- 모든 suite, `check-export.sh`, `test_m4_restart.py`(같은 PCK)가 PASS입니다.

## 다음 계획

- §12 3단계 리뷰(확정된 이름으로 문구 리소스, 생성기, 콘텐츠 검사).
- §12 4단계 화면(메뉴 상세·리뷰 패널·메뉴 아이콘·혼합 주문 직원 문구).
- 5인 플레이테스트(`docs/specs/playtest-price-validation.md`)는 운영자의 시작 문장을 기다립니다.

## 2026-09-21 정정

아래 항목은 Task 1~5 실행 중 이 계획의 서술과 실제로 머지된 코드가 갈린 지점입니다.
이 절 위의 단계 서술은 고치지 않으며, 권위는 인용한 커밋의 코드와 테스트에 있습니다.

- Task 1(커밋 `407168f`)은 계획대로였고, 예외로 `tests/test_service_seed.gd`가 `campaign.duplicate(true)`로 공유 `hot_queue` 시나리오를 변형했습니다(Array 원소는 깊이 복사되지 않음).
  그래서 이 검사는 캠페인을 `CACHE_MODE_IGNORE_DEEP`로 읽으며, 그 결함 자체는 별도로 `f6d7f25`에서 고쳤습니다.
  이 Task 뒤 `mise` checks는 309였습니다.
- Task 2(커밋 `4a19fcf`·`f093155`)에서 브리프 Step 2 산문은 `--keep duties`를 생략하면 담당 없는 실행이 된다고 적었지만, 도구의 기본 `--keep`은 담당을 포함하므로 담당 없는 실행은 `duties`를 뺀 `--keep`을 명시해야 합니다.
  리뷰에서 입력 검증(`--items`, `--scenario`)을 추가하고 문서화된 `--keep` 값에서 쓰이지 않는 `prep`을 지웠습니다.
- Task 3(커밋 `99356d5`)은 첫 slack 시도가 막힌 뒤(계획 정정 `f565702`) 삽입됐습니다.
  섞기 없이 슬롯만 바꾸며, `hot_queue` fixture에서 시드 104076537은 슬롯 2개를 바꾸고 수프의 연속 길이를 2로 올립니다.
  `tests/test_schedule_generator.gd`는 취소된 Task 4가 준비해 둔 zero-slack `fixed` 사본 재작성도 함께 받았습니다.
  최종 리뷰(2026-09-21)에서 연속 길이 `+ 1` 경계는 불변식이 아니라 그 시드의 우연으로 드러났습니다(같은 fixture에서 시드 90은 구이 연속 5).
  검사는 시드 104076537의 연속 길이(수프 2, 구이 1, 샐러드 1)를 고정값으로 확인하도록 바꿨고, 생성기 머리 주석과 명세 §4.2 정정의 "파동 구조가 유지됩니다"는 "바뀐 슬롯 수가 slack 합을 넘지 않습니다(같은 메뉴가 더 길게 이어질 수는 있습니다)"로 고쳤습니다.
  Step 5가 인용한 명세 문장 "건수가 기준과 같은 시드는 없고"도 틀렸습니다: 이동이 서로 상쇄되면(한 슬롯이 기증→수신, 다른 슬롯이 수신→기증) 건수는 기준과 같고 배열만 다르며, 같은 fixture에서 시드 1–500 가운데 68개가 그렇습니다(시드 10이 한 예).
  명세 §4.2 정정은 그 문장을 세 문장(이동이 가능하면 최소 한 번 이동, 상쇄로 건수가 같아도 배열은 바뀐 슬롯만큼 다름, 이동 불가이거나 같은 슬롯에서 상쇄돼 배열까지 같으면 `break_identity`가 첫 인접 이종 쌍을 맞바꿈)으로 바꿨고, `break_identity`의 주석도 같은 슬롯 상쇄가 이 분기에 닿는다고 적었습니다.
  Step 5의 인용 블록과 Task 6 Step 1이 인용한 §4.1 정정 블록은 기록이므로 고치지 않았고, 권위는 명세의 현재 문장에 있습니다.
- Task 4(취소, 커밋 `a152e5c`)의 첫 실행(전체 섞기 포함)은 30행 중 29행이 실패해 BLOCKED로 끝났고, 자리바꿈으로 바꾼 뒤에도 시작 slack에서 24/30이었습니다(`hot_queue` 1/5, `shared_stock` 1/5, `long_route` 2/5, `split_duties` 1/5, `rush_hour` 1/5, `final_service` 0/5).
  컨트롤러 탐침: `hot_queue` 시드 0은 정확히 12건·4,750원(만료 8건)으로 통과하고, 시도 2(교체 3슬롯, 화구 연속 3)는 우선순위 유무와 무관하게(작성 발주·배치 기준) 프렙 조합 104가지 중 통과 0입니다.
  원인은 `check.sh m3`의 "기준 정책 여분 ≤ 제공 1건·손익 2,000" 규칙이 모든 압력 영업을 여분 1건 이내로 맞춰 놓은 조율입니다(정확히 맞는 것으로 측정된 영업은 `hot_queue`뿐).
  자리바꿈 생성기에서 측정된 것은 이 두 가지뿐이며, Step 4의 폭 축소 규칙은 전체 섞기에서만 실행해 메뉴 하나짜리 폭까지 실패했고 자리바꿈에서는 실행하지 않았으므로, "0이 아닌 어떤 폭도 풀리지 않는다"는 측정된 사실이 아닙니다(최종 리뷰 2026-09-21 정정; Task 4 취소 사유, 명세 §4.1 정정, `PLAN.md` §12는 고쳤고 Task 6 Step 1의 인용 블록과 `PLAN.md` 편집 지시 문장은 기록으로 둡니다).
  운영자 결정은 멈추고 발견을 기록하는 것이었습니다: `forecast_slack`은 비운 채 두고 콘텐츠 버전은 6 그대로이며, 재조율 명세는 플레이테스트와 함께 별도로 정합니다.
  되돌린 WIP(시작 slack이 있는 `.tres` 6개, 콘텐츠 7 작업, 검사 리터럴 변경)는 세션 scratchpad에만 있었고 git에는 없습니다.
  브리프(별도 task-4-brief) 표는 `shared_stock` 수프 기준을 8로 적었으나 실제는 9이며, 위 Task 4 Step 4의 표는 이미 9로 고쳐 적혀 있습니다.
- Task 5(커밋 `3a8438a`)는 측정만 했습니다.
  `split_duties`: 시드 0에서 담당 없이 노동량 1짜리 미장 단위(해동 단백질 1, 손질 양송이 1, 손질 현미 1 가운데 아무거나) 하나만으로도 26건·12,350원에 닿아, 목표값으로는 어떤 `prep_labor_capacity` ≥ 1도 담당 유무를 가르지 못합니다(상한은 15로 유지, `m3_policies.gd` 불변).
  `final_service`: 상한 21이 화구 우선순위 2를 되살리는 통과 정책을 만들고(통과 22가지, 최고 27·12,200, 상한 19가 경계), 연어 발주 9는 되살리지 못합니다.
  브리프의 `split_duties` `--items`가 이 시나리오에 없는 `marinated_protein`을 적어 도구가 거부했으므로 실제 4개 항목으로 스윕을 돌렸고, 커밋된 `final_service` 기준 정책에는 우선순위가 없어 우선순위 유지 실행은 스윕 동안만 임시 fixture 편집으로 돌린 뒤 되돌렸습니다.
- Task 7(브리핑의 메뉴별 인내 시간)은 실행하지 않았습니다: 운영자가 승인 시점에 §12 4단계 화면 계획으로 미뤘습니다.
- 최종 전체-브랜치 리뷰로 미루는 항목(고치지 않음): `draw_aware_policy`가 `run_policy`도 다시 계산하는 `order_schedule()`을 한 번 더 계산합니다(계획이 정한 모양).
  `--keep purchases`는 현재 콘텐츠에서 아무 효과가 없습니다.
  숫자가 아니거나 음수인 `--items` 상한은 거부됩니다(`int(parts[1]) < 0` 검사가 이미 있었고, 이 항목이 처음에 "음수는 걸러지지 않는다"고 적은 것은 오독).
  `SWEEP_SUMMARY`는 `--best` 없이도 항상 `best_any`를 담습니다.
  최종 리뷰(2026-09-21)에서 `--attempt`(정수, 0 이상)와 `--keep`(`duties`·`priorities`·`placement`·`purchases`만, 값 없는 `--keep`은 오류) 검증을 더했습니다.
- forward-looking grep(`grep -rn '풀림 검사\|시드 1~5\|forecast_slack' docs/specs docs/plans/PLAN.md AGENTS.md README.md`)은 6줄을 남겼습니다.
  `PLAN.md:531`(위험표 행)은 이 Task의 §12 편집으로 다뤘습니다(표 아래에 한 줄 추가).
  `mise-forecast-reviews.md:54`(§4.1 필드 정의)는 스키마 자체를 서술하며 이미 존재하는 필드이므로 손대지 않았습니다.
  `mise-forecast-reviews.md:111`(§5.1)은 다른 검사인 "시드 0 풀림 검사"(m3 게이트 튜닝)를 가리키며 이 계획의 §10 "풀림 검사"와 다른 대상이므로 손대지 않았습니다.
  `mise-forecast-reviews.md:264`(§10 표의 풀림 검사 행)는 이번 §4.1 정정 문단의 마지막 문장이 이미 그 관계를 서술하므로 행 자체는 그대로 뒀습니다.
  `mise-forecast-reviews.md:238`(§8 콘텐츠 버전 5)은 forecast_slack이 버전 5에 추가된다고 여전히 적고 있어, Task 4 취소 뒤에도 이 서술은 정정되지 않은 채로 남습니다.
  이 Task의 지정 범위(§4.1·§10만)를 벗어나므로 고치지 않았고, 후속 문서 정정이 필요합니다.
  `mise-forecast-reviews.md:291`(§12 구현 순서 1단계의 `forecast_slack` 나열)도 완료된 약속처럼 읽히지만, 이 목록은 명세의 구현 순서 개요이고 이 계획은 그 가운데 시드 게이트·생성기만 마쳤으므로 같은 이유로 손대지 않았습니다.

### Task 6 회귀 결과 (2026-09-21)

`test_m4_restart.py`는 같은 PCK로 한 번만 실행했습니다(콘텐츠 버전이 바뀌지 않아 두 PCK 검사는 없습니다).

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
Ran 10 tests in 0.839s

OK

$ python3 tests/test_ios_export.py
Ran 2 tests in 0.095s

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
PASS: mise checks=314 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh ui-regressions
PASS: ui-regressions checks=302 failures=0

$ python3 tests/test_m4_restart.py
Ran 10 tests in 1.858s

OK
```
