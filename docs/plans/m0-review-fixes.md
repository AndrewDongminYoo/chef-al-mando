# M0 코드 리뷰 후속 수정 계획

작성일: 2026-09-07 · 대상: `origin/main..main`의 M0 구현 diff(25개 파일) · 실행 방식: codex-swarm(순차 worker)

## 1. 리뷰 결과 요약

`/code-review high`의 finder 8개가 보고한 44건을 중복 제거하면 아래 20개 주제가 남습니다.
검증 근거는 각 행에 적었으며, 검증하지 않은 주장은 그대로 표시했습니다.

| #   | 위치                                                                               | 문제                                                                                                      | 근거                                                      | 처리  |
| --- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- | ----- |
| 1   | `presentation/main.gd:71`                                                          | 안전 영역 캐시 키가 `usable`만 비교해 창 크기만 바뀌면 right·bottom offset이 갱신되지 않음                | 코드 읽기로 확인; 데스크톱은 `resized` 경로가 가려 미재현 | T1    |
| 2   | `presentation/main.gd:70`                                                          | 안전 영역이 캔버스와 겹치지 않으면 빈 교집합으로 컨테이너 크기가 음수가 됨                                | headless 프로브 재현(offset_right -1424)                  | T1    |
| 3   | `presentation/main.gd:26`                                                          | 매 프레임 `DisplayServer.get_display_safe_area()` 폴링, `resized`·`_ready`와 진입점 3개                   | 코드 읽기                                                 | T1    |
| 4   | `presentation/main.gd:60`                                                          | 안전 영역 조회가 `presentation/`에 있어 AGENTS.md의 `platform/` 경계를 위반                               | AGENTS.md §Architecture Boundaries                        | T1    |
| 5   | `presentation/main.gd:74`                                                          | 24px 여백이 offset 산식에 4회 하드코딩, MarginContainer 여백 상수를 쓰지 않음                             | 코드 읽기                                                 | T1    |
| 6   | `presentation/main.gd:4,55`                                                        | 불리언 2개로 3상태 표현, `_refresh`가 상태 텍스트를 두 번 대입                                            | 코드 읽기                                                 | T1    |
| 7   | `presentation/main.gd:29`                                                          | 카운터 텍스트를 매 프레임 재포맷, 초기 텍스트는 tscn과 코드 두 곳이 소유                                  | 코드 읽기                                                 | T1    |
| 8   | `platform/app_lifecycle.gd:7`                                                      | FOCUS_OUT과 PAUSED가 한 번의 배경 전환에 `backgrounded`를 두 번 emit; 테스트가 FOCUS_OUT을 주입하지 않음  | 코드 읽기                                                 | T1    |
| 9   | `tests/test_m0.gd`, `tests/capture_m0.gd`                                          | 노드 경로 문자열 9개 중복, `has_method` 이중 guard, capture가 harness를 재구현, capture에 null guard 없음 | 코드 읽기                                                 | T1    |
| 10  | `tests/test_m0.gd:54`                                                              | 안전 영역 기대값이 headless 캔버스 크기(1280×1280)에 암묵적으로 결합, bottom offset 미검사                | 코드 읽기, 프로브에서 size=(1280,1280) 확인               | T1    |
| 11  | `tests/*.gd`                                                                       | untyped 선언(`var screen =`, `var suite =`, `for pressed in`)이 AGENTS.md의 typed GDScript 지침과 어긋남  | 코드 읽기                                                 | T1·T2 |
| 12  | `scripts/check.sh:7,35`, `run_tests.gd:10,14`                                      | suite 이름 `m0`가 4곳에 하드코딩, m1 suite를 등록하지 않음                                                | 코드 읽기                                                 | T2    |
| 13  | `scripts/check.sh:13`, `check.yml:21-29`                                           | Godot 버전 문자열이 스크립트·워크플로 5곳과 문서 5곳에 중복                                               | `grep ed1daf0bf` 6개 파일                                 | T2·T3 |
| 14  | `scripts/check.sh:20`                                                              | export 출력 디렉터리 `build/android`, `build/ios`를 만들지 않아 Godot이 export를 거부                     | finder가 scratch 사본에서 재현                            | T2    |
| 15  | `scripts/check.sh:21`                                                              | `build/.gdignore`를 매 실행 시 생성; 새 clone에서 capture나 export를 먼저 실행하면 import 오염            | 작업 트리에 `build/check/*.png.import` 잔존 확인          | T0    |
| 16  | `.vscode/settings.json`                                                            | 기기 고유 절대 경로가 공유 설정에 커밋됨                                                                  | 파일 읽기                                                 | T0    |
| 17  | `cspell.config.yaml`, `.cspell/*.txt`                                              | 추적 파일에 미등록 단어 14건, 단어 저장소가 두 곳, Team ID가 사전에 등록됨                                | `cspell --gitignore` 실행                                 | T0    |
| 18  | `AGENTS.md:40-47`                                                                  | 예외 문단과 무조건적 전제 조건 목록이 서로 모순                                                           | 파일 읽기                                                 | T3    |
| 19  | `docs/specs/m0-m1.md:23,28,290`                                                    | 템플릿·서명 확인 상태가 실행 기록과 불일치, CI 실패 프로브 문장이 워크플로와 불일치, M0-04 정책이 미기록  | 파일 읽기                                                 | T3    |
| 20  | `docs/notes/m0-verification.md:61,70`, `docs/plans/m0-m1-implementation.md:70,149` | iOS export 경로가 명세와 다름, 산출물 SHA 미기록, `~~`가 취소선으로 렌더링됨                              | 파일 읽기                                                 | T3    |

