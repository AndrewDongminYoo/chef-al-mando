# M4 모바일 제품화 검증 기록

<!-- cspell:ignore msgfmt -->

- 기준일: 2026-09-09
- 상태: 구현·로컬 검사 완료, 전체 M4 실기기 수용 보류
- 실행 계약: [M4 명세](../specs/m4-mobile.md)
- 시작 소스: M3 PR #6 머지 커밋 `7cb8f79d540dd70334e11e3d9bed363a4b68caaa`

## 범위와 판정 경계

운영자는 PR #6 머지 후 다음 마일스톤을 서브에이전트 TDD와 PR loop로 진행하도록 요청했습니다.
이번 범위는 M4 구현, 로컬 검증, 커밋, 푸시, PR 리뷰 대응과 조건 충족 후 머지입니다.
기기 설치·삭제·강제 종료, 스토어 배포, 사용자 모집과 브랜치·worktree 삭제는 수행 범위에 포함하지 않습니다.

아래 결과는 각 검사가 실제로 읽은 속성만 증명합니다.
데스크톱 생명주기 알림과 별도 프로세스 종료 검사는 iOS·Android의 OS 동작을 증명하지 않습니다.
전체 M4 실기기 수용과 사용자 5명 검증은 보류 상태입니다.
기본 증거는 PR 생성 전의 로컬 검증 기록이며, 후속 리뷰 재현은 아래에 구분해 기록합니다.
호스팅 CI와 리뷰의 최종 판정은 PR의 해당 head에서 별도로 확인합니다.

## 단계별 증거

| 단계             | 보호할 속성                                                                       | 현재 증거                                                    |
| ---------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| 상태 복원        | 실제 이동·작업·보류 명령·소비·예약 상태를 복원한 직후와 마감 hash가 같음          | M4 상태 검증 및 결정론 테스트, simulation·session 리뷰 승인  |
| 단일 파일 저장   | 완료 기록과 active session의 원자적 교체, schema 1 무변경 읽기, 실패 후 보존·복구 | M4 저장소 테스트, store·fixture 리뷰 승인                    |
| 설정·효과음 기반 | 새 파일 reader의 설정 복원, 실제 locale 반영, font size, 실제 플레이어 정지       | M4 395건·실패 0건, M3 608건·실패 0건, 설정·오디오 리뷰 승인  |
| 실제 화면 연동   | 저장·이어하기·재시도·설정·현지화 입력과 상태 보존                                 | M4 479건·실패 0건, M3 608건·실패 0건, UI 리뷰 승인           |
| 렌더링           | 두 언어·두 글자 크기·폰/태블릿의 실제 조작·안전 영역·문구                         | 여덟 조합 통과, 펼친 메뉴 이미지 직접 확인                   |
| 새 프로세스      | 저장한 자식 프로세스 종료 후 새 reader의 상태·설정 복원                           | Python 검사 6건·실패 0건                                     |
| 배포 팩          | 새 PCK 안의 세션 저장·복원과 영어 표시                                            | M1–M4 필수 완료 표시 다섯 개 확인, fake engine 검사 8건 통과 |
| 호스팅           | 현재 PR head의 CI·코드 리뷰·보안 리뷰                                             | PR 생성 전                                                   |

설정·효과음 기반의 소스는 `4b97ccebdfb724d2851cf60b03901a3169102b0d`입니다.
해당 단계의 최신 M4 근거는 `build/check/m4-task3-correction2-green.log`이며, locale 회귀를 포함한 M3 근거는 `build/check/m4-task3-correction-m3.log`입니다.
이 결과를 이후 화면 변경의 최종 검사로 재사용하지 않습니다.

## 실패를 확인한 검사

저장소 교체 fixture는 tick 1과 tick 2의 서로 다른 simulation hash를 먼저 확인합니다.
새 설정만 바꾸고 이전 simulation을 저장하는 임시 변형은 원자적 저장 1건과 재시도 4건을 실패시켰습니다.
해당 변형을 제거한 뒤 M4 347건, 실패 0건을 확인했습니다.
근거는 `build/check/m4-task2-state-update-red.log`와 `m4-task2-state-update-green.log`입니다.

