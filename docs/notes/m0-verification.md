# M0 실행 기록

<!-- cspell:words aapt androiddebugkey apksigner -->

작성일: 2026-09-07 · 상태: 로컬·iPhone 재검증 통과, Android 실기기 대기

## 범위와 소스

명세·계획의 기준 커밋은 `505ad0a`이며 M0 구현은 그 이후의 관심사별 커밋으로 기록합니다.
명세 승인에는 Android 구매 전 데스크톱·iPhone·export 준비 예외가 포함됩니다.
2026-09-07 iPhone 재검증 통과 후 운영자가 Android 실기기 검증을 구매 뒤로 미루고 M1 구현에 바로 착수하도록 추가 승인했습니다.
M1 착수는 허용하되 Android 검증과 M0 전체 통과는 보류합니다.
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

PR #1 머지 후 새 worktree에서 `bash scripts/check.sh m0`를 다시 실행했고 `PASS: m0 checks=20 failures=0`을 확인했습니다.
GitHub hosted CI의 `m0`는 [PR #1 실행](https://github.com/AndrewDongminYoo/chef-al-mando/actions/runs/34109482325)(head `db2d969`)과 [머지 후 실행](https://github.com/AndrewDongminYoo/chef-al-mando/actions/runs/34111924984)(`e5df74d`)에서 성공했으며, 검증 범위는 Linux의 `bash scripts/check.sh m0`이고 모바일 export와 실기기 동작은 포함하지 않습니다.

## export와 빌드

최초 iOS export는 명세와 다른 `build/ios-final/`을 사용했고 양 플랫폼 산출물의 SHA도 남기지 않았습니다.
이전 산출물은 M0-05의 재현 근거로 사용하지 않습니다.
2026-09-07에 PR #1의 머지 커밋 `e5df74d7d4f33467903e9a6a78154d5d63ce0244`에서 만든 새 worktree로 아래 export와 빌드를 재수행했습니다.
이번 재검증에서 앱 소스와 export 설정은 이 커밋과 같으며 변경하지 않았습니다.
엔진의 `--version`은 `.godot-version`과 일치했고 설치된 템플릿의 `version.txt`는 `4.7.2.stable`입니다.

Android export에서는 로컬 debug keystore의 경로·사용자·비밀번호를 `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER`, `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`로 함께 전달합니다.
셋 중 일부만 전달하면 Godot이 설정 오류로 거부합니다.
경로와 비밀번호는 로컬 Editor Settings에서 읽고 별칭은 `androiddebugkey`를 사용했으며 로그와 저장소에 비밀 값을 기록하지 않습니다.
`scripts/check.sh m0`가 출력 디렉터리를 준비한 상태에서 다음 명령을 실행했습니다.

```bash
"$GODOT_BIN" --headless --path . --export-debug Android build/android/chef-al-mando.apk
"$GODOT_BIN" --headless --path . --export-debug iOS build/ios/chef_al_mando.xcodeproj
xcodebuild -list -project build/ios/chef_al_mando.xcodeproj
xcodebuild -project build/ios/chef_al_mando.xcodeproj -scheme chef_al_mando \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-derived -jobs 2 build
```

두 export와 `xcodebuild -list`, 개발 서명 빌드는 모두 종료 코드 0으로 끝났고 빌드는 `BUILD SUCCEEDED`를 출력했습니다.
기존 개인 개발 서명을 사용했으며 provisioning 갱신 옵션은 추가하지 않았습니다.
출력 Xcode 프로젝트를 직접 수정하지 않고 Godot 설정에서 재생성합니다.
서명 인증서·개인 키·프로비저닝 파일과 `build/` 산출물은 커밋하지 않습니다.

Android SDK Build Tools `36.0.0`의 `apksigner verify --verbose build/android/chef-al-mando.apk`는 종료 코드 0과 v2·v3 서명 검증 성공을 반환했습니다.
`aapt dump badging`에서 application ID `kr.donminzzi.chefalmandodev`, 버전 `0.0.1` build `1`, ABI `arm64-v8a`를 확인했습니다.
두 export 로그 끝에는 `cannot connect to daemon at tcp:5037: Connection refused`가 남았으며 Android 기기 연결·설치는 검증하지 않았습니다.

iOS `.app`의 `Info.plist`에서 같은 application ID와 버전, iPhone·iPad 지원, 양 가로 방향만 허용하는 설정을 확인했습니다.
다음 서명 검사는 번들의 서명 무결성을 읽으며 종료 코드 0으로 통과했습니다.

```bash
codesign --verify --deep --strict --verbose=2 \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app
ditto -c -k --keepParent \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app \
  build/ios/chef_al_mando.app.zip
shasum -a 256 build/android/chef-al-mando.apk build/ios/chef_al_mando.app.zip \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app/chef_al_mando \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app/chef_al_mando.pck
```

아래 SHA-256은 이번 산출물을 식별하며 재빌드의 바이트 일치를 보장하지 않습니다.
ZIP은 설치한 `.app` 번들을 보관한 파일이며 스토어 배포용 IPA가 아닙니다.

| 산출물                            | SHA-256                                                            |
| --------------------------------- | ------------------------------------------------------------------ |
| `build/android/chef-al-mando.apk` | `8ce2f8e2a791d361aca3b2377363b9512feaa007bd990287debb0fd483e319b7` |
| `build/ios/chef_al_mando.app.zip` | `d7f5bd68eaecc116c3a99725c7a2ac52cb60ab6acdeaf01a95422b152fa69a2f` |
| `.app/chef_al_mando` 실행 파일    | `a9c461ecf083595378d839d05543f3827aa297942f76406183272e5e895da08e` |
| `.app/chef_al_mando.pck` 리소스   | `23bf5fe610589823a460fc6c9152a9866e6b3c63d9f9827d7a938c82de100060` |

APK 크기는 28,374,119바이트이고 ZIP 크기는 28,685,742바이트입니다.
export·빌드 로그는 같은 worktree의 `build/check/android-export.log`, `ios-export.log`, `ios-build.log`에 보관합니다.

## iPhone 재검증

2026-09-07에 연결된 iPhone 16 Pro의 iOS `26.6.1` build `23G83`을 `devicectl`로 다시 확인했습니다.
설치와 실행을 각각 사전 고지한 뒤 위 `.app`으로 다음 명령을 실행했고 모두 종료 코드 0으로 끝났습니다.
`IOS_DEVICE_ID`는 로컬에서 확인한 기기 식별자를 사용합니다.

```bash
xcrun devicectl device install app --device "$IOS_DEVICE_ID" \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app
xcrun devicectl device process launch --device "$IOS_DEVICE_ID" \
  kr.donminzzi.chefalmandodev
xcrun devicectl device info apps --device "$IOS_DEVICE_ID" \
  --bundle-id kr.donminzzi.chefalmandodev
```

설치 후 재조회에서 `Chef al Mando`, `kr.donminzzi.chefalmandodev`, `0.0.1 (1)`을 확인했습니다.
iPhone에는 이 개발 빌드를 남깁니다.
설치·프로세스 실행 성공은 화면 표시나 실제 OS 생명주기 검증을 대신하지 않습니다.
운영자가 이 설치 빌드에서 아래 절차를 직접 수행하고 통과를 확인했습니다.
아래 결과는 운영자의 실기기 관찰이며 자동화 로그나 에이전트의 화면 캡처 결과가 아닙니다.

| 기준        | 실제로 확인한 속성                                              | 결과                               |
| ----------- | --------------------------------------------------------------- | ---------------------------------- |
| M0-01·M0-02 | 양 가로 방향에서 화면·한국어·버튼 표시와 노치·홈 표시줄 간섭    | 양 방향 정상                       |
| M0-03       | 시작·일시정지·재개를 각각 한 번 탭했을 때의 반응                | 정상                               |
| M0-04       | 진행 중 10초 이상 배경 전환 후 복귀, 명시적 재개 전 카운터 유지 | 복귀 `009.2초` → 10초 뒤 `009.2초` |
| M0-04       | 재개 탭 후 카운터 진행                                          | 명시적 재개 후 증가                |

iPhone 재검증은 통과했지만 Android 실기기 증거가 없어 M0 전체 통과와 M0-05의 기기별 실행 기록은 미완료입니다.

## 이전 에이전트 설정 진단

AGENTS.md 변경 후 실행한 `codex doctor --summary --ascii --no-color`는 경고 2건, 실패 0건을 보고했습니다.
경고는 업데이트 구성 진단과 macOS 보안 평가 조회 불가이며, 이 결과는 앱 검증이 아닙니다.
관심사별 커밋 준비 중 같은 명령을 다시 실행한 결과는 경고 0건, 실패 0건입니다.

## 남은 수용 기준

- Android 구매 후 기종·OS를 기록하고 설치 빌드에서 M0-01~M0-04를 검증합니다.
- Android에 실제 설치한 산출물의 SHA와 실행 기록으로 M0-05의 남은 기기 증거를 보완합니다.

M0 전체 통과, M1 구현, 출시 빌드 검증을 완료한 것으로 보고하지 않습니다.
