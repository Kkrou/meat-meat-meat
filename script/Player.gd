extends CharacterBody3D

# --- MOVEMENT ---
const SPEED = 4.0
const SENSITIVITY = 0.001
const BOB_FREQ = 2
const BOB_AMP = 0.08
var t_bob = 0.0
var gravity = 9.8

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# --- CLAW ---
@export_group("Claw")
@export var feet_head_y: float = 0.3          # head height (local Y) at the 8th click
@export var cycles: int = 4                   # 1 cycle = left click + right click
@export var lock_look_while_clawing := true   # also locks mouse look during the sequence
@export var auto_start_for_testing := false   # starts the sequence on launch (testing only)

@export_group("Claw Step Feel")
@export var drop_time: float = 0.18           # fall duration per click (lower = more violent)
@export var impact_dip: float = 0.06          # how far it goes below the target on impact
@export var recover_time: float = 0.3         # time to come back up after the impact

@export_group("Claw Final Collapse")
@export var final_drop_depth: float = 0.15    # how far it falls below feet_head_y
@export var final_drop_time: float = 0.22     # dead-weight fall (short)
@export var final_pause: float = 0.35         # pause on the ground
@export var final_rise: float = 0.25          # how much it rises from the lowest point
@export var final_rise_time: float = 2.0      # slow rise
@export var final_pitch_dive_deg: float = 30.0  # how far the view pitches down
@export var final_fov_kick: float = 12.0        # extra FOV degrees during the fall
@export var final_shake: float = 0.08           # impact shake strength

@export_group("Claw UI")
@export var left_prompt_label: Label          # drag your [Left Click] label here
@export var right_prompt_label: Label         # drag your [Right Click] label here
@export var prompt_fade_time: float = 0.5
@export var final_label: Label                # drag "Reach The Hole" here
@export var final_label_fade_time: float = 1.5
@export var final_label_hold_time: float = 1.5   # seconds visible before fading out (0 = stays on screen)
@export var final_label_fade_out_time: float = 1.5
@export var lock_movement_at_start := true    # keeps the player locked while the intro plays

@export_group("Claw Effects")
@export var claw_effect: Node                 # drag the blood effect node here (its root must be a Node3D to lower with the head)
@export var finish_effect_with_animation := true   # stop spawning early so the last particles end with the animation
@export var effect_min_emit_time: float = 0.8      # blood spawns for at least this long after each click
@export_range(0.0, 1.0) var effect_follow_factor: float = 0.5   # 0 = stays put, 1 = drops exactly as much as the head

enum ClawState { NONE, WAITING_INPUT, ANIMATING, DONE }
var claw_state = ClawState.NONE
var movement_locked := false
var expect_left := true
var steps_done := 0
var standing_head_y := 0.0
var step_height := 0.0
var final_label_tween: Tween
var effect_base_y := 0.0                      # world height of the effect when the game starts

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	standing_head_y = head.position.y
	movement_locked = lock_movement_at_start
	if left_prompt_label:
		left_prompt_label.modulate.a = 0.0
	if right_prompt_label:
		right_prompt_label.modulate.a = 0.0
	if final_label:
		final_label.visible = true
		final_label.modulate.a = 0.0
	_set_effect_emitting(false)
	# remember where the effect starts (only its height is ever changed)
	var fx := claw_effect as Node3D
	if fx:
		effect_base_y = fx.global_position.y
	if auto_start_for_testing:
		start_claw_sequence()

# Lowers the effect (vertically only) by a fraction of the head's drop
func _process(_delta):
	var fx := claw_effect as Node3D
	if fx:
		var drop = standing_head_y - head.position.y
		fx.global_position.y = effect_base_y - drop * effect_follow_factor

# Lock the player manually (the intro script calls this)
func lock_movement():
	movement_locked = true

# Called by the intro when the last label has faded out
func start_claw_sequence():
	if claw_state != ClawState.NONE:
		return
	var total_steps = cycles * 2
	step_height = (standing_head_y - feet_head_y) / total_steps
	steps_done = 0
	expect_left = true
	movement_locked = true
	_show_prompt(true)   # [Left Click] fades in
	claw_state = ClawState.WAITING_INPUT

# --- BLOOD EFFECT ---
# Returns the "main" particle nodes inside the effect (sub-emitters are excluded:
# they are driven by the main particles' collisions and are never touched here).
func _get_main_particles() -> Array:
	var all: Array = []
	if claw_effect == null:
		return all
	if claw_effect is GPUParticles3D or claw_effect is CPUParticles3D:
		all.append(claw_effect)
	all.append_array(claw_effect.find_children("*", "GPUParticles3D", true, false))
	all.append_array(claw_effect.find_children("*", "CPUParticles3D", true, false))

	var sub_emitters: Array = []
	for p in all:
		if p is GPUParticles3D and not p.sub_emitter.is_empty():
			var n = p.get_node_or_null(p.sub_emitter)
			if n:
				sub_emitters.append(n)

	var main: Array = []
	for p in all:
		if not (p in sub_emitters):
			main.append(p)
	return main

func _set_effect_emitting(on: bool):
	for p in _get_main_particles():
		p.emitting = on

# Longest particle lifetime among the main emitters (in real seconds)
func _effect_lifetime() -> float:
	var longest := 0.0
	for p in _get_main_particles():
		longest = max(longest, p.lifetime / max(p.speed_scale, 0.01))
	return longest

