# M5 자산과 라이선스 목록

작성일: 2026-09-09.
자산 목록 갱신일: 2026-09-10.
확인 범위는 `assets/`, `icon.svg`, 프로젝트 설정과 기존 제작 기록입니다.

| 대상                                                                                                             | 출처                                                                                                                                                           | 앱에서 제공할 고지·출시 전 확인                                                                               |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Godot 엔진과 포함된 구성요소                                                                                     | `.godot-version`, 실행 바이너리의 `Engine.get_license_text()`, `Engine.get_copyright_info()`, `Engine.get_license_info()`                                      | 설정의 오픈 소스 라이선스 창에 전체 엔진 본문, 구성요소·저작권·파일·라이선스와 각 라이선스 본문을 표시합니다. |
| 화면 폰트                                                                                                        | `presentation/product_theme.tres`의 `SystemFont`에 `Apple SD Gothic Neo`, `Noto Sans CJK KR`, `Noto Sans KR`를 지정합니다. 별도 폰트 파일은 번들하지 않습니다. | 실제 기기에서 선택되는 폰트와 한글 표시를 확인해야 합니다.                                                    |
| 제품 아이콘과 Android 적응형 아이콘                                                                              | `assets/branding/`의 PNG 원본과 [제작 기록](../../assets/branding/README.md)                                                                                   | 프로젝트와 export 설정에 연결한 현재 제품 아이콘입니다. 제작 경로와 보정 기록을 보존합니다.                   |
| `icon.svg`                                                                                                       | Godot 기본 아이콘 기반의 이전 파일                                                                                                                             | 현재 `project.godot`의 앱 아이콘은 `assets/branding/app-icon.png`를 참조합니다.                               |
| `assets/m2/employee.svg`, `storage.svg`, `cold.svg`, `hot.svg`, `pass.svg`, `salad.svg`, `soup.svg`, `grill.svg` | [M2 제작 기록](m2-production.md)에 기록한 직접 작성 SVG                                                                                                        | 외부 이미지·아트 패키지를 사용하지 않았다는 제작 기록을 보존합니다.                                           |
| `assets/m2/employee_north.svg`, `employee_east.svg`, `employee_south.svg`, `employee_west.svg`                   | 기존 직원 그림의 형태를 바탕으로 화면 개선 작업에서 직접 작성한 네 방향 SVG                                                                                    | 방향별 원본을 보존합니다. 기존 `employee.svg`는 이전 제작 원본입니다.                                         |
| `assets/audio/arrival.wav`, `served.wav`, `warning.wav`                                                          | `scripts/generate-audio.py`의 주파수·엔벌로프 합성                                                                                                             | 외부 음원·목소리·음악을 사용하지 않는 생성기를 원본으로 보존합니다.                                           |
| `.import` 파일과 변환 자산                                                                                       | 위 원본을 Godot에서 import한 결과                                                                                                                              | 별도 제삼자 원본으로 분류하지 않습니다.                                                                       |

이 목록은 프로젝트 코드·자산의 재배포 라이선스를 새로 부여하지 않습니다.
새 폰트·음원·아이콘·SDK를 추가하면 해당 출처와 고지를 먼저 보완합니다.
스토어·운영체제 자체 구성요소와 향후 서명 산출물은 이 소스 목록만으로 검증하지 않습니다.

## 고지 방식의 근거

[Godot 공식 라이선스 안내](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html)는 사용자에게 고지를 제공하고 엔진 API에서 런타임 라이선스 정보를 읽는 방식을 설명합니다.
[Engine API](https://docs.godotengine.org/en/stable/classes/class_engine.html)는 구성요소별 파일·저작권·라이선스와 각 라이선스의 본문을 제공합니다.
고지는 실행 바이너리에서 읽으며, 엔진 내부의 생성 정보를 별도 사본으로 수정하지 않습니다.
