# 목록 행 스크롤 제스처 구현 계획

작성일: 2026-09-14.
상태: 완료.
기준 명세는 [목록 행 스크롤 제스처](../specs/list-row-scroll-gestures.md)입니다.

## 1. 구현 방향

행 버튼 자체의 선택 동작은 유지하고, 해당 행에서 처리되지 않은 포인터 입력만 상위 `ScrollContainer`로 전달합니다.
영향 범위를 좁히기 위해 홈의 영업 행과 게임의 주문 행을 만드는 두 위치에만 입력 필터를 지정합니다.
새 입력 계층, 공통 추상화와 의존성은 추가하지 않습니다.

## 2. 작업 순서

### Task 1: 실제 입력 회귀 테스트

- [x] 실제 캠페인 장면의 영업 행과 상위 스크롤 컨테이너를 사용합니다.
- [x] 영업 행 위에서 시작한 터치 드래그가 상위 스크롤 컨테이너에 전달되지 않는 현재 실패를 확인합니다.
- [x] 20개 주문이 표시된 실제 게임 장면에서도 같은 입력 전달 실패를 확인합니다.
- [x] 드래그 뒤 선택 0회와 짧은 탭 뒤 선택 1회를 함께 확인합니다.

검증 명령은 다음과 같습니다.

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3
```

### Task 2: 행 입력 전달 수정

- [x] `presentation/campaign_screen.gd`의 영업 행에 `MOUSE_FILTER_PASS`를 적용합니다.
- [x] `presentation/main.gd`의 주문 행에 `MOUSE_FILTER_PASS`를 적용합니다.
- [x] Task 1의 같은 테스트가 통과하는지 확인합니다.

### Task 3: 회귀 검증과 기록

- [x] Godot 프로젝트 로드 검사를 실행합니다.
- [x] M4 전체 회귀 검사를 실행합니다.
- [x] 각 검사가 실제로 읽은 속성과 남은 실기기 공백을 `docs/notes/`에 기록합니다.

최종 검증 명령은 다음과 같습니다.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --quit
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4
```

## 3. 제외 범위

커밋, push, 기기 설치와 기기 실행은 이번 구현 범위에 포함하지 않습니다.
다른 종류의 스크롤 컨트롤과 전체 버튼 입력 정책은 별도 재현 증거 없이 변경하지 않습니다.
