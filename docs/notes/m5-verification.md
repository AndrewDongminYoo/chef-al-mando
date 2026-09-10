# M5 로컬 출시 준비 검증

검증일: 2026-09-09.
기준은 [M5 명세](../specs/m5-release-candidate.md)입니다.
소스는 M4 머지 커밋 `02e3c38216159fadc06c64aaf117a9e76271f80d` 위의 `feat/m5-release-preparation` 변경입니다.
이 기록은 로컬 준비 결과이며 M5 전체 통과가 아닙니다.
1~6절은 M5 최초 구현과 PR 리뷰 당시의 근거입니다.
현재 메뉴별 기본 우선순위 후보의 추가 검증은 7절에 기록합니다.

## 1. 완료한 로컬 검사

| 검사                                                     | 직접 읽은 속성                                                                   | 결과                                 |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------ |
| `bash scripts/check.sh m4`                               | 저장·복원·설정·화면 명령 회귀                                                    | 1,085개 검사 통과                    |
| `bash scripts/check.sh m5`                               | 설정에서 연 라이선스 본문, 전체 저작권·파일·라이선스, 한·영 문구와 스크롤 값     | 579개 검사 통과                      |
| `python3 tests/test_export_check.py`                     | export 실패·파일·필수 완료 표시 누락                                             | 10개 검사 통과                       |
| `bash scripts/check-export.sh`                           | 새 Android preset PCK의 M1~M4 동작, 8개 실제 영업·기록 재로드·엔딩 화면·라이선스 | 필수 완료 표시 7개 확인              |
| `bash scripts/check-export.sh /absolute/m5-reviewed.pck` | 보강한 검사로 보존한 후보 PCK 재검증                                             | 통과                                 |
| PR 리뷰 전 iOS 개발 PCK 검사                             | `c0df215` 검사기에서 캠페인·고지 확인                                            | 당시 통과, 후속 현지화 수정은 미포함 |
| `python3 tests/test_m4_restart.py`                       | 별도 프로세스의 이동·작업 중 저장 복원, 마감 해시, 설정, 저장 교체 경계          | 10개 검사 통과                       |
| 두 PCK 환경변수와 위 재시작 명령                         | M4 기준 PCK의 저장을 M5 PCK에서 읽는 프로세스 호환성                             | 10개 검사 통과                       |
| 변경 파일 대상 `trunk check`와 `git diff --check`        | 선언된 정적 검사·포맷·공백 오류                                                  | 통과                                 |

모든 Godot 실행은 버전 조회를 포함해 `--headless`였습니다.
실행 엔진은 `.godot-version`의 `4.7.2.stable.official.ed1daf0bf`와 일치했습니다.
폰트와 스크롤 검사는 headless 컨트롤 상태를 읽으며 실제 픽셀, 기기 안전 영역, 터치 도달성을 검사하지 않습니다.
headless 창의 기본 표시 크기는 실기기 크기를 나타내지 않으므로 새 창의 기기 가독성은 미검증입니다.

## 2. 음성 검사와 리뷰 수정

라이선스 버튼 구현 전 `settings provides an offline licenses button` 실패를 확인한 뒤 본문 검사를 통과시켰습니다.
외부 운영 정책 fixture가 없는 디렉터리에서 export 검사 스크립트를 실행하면 `exported M5 policy fixture is missing`으로 실패합니다.
엔딩 열기를 막은 PCK, 구성요소 저작권 출력을 제거한 PCK, 라이선스 스크롤을 비활성화한 PCK를 각각 만들었습니다.
셋 모두 실제 캠페인 완주 후 `exported M5 ending or license screen failed`로 거부했습니다.
이 변조는 임시 소스 사본에만 적용했습니다.

독립 리뷰에서 같은 PCK를 양쪽에 지정하는 허점, 엔딩 열기 미검사, PCK의 구성요소 고지 미검사를 확인했습니다.
동일 SHA-256의 두 파일을 거부하고, 실제 엔딩 열기·목록 복귀와 전체 고지를 확인하도록 수정했습니다.
같은 경로·내용이 같은 복사본·누락된 PCK 쌍·틀린 저장 해시·누락된 완료 표시의 거부 검사를 포함했습니다.
수정 부위 재리뷰에서 해당 지적이 해소됐음을 확인했습니다.

