# M1 실행 기록

<!-- cspell:words apksigner -->

작성일: 2026-09-07.
기준 문서는 [M0·M1 구현 명세](../specs/m0-m1.md)와 [구현 계획](../plans/m0-m1-implementation.md)입니다.
실행 결과는 해당 소스에서 생성한 `build/check/` 로그를 사용합니다.

## 1. 범위와 상태

고정 주방, 직원 2명, 메뉴 3종, 주문 20건, 300초 영업을 구현했습니다.
준비 요약, 주문 선택, 우선순위·담당·취소, 정지·재개, 1·2·4배속, 마감과 같은 조건 재시작을 연결했습니다.
시뮬레이션은 `RefCounted`, 정적 정의는 `Resource`를 사용하며 화면은 명령을 보내고 분리된 상태 복사본을 표시합니다.

운영자는 Android 실기기를 구매한 뒤 검증하도록 보류하고 M1 구현 착수를 승인했습니다.
이 기록은 M0 또는 M1의 전체 실기기 수용 기준 통과를 뜻하지 않습니다.
iPhone M1 완주와 Android 실기기 검증은 아직 수행하지 않았습니다.
캠페인, 프렙·배치 편집, 중간 저장, 대표 아트는 이번 변경 범위에 없습니다.

## 2. 로컬 검사

엔진은 `.godot-version`과 일치하는 `4.7.2.stable.official.ed1daf0bf`입니다.
다음 명령은 저장소 루트에서 실행합니다.

```bash
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
bash scripts/check.sh m0
bash scripts/check.sh m1
"$GODOT_BIN" --path . --script tests/capture_m1.gd
```

| 검사               | 실제로 읽는 대상                                                               | 결과                                                          |
| ------------------ | ------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| M0 회귀            | 주 화면 시작·정지·재개, 생명주기 어댑터, 안전 영역 좌표, 입력 호출 횟수        | 25개 통과                                                     |
| M1 headless        | 잘못된 콘텐츠, 원재료·배정·이동·마감 상태, 실제 tick 공급기, 주 화면 명령 경로 | 159개 통과                                                    |
| M1 렌더링          | 실제 창의 버튼 좌표와 입력 이벤트, 준비·정지·마감 화면                         | 입력 실패 0건                                                 |
| 잘못된 렌더링 배치 | 시작 버튼을 안전 영역 밖으로 이동한 fixture                                    | `rendered control must remain in the safe area: Start`로 실패 |

M1 검사는 `tests/test_m1.gd`가 콘텐츠·규칙·결정론·화면 suite를 모두 실행합니다.
첫 구현 전에 필수 구현 누락을 실패로 확인했습니다.
화면의 명령 거부 피드백은 취소와 우선순위 명령을 같은 tick에 예약하고 한 프레임에 두 tick을 처리하는 회귀로 재현했습니다.
수정 전에는 해당 assertion이 실패했고, tick별 이벤트를 공급기에 보관한 뒤 화면에서 소비하도록 수정한 후 통과했습니다.
재료 정의를 `null`로 만든 fixture는 오류 상태를 읽는 중 역참조와 화면 표시 실패를 재현했습니다.
잘못된 콘텐츠에서는 정산·보드 표시를 중단하고 안전한 오류 상태를 반환하도록 수정한 후 해당 회귀가 통과했습니다.

재료 마지막 1개 검사는 두 주문을 먼저 대기시키고 두 직원을 같은 tick에 활성화합니다.
독립된 재료 보관대 2개를 사용하므로 같은 작업대의 점유 때문에 경쟁이 사라지지 않습니다.
복수 재료 검사는 첫 수프가 마지막 곡물을 예약·소비하고 채소는 남기는 상태를 만듭니다.
두 번째 수프가 채소만 부분 예약하지 않는지 확인합니다.
서로 다른 설비 ID의 같은 작업 위치 독점과 두 직원의 실제 통로 타일 공유도 검사합니다.
예약 재고 검사 제거, 부분 재료 예약 삽입, 작업 위치 독점 검사 제거를 각각 주입했을 때 해당 assertion이 실패하는지도 확인했습니다.
각 검증 후 시뮬레이션 소스의 원래 바이트를 복원하고 전체 검사를 다시 통과했습니다.

headless 검사와 데스크톱 창 입력은 실제 모바일 터치, 안전 영역, OS의 배경 전환을 대신하지 않습니다.

## 3. 측정한 기본 결과

기본 fixture에 명령을 넣지 않고 tick 3000까지 실행한 결과입니다.

| 항목                     | 결과                           |
| ------------------------ | ------------------------------ |
| 도착·종료 주문           | 20건                           |
| 제공                     | 16건: 샐러드 7, 수프 4, 구이 5 |
| 취소·만료                | 취소 0, 만료 4                 |
| 매출                     | 14600                          |
| 구매비·인건비            | 6600, 2000                     |
| 손익·종료 현금           | 6000, 16000                    |
| 표시용 폐기 비용         | 2500                           |
| 종료 시 작업·원재료 예약 | 모두 0                         |

기본 결과의 canonical SHA256은 `935c9e3f393adc46925b6a8cbabdf6572015b61542ae8e3b3b7c3049e5172dac`입니다.
우선순위·담당·취소를 포함한 고정 명령 로그의 결과는 `8903940608bda1b2de10d66c8c540fab7b6ecf16020655c9d5c9c7be52082170`입니다.
동일 로그 반복과 서로 다른 프레임 간격의 1배·4배 공급기가 같은 tick 3000에서 일치했습니다.
이 해시는 실행 결과이며 임의로 정한 기대값이 아닙니다.

