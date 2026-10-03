# 정책 페이지 초안

[스토어 테스트 배포](store-distribution.md) §1의 결정에 따라 `donminzzi.kr` 하위 도메인에 게시할 개인정보 처리방침과 지원 페이지의 문안입니다.
게시 위치, 호스팅, 연결은 운영자가 정합니다.
`[게시자 이름]`, `[연락처 이메일]`, `[시행일]`은 운영자가 채우며, 임의의 값을 넣지 않습니다.

## 문안의 근거 (2026-10-03, `662cd27` 기준)

- 게임 코드(`sim/`, `content/`, `presentation/`, `persistence/`, `platform/`)와 `project.godot`, `export_presets.cfg`에서 HTTP, 소켓, WebSocket, 분석 SDK, 외부 링크 열기 API를 검색했고 일치 항목이 없었습니다.
  이 검색은 Godot 엔진 자체의 코드를 다루지 않으며, 실제 네트워크 측정을 대신하지 않습니다.
- Android preset의 `permissions/internet`은 `false`입니다.
- 앱은 `user://campaign_records.json`(캠페인 기록과 진행 중 영업, 백업 파일 포함)과 `user://settings.json`(언어, 효과음, 글자 크기)만 기기의 앱 전용 저장 공간에 씁니다.
- TestFlight는 Apple이 운영하며, 테스터의 피드백, 충돌 정보, 설치·세션 정보를 개발자에게 전달합니다.
  Play 테스트 트랙도 Google의 정책에 따라 테스터 정보를 처리합니다.
  이 처리는 앱이 아니라 배포 플랫폼이 하는 것이므로 처리방침에서 따로 밝힙니다.

코드가 이 근거를 바꾸면(네트워크, 분석, 계정, 광고 추가) 문안을 다시 써야 합니다.

## 개인정보 처리방침 (한국어)

**Chef al Mando 개인정보 처리방침**

시행일: [시행일]

[게시자 이름](이하 "개발자")은 Chef al Mando(이하 "게임")를 이용하는 분의 개인정보를 수집하지 않습니다.

1. 수집하는 개인정보
   게임은 이름, 연락처, 기기 식별자, 위치를 포함한 어떤 개인정보도 수집하지 않으며, 계정 가입이 없습니다.
2. 기기에 저장하는 정보
   게임은 진행을 이어 가기 위해 다음 정보를 기기 안의 앱 전용 저장 공간에만 저장합니다.
   - 캠페인 기록: 영업별 완료 여부, 최고 제공 수와 손익, 시도 횟수, 진행 중인 영업의 상태
   - 설정: 언어, 효과음 사용 여부, 글자 크기

   이 정보는 개발자나 다른 곳으로 전송되지 않으며, 게임을 삭제하면 함께 삭제됩니다.

3. 네트워크와 제3자
   게임은 인터넷에 연결하지 않으며, 광고, 분석 도구, 외부 서비스를 사용하지 않습니다.
   개발자는 누구에게도 개인정보를 제공하지 않습니다.
4. 테스트 배포
   TestFlight나 Google Play 테스트로 게임을 받는 경우, Apple과 Google은 각자의 개인정보 처리방침에 따라 테스터 정보를 처리합니다.
   TestFlight는 테스터가 보낸 피드백과 충돌 정보, 설치 정보를 개발자에게 전달할 수 있으며, 개발자는 이 정보를 게임의 문제 해결에만 사용합니다.
5. 문의
   개인정보와 관련한 문의는 [연락처 이메일]로 보내 주세요.
6. 변경
   이 방침이 바뀌면 이 페이지에 새 시행일과 함께 게시합니다.

## Privacy Policy (English)

**Chef al Mando Privacy Policy**

Effective date: [시행일]

[게시자 이름] ("the developer") does not collect personal information from people who play Chef al Mando ("the game").

1. Information we collect
   The game collects no personal information, including names, contact details, device identifiers, or location, and it has no accounts.
2. Information stored on your device
   To let you continue playing, the game stores the following only in its own app storage on your device.
   - Campaign records: whether each service is completed, best orders served and profit, attempt counts, and the state of a service in progress
   - Settings: language, sound effects, and text size

   This information is never sent to the developer or anywhere else, and it is deleted when you delete the game.

3. Network and third parties
   The game does not connect to the internet and uses no advertising, analytics, or external services.
   The developer shares no personal information with anyone.
4. Test distribution
   If you get the game through TestFlight or a Google Play test, Apple and Google process tester information under their own privacy policies.
   TestFlight may share feedback, crash reports, and installation information you send with the developer, who uses it only to fix problems in the game.
5. Contact
   Send privacy questions to [연락처 이메일].
6. Changes
   If this policy changes, the new version will be posted on this page with a new effective date.

## 지원 페이지 (한국어)

**Chef al Mando 지원**

문제가 있거나 의견이 있으면 [연락처 이메일]로 보내 주세요.
기기 이름, OS 버전, 앱 버전(App Store나 TestFlight의 앱 정보에 표시돼요), 문제가 생긴 영업과 상황을 함께 적어 주시면 더 빨리 확인할 수 있어요.

- 인터넷 연결 없이 플레이할 수 있어요.
- 기록은 이 기기에만 저장돼요. 게임을 삭제하면 기록도 함께 지워지고, 다른 기기로 옮길 수 없어요.

## Support (English)

**Chef al Mando Support**

If you run into a problem or have feedback, email [연락처 이메일].
Including your device model, OS version, app version (shown on the game's page in the App Store or TestFlight), and the service and situation where the problem happened helps us look into it faster.

- You can play without an internet connection.
- Your records are stored only on this device. Deleting the game deletes them, and they can't be moved to another device.