`check.yml`의 SHA-256(`cadd3204…29e4`)은 실제 아카이브(77,860,424바이트)를 내려받아 대조했으며 일치합니다.

## 2. 보류·기각 항목과 재개 조건

| 항목                                                          | 결정 | 재개 조건                                                                                                                     |
| ------------------------------------------------------------- | ---- | ----------------------------------------------------------------------------------------------------------------------------- |
| `check.sh`에서 `--import`를 조건부로 건너뛰기                 | 기각 | import 누락은 잘못된 scene 참조 프로브가 잡는 오류를 가리므로, 로컬 6초 CPU는 감수합니다.                                     |
| `ERROR:` grep이 에디터 잡음까지 잡음                          | 기각 | 명세가 요구한 검사이며 이 머신과 scratch 사본 4회 실행 모두 오탐이 없었습니다.                                                |
| CI에서 Godot 아카이브·`.godot/` 캐시                          | 기각 | finder 자신이 절감 폭을 몇 초로 평가했습니다. 러너 시간이 문제로 측정되면 재개합니다.                                         |
| SystemFont 대신 서브셋 한국어 폰트 동봉                       | 보류 | 실기기 화면 증거에서 글리프 누락이나 첫 프레임 지연이 관찰되면 재개합니다.                                                    |
| `run_tests.gd`가 자체 타이머로 timeout을 소유                 | 보류 | M1 suite(3000 tick)가 `--quit-after 600`에 걸리는 순간 재개합니다.                                                            |
| 안전 영역 계산에서 `DisplayServer.window_get_position()` 차감 | 보류 | 모바일에서 창 위치가 0이 아닌 구성(분할 화면·폴더블)을 실기기로 확인할 때 재개합니다. #2의 fallback이 최악의 경우만 막습니다. |
| `docs/plans/PLAN.md:42,351` 문구                              | 보류 | 블루프린트 변경은 AGENTS.md가 명시적 승인을 요구하므로 운영자가 승인하면 수정합니다.                                          |
| `capture_m0.gd`를 `check.sh` 플래그로 통합                    | 기각 | 렌더링 창이 필요해 CI에서 실행할 수 없으므로 수동 도구임을 파일 머리에 밝히는 것으로 대신합니다.                              |

## 3. 작업 순서

T0는 orchestrator가 직접 수행하고, T1부터 T3까지는 worker가 하나씩 순차로 수행합니다.
각 task는 다음 task가 시작되기 전에 `bash scripts/check.sh m0`로 검증합니다.

### T0. 사전 정리(orchestrator)

파일: `.godot-version`(신규), `build/.gdignore`(신규), `.gitignore`, `.vscode/settings.json`(삭제), `cspell.config.yaml`, `.cspell/cucciolo-dictionary.txt`

