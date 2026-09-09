# 제품 화면·아이콘 마감 검증

검증일: 2026-09-09.
기준 자료는 [마감 명세](../specs/product-polish.md), `tests/capture_product_polish.gd`, `build/check/product-polish-artifact.json`입니다.
기준 HEAD는 `aff1826b5563d6eb98a06e8dec8abf69446b3d33`이며, 기존 메뉴별 우선순위 변경 위에 화면 마감을 적용했습니다.
커밋·푸시·배포는 하지 않았습니다.

## 구현과 화면 확인

- 공통 Theme으로 청록색 패널, 크림색 글자, 구리색 실행·선택 상태를 적용했습니다.
- 영업 목록에 제품 아이콘과 브리핑 카드를 추가했습니다.
- 준비 탭, 선택 주문, 배속과 취소 버튼의 상태를 구분했습니다.
- 주방 바닥·벽·작업 위치를 정리하고 세로 여백을 줄였습니다.
  마감 화면에서는 비활성 직원 담당 조작부를 숨겼습니다.
- 첫 설정 창의 내용 배치 후 크기를 다시 맞춰 닫기 버튼이 화면 밖으로 밀리지 않게 했습니다.
- 주문 상세의 실제 표시 상태와 펼치기·접기 문구를 동기화했습니다.

실제 Godot 장면을 한글·영문, 기본·큰 글씨, 휴대폰·태블릿 조합으로 렌더링했습니다.
영업 목록, 준비, 메뉴별 우선순위, 배치, 설정, 진행, 일시정지, 마감 결과와 분석 화면을 직접 읽었습니다.
큰 글씨에서는 실제 정책으로 완료 기록을 만든 영업 목록·엔딩·직원 네 명 장면도 확인했습니다.
화면 이미지는 `build/check/polish/`에 있습니다.

휴대폰 큰 글씨의 일반 영업 보드는 초기 검토의 약 240 × 160픽셀에서 약 290 × 194픽셀로 커졌습니다.
여러 메뉴와 직원 네 명이 있는 장면에서는 보드가 더 작아집니다.
이번 범위에서 조작부와 글자의 잘림은 확인하지 않았지만, 해당 조밀 화면의 보드 크기는 남은 비차단 제약입니다.

## 검증 결과

| 검사                                        | 직접 읽은 속성                                             | 결과                    |
| ------------------------------------------- | ---------------------------------------------------------- | ----------------------- |
| `scripts/check.sh m1`                       | 주문·재료·시간·기본 화면 회귀                              | 190개 통과              |
| `scripts/check.sh m2`                       | 준비·배치·분석·콘텐츠 회귀                                 | 378개 통과              |
| `scripts/check.sh m3`                       | 캠페인 규칙·완료 기록·화면 회귀                            | 732개 통과              |
| `scripts/check.sh m4`                       | 저장·복원·메뉴 우선순위·설정·화면 회귀                     | 1,173개 통과            |
| `scripts/check.sh m5`                       | 아이콘 원본·불투명성·전체 라이선스 본문과 스크롤           | 583개 통과              |
| `tests/capture_product_polish.gd`           | 실제 장면·주요 버튼 영역·문구·취소 상태의 렌더 픽셀        | 420개 통과              |
| `scripts/check-export.sh`에 iOS 앱 PCK 전달 | 패키지 안의 콘텐츠·캠페인 완주·저장·설정·라이선스          | 필수 완료 표시 7개 확인 |
| `tests/test_m4_restart.py`                  | 보존한 이전 PCK의 저장을 새 iOS PCK의 별도 프로세스로 복원 | 10개 통과               |
| 두 독립 리뷰                                | 지정 소스와 실제 화면의 상태·배치·테마 사용                | 수정 후 모두 승인       |

렌더 도구의 `--negative-layout`은 버튼을 안전 영역 밖으로 옮겨 예상한 영역 검사를 실패시켰습니다.
`--negative-cancel`은 취소 버튼의 테마를 제거해 hover·pressed의 경고색 픽셀 검사를 각각 실패시켰습니다.
첫 픽셀 검사에서는 갱신 전 그리기 명령을 읽는 문제가 있었으며, 두 프레임을 기다린 뒤 읽도록 수정하고 실패해야 하는 사례와 정상 사례를 다시 실행했습니다.
취소 상태는 실제 뷰포트 입력으로 만들고, 버튼 밖에서 손을 떼어 시뮬레이션 명령이 추가되지 않았음을 확인했습니다.
다른 장면의 fixture 전환은 프로그램 호출을 사용하므로 이 검사는 실기기 전체 터치 동선 검증을 뜻하지 않습니다.

