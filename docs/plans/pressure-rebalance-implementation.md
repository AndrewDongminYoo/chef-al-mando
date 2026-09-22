# 압력 영업 재조율 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 여섯 압력 영업이 시드 0과 시도 1~5의 추첨을 모두 흡수하고 자기 지렛대를 실제로 요구하도록 재조율한 뒤, `forecast_slack`을 작성하고 콘텐츠 버전을 7로 올립니다.

**Architecture:** 게이트와 도구를 먼저 바꾸고(§4.1 여분 2건·3,000, §4.2 무계획 미달 폭, §4.3 지렛대 게이트, 스윕 도구의 `--purchases draw`·`--without`·`--gate`), 콘텐츠 버전 7의 저장 규칙을 올린 다음, 영업마다 "slack 작성 → 여유 → 목표 → 구성" 순서로 값을 정해 한 영업씩 커밋합니다. 모든 판정은 커밋된 `tests/fixtures/m3_policies.gd`의 정책과 `.tres`의 값이 권위이며, 스윕의 인자·조합 수·통과 수·최고는 `docs/notes/kitchen-pressure-verification.md`의 새 절이 기록합니다.

**Tech Stack:** Godot 4.7.2 headless(`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot`), GDScript 테스트 하니스(`scripts/check.sh <suite>`), `tests/sweep_policies.gd`, python3 `tests/test_m4_restart.py`.

**Spec:** `docs/specs/pressure-rebalance.md`(게이트 §4, 수단 §5, 도구 §6, 버전 §7, 검증 §8, 문서 §9, 순서 §10). 함께 읽는 문서: `docs/specs/mise-forecast-reviews.md` §4·§10, `docs/plans/forecast-content-implementation.md`의 Task 4 취소 사유와 2026-09-21 정정 절(재현 절차·측정 수치), `docs/notes/kitchen-pressure-verification.md`의 2026-09-21 두 절(스윕 도구 사용법·지렛대 측정).

## Global Constraints

- 명세 §5의 불변: 설비 수·직원 수·격자, 레시피(재료·공정·시간·매출·인내), 미장 항목, 저장 스키마 4, `sim_version` 1, 시드 0 항등, 자리바꿈 생성기, 결정론 계약을 바꾸지 않습니다. `minimum_served`·`minimum_profit`은 올리기만 합니다.
- 명세 §5의 구성 제약: 파동 묶음(같은 tick 도착 2건 이상)과 150 tick 이상의 회복 구간(`tests/test_m3_content.gd`의 `RECOVERY_GAP_TICKS`), 메뉴 8종·재료 정의 12종 이내, 캠페인 배치 3종을 유지합니다.
- 명세 §4.4: `first_shift`·`lunch_prep`은 slack 0, `hot_queue`부터 메뉴별 `max(1, 기준 건수 / 5)`에서 시작하고, 어떤 영업의 slack도 전부 0으로 줄이지 않으며, 이동이 하나도 불가능한 slack은 작성하지 않습니다.
- `.tres` 표기: `forecast_slack = Dictionary[String, int]({"grill": 2, "soup": 1, "salad": 1})` 꼴(`hot_queue.tres`의 `purchases` 줄과 같은 typed 표기). Godot 4.7.2에서 `resource.set("typed_dict_export", {untyped})`는 `{}`를 남기므로 테스트 fixture에서는 `var slack: Dictionary[String, int] = {...}`를 대입합니다.
- Godot 프로세스는 한 번에 하나만 띄우고(`check.sh`, 스윕, `test_m4_restart.py` 모두 포함), 스윕 묶음 전에 `uptime`으로 부하를 읽습니다(코어 수를 크게 넘으면 기다립니다).
- 워크트리 Bash 가드: 한 호출에 평범한 명령 하나, 리터럴 절대 경로, git 뒤에 파이프·리다이렉션 없음, "git"이라는 낱말을 담은 heredoc 없음. 파일 내용은 Write/Edit로 쓰고, 커밋 메시지는 scratchpad 파일에 써서 `git commit -F <절대 경로>`로 커밋합니다.
- 커밋 메시지·PR 본문·코멘트에 Co-Author 줄, `Claude-Session` 트레일러, claude.ai 세션 URL을 넣지 않습니다. `git add <경로>`로 명시 스테이징하고 `git add -A`·`git stash`는 쓰지 않습니다.
- 주석과 문서는 한국어, 식별자와 커밋 메시지는 영어. 문서는 한 문장 한 줄, 코드 블록에 언어 id, 한 사실은 한 곳에만 적고 다른 곳은 인용합니다.
- 계획 3의 재현 절차와 수치는 `docs/plans/forecast-content-implementation.md` Task 4 취소 사유가 소유하며 이 계획은 다시 적지 않습니다.

---

## 계획 작성 시점의 측정 (2026-09-21)

명세 §8은 "지렛대 게이트는 현재 콘텐츠의 `split_duties`에서 먼저 실패해야 합니다"라고 적었지만, 명세 §4.3 원문 정의(기준 정책에서 지렛대 명령만 뺀 정책)를 시드 0에서 실행한 결과는 다릅니다.
워크트리에 `.godot` 캐시가 없어 `--import`를 먼저 돌린 뒤, scratchpad의 탐침 스크립트(`Policies.reference_policy`에서 아래 종류를 뺀 정책을 `Policies.run_policy`로 실행)로 쟀습니다.

| 영업           | 뺀 종류                         | 기준 정책   | 무지렛대 정책         | 목표 통과 | 기준과 동일 |
| -------------- | ------------------------------- | ----------- | --------------------- | --------- | ----------- |
| `hot_queue`    | `priorities`                    | 12 · 4,750  | 9 · -950              | 아니오    | 아니오      |
| `shared_stock` | `set_purchase`                  | 18 · 4,700  | 18 · 4,700            | **예**    | **예**      |
| `long_route`   | `move_station`·`rotate_station` | 22 · 13,700 | 15 · 4,500            | 아니오    | 아니오      |
| `split_duties` | `set_duty`                      | 26 · 12,350 | 21 · 5,550            | 아니오    | 아니오      |
| `rush_hour`    | `set_prep`·`priorities`         | 24 · 9,200  | 21 · 4,650 (= 무계획) | 아니오    | 아니오      |

따라서 원문 정의의 게이트는 오늘 `shared_stock`에서 실패하고(기준 정책에 `set_purchase`가 없어 뺄 것이 없음), `split_duties`는 통과합니다.
`split_duties`의 실제 구멍은 기준 정책이 아니라 **다른** 담당 없는 정책(`thawed_protein 1`만, 26 · 12,350)이 통과한다는 것이며, 원문 정의는 이를 잡지 못합니다.
`rush_hour`의 무지렛대 정책은 빈 정책이라 기존 무계획 검사와 같은 값을 재는 데 그칩니다.

이 계획은 §4.3을 다음 두 층으로 구현합니다(운영자 승인 대상, 승인 질문 3번).

1. **기준 의존성**: 기준 정책에서 지렛대 종류를 뺀 정책은 기준과 달라야 하고 한 목표 이상에 미달합니다(§4.3 원문). 지렛대가 둘인 `rush_hour`는 하나씩 뺀 정책과 둘 다 뺀 정책 세 개를 모두 검사합니다.
2. **최강 무지렛대 정책**: `tests/sweep_policies.gd --without <지렛대>`가 시드 0에서 찾은 가장 강한(제공, 손익 사전순) 무지렛대 정책을 `m3_policies.gd`의 `lever_free_policy(scenario_id)`에 고정하고, 게이트는 그 정책이 한 목표 이상에 미달해야 통과합니다. 재실행 비용은 정책 하나의 시뮬레이션이며, 스윕 자체는 게이트에 들어가지 않습니다(시드 104076537의 연속 길이를 고정값으로 검사한 선례와 같은 방식).

운영자가 원문만 고르면 Task 4의 `lever_free_policy`와 그 검사, 각 영업 Task의 "무지렛대 스윕 통과 0" 조건을 뺀 채 나머지를 그대로 실행합니다.

---

## 파일 구조

| 파일                                                                                                         | 책임                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/fixtures/seed_gate.gd` (신설, `.uid` 포함)                                                            | §4.2 판정 `evaluate`와 무계획 미달 폭 `no_plan_misses`; 테스트와 스윕 도구가 같은 판정을 씀(Task 1)                                   |
| `tests/fixtures/m3_policies.gd`                                                                              | 기준·대체 정책, `draw_aware_policy`(기준 발주 명령 반영), `LEVER_KINDS`, `without_kinds`, `without_lever_policy`, `lever_free_policy` |
| `tests/sweep_policies.gd`                                                                                    | `--purchases`(`authored`·`draw`), `--without <종류,…>`, `--gate`(Task 1)                                                              |
| `tests/test_seed_gate.gd`                                                                                    | 내부 클래스를 fixture로 옮기고 §4.2 미달 폭과 세 번째 합성 fixture(Task 1)                                                            |
| `tests/test_m3_playthrough.gd`                                                                               | §4.1 여분 규칙 2건·3,000(Task 1), §4.3 지렛대 게이트와 `_compare_choices` 발주 변형(Task 4)                                           |
| `tests/test_service_seed.gd`                                                                                 | slack 작성 규칙 검사(Task 3), 모든 압력 영업 non-empty(Task 10)                                                                       |
| `persistence/campaign_store.gd`, `tests/test_m4_store.gd`, `tests/test_menu_priorities.gd`                   | 콘텐츠 버전 7과 버전 6 이하 재시작(Task 3)                                                                                            |
| `content/campaign/scenarios/{hot_queue,shared_stock,long_route,split_duties,rush_hour,final_service}.tres`   | slack, 여유, 목표, 구성(Task 5~9)                                                                                                     |
| `docs/notes/kitchen-pressure-verification.md`                                                                | 탐침·재조율 절(Task 2, 5~9), 2026-09-11 규칙 문장의 대체 표시(Task 11)                                                                |
| `docs/specs/pressure-rebalance.md`, `docs/specs/mise-forecast-reviews.md`, `docs/plans/PLAN.md`, `AGENTS.md` | §9의 변경과 이 계획이 발견한 사실의 정정(Task 11)                                                                                     |
| `docs/plans/pressure-rebalance-implementation.md`                                                            | 이 문서: 실행 중 갈린 지점의 정정 절과 회귀 결과(Task 11)                                                                             |

## 공통 절차: 영업 하나의 재조율

Task 5~9는 영업마다 아래 절차를 따릅니다.
각 Task는 이 절차에서 자기 영업의 첫 수단, 중단 조건, 정책 조정 범위만 다르게 적습니다.
`<worktree>`는 `/Users/dongminyu/Development/01_personal/chef-al-mando/.claude/worktrees/feat-pressure-rebalance`, `<scratchpad>`는 세션 scratchpad 디렉터리, `$GODOT_BIN`은 `/Applications/Godot.app/Contents/MacOS/Godot`입니다.

1. `uptime`을 읽고 다른 Godot 프로세스가 없는지 `pgrep -fl Godot`으로 확인합니다.
2. 그 영업의 `.tres`에 시작 slack을 씁니다(아래 표).
   그 뒤 `validate()`의 손익 상한(`maximum_profit(order_count)`)은 slack이 넓힌 예보 상한 기준입니다.
3. 게이트 상태를 읽습니다: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario <id> --gate`.
   `SEED_GATE_ROW` 여섯 줄(시도 0~5)과 `SEED_GATE_VERDICT`를 그대로 note 절에 옮깁니다.