- `.godot-version`에 `4.7.2.stable.official.ed1daf0bf` 한 줄을 기록합니다. 이 파일이 엔진 버전의 유일한 소유자입니다.
- `build/.gdignore`를 빈 파일로 추적하고 `.gitignore`의 `/build/`를 `/build/*`와 `!/build/.gdignore`로 바꿉니다.
- `.vscode/settings.json`을 삭제합니다. 에디터 경로는 사용자 설정이 소유합니다.
- cspell: `words:`의 항목을 사전 파일로 옮기고, `export_presets.cfg`, `**/*.import`, `build/**`, `.godot/**`를 `ignorePaths`에 추가하며, 추적 파일에서 검출된 단어(`backgrounded`, `gdignore`, `xcodeproj`, `iphoneos`, `xcrun`, `unvalidated`)를 사전에 추가합니다. 사용처가 없는 사용자 핸들과 Team ID는 사전에서 제거합니다.

검증: `cspell --gitignore --no-progress "**"`가 0건, `git check-ignore build/.gdignore`가 비어 있음.

### T1. 화면·플랫폼 어댑터·테스트

파일: `platform/safe_area.gd`(신규), `platform/app_lifecycle.gd`, `presentation/main.gd`, `presentation/main.tscn`, `tests/harness.gd`(신규), `tests/test_m0.gd`, `tests/capture_m0.gd`

worker가 건드리지 않는 파일: `tests/run_tests.gd`, `*.uid`(orchestrator가 `--import`로 생성), `scripts/`, `docs/`

#### `platform/safe_area.gd`

```gdscript
extends Node

## Owns the OS safe-area query so that presentation only applies the rect it receives.
## Polls at a low rate because a 180-degree rotation changes the insets without resizing the window.

signal changed(physical_safe: Rect2i)

const POLL_INTERVAL_SECONDS := 0.25

var last_physical_safe: Rect2i = Rect2i()


func _ready() -> void:
	var poll := Timer.new()
	poll.wait_time = POLL_INTERVAL_SECONDS
	poll.timeout.connect(_poll)
	add_child(poll)
	poll.start()
	last_physical_safe = current()


## Returns the safe area in physical screen pixels, or an empty rect where the OS reports none.
func current() -> Rect2i:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return DisplayServer.get_display_safe_area()
	return Rect2i()


func _poll() -> void:
	var physical_safe := current()
	if physical_safe == last_physical_safe:
		return
	last_physical_safe = physical_safe
	changed.emit(physical_safe)
```

#### `platform/app_lifecycle.gd`

```gdscript
extends Node

## Emitted once per transition into the background.
## Focus loss (notification shade, permission dialog, call banner) counts as a background transition
## on purpose: the counter must stop whenever the player cannot see it, and a later PAUSED for the
## same transition must not emit again.
signal backgrounded

var in_background: bool = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if in_background:
				return
			in_background = true
			backgrounded.emit()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			in_background = false
```

#### `presentation/main.gd`