## 3. PCK 저장 호환성의 범위

이전 PCK는 M4 머지 커밋의 `git archive`를 임시 디렉터리에 풀고 고정 엔진과 Android preset으로 export했습니다.
새 PCK는 현재 M5 제품 소스에서 export했습니다.
두 프로세스는 소스가 없는 임시 실행 경로와 전용 저장 경로를 사용했습니다.
동일한 외부 M4 fixture가 이전 PCK의 클래스에서 저장을 만들고 새 PCK의 클래스에서 복원했습니다.
복원 직후와 영업 마감 해시·설정·기록이 일치했습니다.

```bash
M4_WRITER_PACK=/Users/dongminyu/Development/01_personal/chef-m5/build/check/m4-baseline.pck \
M4_READER_PACK=/Users/dongminyu/Development/01_personal/chef-m5/build/check/m5-reviewed.pck \
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
python3 tests/test_m4_restart.py
```

이 검사는 모바일 앱 ID·샌드박스·서명·설치 프로그램·스토어 다운로드를 경유하지 않습니다.
실제 업데이트 수용의 선행 근거로만 사용합니다.

## 4. 개발 서명 산출물

이 절의 개발 서명 산출물은 PR #10 최초 제출 커밋 `c0df2151b2d3cd659491a7297f200b2f1308ff99` 시점입니다.
후속 라이선스 안내 문구의 현지화 수정은 이 모바일 산출물에 포함되지 않았습니다.
후속 수정은 새 PCK와 아래 회귀 검사로 확인했으며 모바일 서명 재빌드·실기기 검증으로 확대해 해석하지 않습니다.

기존 개발 ID `kr.donminzzi.chefalmandodev`, 버전 `0.0.1`, 빌드 `1`을 유지했습니다.
로컬에 있는 개발 서명을 사용했으며 포털 갱신 옵션이나 배포 작업을 실행하지 않았습니다.
Android 서명 환경변수는 로컬 Editor Settings에서 경로·비밀번호를 읽고 기존 별칭 `androiddebugkey`를 사용했습니다.
비밀 값은 로그와 저장소에 기록하지 않았습니다.

```bash
"$GODOT_BIN" --headless --path . --export-debug Android build/android/chef-al-mando.apk
"$GODOT_BIN" --headless --path . --export-debug iOS build/ios/chef_al_mando.xcodeproj
xcodebuild -project build/ios/chef_al_mando.xcodeproj -scheme chef_al_mando \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-derived -jobs 2 build
codesign --verify --deep --strict --verbose=2 build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app
```

두 export와 Xcode 빌드, iOS 서명 무결성 검사는 종료 코드 0으로 통과했습니다.
Android Build Tools `36.0.0`의 `apksigner verify --verbose`는 v2·v3 서명을 확인했습니다.
`aapt dump badging`은 개발 ID·버전을, `aapt dump permissions`는 `INTERNET` 권한이 없음을 확인했습니다.
iOS `Info.plist`는 같은 ID·버전, iPhone·iPad 지원, 양 가로 방향을 확인했습니다.
이 사실은 기기 설치·실행이나 네트워크 차단 완주를 증명하지 않습니다.

| 산출물                             | SHA-256                                                            |
| ---------------------------------- | ------------------------------------------------------------------ |
| `build/android/chef-al-mando.apk`  | `040ac0ae99be5b469086754ab23fa20a14b86e0afa5797279c67b1adc373a46d` |
| iOS `.app/chef_al_mando` 실행 파일 | `98ec29c084aecd9cecb43265ad367e06311c7de9116ef5241d3a1f33d5ad62b2` |
| iOS `.app/chef_al_mando.pck`       | `6ddef573671211882ce2e7e38c107150cbd05345b6293a1443547e10adcbc8d6` |
| 이전 `build/check/m4-baseline.pck` | `057f45daff402e45bdb35dab26627b4f0d8211516f86bdf55d66fcbf33c8eb47` |
| 새 `build/check/m5-candidate.pck`  | `58317fe3c96c912408db50bd49f5e91c54ffe247325de80e809dd51d078418bf` |