설정 검사는 잘못된 `StringName` 값의 저장을 거부하고 기존 파일 바이트가 유지되는지 확인합니다.
테마 fixture는 Label 13과 Button 17의 실제 기본 크기를 먼저 확인한 뒤 큰 글자 16과 21, 기본 크기 복원을 검사합니다.
기본값 로드, 설정 변경, 실제 저장 파일을 읽는 새 AppPreferences 객체가 locale을 적용하는지도 각각 확인합니다.
locale 적용을 임시 제거했을 때 실제 assertion이 실패했고 원래 소스를 복원했습니다.
근거는 `build/check/m4-task3-correction-red-fixtures.log`, `m4-task3-correction-red-locale.log`, `m4-task3-correction2-red-locale.log`입니다.

효과음은 `scripts/generate-audio.py`에서 생성하는 프로젝트 원본 WAV 세 개입니다.
생성기는 외부 음원이나 네트워크를 사용하지 않습니다.
임시 디렉터리에서 다시 생성한 파일과 저장소의 파일이 바이트 단위로 일치했습니다.
바이트 하나를 바꾼 입력으로 비교 검사가 실패하는 것도 먼저 확인했습니다.
PCM 검사는 잘못된 WAV 입력을 먼저 거부한 뒤 세 파일의 mono·16-bit·44,100 Hz 형식을 확인했습니다.
실제 오디오 플레이어 검사는 음소거·중단 직후 정지와 복귀 시 과거 cue 비재생을 확인합니다.
마지막 짧은 cue가 끝나기 전에 엔진을 종료할 때 발생한 비동기 리소스 정리 진단은 테스트의 실제 시간 대기 후 사라졌습니다.
이 검사는 스피커의 음질이나 모바일 OS 중단 수용을 증명하지 않습니다.

전체 코드 리뷰에서 실행 중 저장 실패 대화상자 뒤로 영업이 계속되는 결함을 확인했습니다.
실제 process loop를 켠 준비 시작·자동 저장 fixture는 수정 전 시간 진행, 재시도 후 자동 실행 등 8개 assertion을 실패시켰습니다.
수정 후 M4 476건·실패 0건이며, tick 보존·실제 arrival player 정지·저장 재시도 후 일시정지 유지·명시적 재개를 확인했습니다.
근거는 `build/check/m4-save-failure-pause-red.log`와 `build/check/m4-save-failure-pause-green.log`입니다.
이 결과는 해당 수정 시점의 증거이며 이후 설정 메뉴와 저장 상태 관계 수정의 최종 검사는 별도로 기록합니다.

전체 저장 상태 리뷰에서 작업 시각과 직원 담당의 관계 검증을 보완했습니다.
일반 재료의 첫·후속 공정과 준비 재료의 후속 공정에서 시작·완료 시각을 함께 1 tick 앞당기면, 실제 누적 작업 시간과 맞지 않아 거부합니다.
이동 중 담당 off와 작업 중 잘못된 조리 담당도 거부하며, 실제 담당 변경 명령의 pending_duty는 정상 복원하고 같은 마감 hash를 유지합니다.
손상·미래 버전 설정 파일의 실패 로드는 원래 실패 결과·기본 설정·파일 바이트를 유지하면서 실제 TranslationServer locale을 ko로 맞춥니다.
근거는 `build/check/m4-core-red-working-time.log`, `m4-core-red-active-duty.log`, `m4-core-red-failed-load-locale.log`와 각각의 GREEN 로그입니다.
초기 담당 검사 로그에는 마감 hash assertion을 tick마다 반복한 탓에 검사 수가 부풀려졌으며, 최종 소스는 마감 후 한 번만 비교합니다.
`build/check/m4-core-final.log`의 최종 M4는 535건·실패 0건입니다.
같은 수정 이후의 헤드리스 회귀는 M0 25건, M1 177건, M2 378건, M3 608건이며 모두 실패 0건입니다.
M0 근거는 `build/check/m4-root-final-m0.log`, M1–M3 근거는 `build/check/m4-core-regression-m1.log`부터 `m4-core-regression-m3.log`입니다.

## 새 프로세스와 배포 팩

`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/test_m4_restart.py`는 6건·실패 0건이며 1.779초에 완료했습니다.
근거는 `build/check/m4-task5-restart-final.log`입니다.
writer는 부분 이동 tick 10과 작업 중 tick 15를 각각 실제 파일에 저장하고 새 저장소 객체로 읽은 hash를 확인합니다.
완료 marker 뒤 소유한 자식 프로세스에만 `kill()`을 호출하고, 새 reader가 두 세션의 복원 직후·마감 hash를 비교합니다.
새 AppPreferences 객체는 실제 설정 파일의 `en`, `false`, `large`와 TranslationServer locale을 읽습니다.