4. 실패한 시도마다 통과 조합이 있는지 봅니다: `... --scenario <id> --attempt N --purchases draw --best`(기준 정책의 담당·배치·우선순위를 유지한 채 프렙 수량 전수).
   `--items`는 그 영업의 2026-09-21 절에 적힌 값을 씁니다.
   - 통과 조합이 있으면 시도 0~5 모두에서 통과하는 프렙 수량 조합을 찾습니다: 시도별 `SWEEP` 줄의 `quantities`를 모아 교집합을 만들고, 그 가운데 여섯 시도의 손익 최솟값이 가장 큰 조합을 기준 정책의 프렙으로 둡니다.
     교집합이 비면 여유로 갑니다.
   - 통과 조합이 없으면 여유를 줍니다.
5. 여유는 명세 §5의 순서로 한 번에 한 값씩 올리고, 값을 바꿀 때마다 4를 다시 돌립니다.
   `prep_labor_capacity`는 1씩 최대 3(각 Task가 상한을 적음), `starting_budget`은 500씩 최대 1,500, 작성 `purchases`는 추첨 인지 정책이 `insufficient_budget`으로 거부된 원재료만 그 시도의 필요량까지.
6. 기준 정책이 시도 0~5를 모두 통과하면 무계획 미달 폭을 봅니다(3의 `SEED_GATE_ROW`의 `no_plan_*` 열).
   어떤 시도에서든 제공 2건 미만이고 손익 1,500 미만으로만 미달하면 `minimum_served` 또는 `minimum_profit`을 그 폭이 생기는 값까지 올립니다(내리지 않음, 50 단위).
   올린 뒤 4로 돌아가 기준 정책이 여전히 통과하는지 봅니다.
7. 시드 0의 §4.1 여분을 봅니다: 기준 정책의 제공이 `minimum_served + 2` 이하이고 손익이 `minimum_profit + 3000` 이하여야 합니다.
   넘으면 목표를 그 범위에 들어오는 값까지 올리고(50 단위) 4로 돌아갑니다.
   5–7이 한 바퀴 돌아도 수렴하지 않으면(여유 상한을 다 쓴 뒤에도 시도 1–5 통과와 §4.1 여분을 동시에 만족하는 값이 없으면) §4.4대로 그 영업의 가장 큰 slack 값을 1 줄이고(같으면 `menu_ids` 앞쪽) 2부터 다시 합니다.
   slack을 줄이면 `maximum_profit(order_count)`가 작아지므로, 줄인 뒤 먼저 `minimum_profit <= maximum_profit(order_count)`를 확인하고 넘으면 목표를 그 값 아래로 되돌린 뒤 다시 잽니다(넘긴 채 두면 `scenario_def.gd`의 `validate()`가 손익 목표 오류를 내고 `test_m3_content.gd`가 원인과 먼 문장으로 실패합니다).
   slack이 전부 0이 되어야만 풀리면 멈추고 보고합니다(그 영업은 §5의 구성 재설계 대상).
8. 지렛대를 확인합니다(Task 4가 게이트를 넣은 뒤이며 `final_service`는 제외).
   `... --scenario <id> --attempt 0 --without <지렛대 종류> --best`를 돌려 ~~`passed`가 0이어야 하고~~(계획의 결함, 아래 2026-09-22 정정 절의 Task 9 항목), `best_any`의 수량으로 `m3_policies.gd`의 `lever_free_policy(<id>)`를 갱신합니다(`--without`이 뺀 종류 밖의 기준 명령은 그대로 두고 프렙만 `best_any`로).
   `passed`가 0이 아니면 그 영업의 Task가 적은 지렛대 회복 수단을 씁니다.
9. 대체 정책 둘을 맞춥니다: 시드 0에서 두 목표를 통과하고 기준·대체 세 해시가 쌍별로 다르며 1배·4배 해시가 같아야 합니다.
   미달하는 대체 정책만 프렙 수량을 바꿉니다(2026-09-21 정정 절의 방식).
10. `GODOT_BIN=$GODOT_BIN bash scripts/check.sh m3` → PASS, `GODOT_BIN=$GODOT_BIN bash scripts/check.sh mise` → PASS.
    `test_m3_ui.gd`의 검사 수는 기준 정책 명령 수에 따라 달라지므로 그 수치는 기록만 합니다.
11. `docs/notes/kitchen-pressure-verification.md`에 "### 2026-09-XX 재조율: `<id>`" 절을 더합니다.
    내용: 시작 slack, 단계별 표(수단·값·스윕 인자·조합·통과·최고), 확정값(이전 → 이후; 권위는 `.tres`), 최종 `SEED_GATE_ROW` 표, 지렛대 스윕 결과, 정책 변경(이전 → 이후).
12. 커밋합니다: `content/campaign/scenarios/<id>.tres`, `tests/fixtures/m3_policies.gd`, 바뀐 테스트, note.

시작 slack(계획 3 Task 4 Step 4의 표, 기준 건수는 `order_recipe_ids`에서 셈):

| 영업            | 기준 건수(메뉴 순서)                                                                                      | 시작 slack               |
| --------------- | --------------------------------------------------------------------------------------------------------- | ------------------------ |
| `hot_queue`     | grill 10, soup 5, salad 5                                                                                 | grill 2, soup 1, salad 1 |
| `shared_stock`  | salad 5, soup 9, grain_salad 4, mushroom_salad 4                                                          | 1, 1, 1, 1               |
| `long_route`    | grill 6, mushroom_soup 6, protein_bowl 6, grain_salad 6                                                   | 1, 1, 1, 1               |
| `split_duties`  | salad 7, mushroom_salad 7, grain_grill 6, protein_bowl 6 (Task 6가 구성을 바꾸면 새 기준 건수로 다시 셈)  | 1, 1, 1, 1               |
| `rush_hour`     | salad 4, soup 4, grill 4, grain_salad 4, mushroom_salad 4, mushroom_soup 4, grain_grill 3, protein_bowl 3 | 1 × 8                    |
| `final_service` | 8종 각 4                                                                                                  | 1 × 8                    |

---

### Task 1: 게이트 규칙과 스윕 도구 옵션

**Files:**

- Create: `tests/fixtures/seed_gate.gd` (+ Godot가 만드는 `tests/fixtures/seed_gate.gd.uid`)
- Modify: `tests/fixtures/m3_policies.gd` (`draw_aware_policy`, `without_kinds`)
- Modify: `tests/test_seed_gate.gd` (내부 클래스 제거, 미달 폭, 세 번째 합성 fixture, 추첨 인지 정책 검사)
- Modify: `tests/test_m3_playthrough.gd:73-80` (§4.1 여분 규칙, 미달 폭 헬퍼)
- Modify: `tests/sweep_policies.gd` (`--purchases`, `--without`, `--gate`)
- Modify: `docs/notes/kitchen-pressure-verification.md` (스윕 도구 사용법 단락에 세 옵션)

**Interfaces:**

- Produces: `SeedGate.evaluate(campaign: Resource, scenario: Resource, attempts: Array[int]) -> Dictionary{passed, failures, rows}`와 `SeedGate.no_plan_misses(scenario: Resource, run: Dictionary) -> bool`(`res://tests/fixtures/seed_gate.gd`). `Policies.without_kinds(policy: Dictionary, kinds: Array) -> Dictionary`. 스윕 도구의 `--purchases authored|draw`, `--without set_purchase,set_duty,move_station,rotate_station,priorities`, `--gate`(시도 0~5의 `SEED_GATE_ROW`·`SEED_GATE_VERDICT` 출력).
- Consumes: 기존 `Policies.reference_policy`, `run_policy`, `passes_targets`, `ScheduleGenerator.service_seed_for`.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_seed_gate.gd`의 `_test_synthetic_failures` 끝에 세 번째 fixture를 더합니다(무계획이 제공 1건 차이로만 미달하는 목표는 §4.2 강화 규칙에서 실패해야 합니다).

```gdscript
	var narrow: Resource = hot_queue.duplicate()
	var no_plan: Dictionary = Policies.run_policy(hot_queue)
	narrow.minimum_served = no_plan.snapshot.accounting.served + 1
	narrow.minimum_profit = no_plan.snapshot.accounting.profit
	expect(narrow.validate().is_empty(), "the narrow fixture is still valid content")
	var seed_zero: Array[int] = [0]
	verdict = SeedGate.evaluate(campaign, narrow, seed_zero)
	expect(not verdict.passed and verdict.failures.size() == 1
		and verdict.failures[0].begins_with("attempt 0:") and verdict.failures[0].contains("no plan misses by less than"),
		"targets the no-plan service misses by one order fail the widened gate")
```

같은 함수의 둘째 fixture(`trivial`) 기대 문구 `"no plan passes"`를 `"no plan misses by less than"`으로 바꿉니다.

`_test_draw_aware_policy`의 첫 루프를 기준 정책의 `set_purchase` 명령을 반영한 형태로 바꿉니다(지금은 어떤 기준 정책에도 발주 명령이 없어 값이 같고, Task 4가 `shared_stock`에 발주 명령을 넣으면 이 형태여야 통과합니다).

```gdscript
	for scenario: Resource in campaign.scenarios:
		var policy: Dictionary = Policies.draw_aware_policy(scenario, 0)
		var purchases: Dictionary = {}
		for command: Dictionary in policy.preparation:
			if command.kind == "set_purchase":
				purchases[command.target_id] = command.value
		var reference: Dictionary = Policies.reference_policy(scenario.id)
		var expected: Dictionary = scenario.purchases.duplicate()
		for command: Dictionary in reference.preparation:
			if command.kind == "set_purchase":
				expected[command.target_id] = command.value
		expect(purchases == expected, "seed 0 draw-aware purchases equal the authored purchases overlaid by the reference purchase commands: " + scenario.id)
		var behind: Dictionary = Policies.without_kinds(reference, ["set_purchase"])
		expect(policy.preparation.slice(purchases.size()) == behind.preparation and policy.priorities == reference.priorities,
			"the draw-aware policy is the reference policy behind its purchases: " + scenario.id)
```

`tests/test_m3_playthrough.gd`의 무계획 블록(73~80행)에서 §4.1 여분을 바꾸고 미달 폭을 헬퍼로 잽니다.

```gdscript
				expect(SeedGate.no_plan_misses(scenario, no_plan),
					"a no-plan service misses by at least two orders or 1500 profit: " + scenario.id)
				expect(view.accounting.served - scenario.minimum_served <= 2
					and view.accounting.profit - scenario.minimum_profit <= 3000,
					"the reference policy passes with at most two extra orders and 3000 extra profit: " + scenario.id)
