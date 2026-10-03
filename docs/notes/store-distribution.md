# 스토어 테스트 배포

플레이테스트 빌드를 운영자의 폰에 직접 설치하는 대신 TestFlight와 Google Play 테스트 트랙으로 배포하기 위한 절차입니다.
출시 수용 기준은 [M5 명세](../specs/m5-release-candidate.md) §3이 소유하며, 이 문서는 배포 채널을 여는 데까지만 다룹니다.

## 1. 운영자 결정 (2026-10-03)

| 항목            | 결정                                                                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 출시 앱 ID      | `kr.donminzzi.chefalmando`. 개발 앱(`kr.donminzzi.chefalmandodev`)과 플레이테스트 앱(`kr.donminzzi.chefalmandoplaytest`)은 그대로 남습니다. |
| iOS 테스트 채널 | 출시 ID의 TestFlight. App Store는 무료 앱을 나중에 유료로 바꿀 수 있습니다.                                                                 |
| Play 테스트     | 출시 패키지 `kr.donminzzi.chefalmando` 하나. 첫 업로드 전에 유료로 설정하고, 플레이테스트는 내부 테스트로 진행합니다.                       |
| 정책 페이지     | `donminzzi.kr` 하위 도메인. 문안은 [정책 페이지 초안](store-policy-pages.md)에 있고, 호스팅과 DNS는 운영자가 연결합니다.                    |
| 업로드 자격     | 운영자가 지정하는 개인 계정의 기존 키. `~/.private_keys`에는 다른 팀의 키도 있으므로, 지정받지 않은 키는 쓰지 않습니다.                     |

