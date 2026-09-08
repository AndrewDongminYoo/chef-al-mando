# M4 서브에이전트 TDD 구현 계획

명세: [M4 모바일 제품화](../specs/m4-mobile.md).
기준: `7cb8f79d540dd70334e11e3d9bed363a4b68caaa`, `feat/m4-mobile`, [개인 저장소](https://github.com/AndrewDongminYoo/chef-al-mando).
루트는 명세·파일 소유권·staging·커밋·최종 검증·PR·머지를 소유합니다.
작업자는 지정된 파일만 수정하고, 실패 테스트·통과 테스트·자체 검토를 기록합니다.
작업자는 추가 에이전트를 만들거나 Git·기기·외부 상태를 변경하지 않습니다.
각 작업은 독립적인 명세·품질 검토를 받은 뒤 다음 작업으로 넘어갑니다.

## Global Constraints

- Keep the 100 ms tick, closing tick 3000, existing rules, stable IDs, and content counts.
- Use typed GDScript and the pinned Godot engine with the Compatibility renderer.
- Keep simulation outcomes in `sim/`, file validation and replacement in `persistence/`, and display and audio in `presentation/`.
- Write a behavioral test and observe its intended failure before production code.
- Preserve unrelated work. Do not stage, commit, push, merge, delete worktrees, write to devices, or spawn agents as an implementation worker.
- Use only the personal repository and account. Do not read work-account sources.
- Do not add dependencies, a generic persistence framework, a new PRNG, or online services.
- Report actual commands and results. Headless checks do not prove rendered or physical-device acceptance.

## Task 1: 복원 가능한 simulation과 세션

소유 파일은 `sim/service_sim.gd`, 새 `persistence/service_session.gd`, `tests/test_m4.gd`, `tests/test_m4_determinism.gd`, `tests/test_service_session.gd`, `tests/run_tests.gd`와 새 GDScript의 `.uid`입니다.
기존 `PreparationPlan`을 읽고 재사용하되 소유하지 않은 파일을 수정하지 않습니다.
`ServiceSim.export_state() -> Dictionary`와 `static restore(data: Definitions, state: Dictionary, preparation: Dictionary = {}) -> Dictionary`를 추가합니다.
`ServiceSession.capture(scenario_id: String, selection: Dictionary, simulation: ServiceSim, speed: int = 1, accumulator_us: int = 0) -> Dictionary`와 `static restore(campaign: CampaignDef, session: Dictionary, records: Dictionary) -> Dictionary`를 제공합니다.
세션 키는 `scenario_id`, `preparation`, `simulation`, `speed`, `accumulator_us`입니다.
복원 성공은 `simulation`, `definitions`, `selection`, `scenario_id`, `speed`, `accumulator_us`를 함께 반환합니다.
파일 JSON의 정확한 정수 변환은 ServiceSession 경계에서 처리합니다.
simulation의 일회성 이벤트와 오류, 표시 이름, 파생 회계는 복원 입력으로 신뢰하지 않습니다.

- M4 runner를 등록하고 실제 준비·영업 객체로 실패 테스트를 만듭니다.
- 명세 M4-01·02를 구현합니다. 이동·작업·보류 담당·보류 명령·프렙과 변경 배치·마감 경계에서 즉시와 최종 hash를 비교합니다.
- 필수 `prng_state: null`, 정수·ID·enum·예약·소비식·작업 연결·경로·sequence 변조를 거부합니다.
- JSON 왕복과 읽기 전용 깊은 복사, 실패 시 기존 객체 불변도 확인합니다.
- 최소 검증: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4`; 완료 전에 M1·M2·M3 회귀를 한 번 실행합니다.
- RED/GREEN 로그는 `build/check/m4-task1-*.log`, 전체 보고는 지정된 scratch report에 남깁니다.

## Task 2: 캠페인 파일의 원자적 세션 저장

소유 파일은 `persistence/campaign_store.gd`, 새 `tests/test_m4_store.gd`, `tests/test_m4.gd`와 새 `.uid`입니다.
Task 1의 `ServiceSession.restore()`를 사용합니다.
`load_records()` 성공 결과에 `active_session`을 포함합니다.
`save_records(records)`는 기존 session을 유지합니다.
`save_active_session(session: Variant, records: Dictionary)`는 session 또는 null과 기록을 한 번에 저장합니다.
`clear_active_session()`은 디스크의 유효한 기록을 보존하고 session만 null로 만듭니다.
schema 2의 정확한 키는 `schema_version`, `content_version`, `sim_version`, `records`, `active_session`입니다.
M3 schema 1은 읽기만으로 변경하지 않으며 성공한 다음 쓰기에서만 승격합니다.
기존 파일 쓰기·검증·백업·교체 메서드를 확장하며 두 번째 파일 권위나 범용 추상화를 만들지 않습니다.

- 명세 M4-03·04의 실제 파일 실패 테스트를 먼저 작성합니다.
- schema 1 무변경 읽기와 마이그레이션, records-only 쓰기의 session 보존, 명시적 clear를 검사합니다.
- write·검증·backup replace·primary replace 실패, 손상·누락·미래 버전과 복구를 새 객체로 읽습니다.
- 실제 미래 버전의 primary와 backup 각각을 모든 쓰기 API와 복구 API에서 보호합니다.
- 기존 M3 파일 테스트는 약화하지 않습니다.
- 최소 검증: M4 suite와 M3 suite; RED/GREEN 로그는 `build/check/m4-task2-*.log`입니다.

## Task 3: 설정·번역·제품 효과음 기반

소유 파일은 새 `persistence/settings_store.gd`, `presentation/app_preferences.gd`, `presentation/audio_feedback.gd`, `translations/en.po`, `assets/audio/`, `scripts/generate-audio.py`, `tests/test_m4_preferences.gd`, `tests/test_m4_audio.gd`, `tests/test_m4.gd`, `project.godot`과 새 `.uid`입니다.
기존 presentation 화면과 content Resource는 아직 수정하지 않습니다.
`SettingsStore.new(target)`의 `load_settings()`·`save_settings(values)`를 제공합니다.
값은 `locale: ko|en`, `sound_enabled: bool`, `text_size: normal|large`이며 기본은 ko·true·normal입니다.
`AppPreferences`는 설정 저장소와 현재 값을 소유하고, `load_settings()`, `update_settings(changes)`, `snapshot()`, `font_size(base: int)`와 `apply_to(root: Control)`을 제공합니다.
파일 경로를 생성자로 주입하고 설정 변경 결과는 accepted·reason으로 반환합니다.
성공한 설정 변경 뒤 `changed` 신호를 emit합니다.
적용은 Godot TranslationServer와 실제 font size를 사용하며 Control 자체를 scale하지 않습니다.
런타임 생성 Control과 정적 override를 모두 처리하고 반복 적용으로 font size가 누적 증가하지 않게 합니다.
translation catalog는 기존 한국어 원문을 유지하며 영어를 실제 사용자 문구로 작성합니다.
Task 4가 새 UI 원문과 호출부를 추가할 수 있도록 이 파일의 후속 소유권을 넘깁니다.

`AudioFeedback`은 Node이며 `play_cue(kind)`, `set_enabled(value)`, `suspend()`, `resume()`을 제공합니다.
cue ID는 `arrival`, `served`, `warning`이며 원본 PCM WAV 세 개를 프로젝트의 표준 라이브러리 생성 소스로 만듭니다.
Player 재생을 직접 중단하고, resume은 과거 cue를 다시 재생하지 않고 향후 cue만 허용합니다.
경고 반복은 실제 시간 1초 이상 간격으로 제한합니다.
외부 음원·음성·배경 음악은 추가하지 않습니다.

- 설정 저장·새 객체 로드·잘못된 값·쓰기 실패·미래 버전 거부와 font size 반복 적용의 실패 테스트를 먼저 작성합니다.
- 독립 기대 문구로 native translation 동작을 검사합니다. 키 존재만으로 번역 품질을 주장하지 않습니다.
- 실제 AudioStreamPlayer의 cue·음소거·중단·복귀 비재생을 검사합니다.
- 최소 검증: M4 suite와 M3 suite; 로그는 `build/check/m4-task3-*.log`입니다.

## Task 4: 실제 화면의 이어하기·설정·현지화

소유 파일은 `presentation/campaign_screen.gd`, `presentation/main.gd`, `presentation/preparation_panel.gd`, `presentation/kitchen_board.gd`, `presentation/campaign.tscn`, `presentation/main.tscn`, `translations/en.po`, 새 `tests/test_m4_ui.gd`, `tests/capture_m4.gd`, `tests/test_m4.gd`와 새 `.uid`입니다.
필요한 작은 연동 결함은 먼저 루트에 경계와 근거를 보고하고 소유권을 확인합니다.
Task 1~3의 API를 재사용합니다.
CampaignScreen의 `save_path` 주입은 유지하고 `settings_path`도 주입할 수 있게 합니다.
테스트는 각 fixture의 임시 파일을 사용하고 종료 시 TranslationServer locale을 ko로 복구합니다.

- 명세 M4-06~09의 실제 장면 테스트를 먼저 추가합니다.
- 준비 완료, 100 tick 간격의 프레임 종료 경계, pause/background/menu/closing의 단일 파일 저장을 연결합니다.
- 목록의 이어하기는 새 simulation·driver·화면에서 paused 상태로 복원합니다.
- 진행 중 영업이 있을 때 다른 영업으로 대체하기는 명시적 확인을 받습니다.
- 저장 실패 시 현재 세션·결과와 retry 경로를 유지하며, M3 PR #6의 navigation 보호를 회귀시키지 않습니다.
- 설정은 캠페인·영업 양쪽에서 열고, locale·text size 변경을 기존 상태를 보존한 채 모든 표시 문자열과 동적 Control에 적용합니다.
- 영업 효과음은 실제 새 이벤트에 연결하고 focus/background에서 정지하며 foreground만으로 재생·영업을 재개하지 않습니다.
- 폰의 접이식 상세와 태블릿 병렬 상세를 유지하고 캠페인·브리핑·설정을 두 크기에서 사용할 수 있게 합니다.
- `capture_m4.gd`는 `--locale=ko|en`, 선택적 `--large-text`, `--phone-wide|--tablet`, negative-layout/input을 지원합니다.
- 각 조합에서 설정 입력, 실제 영업과 중간 저장, 새 화면의 이어하기, 언어별 오류·결과, 안전 영역·큰 글자·중요 문구를 검증하고 캡처합니다.
- 최소 검증: M0~M4 suite와 렌더링 ko/en 대표 조합; 루트가 여덟 조합 최종 실행을 직렬로 소유합니다.
- RED/GREEN 로그는 `build/check/m4-task4-*.log`입니다.

## Task 5: 새 프로세스·export·CI 수용 증거

소유 파일은 새 `tests/test_m4_restart.py`, `tests/check_m4_restart.gd`, `tests/check_export.gd`, `tests/test_export_check.py`, `scripts/check-export.sh`, `.github/workflows/check.yml`과 새 `.uid`입니다.
새 프로세스 테스트는 프로젝트 전용 임시 디렉터리와 정확히 소유한 Godot 자식 PID만 사용합니다.
writer가 실제 이동·작업 상태를 쓰고 완료 marker를 낸 뒤 그 프로세스를 강제 종료하고, 새 reader가 저장 상태와 설정을 읽어 같은 최종 hash를 확인합니다.
주 파일 교체 직전 중단은 기존 정상 primary 또는 backup만 복구되며 불완전한 tmp를 채택하지 않아야 합니다.
타임아웃·없는 fixture·없는 완료 marker는 비정상 종료입니다.
모바일 실기기를 호출하거나 테스트를 위해 종료하지 않습니다.

- 프로세스 fixture가 빠지거나 완료 marker가 없을 때 실패하는 것을 먼저 확인합니다.
- M4 suite와 restart 검사를 CI에 추가합니다.
- 새 PCK에서 M4 session 저장·복원과 영어 표시를 실행하고 `PASS: exported M4 resume and localization`을 필수 marker로 추가합니다.
- 기존 M1·M2·M3 marker를 보존하고 Python fake engine 검사에서 신규 marker 누락도 실패시킵니다.
- 최소 검증: `python3 tests/test_m4_restart.py`, `python3 tests/test_export_check.py`, `bash scripts/check-export.sh`입니다.

## 최종 통합과 전달

루트가 README·PLAN의 현재 구현 링크, AGENTS의 실행 기준, `docs/notes/m4-verification.md`를 실제 결과에 맞게 갱신합니다.
원본 iPhone 빌드, 실기기·사용자 검증 보류, 실제 실행하지 않은 조건을 구분합니다.
전체 diff는 simulation/persistence와 presentation/platform으로 나눠 독립 검토하고 반대 관점의 최종 교차 검토를 받습니다.
모든 유효한 차단 사항을 TDD로 수정한 뒤 현재 head에서 로컬 gate와 hosted CI·코드/보안 리뷰·미해결 thread 0건을 확인합니다.
호스팅 리뷰 예산은 공개 저장소에 대한 운영자 제공 `pr-loop` 기본값에 따라 첫 trigger부터 5시간·최대 5회입니다.
허용된 squash merge 후 실제 MERGED와 merge SHA를 다시 조회합니다.
브랜치·worktree는 삭제하지 않습니다.
