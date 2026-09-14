# UI·UX 정보 위계 개선 검증

작성일: 2026-09-14.
기준 명세는 [UI·UX 정보 위계 개선](../specs/ui-ux-information-hierarchy.md)입니다.
구현 순서는 [구현 계획](../plans/ui-ux-information-hierarchy-implementation.md)에 있습니다.

## 현재 상태

명세 범위의 구현과 로컬 검증을 완료했습니다.
검토 시작 HEAD는 `84a274decefbbcdc2b35d3a1aca9889dcf2373d0`입니다.
작업공간은 시작 시 staged, unstaged와 untracked 변경이 없었습니다.
검증은 commit 전에 완료했고, 이후 변경은 `feature/ui-information-hierarchy` 브랜치에 semantic commit으로 기록합니다.

## 실패 우선 확인

| 항목 | 의도한 실패 |
| --- | --- | --- |
| 시간 표기 | M4에서 새 `경과`·`Elapsed` 예상값 7건이 실패했습니다. |
| 직원 상태 크기 | M2에서 기본 18과 큰 글씨 22 예상값 2건이 실패했습니다. |
| 마감 행동 위계 | M2에서 행동 글자 크기와 색상 예상값 2건이 실패했습니다. |
| 취소 눌림 상태 | 제품 마감 캡처에서 hover와 pressed 픽셀 차이 1건이 실패했습니다. |
| 4인 영어 상태 | 실제 렌더에서 재료 이동 문구 잘림을 확인한 뒤, M4의 간결한 번역 예상값 1건이 실패했습니다. |
| 마감 행동 렌더 대조 | 예상 글자 크기와 색상을 고의로 바꾸자 실제 action line 검사 2건이 실패했습니다. |
| 4인 영어 상태 렌더 대조 | 표시 가능 줄 수를 1로 제한하자 `fetching prep`과 `fetching raw`의 전체 표시 검사 2건이 실패했습니다. |

## 최종 자동 검증

| 검사                      | 직접 읽은 속성                                                                                            | 결과                                                   |
| ------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Godot `--check-only`      | 프로젝트 스크립트와 리소스가 Godot 4.7.2에서 로드되는지 확인했습니다.                                     | 종료 코드 0                                            |
| `scripts/check.sh m4`     | 정적 프로젝트 검사 뒤 M4가 읽는 시뮬레이션, 저장, 현지화와 화면 계약을 확인했습니다.                      | `PASS: m4 checks=1191 failures=0`                      |
| M2 대상 suite             | 직원 상태 크기·최대 줄 수와 마감 분석 위계를 직접 확인했습니다.                                           | `PASS: m2 checks=492 failures=0`                       |
| 제품 마감 캡처            | 휴대폰·태블릿, 한국어·영어, 기본·큰 글씨 배치, 4인 영어 상태의 전체 표시와 취소 상태 픽셀을 렌더했습니다. | `PASS: product rendered layouts checks=452 failures=0` |
| 한국어 휴대폰 영업 피드백 | 실제 렌더와 안전 영역, 직원 상태, 헤더 분리와 마감 행동 스타일을 확인했습니다.                            | `Service feedback rendered checks=18 failures=0`       |
| 영어 태블릿 영업 피드백   | 실제 렌더와 안전 영역, 헤더 분리와 마감 행동 스타일을 확인했습니다.                                       | `Service feedback rendered checks=18 failures=0`       |

`scripts/check.sh m4`는 ADB의 `tcp:5037` daemon에 연결하지 못했다는 경고 1건을 출력했습니다.
M4 gate는 실패 0으로 끝났고 Android 실기기 상태를 읽지는 않았습니다.

## 직접 렌더 확인

- 한국어 휴대폰 영업 화면에서 `남은 시간`과 `경과`가 각각 표시되고 직원 상태가 잘리지 않았습니다.
- 영어 태블릿 4인 화면에서 `fetching prep`이 네 줄 이내에 모두 표시되고 주방 보드와 담당 선택 영역을 침범하지 않았습니다.
- 영어 태블릿 4인 영업을 진행한 후 `fetching raw`도 네 줄 이내에 모두 표시되는 것을 확인했습니다.
- 한국어 휴대폰과 영어 태블릿 마감 화면에서 행동 문장이 관찰 본문과 같은 크기이며 구리색으로 표시됐습니다.
- 영어 태블릿 마감 헤더에서 시나리오 제목, 두 시간 값과 설정 버튼이 안전 영역 안에 표시됐습니다.
- 취소 pressed 화면은 hover 화면보다 어두운 채움과 구리색 테두리를 보여 두 상태가 분명히 구분됐습니다.

주요 렌더 파일은 `build/check/service-feedback-hot-queue-ko-large-phone-wide-activity.png`, `build/check/service-feedback-hot-queue-en-large-tablet-analysis.png`, `build/check/polish/tablet-en-large-four-employees-fetching-prep.png`, `build/check/polish/tablet-en-large-four-employees-fetching-raw.png`, `build/check/polish/phone-ko-normal-cancel-hover.png`와 `build/check/polish/phone-ko-normal-cancel-pressed.png`입니다.

## 적대적 리뷰

첫 검토는 마감 행동의 metadata 순환 검증과 4인 영어 상태의 자동 렌더 검증 누락을 MEDIUM 2건으로 분류했습니다.
마감 행동 검사는 실제 RichText action line의 렌더 폭과 픽셀 색상을 읽도록 바꿨습니다.
4인 영어 fixture는 실제 영업 중 `fetching prep`과 `fetching raw`를 모두 관찰하고 각 레이블의 전체 줄 표시를 확인하도록 바꿨습니다.
같은 적대적 리뷰어의 재검토에서는 두 지적이 모두 해소됐고 남은 finding이 없었습니다.

## 남은 외부 검증

Android 실기기, 실제 태블릿, VoiceOver와 TalkBack 검증은 이번 로컬 작업에 포함하지 않습니다.