상세 산출물 메타데이터는 로컬 `build/check/m5-artifacts.json`, 빌드·음성 검사 로그는 `build/check/m5-*`에 있습니다.
산출물과 로컬 서명 자료는 Git에 포함하지 않습니다.

## 5. 남은 출시 수용 기준

- 출시 앱 ID·버전·서명·배포 채널과 지원·개인정보 안내 주소 확정.
- 제품 아이콘과 실제 후보 빌드의 스토어 화면 이미지.
- 실제 다운로드 빌드의 최초 오프라인 완주와 삭제 없는 업데이트·저장 보존.
- 두 플랫폼의 배경 전환·강제 종료·소리 중단·폰·태블릿 가독성·터치·성능.
- 운영자가 재개하는 Android 실기기·사용자 5명 검증과 베타 결과.
- 확인된 차단 문제의 수정·재검증과 남은 차단 문제 0건 판단.

이 로컬 검증 시점에는 기기 설치·실행, 사용자 모집, 스토어 제출·업로드·공개, Git push를 하지 않았습니다.
M5 전체 통과와 출시 준비 완료를 선언하지 않습니다.
출시 자료와 자산 출처는 [자료 초안](m5-release-materials.md)과 [라이선스 목록](m5-asset-licenses.md)에 있습니다.
Oracle의 프로젝트 한정 조회 결과는 `[no precedent found]`이며 기존 블루프린트와 현재 소스 검증을 사용했습니다.

## 6. PR 리뷰 후속 검증

PR #10의 P2 두 건을 현재 명세와 대조해 수정했습니다.
재시작 검사기는 writer·reader를 시작하기 전에 `GODOT_BIN --headless --version`을 한 번 실행하여 `.godot-version`과 비교합니다.
다른 버전 또는 종료 코드가 0이 아닌 probe는 거부합니다.
독립 프로세스에 가짜 엔진을 주입한 검사는 버전 조회 한 번만 실행되고 writer·reader 명령이 실행되지 않았음을 확인합니다.
이 회귀 검사는 수정 전 두 fixture에서 실패했고 수정 후 통과했습니다.

라이선스의 안내 문구와 구성요소 제목을 한국어·영어로 번역하고, 열려 있는 창에서도 언어 변경을 반영합니다.
기본 한국어 문구가 없는 상태에서 회귀 검사가 실패하는 것을 확인했습니다.
엔진·구성요소의 라이선스 본문은 원문을 유지하며 언어 변경 후에도 전체 본문을 다시 비교합니다.
현재 M5 검사 579개, 재시작 검사 10개, M4 회귀 1,085개, export 실패 처리 검사 10개와 새 PCK의 완료 표시 7개가 통과했습니다.
기존 M4 PCK에서 후속 수정 PCK로 복원하는 검사도 10개가 통과했습니다.

후속 PCK는 `build/check/m5-reviewed.pck`이며 SHA-256은 `1d6b3cfa4f6106245ca4bc1c2b5d6ca4107ad894a184c351168ec8cf09ec0d41`입니다.
재현 로그는 `build/check/m5-review-version-red.log`, `m5-review-version-green.log`, `m5-review-locale-red.log`, `m5-review-locale-green.log`, `m5-reviewed-pack.log`, `m5-reviewed-upgrade.log`에 있습니다.

Oracle은 `raw/sources/.claude/rules/evidence-basis-discipline.md`의 검증 원칙을 반환했습니다.
검사가 실제 명령과 문구를 읽어야 하고 실패 입력을 먼저 확인해야 한다는 선례가 이번 검증 방향을 확인해 주었습니다.
조회 revision은 `7049be0f6c7cefadb3d3d24a51ac74aa66e48824`이며 현재 wiki와의 일치 여부는 확인하지 않았습니다.
엔진 버전에 직접 일치하는 프로젝트 선례는 `[no precedent found]`였습니다.