```

`served_gap`·`profit_gap` 두 줄은 지웁니다.
파일 상단에 `const SeedGate := preload("res://tests/fixtures/seed_gate.gd")`를 더합니다.

- [ ] **Step 2: 실패 확인**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise`
Expected: FAIL — `res://tests/fixtures/seed_gate.gd`가 없어 `test_m3`·`test_seed_gate`의 preload가 파싱 오류를 냅니다(`SCRIPT ERROR`).

- [ ] **Step 3: `tests/fixtures/seed_gate.gd` 작성**

`tests/test_seed_gate.gd`의 `class SeedGate` 본문을 옮기고 미달 폭을 넣습니다.

```gdscript
extends RefCounted

## §4.2 시도 게이트: 시도 인덱스마다 그 시드의 추첨 인지 정책이 두 목표를 통과하고, 캠페인 세 번째
## 영업부터는 무계획이 제공 2건 이상 또는 손익 1,500 이상 미달해야 합니다(pressure-rebalance.md §4.1·§4.2).
## 실패 문장은 "attempt N: <이유>" 꼴이며, tests/test_seed_gate.gd와 tests/sweep_policies.gd --gate가 같은 판정을 씁니다.

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const NO_PLAN_SERVED_GAP: int = 2
const NO_PLAN_PROFIT_GAP: int = 1500


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
				if not no_plan_misses(scenario, no_plan):
					failures.append("attempt %d: no plan misses by less than %d orders and %d profit (%d served, %d profit)"
						% [attempt, NO_PLAN_SERVED_GAP, NO_PLAN_PROFIT_GAP, row["no_plan_served"], row["no_plan_profit"]])
		rows.append(row)
	return {"passed": failures.is_empty(), "failures": failures, "rows": rows}


## 무계획 미달 폭: 제공 2건 이상 또는 손익 1,500 이상(§4.1과 §4.2가 같은 폭을 씁니다).
static func no_plan_misses(scenario: Resource, run: Dictionary) -> bool:
	var served_gap: int = maxi(scenario.minimum_served - run.snapshot.accounting.served, 0)
	var profit_gap: int = maxi(scenario.minimum_profit - run.snapshot.accounting.profit, 0)
	return served_gap >= NO_PLAN_SERVED_GAP or profit_gap >= NO_PLAN_PROFIT_GAP
```

`tests/test_seed_gate.gd`에서 `class SeedGate` 전체를 지우고 상단에 `const SeedGate := preload("res://tests/fixtures/seed_gate.gd")`를 더합니다.
`ScheduleGenerator` preload는 `_test_draw_aware_policy`·`_test_campaign_gate`가 쓰므로 남깁니다.

- [ ] **Step 4: `m3_policies.gd`의 `without_kinds`와 `draw_aware_policy`**

`draw_aware_policy` 앞에 헬퍼를 더합니다.

```gdscript
## 정책에서 주어진 명령 종류만 뺀 사본. "priorities"는 priorities 사전을 비웁니다.
static func without_kinds(policy: Dictionary, kinds: Array) -> Dictionary:
	var stripped: Dictionary = {"preparation": [], "priorities": {}}
	for command: Dictionary in policy.get("preparation", []):
		if command.kind not in kinds:
			stripped.preparation.append(command.duplicate(true))
	if "priorities" not in kinds:
		stripped.priorities = policy.get("priorities", {}).duplicate(true)
	return stripped
```

`draw_aware_policy`를 기준 정책의 발주 명령을 반영하도록 바꿉니다(`set_purchase`는 `PreparationPlan`에서 덮어쓰기이므로 기준의 발주 명령을 그대로 뒤에 붙이면 추첨 인지 발주가 지워집니다).

```gdscript
## §4.2의 "추첨 인지 기준 정책": 시드 0 기준 정책 앞에, 원재료마다 작성 발주(기준 정책에 set_purchase가 있으면
## 그 값)와 그 시드의 구성이 필요로 하는 양 가운데 큰 값을 set_purchase로 맞춥니다. 시드 0에서는 기준 정책의 발주와 같습니다.
static func draw_aware_policy(scenario: Definitions, seed_value: int) -> Dictionary:
	var seeded: Definitions = scenario if seed_value == 0 else scenario.with_service_seed(seed_value)
	var needs: Dictionary[String, int] = {}
	for arrival: Dictionary in seeded.order_schedule():
		var recipe := scenario.recipe_for(arrival.recipe_id)
		for ingredient_id: String in recipe.ingredients:
			needs[ingredient_id] = needs.get(ingredient_id, 0) + recipe.ingredients[ingredient_id]
	var reference := reference_policy(scenario.id)
	var authored: Dictionary = scenario.purchases.duplicate()
	for command: Dictionary in reference.preparation:
		if command.kind == "set_purchase":
			authored[command.target_id] = command.value
	var policy: Dictionary = {"preparation": [], "priorities": {}}
	for ingredient: Definitions.IngredientDef in scenario.ingredients:
		if not ingredient.purchasable:
			continue
		var quantity: int = maxi(authored.get(ingredient.id, 0), needs.get(ingredient.id, 0))
		if quantity > 0:
			_add(policy, "set_purchase", ingredient.id, quantity)
	policy.preparation.append_array(without_kinds(reference, ["set_purchase"]).preparation)
	policy.priorities = reference.priorities.duplicate(true)
	return policy
```

- [ ] **Step 5: 스윕 도구의 세 옵션**

`tests/sweep_policies.gd` 상단 상수에 더합니다.

```gdscript
const SeedGate := preload("res://tests/fixtures/seed_gate.gd")
const WITHOUT_KINDS: Array[String] = ["set_purchase", "set_duty", "move_station", "rotate_station", "priorities"]
const PURCHASE_MODES: Array[String] = ["authored", "draw"]
const GATE_ATTEMPTS: Array[int] = [0, 1, 2, 3, 4, 5]
```

`_init`에서 시나리오를 찾은 직후(시도 인자 검증 앞)에 `--gate`를 처리합니다.

```gdscript
	if arguments.has("gate"):
		var verdict: Dictionary = SeedGate.evaluate(campaign, scenario, GATE_ATTEMPTS)
		for row: Dictionary in verdict.rows:
			print("SEED_GATE_ROW ", scenario.id, " ", JSON.stringify(row, "", true))
		print("SEED_GATE_VERDICT ", JSON.stringify({"scenario": scenario.id, "passed": verdict.passed, "failures": verdict.failures}, "", true))
		quit(0)
		return
```

`--keep` 검증 뒤에 두 옵션을 검증합니다.

```gdscript
	var purchase_mode: String = arguments.get("purchases", "authored")
	if purchase_mode not in PURCHASE_MODES:
		push_error("invalid --purchases: " + purchase_mode)
		quit(2)
		return
	var without: PackedStringArray = arguments["without"].split(",") if arguments.has("without") else PackedStringArray()
	for token: String in without:
		if token not in WITHOUT_KINDS:
			push_error("invalid --without token: " + token)
			quit(2)
			return
	if purchase_mode == "draw" and "set_purchase" in without:
		push_error("--purchases draw fixes the purchase commands; drop --without set_purchase")
		quit(2)
		return
```

`base`를 만드는 기존 루프와 `priorities` 유지 뒤에 발주 모드와 제거를 적용합니다.

```gdscript
	if purchase_mode == "draw":
		var drawn: Array = []
		for command: Dictionary in Policies.draw_aware_policy(scenario, seed_value).preparation:
			if command.kind == "set_purchase":
				drawn.append(command)
		var kept: Array = []
		for command: Dictionary in base.preparation:
			if command.kind != "set_purchase":
				kept.append(command)
		base.preparation = drawn + kept
	base = Policies.without_kinds(base, Array(without))
```

`SWEEP_SUMMARY`에 `"purchases": purchase_mode, "without": without` 두 키를 더합니다.
파일 머리 주석의 사용법 문장은 그대로 두고, note의 사용법 단락(2026-09-21 정정 절 끝)에 다음 세 문장을 더합니다: `--purchases draw`는 그 시도의 `draw_aware_policy`가 만드는 발주 명령을 기준 정책의 발주 대신 고정하고, `--without <종류,…>`는 `--keep`이 남긴 기준 명령에서 `set_purchase`·`set_duty`·`move_station`·`rotate_station`·`priorities`를 뺀 뒤 스윕하며, `--gate`는 다른 인자를 무시하고 시도 0~5의 `SEED_GATE_ROW`와 `SEED_GATE_VERDICT`만 찍습니다.
도구의 판정은 시도 0을 포함하므로 `test_seed_gate.gd`(시도 1–5)보다 엄격하며, 시도 0에서만 실패하면 그것은 `check.sh m3`의 시드 0 규칙이 다루는 문제입니다.
`--keep`에서 `duties`를 빼는 것과 `--without set_duty`는 같은 결과를 내며, `--keep`은 하위 호환으로 남깁니다.