작업 상태 fixture의 저장 hash가 없는 초기 marker는 계약 검사에서 실패했습니다.
이 결과와 별도로 reader의 작업 hash 비교를 제거하고 기대 hash를 바꾸자, 잘못된 reader 성공을 negative test가 검출했습니다.
비교를 복원한 뒤에는 `FAIL: fresh reader hash differs immediately after restoration`을 확인하는 검사가 통과했습니다.
따라서 없는 marker와 문법 오류만을 상태 복원 검사의 실패 근거로 사용하지 않습니다.

교체 중단 fixture는 실제 CampaignStore의 임시 파일 검증·백업 작성 뒤 `_replace_file`의 주 파일 교체 직전에서 멈춥니다.
해당 writer를 강제 종료한 후 새 reader가 기존 primary와 backup의 정상 세션 hash를 각각 확인합니다.
불완전한 `.tmp` 파일을 정상 저장으로 채택하지 않는지 확인하고, 명시적 백업 복구 뒤 원래 세션 hash를 다시 읽습니다.
없는 fixture·없는 완료 marker·시간 초과도 성공으로 처리하지 않습니다.

`python3 tests/test_export_check.py`는 fake engine의 M4 완료 표시 누락을 수정 전에 실패시켰고, 수정 후 8건·실패 0건을 기록했습니다.
실제 `bash scripts/check-export.sh`는 새 PCK에서 M1–M3 검사와 M4 tick 100 저장·목록 이동·이어하기를 실행했습니다.
이어하기 뒤 일시정지 상태, `Chef al Mando · Service list`, `Continue`, `Paused`의 영어 문구를 Control에서 읽었습니다.
원본은 `build/check/export.log`와 `build/check/export-runtime.log`이며, 필수 완료 표시 다섯 개와 오류 없는 종료를 확인했습니다.
테스트 전용 임시 설정 파일에서 효과음을 끄므로 실제 앱 설정을 읽거나 바꾸지 않습니다.
같은 단계의 `bash scripts/check.sh m4`는 535건·실패 0건이며 원본은 `build/check/m4.log`입니다.

CI에는 M4 suite, 새 프로세스 검사, export 실패 처리, M1–M4 PCK 검사를 순서대로 연결했습니다.
이 문서의 로컬 실행 결과는 호스팅 CI 결과를 대신하지 않습니다.

## PR 리뷰의 예약 수량 재현

PR #7의 `588413b` 코드 리뷰는 예약 수량이 문자열일 때 검증 전 합산으로 스크립트 오류가 발생할 수 있다고 지적했습니다.
해당 소스의 `_order_restore_error()`는 합산 전에 예약 사전 전체를 레시피의 기대 입력과 비교합니다.
실제 이동·예약 상태에 JSON으로 읽은 `{"vegetable":"x"}`를 넣은 직접 복원은 `invalid_reservation`을 반환했습니다.
실제 CampaignStore 파일도 스크립트 오류 없이 `corrupt_records`, `can_recover: true`를 반환하고 원본·백업 바이트를 보존했습니다.
명시적 복구는 `recovered`를 반환하며 원래 세션 hash를 복원했습니다.
같은 거부 검사에 정상 정수 수량을 넣은 음성 대조는 의도한 단언 한 건만 실패했습니다.
생산 소스를 바꾸지 않고 직접 복원·실제 파일 복구의 회귀 테스트를 추가했으며, 최종 M4는 548건·실패 0건입니다.
근거는 `build/check/m4-hosted-reserved-input-final.log`와 `m4-hosted-reserved-input-negative-control.log`입니다.
이 재현에 따라 해당 지적은 기존 검증에서 처리되는 오탐으로 판정했습니다.

## PR 후속 리뷰의 초기 직원과 마감 효과음

`3d27d6a` 후속 리뷰에서 tick 0 직원 상태와 마감 후 효과음 중단의 결함 두 건을 재현했습니다.
준비에서 `cold`·`hot` 담당을 정한 영업의 초기 저장을 다른 이동 가능 위치나 다른 유효 담당으로 바꾸면, 수정 전에는 두 입력 모두 복원됐습니다.
수정 후에는 준비 상태로 생성한 simulation의 초기 직원 정보와 비교해 거부합니다.
정상적인 사용자 지정 담당은 복원 직후·마감 hash를 보존하며, 실제 tick 1 담당 변경과 이후 이동 진행은 계속 복원됩니다.

