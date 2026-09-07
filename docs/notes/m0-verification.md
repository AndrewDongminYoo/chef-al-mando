# M0 실행 기록

작성일: 2026-09-07 · 상태: 로컬 구현 검증, 양 플랫폼 실기기 통과 미완료

## 범위와 소스

명세·계획의 기준 커밋은 `505ad0a`이며 M0 구현은 그 이후의 관심사별 커밋으로 기록합니다.
명세 승인에는 Android 구매 전 데스크톱·iPhone·export 준비 예외가 포함됩니다.
Android 실기기를 구매하고 M0 기기 검증을 통과하기 전에는 M1을 시작하지 않습니다.
Oracle 조회 결과는 `[no precedent found]`입니다.

## 환경

- Godot: `.godot-version`과 일치하는 `--version` 출력 확인
- export template: `4.7.2.stable`
- 렌더러: Compatibility
- Xcode: 26.6, build `17F113`
- Java: 설치된 Zulu JDK 17.0.19
- Android APK 빌드 도구: 36.0.0
- iPhone: iPhone 16 Pro, iOS 26.6.1, build `23G83`
- Android 실기기: 미보유, 구매 예정

[공식 Godot 4.7.2 릴리스](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)의 `Godot_v4.7.2-stable_export_templates.tpz`를 내려받아 같은 릴리스의 `SHA512-SUMS.txt`와 대조했습니다.
`shasum -a 512 -c` 결과는 `OK`입니다.

```plaintext
ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079
```

전체 템플릿 중 `android_debug.apk`, `android_release.apk`, `ios.zip`, `version.txt`만 로컬 Godot export template 폴더에 설치했습니다.
Godot Editor Settings의 비어 있던 `export/android/java_sdk_path`를 기존 JDK 설치 경로로 설정했습니다.
Android SDK나 JDK를 새로 설치하지 않았습니다.

## 로컬 검증

| 검사                       | 실제로 읽는 속성                                                      | 결과                                            |
| -------------------------- | --------------------------------------------------------------------- | ----------------------------------------------- |
| `bash scripts/check.sh m0` | 엔진 버전, import 오류, 시작·정지·재개·주입된 생명주기·안전 영역 상태 | 20개 assertion 통과                             |
| 빈 suite 프로브            | 검사 0건의 거짓 성공 방지                                             | `FAIL: m0 checks=0 failures=0`, 비정상 종료     |
| 엔진 오류 프로브           | suite가 PASS를 출력해도 엔진 오류가 있으면 실패                       | `FAIL: engine errors`, 비정상 종료              |
| 잘못된 main scene 프로브   | 프로젝트의 실제 main scene 참조 검사                                  | import에서 누락 scene 오류를 감지해 비정상 종료 |
| 렌더링 입력 검사           | 축소된 실제 Godot 창의 hit target과 touch→mouse 변환                  | touch 1회에 action 1회, 입력 실패 0             |
| Trunk                      | 지정한 소스·셸·워크플로 형식과 정적 검사                              | 변경 파일 대상으로 실행                         |

최초 테스트는 main scene 부재로 실패한 뒤 구현으로 통과했습니다.
안전 영역 회귀 검사도 동작 부재로 실패한 뒤, 같은 화면 크기에서 좌우 inset을 교체하는 구현으로 통과했습니다.
테스트의 생명주기 notification 주입은 OS 자체의 알림 전달을 증명하지 않습니다.

렌더링 입력 검사는 다음 명령으로 실행합니다.

```bash
"$GODOT_BIN" --path . --resolution 960x540 --script tests/capture_m0.gd
```

`build/check/m0-ready.png`와 `build/check/m0-paused.png`에서 한국어 라벨과 화면 배치를 확인했습니다.
이 이미지는 데스크톱 렌더링 증거이며 iPhone·Android 화면 증거가 아닙니다.

## export와 빌드

