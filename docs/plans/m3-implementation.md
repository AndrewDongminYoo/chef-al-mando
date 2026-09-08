# M3 구현 계획

목표: [승인된 M3 범위](../specs/m3-campaign.md)에 따라 기존 영업에 고정 캠페인과 완료 기록을 연결합니다.
구조: 정적 시나리오는 `content/`, 진행 판정은 `sim/`, 파일 보존은 `persistence/`, 화면과 입력은 `presentation/`이 소유합니다.
환경: `.godot-version`의 Godot Standard, typed GDScript, Compatibility 렌더러를 유지합니다.
실행: 현재 세션에서 아래 순서로 구현하고 검사합니다.
별도 작업자나 추가 승인 주기를 만들지 않습니다.

## 공통 제약

- 사용자 5명 검증은 운영자의 명시적인 준비 완료 지시까지 보류합니다.
- 시나리오 8개, 메뉴 8종, 주방 3종, 직원 최대 4명, 설비 최대 6개, 전체 재료 정의 최대 12종을 유지합니다.
- tick 100 ms, 마감 tick 3000, 기존 공정·회계·예약 규칙과 M1·M2 fixture를 보존합니다.
- 캠페인 기록만 저장하며 중간 영업 복원은 M4에 남깁니다.
- 새 외부 의존성·콘텐츠 편집기·자동 생성 파이프라인을 추가하지 않습니다.
- 검증 명령에서 `GODOT_BIN`은 `.godot-version`과 같은 엔진의 절대 경로입니다.

## P1. 정적 콘텐츠와 진행 판정

소유 파일은 `content/scenario_def.gd`, `content/campaign_def.gd`, `content/campaign/`, `sim/campaign_progress.gd`, `tests/test_m3.gd`, `tests/test_m3_content.gd`, `tests/test_campaign_progress.gd`, `tests/run_tests.gd`입니다.
`ScenarioDef`는 `Definitions`를 확장하고 `validate(require_stock: bool = true)`와 `order_schedule()`을 제공합니다.
`CampaignDef`는 시나리오 목록을 소유하고 `validate()`와 `scenario_for(id: String)`을 제공합니다.
`CampaignProgress.new(campaign, records)`는 입력 기록을 복사합니다.
`is_unlocked(id)`, `record_result(id, snapshot)`, `snapshot()`으로 진행 상태를 읽고 결과를 반영합니다.

- [x] 없는 M3 suite 실행이 실패하는지 확인합니다.
- [x] 콘텐츠 오류, 목표 직전·동일 경계, 미완료 마감, 중복 완료, 최고 기록 보존의 실패 검사를 작성합니다.
- [x] 새 정적 콘텐츠와 진행 객체를 구현합니다.
- [x] `bash scripts/check.sh m3`으로 위 실패 상태와 정상 상태를 확인합니다.

```gdscript
expect(not progress.is_unlocked("lunch_prep"), "the second service starts locked")
expect(not progress.record_result("first_shift", running).accepted, "a running service cannot record a result")
expect(progress.record_result("first_shift", closed).accepted, "a closed service records its result")
expect(progress.is_unlocked("lunch_prep"), "passing both goals unlocks the next service")
```

## P2. 캠페인 기록 파일

소유 파일은 `persistence/campaign_store.gd`, `tests/test_campaign_store.gd`입니다.
`CampaignStore.new(campaign, file_path)`는 프로젝트 캠페인과 명시적인 파일 경로를 받습니다.
`load_records()`, `save_records(records)`, `recover_backup()`은 성공 상태·이유·기록을 반환합니다.
파일 연산은 좁은 내부 메서드로 두어 테스트가 쓰기·교체 실패를 유발할 수 있게 합니다.
새 저장소 객체가 파일을 다시 읽어 캐시를 검증 결과로 오인하지 않게 합니다.

- [x] 임시 테스트 디렉터리에서 정상 파일을 저장·재로드하고, 손상·미래 버전·잘못된 기록을 주입하는 실패 검사를 작성합니다.
- [x] 임시 파일 검증·정상 백업·교체·명시적 복구를 구현합니다.
- [x] 주 파일 교체 실패 후 정상 백업과 기록을 보존하는지 확인합니다.
- [x] `bash scripts/check.sh m3`에서 모든 파일 실패 변형과 새 객체 재로드를 검사합니다.