- [ ] **Step 6: 통과 확인**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS(검사 수는 세 번째 fixture만큼 늘어남).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS(1,108 그대로여야 하며, 규칙 완화는 통과하던 것을 실패시키지 않습니다).
Run: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario hot_queue --gate` → 시도 0~5 여섯 줄이 모두 같은 회계(slack이 비어 있으므로)와 `"passed": true`.
Run: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario shared_stock --attempt 0 --purchases draw --without set_duty --best`와 같은 명령의 `--purchases authored` → 두 `SWEEP_SUMMARY`의 `combinations`·`passed`·`best`가 같고(시드 0의 추첨 인지 발주는 작성값과 같으므로), 첫 줄의 `purchases`가 `draw`, `without`가 `["set_duty"]`입니다.
Run: `... --scenario shared_stock --purchases draw --without set_purchase` → 종료 코드 2와 오류 문장.

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures/seed_gate.gd tests/fixtures/seed_gate.gd.uid tests/fixtures/m3_policies.gd tests/test_seed_gate.gd tests/test_m3_playthrough.gd tests/sweep_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "test(gate): widen the reference surplus, require the no-plan shortfall on every attempt and add draw, without and gate sweep options"
```

---

### Task 2: `hot_queue` 시도 2 풀림 탐침 (측정만, 중단 분기)

계획 3은 `hot_queue` 시도 2에서 프렙 조합 104가지 전부가 실패해 멈췄습니다.
명세의 접근(여유 우선)이 그 시도를 풀 수 있는지를 콘텐츠를 바꾸기 전에 잽니다.

**Files:**

- Modify(스윕 동안만, 되돌림): `content/campaign/scenarios/hot_queue.tres`
- Modify: `docs/notes/kitchen-pressure-verification.md` (새 절 "### 2026-09-XX 탐침: `hot_queue` 시도 2의 여유")

**Interfaces:**

- Consumes: Task 1의 `--purchases draw`, `--gate`.
- Produces: Task 5가 첫 수단으로 쓸 값(상한과 예산의 첫 통과점) 또는 중단 보고.

- [ ] **Step 1: 시작 slack으로 게이트 읽기**

`hot_queue.tres`의 `menu_ids` 줄 앞에 `forecast_slack = Dictionary[String, int]({"grill": 2, "soup": 1, "salad": 1})`를 넣습니다.
Run: `"$GODOT_BIN" --headless --path <worktree> --script tests/sweep_policies.gd -- --scenario hot_queue --gate`
Expected: 계획 3의 기록대로 시도 1~5 가운데 1개 통과(수치는 note에 옮깁니다).

- [ ] **Step 2: 상한 스윕**

`prep_labor_capacity`를 6부터 11까지 1씩 바꿔 가며(값마다 `.tres` 저장) 다음을 돌립니다.
Run: `... --scenario hot_queue --attempt 2 --purchases draw --items marinated_protein:3,prepped_vegetable:9,prepped_grain:9,soup_base:9 --best`
`--items` 상한은 노동량 상한이 잘라내므로 값마다 같은 인자를 씁니다.
`--keep`을 생략하므로 구이 우선순위 2는 유지됩니다.
`marinated_protein`의 노동량이 3이라 `set_prep marinated_protein 4`는 12이며, 상한 12부터 `_test_hot_queue_focus`의 "marinated_protein 4는 insufficient_labor로 거부" 검사가 깨지므로 11을 넘기지 않습니다.
표에 상한별 `combinations`·`passed`·`best`·`best_any`를 적습니다.

- [ ] **Step 3: 예산 스윕**

상한을 6으로 되돌리고 `starting_budget`을 9,750·10,250·10,750으로 바꿔 Step 2와 같은 명령을 돌립니다.
`hot_queue`의 발주 여유는 `9,250 − 2,000 − 6,250 = 1,000`이며 구이 +2는 연어 +2(800)를 요구하므로, 시도 2의 추첨 인지 발주가 `insufficient_budget`으로 거부되는지 먼저 `SEED_GATE_ROW`의 실패 문장으로 확인합니다.

- [ ] **Step 4: 되돌리고 기록**

Run: `git -C <worktree> checkout -- content/campaign/scenarios/hot_queue.tres`
Run: `git -C <worktree> status --short` → 비어 있어야 합니다(note 파일 편집 전에 확인).
note에 새 절을 씁니다: 명령, 표, 결론("상한 N 또는 예산 M부터 시도 2에 통과 조합이 생긴다" 또는 "~~상한 9~~·예산 +1,500까지 통과 없음"; 상한은 Step 2의 11이 맞으며 아래 2026-09-22 정정 절의 Task 2 항목 참조).

**중단 분기:** 상한 11과 예산 +1,500 어느 값에서도 시도 2의 `passed`가 0이면, 이 Task까지 커밋하고 멈춰 운영자에게 보고합니다.
그 경우 §5의 여유 수단은 가장 어려운 영업에서 작동하지 않으므로 `hot_queue`는 구성(§5의 3단계) 재설계 대상이고, 그 재설계는 승인 대상입니다.

- [ ] **Step 5: Commit**

```bash
git add docs/notes/kitchen-pressure-verification.md
git commit -m "docs(notes): probe how much headroom makes hot_queue attempt 2 solvable"
```

---

### Task 3: 콘텐츠 버전 7과 slack 작성 규칙 검사

첫 slack 커밋(Task 5)보다 앞서 버전을 올려 두어, 이후 모든 콘텐츠 커밋이 버전 7 아래에서 검사됩니다.
명세 §7의 "slack을 작성하는 커밋이 버전을 올린다"는 이 PR 안에서 slack 커밋 여섯 개가 모두 버전 7을 따르는 것으로 만족하며, 이 갈림은 Task 11의 정정 절에 적습니다.
코드는 계획 3 Task 4 Step 1·3(작성·리뷰됐고 실행되지 않음)을 그대로 씁니다.

**Files:**

- Modify: `persistence/campaign_store.gd:6`, `:171`, `:233-236`
- Modify: `tests/test_m4_store.gd`(46·171·186·214·230행의 `== 6` → `== 7`, 53·468·505·553행의 리터럴 6 → 7, 버전 5 검사 블록 뒤 버전 6 검사), `tests/test_menu_priorities.gd:111`, `tests/test_service_seed.gd:347`·`:365`의 6 → 7
- Modify: `tests/test_service_seed.gd:178-181` (slack 작성 규칙)

**Interfaces:**

- Produces: `CampaignStore.VERSIONS.content_version == 7`; 버전 6 이하 문서는 `content_updated`로 읽히고 `active_session`은 `null`. slack이 있는 영업은 값이 `[0, max(1, 기준/5)]` 안이고 합이 0이 아니며 시도 1~5마다 생성기가 순서를 바꿉니다.

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_m4_store.gd`의 버전 5 검사 블록(216~231행) 뒤에 버전 6 검사를 더합니다(세션은 현재 코드로 만든 `lunch_prep` 세션).

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

같은 파일의 `content_version == 6` 기대(46·171·186·214·230행)를 `== 7`로, 현재 세션을 담는 문서 리터럴(53·468·505·553행)의 6을 7로 바꿉니다.
버전 4·5 검사 블록의 문구 "content version 6"은 "content version 7"로 맞춥니다(계획 2b Task 5의 선례).
`tests/test_menu_priorities.gd:111`, `tests/test_service_seed.gd:347`·`:365`의 `"content_version": 6`을 7로 바꿉니다.
`_scenario_session`·`_write`·`current_records`는 그 파일에 이미 있는 헬퍼와 변수입니다.

`tests/test_service_seed.gd`의 `_test_scenario_fields` 첫 루프를 바꿉니다.
파일 상단 상수에 `const FIXED_FORECAST: Array[String] = ["first_shift", "lunch_prep"]`를 더합니다.

```gdscript
	for scenario: Resource in campaign.scenarios:
		if scenario.id in FIXED_FORECAST:
			expect(scenario.forecast_slack.is_empty(), "the first two services keep a fixed forecast: " + scenario.id)
		elif not scenario.forecast_slack.is_empty():
			var total: int = 0
			for recipe_id: String in scenario.menu_ids:
				var slack: int = scenario.forecast_slack.get(recipe_id, 0)
				total += slack
				expect(slack >= 0 and slack <= maxi(1, scenario.baseline_counts()[recipe_id] / 5),
					"authored slack stays within a fifth of the baseline: %s %s" % [scenario.id, recipe_id])
			expect(total > 0, "authored slack is not all zeros: " + scenario.id)
			for attempt: int in [1, 2, 3, 4, 5]:
				expect(ScheduleGenerator.recipe_ids(scenario, ScheduleGenerator.service_seed_for(scenario.id, attempt)) != scenario.order_recipe_ids,
					"authored slack moves at least one order on attempt %d: %s" % [attempt, scenario.id])
		expect(scenario.service_seed == 0, "authored service seed is zero: " + scenario.id)
```

`elif`는 Task 10이 `else`와 non-empty 기대로 바꿉니다(그때까지는 slack이 없는 압력 영업이 남아 있습니다).

- [ ] **Step 2: 실패 확인**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4` → FAIL(버전 6 문서가 `loaded`로 읽히고 `== 7` 기대가 깨짐).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS(slack이 모두 비어 있어 새 규칙이 아직 아무것도 재지 않음; 이 검사는 Task 5부터 의미를 갖습니다).

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

- [ ] **Step 4: 통과 확인**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4-core` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py` → 10 OK(같은 PCK).

- [ ] **Step 5: Commit**

```bash
git add persistence/campaign_store.gd tests/test_m4_store.gd tests/test_menu_priorities.gd tests/test_service_seed.gd
git commit -m "feat(persistence): bump content to version 7 and restart every earlier session ahead of authored forecast slack"
```

---

### Task 4: 지렛대 게이트와 `shared_stock` (발주 지렛대)

원문 정의의 게이트가 오늘 실패하는 유일한 영업이 `shared_stock`이므로(위 측정), 게이트 코드와 `shared_stock` 재조율을 한 Task에서 만들어 함께 커밋합니다(명세 §10의 "실패하는 상태로 커밋하지 않음").
`shared_stock`의 발주가 지렛대가 되려면 작성 `purchases`가 시드 0 필요량에 못 미치고 기준 정책이 `set_purchase`로 채워야 합니다(승인 질문 3번의 둘째 항목).

**Files:**

- Modify: `tests/fixtures/m3_policies.gd` (`LEVER_KINDS`, `without_lever_policy`, `lever_free_policy`, `shared_stock` 기준·대체 정책)
- Modify: `tests/test_m3_playthrough.gd` (지렛대 게이트, `_compare_choices`의 `purchases` 변형)
- Modify: `content/campaign/scenarios/shared_stock.tres` (`purchases`, `forecast_slack`, 여유·목표)
- Modify: `docs/notes/kitchen-pressure-verification.md` (재조율 절)

**Interfaces:**

- Produces: `Policies.LEVER_KINDS: Dictionary`(영업 ID → 명령 종류 배열), `Policies.without_lever_policy(scenario_id: String, kinds: Array = LEVER_KINDS[scenario_id]) -> Dictionary`, `Policies.lever_free_policy(scenario_id: String) -> Dictionary`(스윕이 찾은 최강 무지렛대 정책; 영업마다 고정). `M3_LEVER` 출력 줄.
- Consumes: Task 1의 `without_kinds`, `--without`, `--purchases draw`, `--gate`.

- [ ] **Step 1: 지렛대 데이터와 헬퍼**

`tests/fixtures/m3_policies.gd`의 `reference_policy` 앞에 더합니다.

```gdscript
## §4.3 영업별 지렛대(pressure-rebalance.md). 무지렛대 정책은 정책에서 이 종류의 명령만 뺀 것이고,
## "priorities"는 priorities 사전을 비웁니다. 시나리오 .tres의 operation_problem은 표시용이며 게이트는 이 표를 읽습니다.
const LEVER_KINDS: Dictionary = {
	"hot_queue": ["priorities"],
	"shared_stock": ["set_purchase"],
	"long_route": ["move_station", "rotate_station"],
	"split_duties": ["set_duty"],
	"rush_hour": ["set_prep", "priorities"],
}
```

`without_kinds` 뒤에 더합니다.

```gdscript
## 기준 정책에서 지렛대 종류를 뺀 정책. kinds를 비우면 LEVER_KINDS의 그 영업 항목 전부를 뺍니다.
static func without_lever_policy(scenario_id: String, kinds: Array = []) -> Dictionary:
	var stripped_kinds: Array = kinds if not kinds.is_empty() else LEVER_KINDS.get(scenario_id, [])
	return without_kinds(reference_policy(scenario_id), stripped_kinds)


