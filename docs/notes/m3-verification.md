# M3 로컬 검증 기록

## 범위와 판정

2026-09-08에 승인된 M3 캠페인 구현의 로컬 검증 기록입니다.
기준 커밋은 `9bfc1687c07e01c814fcaaea9d0912cfda7f4fc6`, 작업 브랜치는 `feat/m3-campaign`입니다.
명세는 [M3 캠페인](../specs/m3-campaign.md), 실행 단계는 [M3 구현 계획](../plans/m3-implementation.md)을 따릅니다.
사용자 5명 검증은 운영자가 “이 정도면 테스트 진행해도 좋겠다”라고 명시할 때까지 보류합니다.
이 예외는 M2의 사용자 검증 통과를 뜻하지 않습니다.
M3의 재미·난도·콘텐츠 제작 비용과 사람의 엔딩 도달 경험도 아직 확인하지 않았습니다.

## 실행 환경과 명령

로컬 Godot은 `4.7.2.stable.official.ed1daf0bf`, 렌더러는 Compatibility입니다.
실제 창에서는 OpenGL 4.1, Apple M4가 기록되었습니다.
캡처의 폰·태블릿 구분은 데스크톱 창 크기와 안전 영역 fixture이며 실기기 증거가 아닙니다.

```bash
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
bash scripts/check.sh m0
bash scripts/check.sh m1
bash scripts/check.sh m2
bash scripts/check.sh m3
python3 tests/test_export_check.py
bash scripts/check-export.sh
"$GODOT_BIN" --path . --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd
"$GODOT_BIN" --path . --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd -- --phone-wide
"$GODOT_BIN" --path . --max-fps 60 --quit-after 1800 --script tests/capture_m3.gd -- --tablet
cspell --gitignore --gitignore-root . --no-progress '**'
git diff --check
```

## 완료 정책과 실제 영업 결과

[정책 fixture](../../tests/fixtures/m3_policies.gd)는 기존 준비 명령과 tick·sequence를 갖춘 서비스 명령만 사용합니다.
결과·재고·회계를 주입하지 않고 실제 `ServiceSim`을 마감 tick 3000까지 실행합니다.
각 영업 후 실제 파일을 저장하고 새 저장소·진행 객체로 다시 읽어 다음 영업의 해금을 확인합니다.
같은 정책을 반복 실행하고 1배·4배의 최종 상태 hash를 비교합니다.
아래 손익은 게임 내부 정수 통화 단위이며 판매 가격을 뜻하지 않습니다.

| 영업 ID         | 제공 | 손익   |
| --------------- | ---- | ------ |
| `first_shift`   | 12   | 3,200  |
| `lunch_prep`    | 18   | 6,600  |
| `hot_queue`     | 15   | 9,250  |
| `shared_stock`  | 22   | 8,150  |
| `long_route`    | 23   | 15,200 |
| `split_duties`  | 26   | 12,350 |
| `rush_hour`     | 27   | 13,000 |
| `final_service` | 28   | 14,450 |

### 선택별 비교

각 행은 같은 시나리오의 기본 정책과 한 종류의 변경을 비교합니다.
완료 정책 전체와는 다른 입력입니다.
이 결과는 선택의 영향을 보여 주며 재미나 최적 정책을 증명하지 않습니다.

| 변경     | 시나리오       | 기본 → 변경 결과                                                  |
| -------- | -------------- | ----------------------------------------------------------------- |
| 프렙     | `lunch_prep`   | 제공 18건·손익 6,600을 유지하며 누적 작업량 2,880 → 2,610 tick    |
| 배치     | `long_route`   | 제공 6 → 24건, 손익 -5,900 → 16,800, 누적 이동 2,458 → 1,450 tick |
| 담당     | `split_duties` | 제공 26 → 20건, 손익 12,350 → 4,550                               |
| 우선순위 | `hot_queue`    | 제공 7 → 8건, 손익 -3,350 → -1,250                                |
| 발주     | `shared_stock` | 채소 5개 추가 시 제공 20건 유지, 손익 6,350 → 5,850               |