```gdscript
extends Control

## M0 kitchen screen: a lifecycle counter with start, pause, and resume.

enum State { READY, RUNNING, PAUSED }

const AppLifecycle := preload("res://platform/app_lifecycle.gd")
const SafeAreaSource := preload("res://platform/safe_area.gd")
const STATUS_TEXT := {
	State.READY: "준비 완료 · 시작을 눌러 주방을 확인하세요",
	State.RUNNING: "진행 중 · 언제든지 일시정지할 수 있습니다",
	State.PAUSED: "일시정지 · 재개를 눌러 계속하세요",
}

var state: State = State.READY
var elapsed_seconds: float = 0.0
var shown_tenths: int = -1
var last_usable_area: Rect2 = Rect2()
var last_canvas_size: Vector2 = Vector2.ZERO

@onready var start_button: Button = $SafeArea/Layout/Controls/Start
@onready var pause_button: Button = $SafeArea/Layout/Controls/Pause
@onready var resume_button: Button = $SafeArea/Layout/Controls/Resume
@onready var counter: Label = $SafeArea/Layout/Header/Counter
@onready var status_label: Label = $SafeArea/Layout/Status
@onready var safe_area: MarginContainer = $SafeArea
@onready var safe_area_source: SafeAreaSource = $SafeAreaSource
@onready var lifecycle: AppLifecycle = $Lifecycle


func _ready() -> void:
	start_button.pressed.connect(_start)
	pause_button.pressed.connect(_pause)
	resume_button.pressed.connect(_resume)
	lifecycle.backgrounded.connect(_pause)
	safe_area_source.changed.connect(_on_safe_area_changed)
	resized.connect(_update_safe_area)
	_update_safe_area()
	_refresh()


func _process(delta: float) -> void:
	advance(delta)


## Advances the counter by `delta` seconds while running; a no-op in every other state.
func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed_seconds += delta
	_show_counter()


func is_running() -> bool:
	return state == State.RUNNING


func _start() -> void:
	if state == State.READY:
		_set_state(State.RUNNING)


func _pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)


func _resume() -> void:
	if state == State.PAUSED:
		_set_state(State.RUNNING)


func _set_state(next: State) -> void:
	state = next
	_refresh()


func _refresh() -> void:
	start_button.disabled = state != State.READY
	pause_button.disabled = state != State.RUNNING
	resume_button.disabled = state != State.PAUSED
	status_label.text = STATUS_TEXT[state]
	_show_counter()


func _show_counter() -> void:
	var tenths := int(elapsed_seconds * 10.0)
	if tenths == shown_tenths:
		return
	shown_tenths = tenths
	counter.text = "%05.1f초" % elapsed_seconds


func _on_safe_area_changed(physical_safe: Rect2i) -> void:
	_apply_safe_area(physical_safe, get_viewport().get_screen_transform().affine_inverse())


func _update_safe_area() -> void:
	_on_safe_area_changed(safe_area_source.current())


## Applies the safe-area inset as pure offsets; design padding lives on the MarginContainer.
func _apply_safe_area(physical_safe: Rect2i, to_canvas: Transform2D) -> void:
	var canvas := Rect2(Vector2.ZERO, size)
	var usable := canvas
	if physical_safe.has_area():
		usable = canvas.intersection(to_canvas * Rect2(physical_safe))
		if not usable.has_area():
			usable = canvas
	if usable == last_usable_area and size == last_canvas_size:
		return
	last_usable_area = usable
	last_canvas_size = size
	safe_area.offset_left = usable.position.x
	safe_area.offset_top = usable.position.y
	safe_area.offset_right = usable.end.x - size.x
	safe_area.offset_bottom = usable.end.y - size.y
```

#### `presentation/main.tscn`

변경 4곳입니다. 나머지 노드는 그대로 둡니다.

- 머리글을 `[gd_scene load_steps=6 format=3]`로 바꾸고, 두 번째 `ext_resource` 아래에 `[ext_resource type="Script" path="res://platform/safe_area.gd" id="3_safe_area"]`를 추가합니다.
- `Lifecycle` 노드 바로 아래에 다음 노드를 추가합니다.

  ```plaintext
  [node name="SafeAreaSource" type="Node" parent="."]
  script = ExtResource("3_safe_area")
  ```

- `SafeArea` MarginContainer 노드의 `grow_vertical = 2` 아래에 다음 네 줄을 추가합니다.

  ```plaintext
  theme_override_constants/margin_left = 24
  theme_override_constants/margin_top = 24
  theme_override_constants/margin_right = 24
  theme_override_constants/margin_bottom = 24
  ```

- `Counter` Label 노드에서 `text = "000.0초"` 줄을 제거합니다. 초기 텍스트는 `_refresh`가 소유합니다.

#### `tests/harness.gd`

```gdscript
extends RefCounted

## Shared base for headless suites and the rendered capture script.

var checked: int = 0
var failures: int = 0


func expect(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


## Suites override this; the base fails so that a suite without a body cannot pass.
func run(_tree: SceneTree) -> void:
	expect(false, "suite must override run")


## Instantiates the project's main scene under `tree.root` with frame processing disabled.
## Returns null when the main scene setting is empty or the scene cannot be loaded.
static func boot_main(tree: SceneTree) -> Control:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty() or not ResourceLoader.exists(main_scene):
		return null
	var scene := load(main_scene) as PackedScene
	if scene == null:
		return null
	var screen := scene.instantiate() as Control
	tree.root.add_child(screen)
	screen.set_process(false)
	return screen
```