마감 효과음 fixture는 한 번의 실제 `advance(300.0)`으로 영업을 마치고 제공 이벤트의 AudioStreamPlayer가 재생 중임을 먼저 확인합니다.
수정 전에는 백그라운드와 복귀 뒤 정지 단언 두 건이 실패했습니다.
수정 후에는 상태 분기 전에 효과음을 중단하고, 명시적 시작 때 새 효과음의 재생을 다시 허용합니다.
준비 화면의 백그라운드 왕복은 시간·저장을 진행하지 않으며, 이후 시작하면 실제 다음 주문 효과음이 재생됩니다.
마감 상태의 중단·복귀도 tick과 기존 checkpoint 동작을 유지합니다.

실패 근거는 `build/check/m4-round2-red-tick-zero.log`와 `m4-round2-red-closed-audio.log`이며 각각 의도한 단언 두 건이 실패했습니다.
수정 후 `build/check/m4-round2-green.log`는 M4 569건·실패 0건, `m4-round2-regression-m3.log`는 M3 608건·실패 0건입니다.
두 최종 로그에는 스크립트 오류가 없으며, 모두 헤드리스로 실행했습니다.

## PR 후속 리뷰의 언어 변경 갱신

`0765c40` 리뷰에서 시간 표시 캐시와 접이식 상세 버튼이 언어 변경 직후 이전 문구를 유지하는 결함을 확인했습니다.
READY·PAUSED·CLOSED에서 시간이 멈춘 상태로 한국어→영어→한국어를 전환하고 실제 Label의 정확한 문구를 읽습니다.
휴대폰 상세 버튼은 실행 후 일시정지한 실제 화면에서 접힘·펼침 각각의 번역을 확인합니다.
수정 전 시간 문구 6건과 상세 버튼 문구 2건이 실패했으며, 시뮬레이션 상태·tick·명령·패널 표시 보존 검사는 통과했습니다.

번역 갱신 때 시간 표시 캐시를 무효화하고 화면 갱신 뒤 상세 버튼 문구를 다시 설정하도록 두 줄을 추가했습니다.
별도 저장 파일에 영어 설정을 쓴 뒤 전역 locale을 한국어로 돌리고 새 캠페인을 열어 실제 파일 로드와 시작 직후 영어 시간 문구도 확인했습니다.
이 시작 경로는 수정 전에도 통과했으므로 같은 결함으로 분류하지 않습니다.

근거는 `build/check/m4-round4-localization-red.log`의 M4 602건·실패 8건과 `m4-round4-localization-green.log`의 M4 602건·실패 0건입니다.
`build/check/m4-round4-localization-m3.log`의 M3 608건도 실패 없이 통과했습니다.
모두 헤드리스 검사이며 새로운 렌더링 증거를 추가하지 않습니다.

## 렌더링 증거와 헤드리스 실행 경계

최종 capture 소스는 `a21224f`이며 SHA-256은 `5ff4f0f525a225cddfe1106204792d1a7455ff5ae717f0a714e38f91d5be6238`입니다.
`build/check/m4-task4-final-render-matrix.log`와 각 `m4-root-render-*.log`에서 한국어·영어, 기본·큰 글자, 휴대폰·태블릿의 여덟 조합을 확인했습니다.
기본 글자 네 조합은 각각 130건, 큰 글자 네 조합은 각각 144건이며 실패는 없습니다.
한국어 큰 글자 휴대폰, 영어 큰 글자 휴대폰, 영어 기본 글자 태블릿 실행의 펼친 메뉴 PNG를 직접 읽어 실제 항목이 그려졌는지 확인했습니다.
기본 글자 popup PNG는 첫 언어 전환 중에 찍히므로 파일명의 locale만으로 해당 순간의 언어를 판단하지 않습니다.
최종 locale은 별도 설정 상태·저장 파일·문구 assertion이 검사합니다.

최종 입력은 한 번의 native picker 동작과 popup 열림·닫힘 횟수를 확인합니다.
언어·글자 크기 입력은 효과음을 바꾸지 않고, 사운드 두 번 탭은 false와 true로 각각 한 번만 전환되며 실제 저장 파일도 같은 값을 갖습니다.
동기 강제 draw는 오래된 텍스처를 반환해 폐기했고, 최종 캡처는 실제 frame_post_draw 뒤 이미지를 읽습니다.
레이아웃과 popup theme 제거 검사는 각각 의도한 속성에서 실패했습니다.
잘못된 입력 좌표 검사에는 의도한 viewport 실패와 환경의 focus 사전조건 실패가 함께 있어, 독립된 입력 실패만을 검출한 증거로 취급하지 않습니다.