담당 변경만으로 성과가 좋아지지는 않았습니다.
완료 정책에서는 프렙과 담당을 함께 조정해 목표를 충족했습니다.
누적 작업·이동 tick은 여러 주문의 합이므로 영업 시간과 같지 않습니다.

### 콘텐츠 조정

`long_route`의 다섯 번째 설비를 두 번째 냉식대에서 두 번째 화구로 바꿨습니다.
초기 한 화구 구성에서는 이동을 줄여도 화구 병목이 남았고, 참고 정책은 제공 9건에 그쳤습니다.
화구를 추가한 현재 구성에서 배치·프렙 완료 정책은 23건을 제공했습니다.
시나리오 수, 메뉴 수, 목표, 주문, 예산, 직원 수, 설비 수와 기존 시뮬레이션 규칙은 이 조정으로 변경하지 않았습니다.
정적 `.tres`가 콘텐츠 원본이며 제품용 생성 파이프라인이나 외부 의존성을 추가하지 않았습니다.

## 실패를 먼저 확인한 검사

- M3 suite·진행 객체·저장소·프로젝트 진입 장면이 없을 때 실패한 뒤 구현 후 통과했습니다.
- 음수 마감 결과와 잘못된 마지막 시나리오를 넣어 진행 검사 실패를 확인한 뒤 수정했습니다.
- 실제 임시 파일에 손상·미래 버전·잘못된 ID·분수·불연속 기록을 넣고 쓰기·검증·교체 실패를 유발했습니다.
- export의 M3 완료 표시를 누락한 fake engine이 처음에는 성공으로 처리되는 회귀 실패를 확인했습니다.
  필수 표시 검사를 추가한 뒤 누락은 실패하고 정상 pack은 통과했습니다.
- 캡처에서 시작 버튼을 안전 영역 밖으로 이동하면 `M3 rendered start must remain in the safe area`로 실패합니다.
- `--negative-input`으로 좌표를 화면 밖에 보내면 `viewport input must reach the rendered button`으로 실패합니다.

캡처는 뷰포트 로컬 좌표로 마우스 이동·누름·해제를 전달하고, 실제 hover 대상과 화면 전환을 확인합니다.
버튼 신호를 직접 발생시키는 것으로 좌표 검사를 대신하지 않습니다.
준비·시간 진행·우선순위는 재현 가능한 fixture 명령으로 공급합니다.
이 자동 실행은 사람이 모든 준비 버튼을 조작한 증거나 실기기 터치 증거가 아닙니다.
이전 화면 좌표 기반 캡처에서 단계마다 다른 입력 누락이 발생했으므로, 실패한 실행의 엔딩 파일은 완료 증거로 사용하지 않았습니다.

## 실행 결과

콘텐츠·규칙·진행·저장·실제 장면을 읽는 M3 suite는 최종 594개 검사를 통과했습니다.
M0 25개, M1 177개, M2 376개 회귀 검사도 모두 실패 0건입니다.
실제 새 export PCK에서 M1 콘텐츠·첫 주문, M2 준비·첫 주문, M2 추가 메뉴 제공, M3 캠페인 진입·첫 주문 제공의 네 완료 표시를 확인했습니다.
Python export 검사 6개는 출력 누락·실행 오류·오래된 pack 재사용·M3 표시 누락을 검사하며 모두 통과했습니다.

기본 1280×720, 넓은 폰 1566×720, 태블릿 1024×768의 렌더 입력 검사는 각각 165개, 실패 0건입니다.
목록, 첫 준비, 첫 결과, 마감 분석, 직원 4명, 여덟 번째 메뉴 프렙, 마지막 결과, 엔딩, 완료 목록을 캡처했습니다.
실제 이미지에서 주요 버튼·한글·직원 담당 행과 스크롤된 마지막 메뉴·마지막 영업을 확인했습니다.
캡처는 `build/check/m3-*.png`, 실행 로그는 `build/check/m3-capture*.log`에 있으며 Git에 포함하지 않습니다.