#### `tests/test_m0.gd`

```gdscript
extends "res://tests/harness.gd"

const KitchenScreen := preload("res://presentation/main.gd")

var backgrounded_count: int = 0


func run(tree: SceneTree) -> void:
	var screen := boot_main(tree) as KitchenScreen
	if screen == null:
		expect(false, "main scene must exist")
		return
	await tree.process_frame
	expect(screen.elapsed_seconds == 0.0, "counter starts at zero")
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 0.0, "ready screen must not advance")
	screen.start_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 1.0, "start advances the counter")
	screen.pause_button.pressed.emit()
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 1.0, "pause freezes the counter")
	screen.resume_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 2.0, "resume continues without resetting")
	screen.lifecycle.backgrounded.connect(_count_backgrounded)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	expect(backgrounded_count == 1, "focus loss followed by pause is one background transition")
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 2.0, "background transition freezes the counter")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	screen.advance(10.0)
	expect(screen.elapsed_seconds == 2.0, "foreground must not resume automatically")
	expect(not screen.resume_button.disabled, "resume remains usable")
	screen.resume_button.pressed.emit()
	screen.advance(1.0)
	expect(screen.elapsed_seconds == 3.0, "manual resume excludes background time")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(backgrounded_count == 2, "a later focus loss is a new background transition")
	expect(not screen.is_running(), "focus loss alone pauses the counter")
	screen.lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(screen.status_label.text == KitchenScreen.STATUS_TEXT[KitchenScreen.State.PAUSED], "status text follows the state")
	expect(screen.counter.text == "003.0초", "counter text shows tenths of a second")
	screen.resized.disconnect(screen._update_safe_area)
	screen.size = Vector2(1280, 720)
	var to_canvas := Transform2D.IDENTITY.scaled(Vector2(0.5, 0.5))
	screen._apply_safe_area(Rect2i(100, 0, 2460, 1440), to_canvas)
	expect(screen.safe_area.offset_left == 50.0, "physical left inset converts to logical units")
	expect(screen.safe_area.offset_right == 0.0, "unobscured right edge has no inset")
	screen._apply_safe_area(Rect2i(0, 0, 2460, 1400), to_canvas)
	expect(screen.safe_area.offset_left == 0.0, "rotation releases the old left inset")
	expect(screen.safe_area.offset_right == -50.0 and screen.safe_area.offset_bottom == -20.0, "rotation applies the new insets without resizing")
	screen.size = Vector2(1400, 800)
	screen._apply_safe_area(Rect2i(0, 0, 2460, 1400), to_canvas)
	expect(screen.safe_area.offset_right == -170.0 and screen.safe_area.offset_bottom == -100.0, "a resize with an unchanged safe rect recomputes the far edges")
	screen._apply_safe_area(Rect2i(5000, 5000, 100, 100), to_canvas)
	expect(screen.safe_area.offset_left == 0.0 and screen.safe_area.offset_right == 0.0 and screen.safe_area.offset_bottom == 0.0, "a safe rect outside the canvas falls back to the full canvas")
	screen.queue_free()
	await tree.process_frame


func _count_backgrounded() -> void:
	backgrounded_count += 1
```

기대값 근거: 캔버스 1280×720에서 물리 rect `(100, 0, 2460, 1440)`은 0.5배 변환 뒤 `(50, 0)`부터 `(1280, 720)`이므로 left 50, right 0입니다.
`(0, 0, 2460, 1400)`은 `(0, 0)`부터 `(1230, 700)`이므로 right −50, bottom −20이고, 캔버스를 1400×800으로 바꾸면 같은 usable rect에서 right −170, bottom −100이어야 합니다.
`resized`를 끊는 이유는 데스크톱에서 `size` 대입이 `resized`를 동기적으로 emit해 빈 안전 영역으로 캐시를 초기화하기 때문이며, 실기기에서는 안전 영역이 그대로인 채 창만 커지는 경로가 이 회귀를 재현합니다.

#### `tests/capture_m0.gd`