## tests/sweep_policies.gd --without <지렛대> --best 가 시드 0에서 찾은 가장 강한 무지렛대 정책(best_any).
## 게이트는 이 정책이 한 목표 이상에 미달해야 통과하며, 값의 근거는 docs/notes/kitchen-pressure-verification.md의
## 재조율 절입니다. 아직 스윕하지 않은 영업은 지렛대를 뺀 기준 정책이 그 자리를 채웁니다.
static func lever_free_policy(scenario_id: String) -> Dictionary:
	var policy: Dictionary = without_lever_policy(scenario_id)
	match scenario_id:
		"shared_stock":
			policy = {"preparation": [], "priorities": {}}
			_add(policy, "set_prep", "soup_base", 6)
	return policy
```

`shared_stock` 갈래의 프렙 수량은 이 Step에서는 현재 기준 정책의 프렙 가운데 하나를 임시로 두고, Step 6이 스윕의 `best_any`로 바꾸면서 갈래 바로 위에 근거 주석 한 줄(`## sweep: --scenario shared_stock --attempt 0 --without set_purchase --best → passed 0, best_any {...}`)을 답니다.
Task 5–9는 자기 영업의 갈래와 근거 주석을 같은 꼴로 더하며, Task 10이 다섯 영업 모두 갈래를 가졌는지 검사하므로 `match`의 기본값(지렛대를 뺀 기준 정책)은 완료 시점에는 어느 영업에도 닿지 않습니다.

- [ ] **Step 2: 게이트 검사 작성**

`tests/test_m3_playthrough.gd`의 무계획 블록 안, `M3_PRESSURE` print 뒤에 더합니다.

```gdscript
				if Policies.LEVER_KINDS.has(scenario.id):
					var levers: Array = Policies.LEVER_KINDS[scenario.id]
					var subsets: Array = []
					for kind: String in levers:
						subsets.append([kind])
					if levers.size() > 1:
						subsets.append(levers)
					for subset: Array in subsets:
						var stripped: Dictionary = Policies.without_lever_policy(scenario.id, subset)
						expect(stripped != policy, "the reference policy uses its lever %s: %s" % [str(subset), scenario.id])
						var stripped_run := Policies.run_policy(scenario, stripped)
						expect(stripped_run.accepted and not Policies.passes_targets(scenario, stripped_run),
							"the reference policy misses a target without its lever %s: %s" % [str(subset), scenario.id])
					var lever_free: Dictionary = Policies.lever_free_policy(scenario.id)
					expect(Policies.without_kinds(lever_free, levers) == lever_free,
						"the pinned lever-free policy contains no lever command: " + scenario.id)
					var lever_free_run := Policies.run_policy(scenario, lever_free)
					expect(lever_free_run.accepted and not Policies.passes_targets(scenario, lever_free_run),
						"the strongest lever-free policy found by the sweep misses a target: " + scenario.id)
					if lever_free_run.accepted:
						print("M3_LEVER ", scenario.id, " ", JSON.stringify({"levers": levers,
							"lever_free": {"accounting": lever_free_run.snapshot.accounting, "metrics": lever_free_run.snapshot.metrics}}, "", true))
```

`_compare_choices`의 `purchases` 변형을 바꿉니다: 작성 재고가 모자라도록 재조율한 뒤에는 발주가 제공 건수를 바꿔야 합니다.

```gdscript
		"purchases": {"scenario": "shared_stock", "policy": {"preparation": [], "priorities": {}}},
```

는 그대로 두고, `variants.purchases.policy.preparation.append(...)` 줄을 기준 정책의 발주 명령을 그대로 쓰는 루프로 바꿉니다.

```gdscript
	for choice: Dictionary in Policies.reference_policy("shared_stock").preparation:
		if choice.kind == "set_purchase":
			variants.purchases.policy.preparation.append(choice)
```

`if kind == "purchases":` 분기의 기대를 바꿉니다.

```gdscript
		if kind == "purchases":
			expect(changed.accounting.served > baseline.accounting.served, "the reference purchase serves orders the authored stock cannot")
```

`var stock: Resource = campaign.scenario_for("shared_stock")` 줄은 더 이상 쓰지 않으므로 지웁니다.