## 7. 메뉴별 기본 우선순위 후보의 추가 검증

2026-09-09 운영자는 [우선순위 보완본](hot-queue-followup.md)의 iPhone 플레이를 확인하고 다음 작업을 요청했습니다.
현재 블루프린트의 마지막 마일스톤은 M5이며 M6는 정의하지 않았습니다.
Android 실기기·사용자 5명 검증 보류는 유지합니다.

현재 후보는 머지 커밋 `aff1826b5563d6eb98a06e8dec8abf69446b3d33` 위의 로컬 보완입니다.
19:09에 설치한 개발 앱은 `kr.donminzzi.chefalmandodev`, 버전 `0.0.1`, 빌드 `1`입니다.
산출물과 소스별 해시는 `build/check/menu-priorities-ios-artifact.json`에 기록했습니다.
PCK SHA-256은 `865881a156fd4e957925abde194bc6f629ee23c91b47fdff0d26c30bfd6c5eca`입니다.
설치 전후 캠페인 저장의 동일성과 운영자의 플레이 확인은 기록했지만, 스토어에서 다운로드한 빌드는 아닙니다.

메뉴별 기본 우선순위가 없는 이전 앱 PCK에서 이동·작업 중 저장을 만들고 현재 schema 3 후보의 새 프로세스에서 읽었습니다.
복원 직후와 마감 해시, 영어·큰 글자·효과음 설정, 강제 종료와 저장 교체 경계까지 포함해 10개 검사가 통과했습니다.
명령과 로그는 다음과 같습니다.

```bash
M4_WRITER_PACK=/Users/dongminyu/Development/01_personal/chef-al-mando/build/check/priority-input-baseline.pck \
M4_READER_PACK=/Users/dongminyu/Development/01_personal/chef-al-mando/build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app/chef_al_mando.pck \
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
python3 tests/test_m4_restart.py
```

로그는 `build/check/m5-final-upgrade.log`입니다.
기본값이 없는 기존 저장은 우선순위 `1`로 복원되며, 이 PCK 쌍 검사는 새 메뉴 기본값을 설정한 writer fixture는 아닙니다.
새 기본값의 저장·도착·재개·개별 변경은 [보완 검증 기록](hot-queue-followup.md)의 M4 회귀와 현재 PCK 검사에서 별도로 확인했습니다.

영어·큰 글자 준비 화면은 레이아웃 안정화 뒤 다시 렌더링했고, 우선순위 선택과 배속 버튼을 안전 영역 안에서 확인했습니다.
이전 캡처의 밀림은 재현되지 않아 제품 코드를 변경하지 않았습니다.
기존 명세의 전체 폰·태블릿·생명주기·오프라인·성능 수용 검증은 별도로 남습니다.

다음 작업의 결정 항목은 제품 아이콘·스토어 화면 제작 범위, 출시 앱 ID와 기존 개발 저장의 이전 정책, 후보 버전·빌드 번호, 배포 채널입니다.
지원 연락처·공개 개인정보 안내 URL도 제출 전에 확정해야 합니다.
미확정 값을 임의로 채우거나 스토어 등록·업로드를 실행하지 않았습니다.

Oracle은 `wiki/entities/release-cut.md`와 `wiki/concepts/build-number-convention-continuity.md`의 선례를 반환했습니다.
원본 근거는 `raw/sources/.claude/skills/release-cut/SKILL.md`입니다.
출시 준비와 실제 배포를 구분하고 버전·빌드 번호를 기존 규칙 없이 추측하지 않는 방향을 확인했습니다.
조회 revision은 `7049be0f6c7cefadb3d3d24a51ac74aa66e48824`이며 현재 wiki와의 일치 여부는 미검증입니다.
저장 스키마 전환에 직접 적용할 선례는 제한된 검색에서 찾지 못했으므로 현재 명세와 실행 근거로 판단했습니다.