최소 회귀 명령은 다음과 같습니다.

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4
/Applications/Godot.app/Contents/MacOS/Godot --path . --max-fps 60 --script tests/capture_product_polish.gd
```

## 아이콘과 모바일 산출물

제품 원본은 `assets/branding/app-icon.png`입니다.
1,254 × 1,254픽셀의 불투명 PNG이며 제작 경로는 [아이콘 기록](../../assets/branding/README.md)에 있습니다.
Trunk의 PNG 최적화 전후를 RGBA로 읽어 전체 픽셀이 같음을 확인했습니다.
비교 도구는 한 픽셀을 바꾼 실패 유도 사례를 먼저 거부했습니다.

iOS export가 만든 1,024픽셀 원본과 최종 앱의 `AppIcon60x60@2x.png`를 직접 확인했습니다.
Xcode 개발 빌드와 `codesign --verify --deep --strict`가 통과했습니다.
앱 ID `kr.donminzzi.chefalmandodev`, 버전 `0.0.1`, 빌드 `1`을 유지했습니다.
iOS PCK SHA-256은 `edcfe7fbd74f0a3c8a171238d919dff375a6cafad8272793c27f0bca02c3b88c`입니다.

Android 개발 APK export와 v2·v3 서명 검사도 통과했습니다.
운영자의 일반 이미지 처리 승인 후 투명 전경을 축소하고 여백을 추가했습니다.
`export_presets.cfg`에 전경·배경 원본을 연결하고 APK를 다시 내보냈습니다.
[Android 적응형 아이콘 규격](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)과 [Godot Android 내보내기 안내](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)의 108dp 레이어·중앙 66dp 안전 원을 기준으로 검사했습니다.

- 전경 원본의 모든 알파가 0보다 큰 픽셀은 중심에서 최대 29.006dp 안에 있습니다.
- APK의 `res/mipmap-xxxhdpi-v4/icon_foreground.webp`를 직접 읽은 최대 반경은 29.222dp로, 33dp 제한을 충족했습니다.
  배경은 불투명한 432픽셀 정사각형입니다.
- 검사 도구에 불투명 모서리 픽셀을 넣은 실패 유도 사례는 76.307dp로 거부되었습니다.
- APK manifest의 아이콘 참조와 적응형 XML의 전경·배경 ID를 리소스 표의 실제 파일 경로까지 대조했습니다.
- APK에서 추출한 두 레이어에 원형·둥근 사각형 마스크를 합성해 팬과 손잡이가 잘리지 않음을 직접 확인했습니다.
  이는 마스크 미리보기이며 Android 런처 실기기 확인은 아닙니다.
- 보정 후 `scripts/check.sh m5`는 아이콘 원본·불투명성·라이선스 화면을 검사해 583개가 통과했습니다.

근거 파일은 `build/check/polish-adaptive-{source,negative,apk,export,signature,manifest,xml,resources,m5}.log`와 `build/check/polish-adaptive-{circle,squircle}.png`입니다.
APK와 원본의 최종 SHA-256은 `build/check/product-polish-artifact.json`에 기록했습니다.
iOS 산출물은 이번 Android 전용 설정 보정 전에 만든 빌드이며, 이번 후속 작업에서 iOS 빌드를 다시 만들지는 않았습니다.

iPhone은 기기 목록에서 `unavailable`로 확인되어 이번 화면 마감판을 설치하지 못했습니다.
이번 작업에서는 기기 설치·삭제·실행을 하지 않았습니다.
실기기 화면·터치·홈 화면 아이콘 확인은 남아 있습니다.
Android 실기기·사용자 5명 검증의 기존 보류도 유지합니다.

## Oracle 적용

개인 계정의 `chef-al-mando`에서 화면 정체성·앱 아이콘에 직접 맞는 전례는 `[no precedent found]`였습니다.
공통 전례 `wiki/entities/flutter-ui-ux-review.md`와 `raw/sources/.claude/skills/flutter-ui-ux-review/references/evidence-and-runtime.md`의 실제 화면 근거 원칙을 적용했습니다.
그 결과 속성 검사에 더해 실제 상태를 만든 렌더 이미지·입력·픽셀 검사를 수행했습니다.
Flutter 구현 지침은 Godot 코드에 적용하지 않았습니다.
