# 정책 페이지 초안

[스토어 테스트 배포](store-distribution.md) §1의 결정에 따라 `donminzzi.kr` 하위 도메인에 게시할 개인정보 처리방침과 지원 페이지의 문안입니다.
게시 위치, 호스팅, 연결은 운영자가 정합니다.
`[게시자 이름]`, `[연락처 이메일]`, `[시행일]`, `[보관 기간]`은 운영자가 채우며, 임의의 값을 넣지 않습니다.

## 문안의 근거 (2026-10-03, `662cd27` 기준)

- 게임 코드(`sim/`, `content/`, `presentation/`, `persistence/`, `platform/`)와 `project.godot`, `export_presets.cfg`에서 HTTP, 소켓, WebSocket, 분석 SDK, 외부 링크 열기 API를 검색했고 일치 항목이 없었습니다.
  이 검색은 Godot 엔진 자체의 코드를 다루지 않으며, 실제 네트워크 측정을 대신하지 않습니다.
- Android preset의 `permissions/internet`은 `false`입니다.
- 앱은 `user://campaign_records.json`(캠페인 기록과 진행 중 영업, 백업 파일 포함)과 `user://settings.json`(언어, 효과음, 글자 크기)만 기기의 앱 전용 저장 공간에 씁니다.
- Godot의 `user://`는 iOS에서 앱의 `Documents` 폴더이며(2026-10-03 플레이테스트 앱 컨테이너에서 확인), 앱이 백업 제외를 표시하지 않으므로 iCloud 백업에 포함될 수 있습니다([Apple 문서](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)).
  Android도 OS 백업 기능이 앱 데이터를 백업할 수 있으므로, 문안은 두 OS의 백업을 함께 밝힙니다.
- TestFlight는 Apple이 운영하며, 테스터의 피드백, 충돌 정보, 설치·세션 정보를 개발자에게 전달합니다.
  Play 테스트 트랙도 Google의 정책에 따라 테스터 정보를 처리합니다.
  이 처리는 앱이 아니라 배포 플랫폼이 하는 것이므로 처리방침에서 따로 밝힙니다.

코드가 이 근거를 바꾸면(네트워크, 분석, 계정, 광고 추가) 문안을 다시 써야 합니다.

## 개인정보 처리방침 (한국어)

**Chef al Mando 개인정보 처리방침**

시행일: [시행일]

[게시자 이름](이하 "개발자")은 Chef al Mando(이하 "게임")를 이용하는 분의 개인정보를 게임 안에서 수집하지 않습니다.
개발자가 받는 정보는 아래 4항의 테스트 피드백과 5항의 문의뿐입니다.

1. 게임이 수집하는 정보
   게임은 이름, 연락처, 기기 식별자, 위치를 포함한 어떤 개인정보도 수집하지 않으며, 계정 가입이 없습니다.
2. 기기에 저장하는 정보
   게임은 진행을 이어 가기 위해 다음 정보를 기기 안의 앱 전용 저장 공간에만 저장합니다.
   - 캠페인 기록: 영업별 완료 여부, 최고 제공 수와 손익, 시도 횟수, 진행 중인 영업의 상태
   - 설정: 언어, 효과음 사용 여부, 글자 크기

   게임은 이 정보를 개발자나 다른 곳으로 전송하지 않으며, 게임을 삭제하면 기기에서 함께 삭제됩니다.
   다만 기기의 백업 기능(iCloud 백업, Android 백업)을 켜 두었다면 운영체제가 이 정보를 기기 백업에 포함하고, 그 백업으로 복원한 기기에서 다시 불러올 수 있습니다.
   백업에 남은 사본은 Apple이나 Google의 백업 설정과 정책을 따릅니다.

3. 네트워크와 제3자
   게임은 인터넷에 연결하지 않으며, 광고, 분석 도구, 외부 서비스를 사용하지 않습니다.
   개발자는 4항과 5항으로 받은 정보를 제3자에게 제공하지 않습니다.