렌더링 fixture는 세 번째 주문을 취소하므로 기본 결과와 다릅니다.
이 화면에서는 제공 16, 취소 1, 미제공 3, 매출 14000, 손익 5400을 표시했습니다.
이미지는 `build/check/m1-ready.png`, `m1-paused.png`, `m1-closed.png`에 있습니다.

## 4. 구현 선택과 리뷰

초기 8 tick 프레임 상한은 측정 제안이었습니다.
블루프린트의 프로파일링 선행 조건에 따라 상한 도입을 보류하고, 정수 마이크로초 누적량의 모든 완전한 tick을 처리합니다.
일시정지 시간은 누적하지 않고 기존 잔여량은 유지합니다.
실제 성능 문제가 측정되면 tick 유실 없이 처리 상한을 별도로 검토합니다.

정적 경로는 `AStarGrid2D`의 사방 격자를 사용합니다.
직원 충돌 회피와 통로 예약은 추가하지 않았습니다.
메뉴 순서는 명세의 seed 기반 순환 공식만 사용하므로 PRNG 객체나 미사용 PRNG 상태를 추가하지 않았습니다.

시뮬레이션과 화면을 별도로 읽기 전용 리뷰했습니다.
명령 거부 피드백 유실을 수정하고 재료 경쟁·부분 예약·정지 중 명령 순서의 검증 상태를 보강했습니다.
수정 후 해당 리뷰의 차단 사항은 해소됐습니다.
추가 반대 관점 검토에서 누락된 콘텐츠 오류 경로를 보강했으며 코드의 커밋·export 준비 판정을 받았습니다.
이 판정은 모바일 실기기와 hosted CI·리뷰의 통과 판정이 아닙니다.
이후 hosted 리뷰에서 설비와 공정이 같은 빈 역할을 사용할 때 검증을 통과하는 문제를 확인했습니다.
빈 역할과 지원하지 않는 역할을 두 필드에 함께 넣은 fixture는 수정 전 2개 assertion을 실패시켰습니다.
M1의 네 가지 설비 역할만 등록하도록 수정한 뒤 M1 159개와 M0 25개 검사가 통과했습니다.
개인 계정의 프로젝트 Oracle 조회는 `[no precedent found]`였으며 선례를 가정하지 않았습니다.

## 5. 모바일 export와 남은 실기기 증거

구현 소스는 `6c8363b16e0485dbb56d75078a10ae529af889d2`입니다.
이 커밋 이후 아래 산출물을 생성했으며 문서 변경은 앱 소스를 변경하지 않습니다.
M0와 같은 로컬 Android debug keystore와 기존 Apple 개발 서명을 사용했습니다.
서명 비밀은 기록하거나 커밋하지 않았습니다.

```bash
"$GODOT_BIN" --headless --path . --export-debug Android build/android/chef-al-mando.apk
"$GODOT_BIN" --headless --path . --export-debug iOS build/ios/chef_al_mando.xcodeproj
xcodebuild -project build/ios/chef_al_mando.xcodeproj -scheme chef_al_mando \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-derived -jobs 2 build
codesign --verify --deep --strict \
  build/ios-derived/Build/Products/Debug-iphoneos/chef_al_mando.app
```

두 export, Xcode 빌드와 서명 검사는 종료 코드 0으로 끝났습니다.
Android Build Tools 36.0.0의 `apksigner verify --verbose`는 v2·v3 서명을 검증했습니다.
로그는 `build/check/m1-android-export.log`, `m1-ios-export.log`, `m1-ios-build.log`에 있습니다.
앱 ZIP은 개발용 `.app`을 보관한 파일이며 스토어 배포용 IPA가 아닙니다.

| 산출물                               | SHA-256                                                            |
| ------------------------------------ | ------------------------------------------------------------------ |
| `build/android/chef-al-mando.apk`    | `1d35377d777d9f349b5c8e27b54d3ab73ec39865c4dc306933d990153b86377b` |
| `build/ios/chef-al-mando-m1.app.zip` | `3cde73fe4a7eca09e2b9554cb3efd1063b3acf1df9c2c352782ed3925f0db450` |
| `.app/chef_al_mando` 실행 파일       | `038c09804fa79d8969e24e13e51a83015ba8810c96d852428c8fbda2f649b31d` |
| `.app/chef_al_mando.pck` 리소스      | `84a82eb58bcb7986c957fd72ddb96dde630f492d242a7e1f2cee7e21b4e413c7` |

| 대상                 | 상태                                         |
| -------------------- | -------------------------------------------- |
| M1 Android debug APK | export·서명·SHA 확인 완료                    |
| M1 iOS 개발 빌드     | export·개발 서명 빌드·SHA 확인 완료          |
| iPhone M1-12         | 설치 후 터치·배경 전환·마감·재시작 확인 필요 |
| Android M1-12        | 실기기 구매 후 검증하도록 명시적으로 보류    |
| hosted CI·리뷰       | PR에서 현재 head를 기준으로 별도 확인        |

M0의 실제 입력 횟수 검증을 먼저 마칠 수 있도록 iPhone에는 M0 진단 빌드를 유지했습니다.
M1 빌드는 아직 기기에 설치하거나 실행하지 않았습니다.
기기 실행 결과는 실제 확인 후 기록하며 PR의 현재 head CI·리뷰는 GitHub에서 별도로 확인합니다.
