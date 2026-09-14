# UI·UX 정보 위계 개선 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.
> The current execution uses the main workspace and does not delegate, commit, push, or perform device actions.

**목표:** 시간, 직원 상태, 마감 행동과 주문 취소의 시각적 피드백을 기존 Godot UI 안에서 명확하게 만듭니다.

**구조:** 기존 `main.gd`가 문구와 글자 위계를 계속 관리하고 `product_theme.tres`가 버튼 상태를 관리합니다.
테스트는 현재 장면을 직접 실행하며, 제품 마감 캡처는 실제 입력 뒤의 렌더 픽셀 차이를 읽습니다.

**기술 스택:** Godot 4.7, typed GDScript, Godot Theme resource, 기존 headless·rendered test harness.

**명세:** `docs/specs/ui-ux-information-hierarchy.md`.

## 전체 제약

- 기존 M0 생명주기 카운터와 고정 tick 동작을 유지합니다.
- 새 의존성과 새 UI 추상화를 추가하지 않습니다.
- 현재 `presentation/` 구조와 현지화 방식을 유지합니다.
- 제품 파일을 수정하기 전에 해당 동작의 실패 테스트를 확인합니다.
- 커밋, push, 기기 설치와 기기 실행은 이번 범위에 포함하지 않습니다.

---

### Task 1: 시간 표기 계약

**Files:**

- Modify: `tests/test_m0.gd`
- Modify: `tests/test_m4_ui.gd`
- Modify: `presentation/main.gd`
- Modify: `translations/en.po`

**Interfaces:**

- Consumes: `KitchenScreen._show_counter()` and the existing `elapsed_seconds` value.
- Produces: `Counter.text` with an explicit elapsed-time label in Korean and English.

- [x] **Step 1: 실패 테스트를 작성합니다.**

  한국어 예상값을 `경과 003.0초`로 바꿉니다.
  M4의 준비·일시정지·마감·영어 부팅 예상값도 각각 `경과` 또는 `Elapsed`를 포함하도록 바꿉니다.

- [x] **Step 2: 실패를 확인합니다.**

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --max-fps 120 --quit-after 600 --script tests/run_tests.gd -- --suite m4
  ```

  예상 결과는 기존 `Counter.text`에 이름이 없어서 시간 표기 assertion이 실패하는 것입니다.

- [x] **Step 3: 최소 구현을 적용합니다.**

  `_show_counter()`가 다음 문구를 사용하게 합니다.

  ```gdscript
  counter.text = tr("경과 %05.1f초") % elapsed_seconds
  ```

  `translations/en.po`에는 다음 번역을 추가합니다.

  ```po
  msgid "경과 %05.1f초"
  msgstr "Elapsed %05.1f s"
  ```

- [x] **Step 4: 대상 테스트를 다시 실행합니다.**

  같은 M4 명령에서 시간 표기 assertion이 통과하는지 확인합니다.

### Task 2: 직원 상태 가독성

**Files:**

- Modify: `tests/test_m2_ui.gd`
- Modify: `tests/test_m4_ui.gd`
- Modify: `presentation/main.gd`
- Modify: `translations/en.po`

**Interfaces:**

- Consumes: the existing `duty_labels: Array[Label]` controls and `AppPreferences.apply_to()` scaling.
- Produces: employee status text at 18 for normal text and 22 for large text.

- [x] **Step 1: 실패 테스트를 작성합니다.**

  M2 UI fixture에서 직원 상태 레이블의 기본 글자 크기가 18인지 확인합니다.
  큰 글씨 설정을 적용한 뒤 같은 레이블의 글자 크기가 22인지 확인합니다.
  상태 문구가 최대 4줄을 허용하고 영어 이동 문구가 좁은 4인 열에 맞게 간결한지 확인합니다.

- [x] **Step 2: 실패를 확인합니다.**

  다음 M2 테스트 명령을 실행합니다.

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --max-fps 120 --quit-after 600 --script tests/run_tests.gd -- --suite m2
  ```

  예상 결과는 현재 기본 크기 13 때문에 새 assertion이 실패하는 것입니다.

- [x] **Step 3: 최소 구현을 적용합니다.**

  직원 상태 레이블의 명시적 기본 글자 크기를 13에서 18로 바꿉니다.
  최대 줄 수를 4로 바꾸고 영어 재료 이동 문구를 `fetching prep`과 `fetching raw`로 줄입니다.