저장·진행 검토에서 발견한 불가능한 손익 허용과 캠페인 순서 누락을 수정했습니다.
제공 수에 따른 최대 재료 차익에서 고정 인건비를 뺀 보수적 상한을 목표·결과·기록에 적용했습니다.
기본 발주량은 플레이어가 바꿀 수 있으므로 이를 고정 비용으로 오인하지 않습니다.
두 최고 기록은 여전히 서로 다른 시도에서 나올 수 있습니다.
고정 ID 순서와 손익 위반을 넣은 회귀는 먼저 591개 중 11개 실패했고 수정 후 통과했습니다.
정확한 손익 상한과 서로 다른 시도의 최고 기록 검사도 추가했습니다.
화면·export 검토와 수정 후 저장·진행 재검토에서 남은 결함은 보고되지 않았습니다.

CSpell의 최초 명령은 상위 ignore 규칙 때문에 파일 0개를 읽어 실패했습니다.
`--gitignore-root .`로 저장소 경계를 고정한 실행은 108개 파일을 읽었습니다.
Godot이 생성하는 리소스 식별자만 `.tres`의 문자열 패턴으로 제외하고, 사용 중인 `playthrough`만 사전에 등록했습니다.
README에 임시 오타를 넣었을 때 같은 명령이 해당 오타로 실패했고 원래 바이트로 복구했습니다.
최종 Trunk는 변경·신규 파일 73개를 검사했고 기존 문제 표시를 포함한 검사에서 문제 0건입니다.
CSpell은 108개 파일을 검사해 문제 0건이며 `git diff --check`도 통과했습니다.
Trunk가 처음 기존 문제로 분류한 새 정규식의 불필요한 YAML 따옴표도 원인을 확인해 수정했습니다.
반대 관점 교차 검토는 M3-01~M3-09의 로컬 수용 기준을 승인했으며 차단 결함을 보고하지 않았습니다.
이 판정은 아래 실기기·호스팅·사용자 검증의 보류를 해제하지 않습니다.
로컬 구현 검증을 완료한 시점에는 커밋·푸시·PR 생성을 하지 않았습니다.
이후 운영자가 M3 변경 커밋과 기존 iPhone 앱 위의 설치를 승인했습니다.
설치 빌드·검사·기기 결과는 아래 iPhone 설치 절에 기록합니다.

## 남은 수용 기준

- Android 실기기와 양 플랫폼 전체 수용 기준은 보류 상태입니다.
- M3 소스를 iPhone에 설치했습니다.
  운영자가 설치본 플레이를 완료했다고 보고했습니다.
  별도 성능·OS 생명주기 체크리스트 검증은 남아 있습니다.
- PCK 검사 자체는 콘텐츠와 실제 진입 장면을 읽습니다.
  APK·IPA 빌드, 서명, 설치, 스토어 배포를 검사하지 않습니다.
- 중간 영업 저장·복원은 M4 범위입니다.
  이번 저장은 마감 결과의 완료·최고 기록만 보존합니다.
- 호스팅 CI는 PR 단계에서 확인합니다.
  사용자 5명 검증은 운영자의 명시적인 재개 지시까지 보류합니다.

## 선례 조회

개인 계정의 `chef-al-mando`에 대해 캠페인 진행·기록과 고정 시나리오·완료 기록을 조회했으나 적용 가능한 결과가 없었습니다: `[no precedent found]`.
이는 해당 조회 결과의 범위이며 프로젝트에 선례가 전혀 없다는 뜻은 아닙니다.
승인된 명세와 현재 저장소 규칙을 구현 기준으로 사용했습니다.

## iPhone 설치

