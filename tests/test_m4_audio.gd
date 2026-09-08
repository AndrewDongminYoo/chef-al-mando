extends "res://tests/harness.gd"

const AudioFeedback := preload("res://presentation/audio_feedback.gd")


func run(tree: SceneTree) -> void:
	var feedback := AudioFeedback.new()
	tree.root.add_child(feedback)
	expect(feedback.play_cue("arrival"), "an arrival cue starts a real player")
	var arrival: Variant = feedback.get_node_or_null("ArrivalPlayer")
	var arrival_player: AudioStreamPlayer = arrival as AudioStreamPlayer
	var arrival_ready: bool = arrival_player != null and arrival_player.stream is AudioStreamWAV and arrival_player.playing
	expect(arrival_ready,
		"arrival uses a product PCM WAV stream through AudioStreamPlayer")
	if not arrival_ready:
		feedback.queue_free()
		await tree.process_frame
		await tree.process_frame
		return
	feedback.set_enabled(false)
	expect(not arrival.playing, "muting stops active player playback")
	feedback.set_enabled(true)
	expect(feedback.play_cue("served"), "enabling sound permits a new served cue")
	var served: Variant = feedback.get_node_or_null("ServedPlayer")
	var served_player: AudioStreamPlayer = served as AudioStreamPlayer
	var served_ready: bool = served_player != null and served_player.playing
	expect(served_ready, "served cue has an active real player")
	if not served_ready:
		feedback.queue_free()
		await tree.process_frame
		await tree.process_frame
		return
	feedback.suspend()
	expect(not served.playing, "suspending stops active playback")
	feedback.resume()
	expect(not served.playing, "resuming never replays the interrupted cue")
	expect(feedback.play_cue("warning"), "a new warning can play after resume")
	expect(not feedback.play_cue("warning"), "warning cues are rate limited for one real second")
	var retry_started_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - retry_started_ms < 1_050:
		await tree.process_frame
	expect(feedback.play_cue("warning"), "warning cues play again after the real-time limit")
	expect(not feedback.play_cue("unknown"), "unknown audio cue IDs are rejected")
	await tree.create_timer(0.3).timeout
	feedback.set_enabled(false)
	feedback.queue_free()
	await tree.process_frame
	await tree.process_frame