- [ ] **Step 3: 실패 확인**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3`
Expected: FAIL — `shared_stock`에서 "uses its lever" 기대(뺀 정책이 기준과 같음)와 `_compare_choices`의 `purchases` 기대(작성 재고로 이미 다 제공하므로 `served`가 같음)가 실패합니다. `hot_queue`·`long_route`·`split_duties`·`rush_hour`의 기준 의존성 검사는 위 측정대로 통과해야 하며, 다른 영업이 실패하면 그 값을 note에 적고 이 Task의 범위 밖이므로 보고합니다.

- [ ] **Step 4: `shared_stock` 재조율(공통 절차 1~7)**

시작 slack `salad 1, soup 1, grain_salad 1, mushroom_salad 1`.
발주 지렛대: 작성 `purchases`를 시드 0 필요량 아래로 줄이고(첫 후보: `vegetable` 31 → 20, `grain`·`mushroom`은 유지), 기준 정책 앞에 `_add(policy, "set_purchase", "vegetable", <시드 0 필요량 이상>)`을 둡니다.
기준 정책의 발주는 시드 0 필요량 이상이어야 `draw_aware_policy`의 시드 0 항등(Task 1의 검사)이 성립합니다.
줄어든 작성 발주만큼 예산 여유(`9,250 − 2,400 − 발주 원가`)가 커지므로 §5의 예산 수단은 그 여유가 시도 1~5의 추첨 인지 발주를 못 받을 때만 씁니다(500 단위, 최대 +1,500).
`prep_labor_capacity`는 9에서 최대 12까지.
무계획 미달 폭이 작성 재고 감소로 커지므로 목표는 §4.1 여분(공통 절차 7)이 요구할 때만 올립니다.
`--items`는 `prepped_grain:9,soup_base:9,prepped_mushroom:9,prepped_vegetable:9`.

- [ ] **Step 5: 대체 정책**

대체 A(`set_purchase vegetable 29` + 프렙)는 기준과 발주가 겹치므로 기준과 다른 발주량과 프렙으로 다시 맞추고, 대체 B(`soup` 우선순위 2)는 발주 없이 통과하지 못하므로 발주 명령을 더합니다.
셋의 해시가 쌍별로 달라야 합니다(공통 절차 9).

- [ ] **Step 6: 지렛대 스윕과 고정**

Run: `... --scenario shared_stock --attempt 0 --without set_purchase --best`
Expected: `passed` 0. `best_any`의 `quantities`를 `lever_free_policy("shared_stock")`의 프렙으로 적습니다.
`passed`가 0이 아니면 작성 `purchases`를 더 줄입니다(지렛대 회복 수단).
Run: `... --scenario shared_stock --gate` → `passed: true`.

- [ ] **Step 7: 통과 확인과 기록(공통 절차 10~11)**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.
note 절에 위 측정 표(계획 작성 시점의 다섯 행)도 옮겨 적습니다(권위는 이 계획이 아니라 note).

- [ ] **Step 8: Commit**

```bash
git add tests/fixtures/m3_policies.gd tests/test_m3_playthrough.gd content/campaign/scenarios/shared_stock.tres docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): add the lever-necessity gate and make shared_stock purchases a required lever with authored slack"
```

---

### Task 5: `hot_queue` 재조율

**Files:**

- Modify: `content/campaign/scenarios/hot_queue.tres`, `tests/fixtures/m3_policies.gd`, `docs/notes/kitchen-pressure-verification.md`
- Modify(값에 따라): `tests/test_m3_playthrough.gd`의 `_test_hot_queue_focus`

- [ ] **Step 1: 공통 절차 1~7**

시작 slack `grill 2, soup 1, salad 1`.
첫 수단은 Task 2가 찾은 첫 통과점(상한 또는 예산)이고, 그 값에서 시작해 공통 절차 4~7을 돌립니다.
상한은 11까지(12부터 `_test_hot_queue_focus`의 "marinated_protein 4 거부" 검사가 깨지며, 이 계획은 11을 넘기지 않습니다).
`--items`는 `marinated_protein:3,prepped_vegetable:9,prepped_grain:9,soup_base:9`.
시드 0 기준 정책이 12건·4,750원 정확히 통과하는 상태(수프 5건 전부 만료)는 여유를 주면 바뀌므로, 공통 절차 7의 §4.1 여분이 넘치면 목표를 올립니다(명세 §5 표: "노동량·예산 여유 뒤 목표 상향").

- [ ] **Step 2: 공통 절차 8~9**

Run: `... --scenario hot_queue --attempt 0 --without priorities --best` → `passed` 0, `best_any`로 `lever_free_policy("hot_queue")` 고정.
`passed`가 0이 아니면 목표를 올려 우선순위 없는 최고가 목표 아래에 오게 합니다(기준 정책은 통과 유지).
대체 A(우선순위 `grill 2, soup 0` + 프렙)와 대체 B(기준 + `set_purchase protein 5`)를 맞춥니다.

- [ ] **Step 3: 공통 절차 10~11**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS(`_test_hot_queue_focus` 포함).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.

- [ ] **Step 4: Commit**

```bash
git add content/campaign/scenarios/hot_queue.tres tests/fixtures/m3_policies.gd tests/test_m3_playthrough.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): give hot_queue headroom for its forecast draws and author its slack"
```

---

### Task 6: `split_duties` 구성 재설계

측정된 사실: 담당 없이 노동량 1짜리 미장 한 단위만으로 최대치(26 · 12,350)에 닿아 어떤 목표·상한도 담당 유무를 가르지 못합니다.
자원으로는 고칠 수 없으므로 명세 §5의 3단계(구성)를 씁니다.

**Files:**

- Modify: `content/campaign/scenarios/split_duties.tres` (`order_recipe_ids`, `order_arrival_ticks`, `order_count`, 필요하면 `purchases`·목표, `forecast_slack`)
- Modify: `tests/fixtures/m3_policies.gd` (`split_duties` 기준·대체, `lever_free_policy`)
- Modify(값에 따라): `tests/test_kitchen_screen.gd`, `tests/capture_m4.gd`, `tests/capture_product_polish.gd`(기준 정책 명령을 그대로 적용하므로 보통 바뀌지 않음; 고정 수치 기대가 깨지면 그 줄만)
- Modify: `docs/notes/kitchen-pressure-verification.md`

- [ ] **Step 1: 재설계 방향**

이 영업의 메뉴 4종은 레시피 `cook_role`이 냉식인 `salad`·`mushroom_salad`와 온식인 `grain_grill`·`protein_bowl`입니다(메뉴 4종은 유지하며, 메뉴를 더하면 재료 정의가 늘어 12종 상한과 `test_mise_items.gd`의 기대에 닿습니다).
담당이 필요해지는 구성은 냉식과 온식이 같은 묶음에 함께 도착해, 담당 없는 네 직원이 같은 설비로 몰려 한쪽 열이 만료되는 구성입니다.
후보 순서(하나씩 시도하고 각 후보의 `--without set_duty` 스윕 결과를 표에 남깁니다):

1. 묶음 크기를 2에서 3~4로 키우고 묶음 안에 냉식 2·온식 2를 둡니다(도착 tick 배열만 바꾸고 `order_count` 26 유지, 묶음 사이 회복 구간 150 tick 이상).
2. 1에 더해 온식 비중을 올립니다(`grain_grill`·`protein_bowl` 합 12 → 14, `salad` 7 → 5).
3. 2에 더해 `order_count`를 28로 늘립니다(`order_recipe_ids`·`order_arrival_ticks` 길이도 28, 마지막 도착은 인내 500 tick을 남기고 2,500 이전).

각 후보에서 `--keep duties,priorities,placement --attempt 0 --best`(담당 유지)와 `--attempt 0 --without set_duty --best`(담당 없음)를 돌려, 담당 유지 `passed > 0`이고 담당 없음 `passed == 0`인 첫 후보를 고릅니다.
`--items`는 `prepped_vegetable:7,prepped_grain:6,prepped_mushroom:6,thawed_protein:3`.
셋 다 가르지 못하면 목표 상향(명세 §5 표의 "목표 상향")을 후보 3에 더해 다시 재고, 그래도 안 되면 멈추고 보고합니다.

- [ ] **Step 2: 공통 절차 1~7**

고른 구성의 새 기준 건수로 시작 slack을 다시 셉니다(`max(1, 기준/5)`).
여유 수단: `prep_labor_capacity` 15 → 최대 18, `starting_budget` 13,000 → 최대 +1,500, `purchases`는 새 구성의 시드 0 필요량 이상으로 맞춥니다(구성이 바뀌면 작성 발주도 맞추는 것이 §5의 3단계에 포함됩니다).

- [ ] **Step 3: 공통 절차 8~9**

담당 없음 스윕의 `best_any`로 `lever_free_policy("split_duties")`를 고정합니다.
기준 정책의 담당(직원 2 냉식, 직원 3·4 온식)은 유지하고 프렙만 다시 맞춥니다.
대체 A(담당 없는 프렙)는 새 구성에서 통과하지 못하면 담당을 다르게 나눈 정책(예: 직원 1·2 냉식, 직원 3·4 온식)으로 바꿉니다.

- [ ] **Step 4: 공통 절차 10~11과 화면 검사**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh ui-regressions` → PASS(`test_kitchen_screen.gd`가 이 시나리오로 부팅).
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4` → PASS(`capture_m4.gd`가 이 시나리오의 기준 정책을 적용).
note 절에 후보별 표(구성 요약·담당 유지 통과·담당 없음 통과·최고)를 남깁니다.

- [ ] **Step 5: Commit**

```bash
git add content/campaign/scenarios/split_duties.tres tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): redesign split_duties so duties are required and author its slack"
```

바뀐 테스트 파일이 있으면 같은 커밋에 넣습니다.

---

### Task 7: `final_service` 재조율

측정된 사실: 상한 21에서 구이 우선순위 2를 둔 통과 조합 22가지(경계 19), 연어 발주 9는 되살리지 못함.
운영자 결정(2026-09-21): 목표를 올리지 않고 여유를 측정 — 이 명세가 그 결정을 "여유 뒤 목표"로 바꿨습니다(§5 표).

**Files:**

- Modify: `content/campaign/scenarios/final_service.tres`, `tests/fixtures/m3_policies.gd`, `docs/notes/kitchen-pressure-verification.md`

- [ ] **Step 1: 공통 절차 1~7**

시작 slack 8종 각 1.
첫 수단 `prep_labor_capacity` 18 → 19, 통과가 없으면 20, 21(최대 21).
기준 정책은 `policy.priorities = {"grill": 2}`를 되찾고 프렙은 스윕으로 정합니다(2026-09-21 지렛대 측정 표의 상한 21 최고 `marinated_protein 5, prepped_vegetable 3, thawed_protein 2`가 첫 후보).
`--items`는 `marinated_protein:6,prepped_vegetable:6,prepped_grain:4,prepped_mushroom:3,soup_base:2,thawed_protein:3`.
§4.1 여분이 넘치면 목표를 올립니다(`minimum_profit` 10,000 → 최대 시도 0~5 손익 최솟값을 50 단위로 내림한 값).

- [ ] **Step 2: 공통 절차 9**

`final_service`는 `LEVER_KINDS`에 없으므로 지렛대 스윕은 없고, 무계획 미달(18 · 1,500)이 곧 지렛대 필요성입니다.
대체 A(`marinated_protein 6` + `hot_02` 오른쪽 1)와 대체 B(기준 + `set_purchase protein 6`)를 새 상한에서 다시 맞춥니다.

- [ ] **Step 3: 공통 절차 10~11**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.

- [ ] **Step 4: Commit**

```bash
git add content/campaign/scenarios/final_service.tres tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): raise final_service prep capacity so the grill priority lever returns and author its slack"
```

---

### Task 8: `long_route` 재조율

**Files:**

- Modify: `content/campaign/scenarios/long_route.tres`, `tests/fixtures/m3_policies.gd`, `docs/notes/kitchen-pressure-verification.md`

- [ ] **Step 1: 공통 절차 1~7**

시작 slack 4종 각 1.
첫 수단 `prep_labor_capacity` 12 → 13, 14, 15(최대 15); 그 다음 예산(13,600 → 최대 +1,500).
`--items`는 `marinated_protein:5,prepped_vegetable:6,prepped_grain:6,prepped_mushroom:6,soup_base:6,thawed_protein:6`.
기준 정책의 배치 명령(냉식 위 1·왼쪽 3, 화구 1 위 1·왼쪽 5, 화구 2 회전·위 2)은 유지합니다.

- [ ] **Step 2: 공통 절차 8~9**

Run: `... --scenario long_route --attempt 0 --without move_station,rotate_station --best` → `passed` 0, `best_any`로 `lever_free_policy("long_route")` 고정.
`passed`가 0이 아니면 여유를 되돌리고 목표를 올립니다.
대체 A(배치 변형: 화구 1 왼쪽 4)와 대체 B(기준 + 직원 3 온식 담당)를 맞춥니다.

- [ ] **Step 3: 공통 절차 10~11**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.

- [ ] **Step 4: Commit**

```bash
git add content/campaign/scenarios/long_route.tres tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): give long_route prep headroom for its forecast draws and author its slack"
```

---

### Task 9: `rush_hour` 재조율

**Files:**

- Modify: `content/campaign/scenarios/rush_hour.tres`, `tests/fixtures/m3_policies.gd`, `docs/notes/kitchen-pressure-verification.md`

- [ ] **Step 1: 공통 절차 1~7**

시작 slack 8종 각 1.
첫 수단 `prep_labor_capacity` 18 → 19, 20, 21(최대 21); 그 다음 예산(14,400 → 최대 +1,500).
`--items`는 `marinated_protein:3,prepped_vegetable:6,prepped_grain:6,prepped_mushroom:6,soup_base:3,thawed_protein:3`.

- [ ] **Step 2: 공통 절차 8~9(지렛대 둘)**

프렙은 스윕 도구가 항상 순회하므로 `--without`에 `set_prep`은 없고, "프렙 없음"은 `--items`의 상한을 모두 0으로 두어 만듭니다.
세 스윕을 돌립니다.
Run: `... --scenario rush_hour --attempt 0 --without priorities --best`(프렙만) → ~~`passed` 0이어야 하며~~(계획의 결함, 아래 2026-09-22 정정 절의 Task 9 항목), 2026-09-21 절에서는 우선순위 없는 통과가 150이었으므로 목표 상향이 필요할 가능성이 큽니다: 우선순위 없는 `best_any`가 목표 아래에 오도록 `minimum_profit`(또는 `minimum_served`)을 올리되 기준 정책은 시도 0~5를 통과해야 합니다.
Run: `... --scenario rush_hour --attempt 0 --items marinated_protein:0,prepped_vegetable:0,prepped_grain:0,prepped_mushroom:0,soup_base:0,thawed_protein:0 --best`(우선순위만, 프렙 0, 조합 1) → `passed` 0.
Run: `... --scenario rush_hour --attempt 0 --without priorities --items <위와 같은 0 상한> --best`(무계획과 같음, 조합 1) → `passed` 0.
`lever_free_policy("rush_hour")`는 세 스윕 가운데 `best_any`가 가장 큰 것(제공, 손익 사전순)으로 고정합니다.
대체 A(프렙만, `marinated_protein 1, prepped_vegetable 5, prepped_grain 3, thawed_protein 1, prepped_mushroom 3`)는 우선순위 없이 통과하는 정책이므로 목표가 오르면 통과하지 못하며, 그 경우 우선순위를 다르게 둔 정책(예: `mushroom_soup 2, grill 2`)으로 바꿉니다.
대체 B(`mushroom_soup` 우선순위 0)도 같은 이유로 프렙을 더해야 할 수 있습니다.

- [ ] **Step 3: 공통 절차 10~11**

Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3` → PASS.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.

- [ ] **Step 4: Commit**

```bash
git add content/campaign/scenarios/rush_hour.tres tests/fixtures/m3_policies.gd docs/notes/kitchen-pressure-verification.md
git commit -m "feat(content): make rush_hour require both prep and priorities and author its slack"
```

---

### Task 10: 모든 압력 영업의 slack 확정, 두 PCK 6→7, 전체 회귀

**Files:**

- Modify: `tests/test_service_seed.gd` (Task 3의 `elif` → `else` + non-empty 기대)
- Modify: `docs/notes/kitchen-pressure-verification.md` (시드 게이트 종합 표)

- [ ] **Step 1: 실패하는 검사 작성**

`tests/test_m3_playthrough.gd`의 지렛대 게이트(Task 4)에서 `var lever_free: Dictionary = Policies.lever_free_policy(scenario.id)` 뒤에 한 줄을 더해, 고정된 갈래가 없는 영업(기본값인 "지렛대를 뺀 기준 정책"과 같은 값)을 잡습니다.

```gdscript
					expect(lever_free != Policies.without_lever_policy(scenario.id),
						"the lever-free policy is pinned from a sweep, not the stripped reference: " + scenario.id)
```

스윕의 `best_any`가 우연히 지렛대를 뺀 기준 정책과 같은 프렙이면 이 검사가 실패하므로, 그 영업의 갈래는 `best_any`와 같은 회계를 내는 다른 통과-무관 최고 조합(`SWEEP` 출력의 다음 행)으로 고정하고 근거 주석에 그 사실을 적습니다.

Task 3의 루프에서 `elif not scenario.forecast_slack.is_empty():`를 다음 두 줄로 바꾸고 나머지 본문은 그대로 둡니다.

```gdscript
		else:
			expect(not scenario.forecast_slack.is_empty(), "every pressure service varies from the second attempt: " + scenario.id)
```

