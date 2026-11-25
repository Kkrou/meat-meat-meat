extends Area3D

@onready var color_rect: ColorRect = $"../Bliss-endScreen"
@onready var label: Label = $"../Bliss-endScreen/Bliss"

var triggered := false

func _ready() -> void:
	color_rect.hide()
	label.modulate.a = 0.0
	body_entered.connect(_on_body_entered)

func enable_rect() -> void:
	color_rect.show()

func _on_body_entered(body: Node3D) -> void:
	if triggered:
		return
	if body.is_in_group("player"):
		triggered = true
		enable_rect()
		_play_end_sequence()

func _play_end_sequence() -> void:
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 1.0, 0.25)

	await get_tree().create_timer(5.0).timeout
	if is_inside_tree():
		get_tree().quit()