```gdscript
extends SceneTree

## Manual desktop tool: renders the M0 screen in a real window, saves two screenshots under
## build/check, and checks that rendered hit targets and one touch each produce one action.
## Not part of scripts/check.sh because it needs a rendered window; see docs/notes/m0-verification.md.
## Keep the window focused while it runs: losing focus pauses the counter through the lifecycle adapter.

const Harness := preload("res://tests/harness.gd")
const KitchenScreen := preload("res://presentation/main.gd")

var checks := Harness.new()
var touch_actions: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: capture requires a rendered window")
		quit(1)
		return
	var screen := Harness.boot_main(self) as KitchenScreen
	if screen == null:
		printerr("FAIL: main scene must exist")
		quit(1)
		return
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/check")
	await save_frame("res://build/check/m0-ready.png")
	await click(screen.start_button)
	checks.expect(screen.is_running(), "start hit target starts the counter")
	screen.advance(12.3)
	await click(screen.pause_button)
	checks.expect(not screen.is_running(), "pause hit target stops the counter")
	await save_frame("res://build/check/m0-paused.png")
	await click(screen.resume_button)
	checks.expect(screen.is_running(), "resume hit target resumes the counter")
	screen.pause_button.pressed.connect(func() -> void: touch_actions += 1)
	await tap(screen_point(screen.pause_button), _touch_event)
	checks.expect(touch_actions == 1 and not screen.is_running(), "one touch pauses exactly once (actions=%d)" % touch_actions)
	print("Touch actions=%d" % touch_actions)
	print("Rendered input failures=%d" % checks.failures)
	screen.queue_free()
	await process_frame
	quit(1 if checks.failures > 0 else 0)


func screen_point(button: Button) -> Vector2:
	return root.get_screen_transform() * button.get_global_rect().get_center()


## Sends a press and a release built by `make_event(point, pressed)`, one frame apart.
func tap(point: Vector2, make_event: Callable) -> void:
	for pressed: bool in [true, false]:
		var event: InputEvent = make_event.call(point, pressed)
		Input.parse_input_event(event)
		await process_frame


func click(button: Button) -> void:
	var point := screen_point(button)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await tap(point, _mouse_event)


func _mouse_event(point: Vector2, pressed: bool) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _touch_event(point: Vector2, pressed: bool) -> InputEvent:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = pressed
	return touch


func save_frame(file_path: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(file_path)
	checks.expect(result == OK, "could not save rendered frame")
```

검증: `bash scripts/check.sh m0`가 `PASS: m0 checks=20 failures=0`을 출력합니다(기존 `run_tests.gd`는 harness 기반 suite와 호환됩니다).
`"$GODOT_BIN" --path . --resolution 960x540 --script tests/capture_m0.gd`가 `Touch actions=1`, `Rendered input failures=0`으로 종료 코드 0을 반환합니다.

### T2. suite 등록·check 스크립트·CI

파일: `tests/run_tests.gd`, `scripts/check.sh`, `.github/workflows/check.yml`

#### `tests/run_tests.gd`

```gdscript
extends SceneTree

const Harness := preload("res://tests/harness.gd")
## Required suites are registered here even before their script exists, so that a missing
## suite fails as "cannot load" instead of passing or looking like a typo.
const SUITES := {
	"m0": "res://tests/test_m0.gd",
	"m1": "res://tests/test_m1.gd",
}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--suite" or not SUITES.has(args[1]):
		printerr("FAIL: usage is --suite <%s>" % "|".join(PackedStringArray(SUITES.keys())))
		quit(1)
		return
	var suite_name: String = args[1]
	var suite_script := load(SUITES[suite_name]) as GDScript
	if suite_script == null:
		printerr("FAIL: cannot load %s suite" % suite_name)
		quit(1)
		return
	var suite: Harness = suite_script.new()
	await suite.run(self)
	if suite.checked == 0 or suite.failures > 0:
		printerr("FAIL: %s checks=%d failures=%d" % [suite_name, suite.checked, suite.failures])
		quit(1)
		return
	print("PASS: %s checks=%d failures=0" % [suite_name, suite.checked])
	quit(0)
```

#### `scripts/check.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [[ $# -gt 1 ]]; then
	echo "FAIL: usage is check.sh [suite]" >&2
	exit 1
fi
suite="${1:-m0}"