운영자는 M3 변경의 커밋과 개인 iPhone 설치를 승인했습니다.
앱 소스는 `850b3fd15b0e2b6910875377c6ecb679a948eb5b`이며 빌드 시작 시 작업 트리가 깨끗했습니다.
기능 커밋은 `9b66b80`, export 검사 커밋은 `c9171c4`, 명세·로컬 검증 기록 커밋은 `850b3fd`입니다.
이 설치 기록의 후속 문서 커밋은 앱 소스를 변경하지 않습니다.

Godot `4.7.2.stable.official.ed1daf0bf`로 iOS 프로젝트를 새로 export하고, Xcode 26.6 빌드 `17F113`에서 Debug 개발 서명 앱을 만들었습니다.
iOS export와 Xcode 빌드는 종료 코드 0이며 빌드 로그에 `BUILD SUCCEEDED`가 있습니다.
실제 `.app`의 서명 무결성을 검사했고, 그 앱의 `chef_al_mando.pck`에서 M1·M2·M3 완료 표시 네 개를 확인했습니다.
앱 식별자는 `kr.donminzzi.chefalmandodev`, 버전은 `0.0.1`, 빌드 번호는 `1`입니다.
iPhone·iPad 대상이며 두 기기군 모두 가로 방향 두 가지가 선언되어 있습니다.

```bash
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --path . --export-debug iOS build/ios/chef_al_mando.xcodeproj
xcodebuild -project build/ios/chef_al_mando.xcodeproj -scheme chef_al_mando \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-derived -jobs 2 build
codesign --verify --deep --strict --verbose=2 \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app
bash scripts/check-export.sh \
  "$PWD/build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app/chef_al_mando.pck"
```

| 산출물                   |    바이트 | SHA-256                                                            |
| ------------------------ | --------: | ------------------------------------------------------------------ |
| `.app/chef_al_mando`     | 103163552 | `3be31a0ab374147860a9e97930028b06c90580e26dfe7ccd6766b3cbfd5bfa18` |
| `.app/chef_al_mando.pck` |    214780 | `961cb0477be52af952de776bac3c58a1338e7615e44e8525f1bbe8d03141585c` |

2026-09-08 14:36 KST에 연결된 iPhone 16 Pro, iOS 26.6.1의 기존 개발 앱 위에 설치했습니다.
설치 전에 빌드와 교체 방식을 고지했고 `devicectl device install app`을 사용했습니다.
설치 JSON의 `info.outcome`은 `success`이며 같은 앱 식별자를 반환했습니다.
14:37 KST에 앱 목록을 다시 조회해 설치된 앱을 확인했습니다.
이 작업에서는 별도 앱 실행 명령을 보내지 않았습니다.
앱 삭제, 강제 종료 실행, 사용자 5명 검증 재개나 Android 설치를 하지 않았습니다.
현재 iPhone에 남긴 빌드는 위 M3 소스이며 기존 M2 설치본을 교체했습니다.

근거는 `build/check/m3-ios-export.log`, `m3-ios-build.log`, `m3-ios-codesign.log`, `m3-ios-pack.log`, `m3-ios-artifact.json`, `m3-iphone-install-850b3fd.json`, `m3-installed-after.json`입니다.
생성 Xcode 프로젝트·앱·서명 자료와 기기 JSON은 Git에 포함하지 않습니다.
이 설치 성공은 실기기 플레이 수용이나 사용자 5명 검증 통과를 뜻하지 않습니다.

## 운영자 플레이 확인

2026-09-08 운영자는 위 M3 iPhone 설치본을 플레이한 뒤 “플레이 완료했습니다. 좋습니다.”라고 보고했습니다.
이어서 푸시와 PR 리뷰 대응을 승인했습니다.
이 보고를 운영자 한 명의 설치본 플레이 확인으로 기록합니다.
시나리오별 관찰 기록이나 성능·OS 생명주기 체크리스트의 통과로 확대하지 않습니다.
사용자 5명 검증과 Android 실기기 검증은 기존 보류 상태를 유지합니다.