4. 테스트 배포
   TestFlight나 Google Play 테스트로 게임을 받는 경우, Apple과 Google은 각자의 개인정보 처리방침에 따라 테스터 정보를 처리합니다.
   TestFlight는 테스터가 보낸 피드백(의견과 스크린샷), 충돌 정보, 설치와 사용 기록을 개발자에게 전달할 수 있고, 이메일로 초대받은 테스터라면 초대에 쓴 이름과 이메일 주소도 개발자가 알게 됩니다.
   개발자는 이 정보를 테스트 운영과 게임의 문제 해결에만 사용하고, [보관 기간]이 지나면 삭제합니다.
5. 문의
   [연락처 이메일]로 문의하면 개발자는 보낸 분의 이메일 주소와 문의 내용(적어 주신 기기, OS, 앱 버전 포함)을 받습니다.
   개발자는 이 정보를 답변과 문제 해결에만 사용하고, [보관 기간]이 지나면 삭제합니다.
   개인정보와 관련한 요청도 같은 주소로 보내 주세요.
6. 변경
   이 방침이 바뀌면 이 페이지에 새 시행일과 함께 게시합니다.

## Privacy Policy (English)

**Chef al Mando Privacy Policy**

Effective date: [시행일]

[게시자 이름] ("the developer") does not collect personal information inside Chef al Mando ("the game").
The only information the developer receives is the test feedback in section 4 and the messages in section 5.

1. Information the game collects
   The game collects no personal information, including names, contact details, device identifiers, or location, and it has no accounts.
2. Information stored on your device
   To let you continue playing, the game stores the following only in its own app storage on your device.
   - Campaign records: whether each service is completed, best orders served and profit, attempt counts, and the state of a service in progress
   - Settings: language, sound effects, and text size

   The game never sends this information to the developer or anywhere else, and deleting the game deletes it from the device.
   If your device backup (iCloud Backup or Android backup) is on, the operating system may include this information in the device backup and restore it to a device restored from that backup.
   Copies kept in a backup follow Apple's or Google's backup settings and policies.

3. Network and third parties
   The game does not connect to the internet and uses no advertising, analytics, or external services.
   The developer does not share the information received under sections 4 and 5 with third parties.
4. Test distribution
   If you get the game through TestFlight or a Google Play test, Apple and Google process tester information under their own privacy policies.
   TestFlight may send the developer the feedback you submit (comments and screenshots), crash reports, and installation and usage records; if you were invited by email, the developer also knows the name and email address used for the invitation.
   The developer uses this information only to run the test and fix problems in the game, and deletes it after [보관 기간].
5. Contact
   If you email [연락처 이메일], the developer receives your email address and your message, including any device, OS, and app version details you include.
   The developer uses this only to reply and fix problems, and deletes it after [보관 기간].
   Send privacy requests to the same address.
6. Changes
   If this policy changes, the new version will be posted on this page with a new effective date.

## 지원 페이지 (한국어)

**Chef al Mando 지원**

문제가 있거나 의견이 있으면 [연락처 이메일]로 보내 주세요.
기기 이름, OS 버전, 앱 버전(App Store나 TestFlight의 앱 정보에 표시돼요), 문제가 생긴 영업과 상황을 함께 적어 주시면 더 빨리 확인할 수 있어요.

- 인터넷 연결 없이 플레이할 수 있어요.
- 기록은 이 기기 안에 저장돼요. 게임을 삭제하면 기록도 함께 지워져요.
- 기록을 다른 기기로 옮기는 기능은 없어요. 기기 백업(iCloud 백업, Android 백업)으로 복원하면 기록이 함께 돌아올 수 있어요.

## Support (English)

**Chef al Mando Support**

If you run into a problem or have feedback, email [연락처 이메일].
Including your device model, OS version, app version (shown on the game's page in the App Store or TestFlight), and the service and situation where the problem happened helps us look into it faster.

- You can play without an internet connection.
- Your records are stored on this device. Deleting the game deletes them.
- The game has no way to move records to another device. Restoring a device backup (iCloud Backup or Android backup) may bring them back.