`tests/test_seed_gate.gd`의 `_test_campaign_gate`에 있는 "an empty forecast slack reproduces the authored order" 검사는 조건부라 그대로 두되, 압력 영업이 모두 slack을 가지므로 실행되지 않는 분기가 됩니다(계획 3의 "설계상 꺼진다"는 문구가 이 시점).

- [ ] **Step 2: 실패 확인 뒤 통과**

이 검사는 Task 5~9가 모두 끝났으면 바로 통과합니다.
먼저 실패를 보려면 `hot_queue.tres`의 `forecast_slack` 줄을 잠시 지우고 `check.sh mise`가 "every pressure service varies" 기대에서 실패하는지 확인한 뒤 `git -C <worktree> checkout -- content/campaign/scenarios/hot_queue.tres`로 되돌립니다.
Run: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise` → PASS.

- [ ] **Step 3: 두 PCK 6→7**

콘텐츠 6 PCK를 `origin/main`(`567fe9a`)에서 만듭니다.

```bash
git -C <worktree> archive --format=tar --prefix=content6/ 567fe9a --output <scratchpad>/content6.tar
tar -xf <scratchpad>/content6.tar -C <scratchpad>
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content6 --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <scratchpad>/content6 --export-pack Android <scratchpad>/content6.pck
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <worktree> --export-pack Android <scratchpad>/content7.pck
M4_EXPECT_RESTART=1 M4_WRITER_PACK=<scratchpad>/content6.pck M4_READER_PACK=<scratchpad>/content7.pck GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py
```

Expected: 9 OK / 1 skip(`RESTART_PASS`).
강제 실패 확인: `_content_update_restarts_session`을 잠시 `< 6`으로 되돌려 두 reader 검사가 실패하는 것을 본 뒤 `< 7`로 되돌리고 `git -C <worktree> status --short`가 `tests/`·`docs/` 변경만 보이는지 확인합니다.
Godot 프로세스는 이 단계에서도 한 번에 하나입니다.

- [ ] **Step 4: 전체 회귀**

Run(순서대로, 하나씩): `bash scripts/check-export.sh`, `python3 tests/test_export_check.py`, `python3 tests/test_ios_export.py`, `bash scripts/check.sh m0`, `m1`, `m2`, `m3`, `m4-core`, `m4`, `m5`, `mise`, `ui-regressions`(모두 `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot`) → 모두 PASS.
`ui-regressions`는 브리핑이 새 예보 범위를 보이는 검사를 포함합니다(명세 §8).
note에 "### 2026-09-XX 시드 게이트 종합" 절을 더해 여섯 영업의 최종 `SEED_GATE_ROW`를 한 표로 모읍니다(영업별 절이 이미 적은 값의 인용이며, 새 사실은 이 표의 "여섯 영업 30행 통과"뿐입니다).

- [ ] **Step 5: Commit**

```bash
git add tests/test_service_seed.gd docs/notes/kitchen-pressure-verification.md
git commit -m "test(seed): require authored slack on every pressure service and record the full seed gate"
```

---

### Task 11: 명세·지침·기록 정정

**Files:**

- Modify: `docs/plans/PLAN.md:531-534` (§12 위험 표의 행과 그 아래 단락)
- Modify: `docs/specs/mise-forecast-reviews.md:64` 뒤(§4.1 포인터), `:249`(§8 콘텐츠 버전 5의 `forecast_slack` 서술), `:275`(§10 풀림 검사 행)
- Modify: `AGENTS.md:158` 뒤(Simulation Rules 한 문장)
- Modify: `docs/notes/kitchen-pressure-verification.md:22-23` (2026-09-11 규칙 문장)
- Modify: `docs/specs/pressure-rebalance.md` (정정 단락)
- Modify: `docs/plans/pressure-rebalance-implementation.md` (이 문서: 정정 절과 회귀 결과)

- [ ] **Step 1: PLAN.md §12**

531행의 행을 바꿉니다: 최소 대응 "§4 게이트(여유 2건·3,000, 시도 1–5, 무지렛대 미달)", 확장 전 판단 "실패한 영업은 §5 순서로 여유·목표·구성을 조정하고 slack을 0으로 만들지 않음"(명세 §9의 문구).
533–534행의 두 문장 뒤에 한 문장을 더합니다: 재조율 명세(`../specs/pressure-rebalance.md`)와 이 계획이 여섯 영업의 slack을 작성했고 콘텐츠 버전은 7입니다.

- [ ] **Step 2: mise-forecast-reviews.md**

64행의 2026-09-21 정정 단락 뒤에 한 문장: "2026-09-XX부터 게이트 규칙과 slack 작성은 `pressure-rebalance.md` §4가 소유합니다."
249행의 "콘텐츠 버전 5. 미장 구조, `forecast_slack`, 리뷰 리소스가 추가됩니다."에서 `forecast_slack`을 빼고 "**콘텐츠 버전 7.** `forecast_slack` 작성(`pressure-rebalance.md` §7)" 항목을 253행 뒤에 더합니다.
275행의 풀림 검사 행 문구를 "시드 1~5마다 실제 추첨을 아는 기준 정책이 두 목표를 통과하고 무계획은 제공 2건 이상 또는 손익 1,500 이상 미달(`pressure-rebalance.md` §4.2)"로 바꿉니다.

- [ ] **Step 3: AGENTS.md**

158행 뒤에 한 줄: `- Every pressure service names its lever in tests/fixtures/m3_policies.gd, and check.sh m3 requires the reference policy stripped of that lever, and the strongest lever-free policy the sweep found, to miss a target (docs/specs/pressure-rebalance.md §4.3).`
운영자가 원문 정의를 골랐으면 "and the strongest lever-free policy the sweep found" 절을 뺍니다.

- [ ] **Step 4: note와 명세 정정**

note 22–23행(작은 여유·무계획 미달 문장) 뒤에 "2026-09-XX부터 `../specs/pressure-rebalance.md` §4가 이 두 문장을 대체합니다(여분 2건·3,000, 무계획 미달 폭은 시도 1–5에도 적용)."를 더합니다.
note의 2026-09-20 정정 표와 2026-09-21 정정 표(두 번째, `M3_PRESSURE` 회계 표) 위에 각각 한 문장을 더합니다: "이 표의 여섯 압력 영업 값은 2026-09-XX 재조율 절이 대체하며, 권위는 그 절과 `.tres`·`m3_policies.gd`에 있습니다."(이미 쓰는 "위 표는 … 아래 절이 권위입니다" 꼴).
`docs/specs/pressure-rebalance.md` 끝에 "## 2026-09-XX 정정" 절을 더합니다: (1) §4.3 원문 정의의 시드 0 측정(위 다섯 행은 note 절을 인용)과 채택한 두 층(또는 원문 유지), `rush_hour`의 지렛대별 검사; (2) §8의 "`split_duties`에서 먼저 실패" 문장은 측정과 달랐고 실제로는 `shared_stock`에서 실패했음; (3) §6의 세 번째 옵션 `--gate`와 `SeedGate` fixture 분리; (4) §7의 버전 상향이 첫 slack 커밋보다 앞선 Task 3에서 이루어진 이유; (5) 영업별로 실제로 쓴 수단(여유·목표·구성)의 요약(수치는 note 인용).

- [ ] **Step 5: 이 계획의 정정 절과 회귀 결과**

이 문서 끝에 "## 2026-09-XX 정정"(Task별로 계획 서술과 실제 커밋이 갈린 지점, 컨트롤러 판정)과 "### Task 10 회귀 결과"(`log` 블록, Task 10 Step 4의 출력)를 더합니다.

- [ ] **Step 6: Commit**

```bash
git add docs/plans/PLAN.md docs/specs/mise-forecast-reviews.md docs/specs/pressure-rebalance.md AGENTS.md docs/notes/kitchen-pressure-verification.md docs/plans/pressure-rebalance-implementation.md
git commit -m "docs: point the blueprint, mise spec and agent rules at the rebalance gate and record the plan's divergences"
```

---

## 완료 조건

- `check.sh m3`가 §4.1(여분 2건·3,000, 무계획 미달 폭, 세 해시, 1배·4배)과 §4.3(다섯 영업의 기준 의존성과 고정된 최강 무지렛대 정책 미달)을 검사하며 통과하고, `LEVER_KINDS`의 다섯 영업 모두 스윕에서 고정된 `lever_free_policy` 갈래와 근거 주석을 가집니다.
- `check.sh mise`의 `test_seed_gate.gd`가 여섯 압력 영업의 시도 1~5 통과와 무계획 미달 폭을 검사하며 통과하고, 세 합성 fixture가 실패합니다.
- 여섯 압력 영업의 `forecast_slack`이 비어 있지 않고 `[0, max(1, 기준/5)]` 안이며 시도 1~5마다 순서가 바뀝니다; `first_shift`·`lunch_prep`은 비어 있습니다.
- 콘텐츠 버전 7, 두 PCK 6→7 `M4_EXPECT_RESTART=1` 9 OK / 1 skip, 같은 PCK 10 OK.
- 모든 suite와 `check-export.sh`, `test_export_check.py`, `test_ios_export.py`가 PASS.
- 영업마다 note에 스윕 인자·조합·통과·최고·확정값이 있고, 명세 §9의 네 문서와 명세 자체의 정정 절이 있습니다.
- PR은 `main`을 대상으로 열고 운영자가 머지합니다.

## 다음 계획

- 플레이테스트(`docs/specs/playtest-price-validation.md`)는 이 PR이 머지된 뒤 운영자의 시작 문장으로 시작합니다.
- 브리핑의 메뉴별 인내 시간 표시와 메뉴 아이콘은 4단계 화면 계획으로 미뤄져 있습니다.

## 2026-09-22 정정

아래 항목은 Task 1–11 실행 중 이 계획의 서술과 실제 커밋이 갈린 지점과 그때의 판정입니다.
이 절 위의 단계 서술은 고치지 않으며(지금 틀린 세 구절만 취소선과 이 절로의 포인터를 달았습니다), 권위는 인용한 커밋의 코드·`.tres`·테스트와 `docs/notes/kitchen-pressure-verification.md`(아래 "note")의 영업별 "2026-09-21 재조율" 절에 있습니다.
커밋 SHA는 `feat/pressure-rebalance`의 것이며 `git log --oneline 567fe9a..HEAD`로 확인했습니다.
`567fe9a`는 계획 작성 시점의 `origin/main`이고 그 뒤 `origin/main`은 움직였으므로, 이 절과 Task 10 Step 3의 명령은 리터럴 SHA로만 읽습니다.

### 실행 순서

계획의 Task 번호 순서가 아니라 다음 순서로 실행했습니다: 1, 2(확장 넷), 3, 4, 6, 7(수렴 실패), 8, 9(수렴 실패), 10a(계획에 없음), 5, 7b, 9b(수렴 실패), 9c, 10, 11.
`hot_queue`(Task 5)는 Task 2의 중단 분기가 걸려 운영자 결정까지 미뤄졌고 Task 3–9 뒤에 실행했습니다.
note의 여섯 재조율 절은 제목을 "2026-09-21 재조율" 계열로 통일하고 측정일은 본문에 적었습니다.

### 운영자 판정 (2026-09-21·22)

1. 계획 승인, subagent 주도 실행(2026-09-21).
2. §4.3은 두 층으로(승인 질문 3번): 기준 의존성과 스윕이 고정한 최강 무지렛대 정책(`Policies.lever_free_policy`).
   `rush_hour`는 지렛대별(`set_prep`·`priorities`·둘 다)로 검사하고, 배치(`move_station`·`rotate_station`)는 `Policies.lever_subsets`의 한 부분집합입니다(회전만 뺀 `long_route` 기준 정책은 통과하므로, Task 4).
3. `shared_stock`의 작성 `purchases`는 시드 0 필요량 아래로 줄여 기준 정책이 `set_purchase`로 채우도록 합니다(Task 4).
4. `hot_queue`의 구성 재설계 허용(2026-09-22, Task 5).
5. `final_service`는 상한 22–24를 먼저 재고 그 다음 구성(2026-09-22, Task 7b).
6. `rush_hour`의 구성 재설계 허용(2026-09-22, Task 9b) — 이후 컨트롤러 판정으로 원래 구성에서 수렴(Task 9c).
7. 부하가 낮을 때는 Godot 프로세스 둘까지(2026-09-22; Global Constraints의 "한 번에 하나"를 완화한 진행 규칙이며 문서 규칙은 바꾸지 않았습니다).

### Task별 갈린 지점과 컨트롤러 판정

- 사전 판정: 한 Task 안에서 올린 목표는 다시 내릴 수 있되 `567fe9a`의 값 아래로는 내리지 않습니다.
- Task 1(커밋 `b1bd756`, note 정정 `058dede`): 계획대로였고, note의 `--keep purchases` 문장은 `--purchases draw`와 모순되지 않게 `--keep`으로 범위를 좁혔습니다.
- Task 2(커밋 `123c9bd`, 확장 `0f9d91a`·`04459d6`·`5c93a31`·`981c15b`): 상한의 상한은 Step 2대로 11이며(`marinated_protein 4`가 노동량 12라 `_test_hot_queue_focus`가 깨짐) Step 4의 "상한 9"는 오기입니다(취소선).
  중단 분기가 건너뛰는 §4.4의 slack 축소를 멈추기 전에 쟀고("가장 큰 값, `menu_ids` 순서" 사다리는 계획의 규칙이라 두 메뉴 slack 둘도 쟀음), 우선순위 지도와 실패 원인 탐침을 운영자 질문 전에 돌렸습니다.
  수치는 note "탐침: `hot_queue` 시도 2의 여유" 절.
- Task 3(커밋 `621adb3`): 첫 slack 커밋보다 앞서 버전 7을 올렸습니다(명세 §7의 문장과 다르며 명세의 2026-09-22 정정 절 4).
  Step 2의 "`check.sh mise` → PASS" 예측은 틀렸습니다: `tests/test_service_seed.gd`의 현재 버전 리터럴 둘을 같은 Step에서 7로 올려 상향 전에는 미래 버전 검사가 실패하며, 결함이 아니라 예상되는 실패입니다.
- Task 4(커밋 `f6d1626`, 리팩터 `bae9289`): 운영자 판정 2·3대로이며, `_compare_choices`의 `purchases` 변형은 기준 발주가 작성 재고보다 더 제공하는지로 바뀌었습니다.
  값은 note "재조율: `shared_stock`" 절.
- Task 6(커밋 `3a72a01`, 브리핑·note 정리 `64ae801`): slack `salad 1, mushroom_salad 1`(온식 0)은 온식→냉식 추첨이 매출 상한을 고정된 손익 목표 아래로 내리므로 §4.4로 수용했습니다(명세 §3의 "미세 slack" 거부와 긴장; `order_count` 28은 재지 않은 대안).
  `prep_labor_capacity` 15 → 7 인하를 수용했습니다: 명세 §5의 방향 제약은 목표에만 걸리고 운영자가 2026-09-21에 이 영업의 상한 스윕을 허용했으며, Step 2의 "15 → 최대 18"은 올리는 쪽만 가정한 서술입니다.
  묶음 3+1과 2/2 담당 분할은 공학적 선택이고, 브리핑과 `translations/en.po`는 제자리에서 교체했습니다.
  값은 note "재조율: `split_duties`" 절.
- Task 7(커밋 `cd6d2a3`, 수렴 실패): 1바퀴에서 온식 다섯 메뉴를 한 번에 0으로 뒀고(공통 절차 7은 가장 큰 값부터 하나씩; 논거는 note), 상한 21 이하에서 여섯 시도 교집합이 없어 멈췄습니다.
- Task 7b(커밋 `c233ffb`, note 정정 `9c9da50`): 운영자 판정 5에 따라 상한 22에서 냉식 두 메뉴 slack으로 수렴했고 목표는 그대로입니다.
  §4.4의 중간 단계는 22–24에서 재지 않았습니다(후속).
  값은 note "재조율: `final_service`" 절의 2차 소절.
- Task 8(커밋 `220874e`, note 정정 `9049cf8`): `lever_free_policy("long_route")`는 `best_any`가 지렛대를 뺀 기준 정책과 같아 다음 순위 행으로 고정했습니다(Task 10 Step 1의 허용 조항).
  값은 note "재조율: `long_route`" 절.
- Task 9(커밋 `8bdbc89`, note 정정 `454b72e`, 수렴 실패)·9b(커밋 `e8fb5b5`, 측정만)·9c(커밋 `3099b2b`, note 정정 `7fef392`, 기준 재선정 `07735de`): Step 2와 공통 절차 8의 "프렙만 스윕 `passed` 0"은 계획의 결함입니다(취소선).
  명세 §4.3은 무지렛대 정책에서 두 지렛대를 모두 빼며, 승인된 정의는 `tests/test_m3_playthrough.gd`에 코드화된 게이트뿐입니다.
  그 기준으로 원래 구성에서 수렴했고, 9c의 기준 정책은 리뷰 뒤 1층을 모두 만족하는 행 가운데 시드 0 편차가 가장 작은 행으로 다시 골랐습니다(리뷰가 제안한 행은 `priorities`만 뺀 갈래에서 실패).
  값은 note "재조율: `rush_hour`" 절의 3차 소절.
- Task 10a(커밋 `af226c5`, 계획에 없음): `hot_queue`·`rush_hour`의 `lever_free_policy`를 운영자 질문 전에 고정해 Task 10의 검사가 구성 결정과 무관하게 들어가게 했습니다.
  `rush_hour`의 고정값은 스윕 도구가 프렙만 순회하므로 배치·담당·발주 탐침에서 나온 `move_station cold_01 left` 2회이고, `hot_queue`는 Task 5의 재설계 뒤 다시 고정했습니다.
- Task 5(커밋 `276e2aa`, note 정정 `e11f4ab`): 운영자 판정 4에 따라 구성을 재설계했습니다.
  여섯 시도 교집합 세 조합의 손익 최솟값이 같아 공통 절차 4의 규칙으로는 갈리지 않았고 이전 기준 프렙을 유지했습니다.
  값은 note "재조율: `hot_queue`" 절.
- Task 10(커밋 `11a48e6`): 계획대로였고, Step 3의 "`origin/main`(`567fe9a`)"은 그 뒤 `origin/main`이 움직여 라벨만 낡았습니다.
- 리뷰: Task 8·9b의 한 줄 note 수정은 컨트롤러가 범위 재리뷰 없이 확인했고, 나머지 수정 라운드는 모두 범위 리뷰를 거쳤습니다.

### 후속 (이 PR에서 풀지 않음)

- `final_service`의 기준 정책은 `grain_grill` 네 건을 모두 만료시키고 덮밥 두 건을 굶겨 통과하며(주문별 수치는 note 2차 소절), 대체 B가 시드 0에서 기준보다 높습니다.
- `split_duties`의 변동은 냉식뿐이며, `order_count` 28이 온식 slack의 매출 여유를 줄 수 있습니다(미측정).
- `final_service`의 §4.4 중간 단계는 상한 22–24에서 재지 않았습니다(더 넓은 slack이 있을 수 있음).
- `hot_queue`의 여분은 구속 폭입니다(시도 5의 제공이 목표와 같고 시드 0의 제공 여분이 §4.1의 상한과 같음; note "재조율: `hot_queue`" 절).
- 후속으로 다루지 않은 구속 폭: `split_duties`의 기준 정책은 시드 0과 시도 1–5 전부에서 제공 여분이 0이며(목표 26건에 26건 제공), `hot_queue`·`split_duties` 둘 다 마지막 도착(2500)이 손님 인내 500을 더한 마감 tick(3000)에 정확히 걸리고 발주도 시드 0 필요량과 정확히 같습니다(note "재조율: `hot_queue`"·"재조율: `split_duties`" 절).
- `tests/sweep_policies.gd`의 `--gate` 분기는 `--attempt`·`--purchases`·`--without`·`--items` 검증보다 먼저 반환해, `--gate --purchases draw`가 그 플래그를 조용히 무시합니다(도구 결함).
- 기존 결함: `persistence/campaign_store.gd`의 `load_records()` 종단 실패 분기가 `active_session`을 빠뜨리고 `_failure()`는 null을 둡니다.
- 플레이테스트(`docs/specs/playtest-price-validation.md`)는 운영자의 시작 문장을 기다립니다.

### Task 10 회귀 결과 (2026-09-22)

두 PCK 검사는 `567fe9a`에서 만든 콘텐츠 6 PCK를 writer로, 워크트리에서 만든 콘텐츠 7 PCK를 reader로 돌렸고, 같은 PCK 검사는 콘텐츠 7 PCK로 돌렸습니다.
회귀는 하나씩 순서대로 실행했고 모든 suite의 로그에 `SCRIPT ERROR`·`ERROR:` 줄은 없었습니다.

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
Ran 10 tests in 0.818s

OK

$ python3 tests/test_ios_export.py
Ran 2 tests in 0.092s

OK

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m0
PASS: m0 checks=25 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m1
PASS: m1 checks=192 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m2
PASS: m2 checks=489 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3
PASS: m3 checks=1120 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4-core
PASS: m4-core checks=902 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4
PASS: m4 checks=1206 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m5
PASS: m5 checks=583 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh mise
PASS: mise checks=393 failures=0

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh ui-regressions
PASS: ui-regressions checks=285 failures=0

$ M4_EXPECT_RESTART=1 M4_WRITER_PACK=content6.pck M4_READER_PACK=content7.pck GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py
Ran 10 tests in 1.720s

OK (skipped=1)

$ GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py
Ran 10 tests in 1.691s

OK
```