# --- PROMPTS ---
# true = show [Left Click], false = show [Right Click]; the other one fades out
func _show_prompt(left: bool):
	_fade_label(left_prompt_label, 1.0 if left else 0.0)
	_fade_label(right_prompt_label, 0.0 if left else 1.0)

func _hide_prompt():
	_fade_label(left_prompt_label, 0.0)
	_fade_label(right_prompt_label, 0.0)

func _fade_label(label: Label, target_alpha: float):
	if label == null:
		return
	if label.has_meta("fade_tween"):
		var old = label.get_meta("fade_tween")
		if old is Tween and old.is_valid():
			old.kill()
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", target_alpha, prompt_fade_time)
	label.set_meta("fade_tween", tween)

# --- CLAW STEP ---
func _do_claw_step(anim_name: String):
	claw_state = ClawState.ANIMATING   # inputs are ignored from here
	_hide_prompt()                     # prompt fades out as the animation starts
	steps_done += 1
	expect_left = not expect_left
	var target_y = standing_head_y - step_height * steps_done
	var anim_length = anim_player.get_animation(anim_name).length
	anim_player.play(anim_name)

	# blood starts on the click...
	_set_effect_emitting(true)
	if finish_effect_with_animation:
		# ...and stops spawning one particle lifetime before the animation ends
		# (but never sooner than effect_min_emit_time), so the last particles
		# finish falling together with the animation
		var stop_after = max(anim_length - _effect_lifetime(), effect_min_emit_time)
		get_tree().create_timer(stop_after).timeout.connect(_set_effect_emitting.bind(false))

	# energetic fall: accelerates down, then bounces onto the target
	var tween = create_tween()
	tween.tween_property(head, "position:y", target_y - impact_dip, drop_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(head, "position:y", target_y, recover_time)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await anim_player.animation_finished
	_set_effect_emitting(false)        # safety: make sure spawning is off (nothing is cleared)
	head.position.y = target_y
	if steps_done >= cycles * 2:
		# last click: final collapse, then control returns to the player
		await _final_collapse()
		claw_state = ClawState.DONE
		movement_locked = false
		if final_label:
			if final_label_tween and final_label_tween.is_valid():
				final_label_tween.kill()
			final_label_tween = create_tween()
			final_label_tween.tween_property(final_label, "modulate:a", 1.0, final_label_fade_time)
			if final_label_hold_time > 0.0:
				final_label_tween.tween_interval(final_label_hold_time)
				final_label_tween.tween_property(final_label, "modulate:a", 0.0, final_label_fade_out_time)
	else:
		# next prompt fades in once the animation is over
		_show_prompt(expect_left)
		claw_state = ClawState.WAITING_INPUT

func _final_collapse():
	var low_y = feet_head_y - final_drop_depth
	var rest_y = low_y + final_rise
	var start_pitch = camera.rotation.x
	var dive_pitch = max(start_pitch - deg_to_rad(final_pitch_dive_deg), deg_to_rad(-40))
	var start_fov = camera.fov
	anim_player.play("claw_final")

	# head height: heavy fall, pause, slow rise
	var tween = create_tween()
	tween.tween_property(head, "position:y", low_y, final_drop_time)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_interval(final_pause)
	tween.tween_property(head, "position:y", rest_y, final_rise_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# view pitches down with the fall, then recovers slowly
	var pitch_tween = create_tween()
	pitch_tween.tween_property(camera, "rotation:x", dive_pitch, final_drop_time)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	pitch_tween.tween_interval(final_pause)
	pitch_tween.tween_property(camera, "rotation:x", start_pitch, final_rise_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# FOV widens during the fall, settles after impact
	var fov_tween = create_tween()
	fov_tween.tween_property(camera, "fov", start_fov + final_fov_kick, final_drop_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fov_tween.tween_property(camera, "fov", start_fov, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# shake right at impact, fading out
	var shake_tween = create_tween()
	shake_tween.tween_interval(final_drop_time)
	var shakes = 6
	for i in shakes:
		var s = final_shake * (1.0 - float(i) / shakes)
		shake_tween.tween_property(camera, "h_offset", randf_range(-s, s), 0.04)
		shake_tween.parallel().tween_property(camera, "v_offset", randf_range(-s, s), 0.04)
	shake_tween.tween_property(camera, "h_offset", 0.0, 0.05)
	shake_tween.parallel().tween_property(camera, "v_offset", 0.0, 0.05)

	await anim_player.animation_finished
	head.position.y = rest_y
	camera.rotation.x = start_pitch
	camera.fov = start_fov
	camera.h_offset = 0.0
	camera.v_offset = 0.0

func _unhandled_input(event):
	# Claw sequence input: left click, then right click, alternating
	if claw_state == ClawState.WAITING_INPUT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("claw_left") and expect_left:
			_do_claw_step("claw_left")
			return
		elif event.is_action_pressed("claw_right") and not expect_left:
			_do_claw_step("claw_right")
			return
	# ESC: release / recapture the mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Mouse look
	if event is InputEventMouseMotion:
		if movement_locked and lock_look_while_clawing:
			return
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	if movement_locked:
		# movement stopped during the intro, the claw sequence and the fall
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
	move_and_slide()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _on_falling_trigger_body_entered(body: Node3D) -> void:
	print("falling")
	movement_locked = true
	anim_player.play("falling")