운영자는 화면을 띄우는 검사가 다른 작업을 방해한다고 알리고 헤드리스 실행을 요청했습니다.
해당 시점에 실행 중인 Godot 프로세스가 없음을 확인했고 추가 창 실행을 중단했습니다.
이후 시뮬레이션·저장·설정·새 프로세스·배포 팩은 --headless로만 검사합니다.
추가 화면 캡처와 포커스 변경은 운영자의 별도 요청 전까지 보류합니다.
헤드리스 성공을 새로운 렌더링 증거로 대신하지 않습니다.

## 도구 진단

설정 기반 단계의 CSpell은 122개 파일에서 문제 0건, Trunk는 지정한 변경 파일 3개에서 문제 0건을 기록했습니다.
Trunk formatter와 커밋 hook은 해당 경로에 적용할 linter가 없다고 보고했습니다.
`git diff --check`와 실제 커밋 hook을 통과했습니다.
PO 중복 항목을 제거한 뒤 `msgfmt --check --output-file=/dev/null translations/en.po`는 종료 코드 0이며 선택적 헤더 누락 경고만 남았습니다.

M4 실행 기준을 AGENTS에 연결한 뒤 `codex doctor --summary --ascii --no-color`를 실행했습니다.
이 명령은 Codex 환경의 advisory 진단이며 게임 동작을 검사하지 않습니다.
결과는 경고 1건, 실패 0건, note 3건이며 원본은 `build/check/m4-codex-doctor.log`입니다.
update 구성의 경고가 남아 있으므로 종료 코드 0을 무경고 상태로 해석하지 않습니다.
최종 단계에서 같은 명령을 다시 실행한 결과는 경고 0건, 실패 0건, note 2건입니다.
이 최신 결과는 앞선 진단과 구분합니다.

최종 CSpell은 파일 127개를 검사하고 5개를 건너뛰었으며 문제 0건입니다.
Trunk는 지정한 테스트·스크립트·CI 파일 7개와 문서 5개에서 문제 0건을 보고했습니다.
각 검사의 소스 범위와 역할을 넘어 실기기 수용을 증명하지 않습니다.

Godot import 중 `cannot connect to daemon at tcp:5037: Connection refused` 진단이 계속 출력됐습니다.
최종 headless 실행은 필수 PASS marker와 오류 없는 종료를 확인했습니다.
이 진단 때문에 Android 환경이나 기기를 변경하지 않았으며, Android 수용 통과로 기록하지 않습니다.

## 실기기와 이전 설치본

이번 M4 작업에서는 iPhone이나 Android에 앱을 설치하지 않았습니다.
[M3 설치 기록](m3-verification.md)에 따르면 마지막으로 설치한 iPhone 앱은 `850b3fd15b0e2b6910875377c6ecb679a948eb5b` 기반이며, 이후 PR #6의 저장 실패 회귀 수정은 재설치하지 않았습니다.
이 절은 기존 기록을 인용하며 이번 작업에서 기기 상태를 다시 조회했다는 뜻이 아닙니다.

남은 실기기 검사는 저장 후 앱 종료·이어하기, 통화·알림·권한창 중단 후 수동 재개, 두 언어·글자 크기·안전 영역입니다.
사용자 5명 검증은 운영자의 명시적 재개 지시까지 보류합니다.

## 선례와 구현 결정

Oracle의 관련 전역 선례는 `raw/sources/.claude/rules/evidence-basis-discipline.md`이며 대응 페이지는 `wiki/sources/claude--rules--evidence-basis-discipline.md`입니다.
번역 키의 값이나 캐시 재조회만으로 실제 문구·렌더링·영속 저장을 증명할 수 없다는 선례를 반영해, 독립 기대 문구와 새 reader·새 실행·렌더링을 분리했습니다.
Oracle sourceCommit은 `7049be0f6c7cefadb3d3d24a51ac74aa66e48824`이며 현재 wiki revision과의 일치는 미검증입니다.
중간 영업 복원에 직접 적용할 프로젝트 선례는 `[no precedent found]`입니다.

기록과 active session은 schema 2의 단일 CampaignStore 파일에 저장합니다.
이는 두 파일 사이의 교체·복구 규칙을 추가하지 않기 위한 결정이며, 잘못된 호환성 가정이 발견되면 migration 경계를 다시 검증해야 합니다.
현재 주문 일정에는 가변 PRNG가 없으므로 필수 `prng_state`는 `null`입니다.
실제 PRNG가 도입되면 상태와 sim version을 함께 변경해야 합니다.