godot_bin="${GODOT_BIN:-godot}"
expected_version="$(tr -d '[:space:]' <.godot-version)"
actual_version="$("$godot_bin" --version)"
if [[ $actual_version != "$expected_version" ]]; then
	echo "FAIL: Godot version must be $expected_version (found $actual_version)" >&2
	exit 1
fi

mkdir -p build/check build/android build/ios
run_engine() {
	local log_file="$1"
	shift
	local status=0
	"$godot_bin" --headless --path "$repo_dir" "$@" 2>&1 | tee "$log_file" || status=$?
	if ((status != 0)) || grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:)' "$log_file"; then
		echo "FAIL: engine run failed with exit $status; see $log_file" >&2
		return 1
	fi
}

run_engine build/check/import.log --import
run_engine "build/check/$suite.log" --max-fps 120 --quit-after 600 \
	--script tests/run_tests.gd -- --suite "$suite"
if ! grep -Eq "^PASS: $suite checks=[1-9][0-9]* failures=0\$" "build/check/$suite.log"; then
	echo "FAIL: $suite completion marker is missing" >&2
	exit 1
fi
```

#### `.github/workflows/check.yml`

`Install pinned Godot` 단계만 아래로 바꿉니다. 체크섬은 아카이브별 값이므로 유일한 독립 literal로 남습니다.

```yaml
- name: Install pinned Godot
  env:
    GODOT_SHA256: cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
  run: |
    version="$(tr -d '[:space:]' < .godot-version)"
    release="$(cut -d. -f1-3 <<< "$version")-$(cut -d. -f4 <<< "$version")"
    archive="Godot_v${release}_linux.x86_64.zip"
    curl --fail --location --retry 2 \
      "https://github.com/godotengine/godot-builds/releases/download/$release/$archive" \
      --output "$RUNNER_TEMP/$archive"
    echo "$GODOT_SHA256  $RUNNER_TEMP/$archive" | sha256sum --check
    unzip -q "$RUNNER_TEMP/$archive" -d "$RUNNER_TEMP/godot"
    echo "GODOT_BIN=$RUNNER_TEMP/godot/${archive%.zip}" >> "$GITHUB_ENV"
