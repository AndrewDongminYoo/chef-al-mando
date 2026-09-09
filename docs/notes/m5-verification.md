# M5 로컬 출시 준비 검증

검증일: 2026-09-09.
기준은 [M5 명세](../specs/m5-release-candidate.md)입니다.
소스는 M4 머지 커밋 `02e3c38216159fadc06c64aaf117a9e76271f80d` 위의 `feat/m5-release-preparation` 변경입니다.
이 기록은 로컬 준비 결과이며 M5 전체 통과가 아닙니다.

## 1. 완료한 로컬 검사

| 검사                                                                         | 직접 읽은 속성                                                                   | 결과                    |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------- |
| `bash scripts/check.sh m4`                                                   | 저장·복원·설정·화면 명령 회귀                                                    | 1,085개 검사 통과       |
| `bash scripts/check.sh m5`                                                   | 설정에서 연 라이선스 본문, 전체 저작권·파일·라이선스, 한·영 문구와 스크롤 값     | 558개 검사 통과         |
| `python3 tests/test_export_check.py`                                         | export 실패·파일·필수 완료 표시 누락                                             | 10개 검사 통과          |
| `bash scripts/check-export.sh`                                               | 새 Android preset PCK의 M1~M4 동작, 8개 실제 영업·기록 재로드·엔딩 화면·라이선스 | 필수 완료 표시 7개 확인 |
| `bash scripts/check-export.sh /absolute/m5-candidate.pck`                    | 보강한 검사로 보존한 후보 PCK 재검증                                             | 통과                    |
| `bash scripts/check-export.sh /absolute/chef_al_mando.app/chef_al_mando.pck` | iOS 개발 빌드에 포함된 실제 PCK의 동일 경로                                      | 통과                    |
| `python3 tests/test_m4_restart.py`                                           | 별도 프로세스의 이동·작업 중 저장 복원, 마감 해시, 설정, 저장 교체 경계          | 9개 검사 통과           |
| 두 PCK 환경변수와 위 재시작 명령                                             | M4 기준 PCK의 저장을 M5 PCK에서 읽는 프로세스 호환성                             | 9개 검사 통과           |
| 변경 파일 대상 `trunk check`와 `git diff --check`                            | 선언된 정적 검사·포맷·공백 오류                                                  | 통과                    |

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
M4_READER_PACK=/Users/dongminyu/Development/01_personal/chef-m5/build/check/m5-candidate.pck \
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
python3 tests/test_m4_restart.py
```

이 검사는 모바일 앱 ID·샌드박스·서명·설치 프로그램·스토어 다운로드를 경유하지 않습니다.
실제 업데이트 수용의 선행 근거로만 사용합니다.

## 4. 개발 서명 산출물

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
