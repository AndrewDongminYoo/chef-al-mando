# 영업 피드백 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 영업 중 직원 행동과 문제를 읽을 수 있게 하고 마감 뒤 프렙·발주·우선순위 개선 행동을 근거와 함께 제시합니다.

**Architecture:** `ServiceSim`은 순간 사건만 발행하고 기존 스냅샷과 저장 형식을 유지합니다.
새 `ServiceAnalysis`는 최종 스냅샷과 준비 선택을 분석하며, 프레젠테이션은 구조화된 결과를 현지화해 직원 상태, 배지, 말풍선, 마감 제안으로 표시합니다.

**Tech Stack:** Godot 4.7, typed GDScript, 기존 headless test harness, SVG 기반 2D 주방 보드.

**Spec:** `docs/specs/service-feedback.md`

## 전역 제약

- 시뮬레이션 tick 순서와 결정성 해시를 바꾸지 않습니다.
- 저장 스키마를 변경하지 않습니다.
- 마이크, 음성 인식, 새 권한이나 새 의존성을 추가하지 않습니다.
- 프레젠테이션은 시뮬레이션 결과를 결정하지 않습니다.
- 한국어를 기본으로 하고 `translations/en.po`에 영어 문구를 추가합니다.

---

### 작업 1: 구조화된 마감 분석

**Files:**

- Create: `sim/service_analysis.gd`
- Create: `tests/test_service_feedback.gd`
- Modify: `tests/test_m2.gd`

**Interfaces:**

- Consumes: `Definitions`, `ServiceSim.snapshot()`, `PreparationPlan`의 `selection`.
- Produces: `ServiceAnalysis.build(data: Definitions, view: Dictionary, selection: Dictionary) -> Dictionary`.

- [x] **Step 1: 실패 테스트 작성**

  `hot_queue`와 작은 분석 fixture에서 프렙 사용·잔량·생재료 손질, 발주·잔량·부족 시간, 우선순위·제공·미제공·경합을 구조화된 숫자로 단언합니다.
  프렙 노동량과 우선순위가 상한이면 `increase_prep`과 `raise_priority`가 나오지 않는지 단언합니다.

- [x] **Step 2: RED 확인**

  Run: `bash scripts/check.sh m2`
  Expected: `service_analysis.gd` 또는 분석 결과가 없어서 실패합니다.

- [x] **Step 3: 최소 구현**

  `ServiceAnalysis.build`에서 메뉴·재료별 관측값을 집계하고 `recommendations`에 최대 3개의 구조화된 행동을 넣습니다.
  행동 식별자는 `increase_prep`, `reduce_prep`, `prep_at_capacity`, `increase_purchase`, `reduce_purchase`, `purchase_consumed`, `raise_priority`, `priority_at_max`로 제한합니다.

- [x] **Step 4: GREEN 확인**

  Run: `bash scripts/check.sh m2`
  Expected: `PASS: m2 checks=<count> failures=0`.

### 작업 2: 시뮬레이션 사건

**Files:**

- Modify: `sim/service_sim.gd`
- Modify: `tests/test_service_feedback.gd`

**Interfaces:**

- Consumes: 기존 주문 대기 전환과 입력 소비 흐름.
- Produces: `order_wait_started`, `prepared_stock_depleted`, 확장된 `order_ended` 이벤트.

- [x] **Step 1: 실패 테스트 작성**

  재료 부족 진입이 한 번만 발생하고, 마지막 프렙 소비가 소진 사건을 만들며, `serve` 공정 만료가 공정 식별자를 보존하는지 단언합니다.

- [x] **Step 2: RED 확인**

  Run: `bash scripts/check.sh m2`
  Expected: 새 이벤트가 없어서 실패합니다.

- [x] **Step 3: 최소 구현**

  대기 원인 전환을 한 helper에서 기록하고 `_begin_work`와 `_terminate_order`가 사건에 필요한 식별자만 추가합니다.
  이벤트를 저장 상태와 상태 해시에는 넣지 않습니다.

- [x] **Step 4: GREEN 확인**

  Run: `bash scripts/check.sh m2`
  Expected: `PASS: m2 checks=<count> failures=0`.

### 작업 3: 직원 상태와 말풍선

**Files:**

- Modify: `presentation/main.gd`
- Modify: `presentation/kitchen_board.gd`
- Modify: `tests/test_m2_ui.gd`
- Modify: `translations/en.po`

**Interfaces:**

- Consumes: 서비스 스냅샷의 `orders`, `tasks`, `employees`와 새 순간 이벤트.
- Produces: 직원별 현지화 상태, 공정 배지, 한 개의 우선 말풍선.

- [x] **Step 1: 실패 테스트 작성**

  실제 scene에서 재료 수거, 손질, 조리, 제공 이동과 작업 문구를 확인합니다.
  재료 부족과 프렙 소진 이벤트가 한국어 말풍선으로 보이고 4배속에서도 이벤트가 유실되지 않는지 확인합니다.

- [x] **Step 2: RED 확인**

  Run: `bash scripts/check.sh m2`
  Expected: 구체적인 직원 상태 또는 말풍선 표시가 없어서 실패합니다.

- [x] **Step 3: 최소 구현**

  `main.gd`가 현재 주문과 작업에서 직원 활동을 만들고 사건 우선순위와 실제 시간 표시 수명을 관리합니다.
  `kitchen_board.gd`는 메뉴 아이콘, 공정 배지, 주방 안으로 제한한 말풍선을 그립니다.
  영어 번역을 같은 변경에 추가합니다.

- [x] **Step 4: GREEN 확인**

  Run: `bash scripts/check.sh m2`
  Expected: `PASS: m2 checks=<count> failures=0`.

### 작업 4: 마감 화면과 전체 회귀

**Files:**

- Modify: `presentation/main.gd`
- Modify: `tests/test_m2_ui.gd`
- Modify: `translations/en.po`
- Create: `tests/capture_service_feedback.gd`

**Interfaces:**

- Consumes: `ServiceAnalysis.build` 결과.
- Produces: `다음 영업에서 바꿀 것`과 기존 상세 지표를 함께 표시하는 마감 화면.

- [x] **Step 1: 실패 테스트 작성**

  마감 화면이 관찰값과 행동을 표시하고 `hot_queue` 상한 선택에서 불가능한 증가 제안을 하지 않는지 확인합니다.

- [x] **Step 2: RED 확인**

  Run: `bash scripts/check.sh m2`
  Expected: 새 마감 섹션이 없어서 실패합니다.

- [x] **Step 3: 최소 구현**

  `_show_analysis`가 최대 3개 제안을 먼저 현지화하고 기존 누적 시간과 설비별 예약 시간을 상세 근거로 이어서 표시하게 합니다.

- [x] **Step 4: 전체 GREEN 확인**

  Run: `bash scripts/check.sh m2`
  Run: `bash scripts/check.sh m3`
  Run: `bash scripts/check.sh m4`
  Expected: 세 명령 모두 `failures=0`입니다.

- [x] **Step 5: 렌더 검증**

  전용 서비스 피드백 캡처로 한국어·영어, 기본·큰 글자, 휴대폰·태블릿 조합과 `hot_queue` 상한 선택을 생성하고 이미지에서 말풍선, 직원 상태, 마감 분석의 잘림·겹침을 확인합니다.