Google Play는 "Once your app has been offered for free, the app can't be changed to paid"이므로([도움말](https://support.google.com/googleplay/android-developer/answer/6334373), 2026-10-03 확인), 출시 패키지를 처음부터 유료로 둡니다.
유료에서 무료로 바꾸거나 금액을 바꾸는 것은 나중에도 가능하므로, 첫 가격은 6,600원 가설을 확정하지 않는 임시값입니다.
Play Console도 "게시 전까지는 앱을 유료에서 무료로 변경할 수 있습니다"라고 안내합니다(2026-10-03 운영자 화면).
같은 날 처음에는 Play 테스트를 플레이테스트 패키지로 분리하기로 했다가, 출시 패키지 하나를 유료로 두고 테스트하는 운영자의 제안으로 바꿨습니다.
Play 앱의 패키지 이름은 처음 올린 AAB가 정하므로, 첫 업로드 전에 정했습니다.

유료 앱의 테스터 비용은 트랙마다 다릅니다([도움말](https://support.google.com/googleplay/android-developer/answer/9845334), 2026-10-03 확인).

- 내부 테스트: "For paid apps, testers can install your internal test version for free." 5명 플레이테스트는 내부 테스트로 진행합니다.
- 비공개·공개 테스트: "Testers must purchase paid apps when participating in open or closed tests."
  2023-11-13 이후 만든 개인 계정은 프로덕션 신청 전에 앱마다 12명 이상이 14일 연속 참여한 비공개 테스트가 필요합니다([도움말](https://support.google.com/googleplay/android-developer/answer/14151465)).
  라이선스 테스터는 테스트 결제 수단으로 돈을 내지 않고 구매하지만([결제 테스트](https://developer.android.com/google/play/billing/test)), 문서가 다루는 대상은 앱 안의 상품과 구독이므로 유료 앱 자체도 무료가 되는지는 비공개 테스트를 시작할 때 테스터 한 명으로 확인합니다.

## 2. iOS (TestFlight)

`export_presets.cfg`의 "iOS App Store" preset이 출시 ID, 표시 버전, 빌드 번호와 `ITSAppUsesNonExemptEncryption = false`를 소유합니다.
게임 코드(`sim/`, `content/`, `presentation/`, `persistence/`, `platform/`)는 네트워크와 암호화 API를 호출하지 않으므로(2026-10-03 검색) 수출 규정 답변은 "아니요"로 두었고, 이 선언이 있으면 빌드마다 App Store Connect에서 따로 답하지 않아도 됩니다.

### 2.1 순서

1. 운영자: Apple Developer의 Identifiers에 `kr.donminzzi.chefalmando`를 등록합니다.
2. 운영자: App Store Connect에서 그 번들 ID로 새 앱을 만듭니다(기본 언어 한국어, 이름과 SKU는 운영자가 정함).
3. `bash scripts/release-ios.sh build`: 로컬에서만 동작합니다.
   변경 사항이 없는 checkout에서 release export, archive를 만들고, archive된 앱의 번들 ID, 수출 규정 선언, 불필요 권한 키 제거, 서명을 검사한 뒤 commit, 버전, PCK SHA-256을 출력합니다.
   검사를 통과하면 그 commit과 archive 전체의 해시를 `build/ios-release/built-record`에 기록합니다.
4. `bash scripts/release-ios.sh upload`: 기록된 commit이 HEAD와 다르거나 archive가 검사 뒤에 바뀌었으면 거부합니다. 통과하면 Apple Developer 포털에 배포 프로비저닝 프로필을 만들고(`-allowProvisioningUpdates`) App Store Connect에 업로드합니다.
   외부에 쓰는 단계이므로 실행 전에 운영자에게 알립니다.
5. 운영자: TestFlight에서 테스트 그룹을 정합니다.
   내부 그룹은 App Store Connect 사용자만 들어갈 수 있고 심사 없이 바로 설치됩니다.
   외부 그룹과 공개 링크는 베타 앱 설명, 피드백 이메일, 개인정보 처리방침 URL이 필요하고, 버전마다 첫 빌드가 Beta App Review를 거칩니다([App Store Connect 도움말](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), 2026-10-03 검색).

### 2.2 자격 증명

`upload`는 다음 환경 변수만 읽고, 키 파일은 저장소 밖에 둡니다.

| 변수            | 값                          |
| --------------- | --------------------------- |
| `ASC_KEY_ID`    | App Store Connect API 키 ID |
| `ASC_ISSUER_ID` | 그 키의 Issuer ID           |
| `ASC_KEY_PATH`  | `.p8` 파일의 절대 경로      |

### 2.3 빌드 식별

TestFlight로 받은 앱은 Apple이 다시 서명하므로 실행 파일의 SHA-256이 로컬 빌드와 다릅니다.
스토어 빌드의 식별은 소스 commit, 표시 버전, 빌드 번호, PCK SHA-256입니다.
2026-10-03 `e15ca08`의 `build` 실행은 0.1.0 (1), PCK SHA-256 `8899c46d…`를 냈습니다(업로드하지 않음).

| 업로드 날짜 | 소스 commit | 버전 (빌드) | PCK SHA-256                                                        | 실행                                                                            |
| ----------- | ----------- | ----------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| 2026-10-03  | `4355b4c`   | 0.1.0 (1)   | `8c37c1b8dc33019ca9afdc00c9a6d2f0d7204c64c19dc285dcfac6545f18b5b0` | 운영자가 `build`와 `upload`를 직접 실행, App Store Connect에서 처리 중으로 끝남 |

같은 소스라도 checkout마다 Godot의 가져오기 캐시가 달라 PCK 해시가 다를 수 있으므로(`e15ca08` 워크트리와 `4355b4c` main checkout의 트리는 같지만 해시가 다름), 빌드 식별은 업로드한 빌드의 값을 씁니다.
iOS 빌드 번호 1은 사용했으므로 다음 업로드 전에 "iOS App Store" preset의 `application/version`을 2로 올립니다.

## 3. 버전과 빌드 번호

- 표시 버전은 베타 동안 `0.1.0`이고, 출시 후보에서 운영자가 올립니다.
- 빌드 번호는 플랫폼마다 1부터 시작해 업로드마다 1씩 올리는 정수입니다.
  iOS는 "iOS App Store" preset의 `application/version`, Android는 테스트 preset의 `version/code`입니다.
- 업로드 전에 preset의 번호를 올리는 커밋을 먼저 만들고, 그 커밋의 변경 없는 checkout에서 빌드합니다.
- 한 번 업로드한 번호는 다시 쓰지 않습니다.

## 4. Android (Play 내부 테스트)

`export_presets.cfg`의 "Android Play Store" preset이 패키지 `kr.donminzzi.chefalmando`, 표시 이름, 표시 버전, `version/code`, Gradle AAB 출력과 `target_sdk` 36을 소유합니다.
Google Play는 2026-08-31부터 새 앱과 업데이트에 API 36(Android 16) 이상을 요구합니다([요구 사항](https://developer.android.com/google/play/requirements/target-sdk), 2026-10-03 확인).
Play는 새 앱에 AAB를 요구하고, Godot은 Gradle 빌드에서만 AAB를 만들므로 `build`가 매번 `android/`(이미 `.gitignore`에 있음)를 지우고 `--install-android-build-template`로 새로 설치합니다.
Godot은 이미 설치된 템플릿을 덮어쓰지 않고, git이 무시하는 폴더는 변경 사항 없는 checkout 검사에 잡히지 않으므로, 지우지 않으면 그 안에 남은 수정이 서명된 AAB에 들어갈 수 있습니다.

### 4.1 순서

1. 운영자: Play Console에서 앱을 만들고 첫 업로드 전에 모든 국가·지역의 가격을 유료로 설정합니다(2026-10-03 "Chef Al Mando" 앱을 유료로 만들어 둠).
2. `bash scripts/release-android.sh build`: 로컬에서만 동작합니다.
   변경 사항이 없는 checkout에서 서명된 AAB를 내보내고, manifest의 패키지, `targetSdkVersion` 36, `INTERNET` 권한 없음과 서명을 검사한 뒤 commit, 버전, AAB SHA-256을 출력하고 `build/android-release/built-record`에 기록합니다.
3. 운영자: 첫 AAB는 Play Console의 내부 테스트 트랙에 직접 올립니다.
   Play의 새 앱은 첫 빌드를 Play Console에서 올려야 `fastlane supply` 업로드가 가능합니다([supply 문서](https://docs.fastlane.tools/actions/supply/), 2026-10-03 확인).
4. 두 번째 빌드부터 `bash scripts/release-android.sh upload`: 기록된 commit이 HEAD와 다르거나 AAB가 바뀌었으면 거부하고, 통과하면 내부 테스트 트랙에 올립니다.
   외부에 쓰는 단계이므로 실행 전에 운영자에게 알립니다.
5. 운영자: 내부 테스트의 테스터 이메일 목록과 참여 링크를 관리합니다.

### 4.2 자격 증명

| 변수                                      | 값                                   |
| ----------------------------------------- | ------------------------------------ |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`     | 업로드 키스토어(`.jks`)의 절대 경로  |
| `GODOT_ANDROID_KEYSTORE_RELEASE_USER`     | 키 별칭                              |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` | 키스토어 비밀번호                    |
| `SUPPLY_JSON_KEY`                         | Play 서비스 계정 JSON 키의 절대 경로 |

2026-10-03 운영자가 업로드 키스토어(`~/Development/release-android.jks`)와 서비스 계정 키를 지정했습니다.
비밀번호는 저장소, 문서, 메모리에 적지 않고, 셸에서 Keychain을 읽어 넘깁니다.
`build`는 AAB의 서명 인증서를 이 키의 SHA-256 지문(`84:10:5B:BF:…:C3:97:E5`, 전체 값은 `scripts/release-android.sh`가 소유)과 비교하므로, 다른 키로 서명한 빌드는 기록되지 않습니다.

```bash
security add-generic-password -a "$USER" -s mac-setup.ANDROID_UPLOAD_KEYSTORE_PASSWORD -w  # 한 번, 입력 프롬프트로 저장
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$HOME/Development/release-android.jks GODOT_ANDROID_KEYSTORE_RELEASE_USER=donminzzi \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(security find-generic-password -a "$USER" -s mac-setup.ANDROID_UPLOAD_KEYSTORE_PASSWORD -w)" \
  bash scripts/release-android.sh build  # 변수를 명령 앞에 붙여 그 실행에만 넘깁니다
```

Android 실기기 검증은 [AGENTS.md](../../AGENTS.md)에 보류로 남아 있으므로, Play로 받은 Android 참가자의 세션이 첫 Android 실기기 실행이 됩니다.
