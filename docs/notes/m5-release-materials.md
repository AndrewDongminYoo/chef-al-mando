# M5 출시 자료 초안

작성일: 2026-09-09.
이 문서는 검토용 초안입니다.
스토어에 제출하거나 공개하지 않았습니다.
기준 자료는 [블루프린트](../plans/PLAN.md), `export_presets.cfg`, [M5 명세](../specs/m5-release-candidate.md)입니다.

## 1. 스토어 소개 문구

### 한국어

이름: Chef al Mando.
짧은 소개: 준비와 지시로 완성하는 작은 주방.

한정된 재료와 인력으로 여덟 번의 영업에 도전하세요.
영업 전에는 재료를 발주하고, 미리 준비할 음식과 설비 배치, 직원 담당을 정합니다.
영업 중에는 주문의 우선순위를 바꾸고, 잠시 멈춰 주방의 병목을 살펴보세요.
마감 뒤에는 손익과 제공률, 폐기와 지연의 원인을 확인하고 다음 운영 방식을 고민할 수 있습니다.

- 언제든 일시정지하고 1배·2배·4배 속도로 진행합니다.
- 진행 중인 영업을 저장하고 일시정지한 상태로 이어갑니다.
- 한국어·영어, 글자 크기와 효과음 설정을 제공합니다.
- 완료한 영업을 다시 선택해 개별 최고 기록에 도전합니다.

### English

Name: Chef al Mando.
Short description: Plan your kitchen. Direct each service.

Run eight services with limited ingredients and staff.
Before each service, buy ingredients, prepare food, place stations, and assign staff duties.
During service, change order priorities or pause to find delays in your kitchen.
After closing, review profit, served orders, waste, and delays to plan your next attempt.

- Pause at any time and play at 1x, 2x, or 4x speed.
- Save a service and continue from a paused state.
- Choose Korean or English, adjust text size, and turn sound effects on or off.
- Replay completed services and improve your best results.

## 2. 제출 전 확정할 항목

| 항목                 | 현재 근거와 남은 결정                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| 앱 ID                | 양 플랫폼 개발 ID는 `kr.donminzzi.chefalmandodev`입니다. 출시 ID와 기존 설치본의 이전 정책은 미확정입니다.            |
| 버전                 | 양 preset은 `0.0.1`, 빌드 `1`입니다. 배포 후보 버전·증가 규칙은 미확정입니다.                                         |
| 서명·채널            | 개발 preset을 사용합니다. 출시 서명 자격과 배포 채널·등록 상태는 확인하지 않았습니다.                                 |
| 가격                 | 6,600원은 블루프린트의 검증 전 가설입니다. 제출 가격으로 확정하지 않았습니다.                                         |
| 아이콘               | 현재 `icon.svg`는 Godot 아이콘 기반입니다. 제품용 최종 아이콘이 필요합니다.                                           |
| 화면 이미지          | 실제 후보 빌드의 폰·태블릿, 한·영 화면을 촬영해야 합니다. headless 출력은 제출 이미지가 아닙니다.                     |
| 지원·개인정보        | 운영자가 사용할 연락처와 공개 안내 URL을 확정해야 합니다. 임의 주소를 만들지 않습니다.                                |
| 연령·지역·설명 제한  | 제출 시 각 스토어의 현재 입력 계약을 확인해야 합니다. 현재 초안은 입력 길이나 심사 통과를 보장하지 않습니다.          |
| 오프라인·플레이 시간 | 로컬 완주 검사와 실제 다운로드 빌드의 네트워크 차단 검증을 구분합니다. 측정하지 않은 플레이 시간을 홍보하지 않습니다. |

## 3. 개인정보 안내에 사용할 구현 사실

현재 `persistence/campaign_store.gd`는 캠페인 기록과 진행 중인 영업을 기기의 로컬 파일에 저장합니다.
`persistence/settings_store.gd`는 언어·효과음·글자 크기 설정을 로컬 파일에 저장합니다.
Android preset의 `permissions/internet`은 `false`입니다.
2026-09-09 `sim/`, `content/`, `presentation/`, `persistence/`, `platform/`와 프로젝트·export 설정에서 HTTP·소켓·분석 SDK 식별자를 검색했으며 일치 항목은 없었습니다.
이 검색은 네트워크 측정이나 스토어의 개인정보 설문 답변 검증을 대신하지 않습니다.
최종 네이티브 산출물과 배포 채널의 동작을 확인한 뒤 공개 안내문과 스토어 응답을 확정합니다.

## 4. 베타와 다운로드 빌드 기록

Android 실기기와 사용자 5명 검증은 기존 보류 지시를 유지합니다.
운영자의 재개 지시가 있을 때 [M5 명세](../specs/m5-release-candidate.md)의 실제 출시 수용 계약에 따라 기록합니다.
참가자 정보 대신 익명 세션 ID, 기종·OS, 빌드 식별, 과제, 관찰, 차단 문제, 수정 후 재검증 결과를 남깁니다.
동의나 검증 결과를 미리 채우지 않습니다.