- [x] **Step 4: 대상 테스트를 다시 실행합니다.**

  같은 M2 명령에서 기본·큰 글씨 assertion이 모두 통과하는지 확인합니다.

### Task 3: 마감 행동 위계

**Files:**

- Modify: `tests/test_m2_ui.gd`
- Modify: `presentation/main.gd`

**Interfaces:**

- Consumes: `KitchenScreen._render_analysis()` and the existing analysis metadata.
- Produces: action text with the body font size and `ANALYSIS_HEADING_COLOR`.

- [x] **Step 1: 실패 테스트를 작성합니다.**

  행동 글자 크기가 관찰 본문의 기본 크기 18인지 확인합니다.
  행동 색상이 `Color("eab06c")`인지 확인합니다.

- [x] **Step 2: 실패를 확인합니다.**

  Task 2와 같은 M2 테스트 명령을 실행합니다.
  예상 결과는 현재 행동 크기 15와 색상 `a6b5a8` 때문에 assertion이 실패하는 것입니다.

- [x] **Step 3: 최소 구현을 적용합니다.**

  `action_size`를 `body_size`와 같게 설정합니다.
  행동 문장에는 `ANALYSIS_HEADING_COLOR`를 사용합니다.

- [x] **Step 4: 대상 테스트를 다시 실행합니다.**

  같은 M2 명령에서 위계 assertion과 기존 분석 순서 assertion이 모두 통과하는지 확인합니다.

### Task 4: 주문 취소 눌림 상태

**Files:**

- Modify: `tests/capture_product_polish.gd`
- Modify: `presentation/product_theme.tres`

**Interfaces:**

- Consumes: the existing `DangerButton` theme variation and rendered cancel-button fixture.
- Produces: a pressed style that is visibly different from hover while it retains the warning color.

- [x] **Step 1: 실패하는 렌더 assertion을 작성합니다.**

  취소 hover에서 버튼 내부 픽셀을 저장합니다.
  pressed 상태에서 같은 위치의 픽셀을 읽고 두 색상이 다르다고 확인합니다.

- [x] **Step 2: 실패를 확인합니다.**

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --path . --max-fps 60 --script tests/capture_product_polish.gd
  ```

  예상 결과는 현재 hover와 pressed가 같은 `danger` 스타일을 사용해서 픽셀 차이 assertion이 실패하는 것입니다.

- [x] **Step 3: 최소 구현을 적용합니다.**

  `danger_pressed` StyleBoxFlat을 추가합니다.
  채움은 `Color(0.262745, 0.184314, 0.168627, 1)`을 사용합니다.
  테두리는 2픽셀과 `Color(0.917647, 0.690196, 0.423529, 1)`을 사용합니다.
  `DangerButton`의 pressed와 hover_pressed에 새 스타일을 연결합니다.

- [x] **Step 4: 렌더 테스트를 다시 실행합니다.**

  같은 캡처 명령이 실패 0으로 끝나는지 확인합니다.
  새 취소 hover·pressed 화면을 직접 비교합니다.

### Task 5: 전체 회귀와 기록

**Files:**

- Modify: `docs/notes/ui-ux-information-hierarchy-verification.md`

**Interfaces:**

- Consumes: the implementation diff and all verification output.
- Produces: the current verification record with command scope, result, and remaining evidence gaps.

- [x] **Step 1: 정적 형식과 전체 M4 회귀를 실행합니다.**

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --quit
  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4
  ```

- [x] **Step 2: 영업 피드백 렌더를 실행합니다.**

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --path . --max-fps 60 --script tests/capture_service_feedback.gd -- --hot-queue --large-text
  /Applications/Godot.app/Contents/MacOS/Godot --path . --max-fps 60 --script tests/capture_service_feedback.gd -- --hot-queue --tablet --large-text --locale=en
  ```

- [x] **Step 3: 화면을 직접 읽습니다.**

  휴대폰 한국어와 태블릿 영어 화면에서 시간 이름, 직원 상태, 마감 행동과 버튼 잘림을 확인합니다.
  제품 마감 캡처에서 취소 hover와 pressed의 차이를 확인합니다.

- [x] **Step 4: 검증 노트를 갱신합니다.**

  각 명령이 실제로 읽은 속성과 실패 수를 기록합니다.
  Android 실기기, 실제 태블릿과 보조 기술 검증은 별도 공백으로 유지합니다.