```

`run_engine`의 `|| status=$?`는 `set -e`가 엔진의 비정상 종료에서 함수를 중단시켜 진단 문장 없이 끝나던 경로를 막습니다.

`4.7.2.stable.official.ed1daf0bf`에서 `cut -d. -f1-3`은 `4.7.2`, `-f4`는 `stable`이므로 release는 `4.7.2-stable`, 아카이브는 `Godot_v4.7.2-stable_linux.x86_64.zip`, 바이너리는 확장자를 뺀 이름이 되어 기존 세 literal과 같습니다.

검증: `bash scripts/check.sh m0` 통과, `bash scripts/check.sh m1`이 `FAIL: cannot load m1 suite`로 종료 코드 1, `bash scripts/check.sh m0 extra`가 usage 오류, `shellcheck scripts/check.sh` 경고 0, `trunk check scripts/check.sh .github/workflows/check.yml` 통과.

### T3. 문서 정합성

파일: `README.md`, `AGENTS.md`, `docs/specs/m0-m1.md`, `docs/plans/m0-m1-implementation.md`, `docs/notes/m0-verification.md`

각 파일의 언어(AGENTS.md는 영어, 나머지는 한국어)를 유지하고, 한 문장마다 줄을 바꾸는 기존 형식을 따릅니다.

- `README.md` 12행 엔진 행: `Godot Standard(버전은 저장소 루트의 \`.godot-version\`이 소유), 같은 버전의 export template, Compatibility 렌더러를 사용합니다.`
- `README.md` 93-97행 코드 블록: `export GODOT_BIN=…`과 `bash scripts/check.sh m0` 두 줄을 제거하고 `"$GODOT_BIN" --path .`만 남깁니다. 블록 앞 문장에 `검사 명령은 [구현 명세의 검증 명령 계약](docs/specs/m0-m1.md)이 소유합니다.`를 추가합니다.
- `AGENTS.md` 33행: `The M0 implementation specification pins the Godot version recorded in \`.godot-version\` and the matching export templates.`
- `AGENTS.md` 40-47행(목록 포함)을 다음 두 문장으로 바꿉니다: `The M0-M1 specification defines the exact stable Godot version, the matching export-template version, the reference iPhone, the three menu fixtures, the 20-order fixture, and the exact local and CI verification commands.` / `The reference Android device is not defined yet; the 2026-09-07 exception above covers M0 preparation without it, and M0 approval still waits for it.`
- `docs/specs/m0-m1.md` 22행 엔진 행: 구현 기준을 "Godot Standard, 버전은 `.godot-version`"으로, 확인 상태를 "설치된 바이너리의 `--version`과 일치 확인"으로 바꿉니다.
- 23행 템플릿 행 확인 상태: `공식 릴리스 tpz의 SHA512 대조 후 설치; [M0 실행 기록](../notes/m0-verification.md) 참조`.
- 28행 서명 행 확인 상태: `Apple 개발 서명 iOS 빌드와 Android debug keystore 서명 성공; 실행 기록 참조`.
- 30행 뒤에 문장 추가: `\`project.godot\`의 \`textures/vram_compression/import_etc2_astc=true\`는 Android·iOS export가 요구하는 텍스처 압축 설정이며 이 명세의 일부입니다.`
- 52행(M0-05 행 다음 빈 줄 뒤) 문장 추가: `배경 전환에는 OS의 일시정지 알림뿐 아니라 포커스 상실(알림 창, 권한 대화상자, 전화 배너)도 포함하며, 한 번의 전환은 한 번의 정지로 처리합니다.`
- 290행: `CI에서도 같은 wrapper를 실행합니다.` / `잘못된 fixture와 빈 suite를 거부하는 실패 프로브는 수동으로 실행하며 결과는 [M0 실행 기록](../notes/m0-verification.md)에 남깁니다.`
- `docs/plans/m0-m1-implementation.md` 45행: `- [x] \`.godot-version\`의 엔진과 동일 버전 템플릿의 출처·체크섬을 확인합니다.`
- 70행: `- [x] 명세의 export 명령으로 APK와 Xcode 프로젝트를 생성합니다. iOS 출력 경로는 명세의 \`build/ios/\` 대신 \`build/ios-final/\`을 사용했고 산출물 SHA는 기록하지 않았습니다.`
- 149행: `구현 완료 기준은 명세의 M0-01부터 M0-05까지와 M1-01부터 M1-12까지를 실제로 통과하는 것입니다.`
- `docs/notes/m0-verification.md` 14행: `- Godot: \`.godot-version\`과 일치하는 \`--version\` 출력 확인`
- 38행 결과 열: `20개 assertion 통과`(orchestrator가 최종 실행 결과로 대조합니다).
- 61행 뒤 문장 추가: `Android APK와 iOS 산출물의 SHA는 기록하지 않았고 \`build/\`는 추적하지 않으므로, 이 산출물은 커밋과 연결되지 않으며 M0-05 증거로는 재수행이 필요합니다.`
- 68행 코드 블록 앞 문장 추가: `아래 iOS export는 명세와 preset의 \`build/ios/\` 대신 \`build/ios-final/\`을 사용했습니다.`/`재현할 때는 명세의 경로를 사용하고 \`xcodebuild\`의 \`-project\`와 \`-derivedDataPath\`를 그에 맞춥니다.`
- 남은 수용 기준 목록에 추가: `- 명세 경로로 export를 재수행하고 산출물 SHA를 기록합니다.`

검증: 이 계획 문서를 제외한 `grep -rn ed1daf0bf --include='*.md' --include='*.sh' --include='*.yml' .`의 결과가 없음(`.godot-version`만 소유), 이 계획 문서를 제외한 `grep -rn '~~' docs README.md AGENTS.md`가 없음, `trunk check` markdownlint·prettier 통과.

## 4. 전체 검증

1. `bash scripts/check.sh m0` → `PASS: m0 checks=20 failures=0`
2. `bash scripts/check.sh m1` → 종료 코드 1, `FAIL: cannot load m1 suite`
3. `"$GODOT_BIN" --path . --resolution 960x540 --script tests/capture_m0.gd` → 종료 코드 0
4. `cspell --gitignore --no-progress "**"` → 0건
5. `trunk fmt` + `trunk check` → 통과