```gdscript
expect(store.save_records(records).accepted, "a valid record is saved")
var reopened := CampaignStore.new(campaign, file_path)
expect(reopened.load_records().records == records, "a new store reads the saved bytes")
```

## P3. 실제 시뮬레이션과 콘텐츠 조정

소유 파일은 `tests/test_m3_playthrough.gd`, `tests/fixtures/m3_policies.gd`, `content/campaign/`, `docs/notes/m3-verification.md`입니다.
정책 fixture는 실제 `PreparationPlan` 명령과 tick·sequence가 있는 서비스 명령만 사용합니다.
테스트가 주문 결과나 회계 값을 직접 바꾸어 완주를 만들지 않습니다.

- [x] 모든 영업의 실제 기본 결과를 기록하고 완료 정책을 작성합니다.
- [x] 실제 완주 결과에 따라 기존 콘텐츠 상한 안에서 필요한 구성을 조정하고 근거를 기록합니다.
- [x] 프렙·발주·배치·담당·우선순위의 비교 정책을 실행합니다.
- [x] 여덟 영업의 순차 해금·엔딩과 반복 hash·1배/4배 결과를 검사합니다.

```gdscript
var result := run_policy(scenario, policy)
expect(result.snapshot.closed, "the real service reaches closing")
expect(progress.record_result(scenario.id, result.snapshot).passed, "the reference policy passes the service goals")
```

## P4. 캠페인 화면과 기존 영업 연결

소유 파일은 `presentation/campaign.tscn`, `presentation/campaign_screen.gd`, `presentation/main.gd`, `project.godot`, `tests/harness.gd`, `tests/test_m3_ui.gd`, `tests/capture_m3.gd`입니다.
기존 화면에 선택적인 정의 입력과 `service_closed(snapshot)` 신호를 추가합니다.
캠페인 화면이 정상 마감 신호를 진행 객체와 저장소로 전달합니다.
기존 단독 영업 테스트는 `main.tscn`을 직접 인스턴스화하고, M3 검사는 프로젝트의 실제 진입 장면을 읽습니다.

- [x] 실제 장면에서 잠긴 항목 선택·마감 신호·중복 기록·재도전·다음 영업·복구 안내를 검사하는 실패 테스트를 작성합니다.
- [x] 목록·브리핑·영업·결과·엔딩과 저장 상태 표시를 구현합니다.
- [x] `bash scripts/check.sh m0`, `m1`, `m2`, `m3`을 실행합니다.
- [x] `tests/capture_m3.gd`를 기본·넓은 폰·태블릿 크기로 실행합니다.
- [x] 좌표 검사에 안전 영역 밖으로 옮긴 실패 변형을 적용한 뒤 정상 캡처를 직접 확인합니다.

## P5. export·최종 검토·실행 기록

소유 파일은 `tests/check_export.gd`, `scripts/check-export.sh`, `tests/test_export_check.py`, `.github/workflows/check.yml`, `README.md`, `docs/notes/m3-verification.md`, `cspell.config.yaml`, `.cspell/cucciolo-dictionary.txt`입니다.
기존 세 export 완료 표시는 보존하고 M3 진입 장면·콘텐츠·첫 주문 완료 표시를 추가합니다.

- [x] Python fake engine에도 신규 필수 표시를 반영하고, 표시가 누락되면 실패하는 검사를 확인합니다.
- [x] 실제 새 pack에서 M1·M2와 M3 프로젝트 진입 경로를 실행합니다.
- [x] 변경 파일에 Trunk·CSpell과 `git diff --check`를 실행합니다.
- [x] 큰 변경 범위의 독립 코드 검토와 반대 관점 교차 검토를 수행하고 유효한 발견 사항을 수정합니다.
- [x] 현재 소스·실행 명령·결과·사용자 검증 보류·실기기 한계를 실행 기록에 남깁니다.

```bash
bash scripts/check.sh m3
python3 tests/test_export_check.py
bash scripts/check-export.sh
git diff --check
```