가로 회전 설정과 안전 영역 코드 수정 후 Android debug APK의 export·서명·검증과 iOS 프로젝트 export·개발 서명 빌드가 모두 종료 코드 0으로 통과했습니다.
최종 산출물은 `build/android/chef-al-mando.apk`와 `build/ios-final-derived/Build/Products/Debug-iphoneos/chef_al_mando.app`입니다.
Android APK와 iOS 산출물의 SHA는 기록하지 않았고 `build/`는 추적하지 않으므로, 이 산출물은 커밋과 연결되지 않으며 M0-05 증거로는 재수행이 필요합니다.
iOS 빌드의 Info.plist는 양 가로 방향만 포함하며 Android manifest의 `screenOrientation` 값은 `0xb`입니다.
Android APK의 확인된 application ID는 `kr.donminzzi.chefalmandodev`, 버전은 `0.0.1` build `1`, ABI는 `arm64-v8a`입니다.

Android export에서는 로컬 debug keystore의 경로·사용자·비밀번호를 `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER`, `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`로 함께 전달합니다.
셋 중 일부만 전달하면 Godot이 설정 오류로 거부합니다.

아래 iOS export는 명세와 preset의 `build/ios/` 대신 `build/ios-final/`을 사용했습니다.
재현할 때는 명세의 경로를 사용하고 `xcodebuild`의 `-project`와 `-derivedDataPath`를 그에 맞춥니다.

```bash
"$GODOT_BIN" --headless --path . --export-debug Android build/android/chef-al-mando.apk
"$GODOT_BIN" --headless --path . --export-debug iOS build/ios-final/chef_al_mando.xcodeproj
xcodebuild -project build/ios-final/chef_al_mando.xcodeproj -scheme chef_al_mando \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-final-derived -jobs 2 build
```

처음 실행한 iOS 빌드는 연결된 iPhone을 destination으로 사용했고 개발 프로비저닝 확인 옵션을 포함했습니다.
기기 식별자는 저장소 명령에 고정하지 않습니다.
개발 서명 Team ID는 개인 개발 인증서의 OU와 대조했습니다.
Team ID는 공개 식별자이며 인증서·개인 키·프로비저닝 파일은 저장소에 포함하지 않습니다.
출력 Xcode 프로젝트를 직접 수정하지 않고 Godot 설정에서 재생성합니다.

최종 빌드도 연결된 iPhone을 destination으로 사용했으며 `BUILD SUCCEEDED`를 확인했습니다.
`devicectl device install app`과 `devicectl device process launch`가 모두 종료 코드 0으로 완료됐습니다.
iPhone에는 `kr.donminzzi.chefalmandodev` 개발 빌드 `0.0.1 (1)`을 남겼습니다.
설치·프로세스 실행 성공은 화면 표시나 실제 OS 생명주기 검증을 대신하지 않습니다.

AGENTS.md 변경 후 실행한 `codex doctor --summary --ascii --no-color`는 경고 2건, 실패 0건을 보고했습니다.
경고는 업데이트 구성 진단과 macOS 보안 평가 조회 불가이며, 이 결과는 앱 검증이 아닙니다.
관심사별 커밋 준비 중 같은 명령을 다시 실행한 결과는 경고 0건, 실패 0건입니다.

## 남은 수용 기준

- 명세 경로로 export를 재수행하고 산출물 SHA를 기록합니다.
- iPhone에서 최종 빌드의 화면 표시를 확인합니다.
- iPhone에서 시작 후 10초 배경 전환·복귀 시 카운터 정지 유지와 명시적 재개를 확인합니다.
- iPhone 양 가로 방향의 안전 영역과 터치 입력을 확인합니다.
- Android 구매 후 같은 기기 검증을 수행합니다.
- GitHub hosted CI는 아직 실행하지 않았습니다.

M0 전체 통과, M1 구현, 출시 빌드 검증을 완료한 것으로 보고하지 않습니다.
