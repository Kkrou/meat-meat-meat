extends VBoxContainer

@export var start_delay := 1.0     # wait before the first label
@export var fade_in_time := 1.5    # how long each label takes to fade in
@export var stagger := 2.0        # delay between each label starting
@export var hold_time := 2.5       # how long all labels stay visible
@export var fade_out_time := 1.5

func _ready() -> void:
	play_sequence()

func play_sequence() -> void:
	var labels := get_children().filter(func(c): return c is Label)

	for l in labels:
		l.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Fade in one by one
	for i in labels.size():
		tween.tween_property(labels[i], "modulate:a", 1.0, fade_in_time) \
			.set_delay(start_delay + i * stagger)

	# Fade out together, after the last label is fully in + hold
	var fade_out_start := start_delay + (labels.size() - 1) * stagger + fade_in_time + hold_time
	for l in labels:
		tween.tween_property(l, "modulate:a", 0.0, fade_out_time) \
			.set_delay(fade_out_start)
