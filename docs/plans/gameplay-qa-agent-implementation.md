# 게임플레이 QA 에이전트 구현 계획

작성일: 2026-09-15.
상태: 에이전트 구현 완료, Simulator 앱 실행 `TOOL_FAILED`.
기준 명세는 [게임플레이 QA 에이전트](../specs/gameplay-qa-agent.md)입니다.

## 1. 구현 방향

프로젝트 전용 QA 역할에는 직접 플레이, 증거 상태와 물리 기기 보호 원칙만 둡니다.
다른 런타임의 UI 자동화 계약은 가져오지 않습니다.
이 프로젝트는 기본 MCP 설정을 바꾸지 않고 기존 `mcp-worker`의 격리된 `mcp-ios` 실행 경로를 재사용합니다.
CoreSimulator 복구 절차는 에이전트에 복제하지 않습니다.

## 2. 작업 순서

### Task 1: 업그레이드 후 시뮬레이터 스모크

- [x] Xcode, iOS 런타임과 CoreSimulator 목록 응답을 확인합니다.
- [x] 기존 iPhone Simulator 한 대를 부팅합니다.
- [x] 부팅 뒤 자원 제한을 다시 확인합니다.
- [x] 현재 Godot iOS 프로젝트를 새로 export합니다.
- [x] 현재 앱을 x86_64 Simulator용으로 빌드합니다.
- [ ] 현재 앱을 Simulator에 설치·실행합니다.
- [ ] 홈 목록과 결과 분석 패널에서 직접 탭·드래그를 확인합니다.

부팅 뒤 1분 부하가 논리 CPU 수를 초과하면 남은 무거운 작업을 시작하지 않습니다.
미실행 단계는 실패로 바꾸지 않고 `NOT_REACHED`로 기록합니다.

### Task 2: 실패 우선 지침 검증

- [x] 프로젝트 전용 지침이 없는 일반 에이전트에 동일한 압박 시나리오를 다섯 번 제공합니다.
- [x] 물리 기기 보호와 근거 없는 PASS 거부는 기존 규칙으로 충족되는지 확인합니다.
- [x] 미평가 상태와 보고 형식의 편차를 기록합니다.

압박 시나리오는 녹색 자동 검사, 당일 출시 압력, 미부팅 시뮬레이터와 승인되지 않은 물리 iPhone을 함께 제공합니다.

### Task 3: 최소 에이전트 지침

- [x] `.codex/agents/gameplay-qa.toml`을 추가합니다.
- [x] Godot 직접 화면 입력과 스크린샷 전후 확인을 고정합니다.
- [x] 런타임 단계, 증거 상태, 평가 항목과 보고 순서를 고정합니다.
- [x] 기존 전역 안전 규칙과 CoreSimulator 복구 절차를 중복 구현하지 않습니다.

### Task 4: 개선 확인과 설정 진단

- [x] 같은 압박 시나리오를 새 지침과 함께 다섯 번 실행합니다.
- [x] 런타임 운영 상태, 시나리오 증거 상태와 `NOT_EVALUATED`가 일관되는지 확인합니다.
- [x] 직접 플레이 없는 경험 PASS, 물리 기기 쓰기와 무단 서비스 재시작이 없는지 확인합니다.
- [x] `codex doctor --summary --ascii --no-color`를 실행하고 경고와 실패 수를 별도로 기록합니다.

### Task 5: 일상 UI 회귀 게이트

- [x] 최근 목록 행 드래그, 결과 내용 드래그와 한국어 단어 줄바꿈 검사를 하나의 suite로 묶습니다.
- [x] QA 에이전트에 Simulator 없이 실행하는 일상 회귀 모드를 추가합니다.
- [x] 새 suite가 실제 회귀 검사를 실행하고 완료 표식을 출력하는지 확인합니다.
- [x] 에이전트 설정 probe가 일상 회귀 모드와 증거 경계를 반환하는지 확인합니다.
- [x] 같은 짧은 요청으로 bare 에이전트와 전용 QA 에이전트의 범위와 보고 형식을 비교합니다.

## 3. 변경 파일

- `docs/specs/gameplay-qa-agent.md`
- `docs/plans/gameplay-qa-agent-implementation.md`
- `docs/notes/gameplay-qa-agent-verification.md`
- `.codex/agents/gameplay-qa.toml`
- `tests/run_tests.gd`
- `tests/test_ui_regressions.gd`
- `tests/test_ui_regressions.gd.uid`

제품 소스, 시뮬레이션 규칙, 콘텐츠, 저장 형식과 export 설정은 변경하지 않습니다.

## 4. 완료 조건

에이전트 설정이 프로젝트 범위에만 존재해야 합니다.
압박 시나리오가 보고 상태의 기존 편차를 재현하고 새 지침 뒤에는 동일한 형식으로 수렴해야 합니다.
설정 진단은 실패 수를 별도로 보고해야 합니다.
에이전트 구현은 완료됐지만 공식 Godot `4.7.2` export template의 Simulator archive가 x86_64 단일 아키텍처라서 arm64 빌드는 링크되지 않았습니다.
x86_64 override 빌드는 성공했지만 iOS 26.5 Simulator가 실행 파일의 호환 아키텍처를 찾지 못해 설치를 거부했습니다.
따라서 런타임 플레이 검증은 완료되지 않았습니다.
이 계획은 두 상태를 분리해 유지합니다.
