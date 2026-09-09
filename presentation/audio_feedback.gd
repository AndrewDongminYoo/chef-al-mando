extends Node

const CUE_PATHS := {
	"arrival": "res://assets/audio/arrival.wav",
	"served": "res://assets/audio/served.wav",
	"warning": "res://assets/audio/warning.wav",
}
const WARNING_INTERVAL_MS := 1_000

var enabled: bool = true
var suspended: bool = false
var last_warning_ms: int = -WARNING_INTERVAL_MS
var players: Dictionary[String, AudioStreamPlayer] = {}


func _ready() -> void:
	for kind: String in CUE_PATHS:
		var player := AudioStreamPlayer.new()
		player.name = kind.capitalize() + "Player"
		player.stream = load(CUE_PATHS[kind]) as AudioStreamWAV
		add_child(player)
		players[kind] = player


func _exit_tree() -> void:
	_stop_players()
	for player: AudioStreamPlayer in players.values():
		player.stream = null
	players.clear()


func play_cue(kind: String) -> bool:
	if not enabled or suspended or not players.has(kind):
		return false
	var now := Time.get_ticks_msec()
	if kind == "warning" and now - last_warning_ms < WARNING_INTERVAL_MS:
		return false
	var player: AudioStreamPlayer = players[kind]
	if player.stream == null:
		return false
	player.play()
	if kind == "warning":
		last_warning_ms = now
	return true


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_stop_players()


func suspend() -> void:
	suspended = true
	_stop_players()


func resume() -> void:
	suspended = false


func _stop_players() -> void:
	for player: AudioStreamPlayer in players.values():
		player.stop()
