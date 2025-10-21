extends CharacterBody2D

const SPEED := 1850.0
const JUMP_VELOCITY := -3600.0

# --- ledge tuning ---
const RAY_FORWARD := 46.0     # forward reach of rays (increase if still missing ledges)
const HANG_X_DIST := 35.0     # stand-off from wall when hanging
const HAND_Y_OFF  := -410.0      # hands below the ledge top (visual tweak)

@onready var spined_archer: SpineSprite = $SpineSprite
@onready var archer: Node2D = $Archer
@onready var archer_anim: AnimationPlayer = $Archer/AnimationPlayer
@onready var grab_hand_ray_cast: RayCast2D = $GrabHandRayCast   # head/eye level (placed in editor)
@onready var grab_check_ray_cast: RayCast2D = $GrabCheckRayCast # chest level (placed in editor)

var _ledge_snap_point := Vector2.ZERO
var _using_jump_proxy := false
var _archer_anim_finished := false
var _current_anim := ""
var isGrabbing := false
var _ledge_facing: float = 1.0  # +1 right, -1 left while hanging

func _ready() -> void:
	# RayCast setup
	grab_hand_ray_cast.enabled = true
	grab_check_ray_cast.enabled = true
	grab_hand_ray_cast.set_exclude_parent_body(true)
	grab_check_ray_cast.set_exclude_parent_body(true)
	# Visuals
	spined_archer.visible = true
	archer.visible = false
	archer.z_index = spined_archer.z_index + 1
	# Jump clip finished
	archer_anim.animation_finished.connect(_on_archer_anim_finished)

# ------------ Jump proxy helpers ------------
func _start_jump_visual() -> void:
	_using_jump_proxy = true
	_archer_anim_finished = false
	if archer_anim:
		archer_anim.stop(true)
		archer_anim.seek(0.0, true)
	archer.visible = true
	spined_archer.visible = false
	if archer.has_method("play_jump_animation"):
		archer.call("play_jump_animation")
	elif archer_anim and archer_anim.has_animation("new_animation"):
		archer_anim.play("new_animation")

func _end_jump_visual() -> void:
	_using_jump_proxy = false
	archer.visible = false
	spined_archer.visible = true

func _on_archer_anim_finished(name: String) -> void:
	if name == "new_animation":
		_archer_anim_finished = true

# ------------ Ledge helpers ------------
func _end_ledge_grab() -> void:
	isGrabbing = false
	_using_jump_proxy = false
	if archer_anim:
		archer_anim.stop(true)
		archer_anim.seek(0.0, true)
	archer.visible = false
	spined_archer.visible = true

func _aim_ledge_rays() -> void:
	# Keep ray origins from the editor; only adjust direction/length
	var facing: float = 1.0 if spined_archer.scale.x >= 0.0 else -1.0
	grab_check_ray_cast.target_position = Vector2(RAY_FORWARD * facing, 0.0)
	grab_hand_ray_cast.target_position  = Vector2(RAY_FORWARD * facing, 0.0)

func _check_ledge_grab() -> void:
	# Must be falling, chest ray hits wall, head ray clear
	var is_falling: bool = velocity.y > 0.0
	var chest_hits: bool = grab_check_ray_cast.is_colliding()
	var head_clear: bool = not grab_hand_ray_cast.is_colliding()
	var can_grab: bool = is_falling and chest_hits and head_clear and not is_on_floor() and not isGrabbing
	if not can_grab:
		return

	# Compute hang point from chest hit with small offsets
	var facing: float = 1.0 if spined_archer.scale.x >= 0.0 else -1.0
	_ledge_facing = facing  # remember which side we're hanging on
	var wall_point: Vector2 = grab_check_ray_cast.get_collision_point()
	_ledge_snap_point = wall_point + Vector2(-HANG_X_DIST * facing, -HAND_Y_OFF)

	# Enter grab state + play ledge clip on Archer proxy
	isGrabbing = true
	_using_jump_proxy = true
	archer.visible = true
	spined_archer.visible = false
	if archer_anim:
		archer_anim.stop(true)
		archer_anim.seek(0.0, true)
		if archer_anim.has_animation("GrabLedge"):   # ensure exact name
			archer_anim.play("GrabLedge")

# ------------ Main loop ------------
func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()

	# Gravity
	if not was_on_floor:
		var gravity := get_gravity() * 8.0
		if velocity.y > 0.0:  # falling
			gravity *= 1.5
		velocity += gravity * delta

	# Jump (also allowed from ledge)
	if Input.is_action_just_pressed("jump") and (was_on_floor or isGrabbing):
		isGrabbing = false
		velocity.y = JUMP_VELOCITY
		_start_jump_visual()

	# Read input and flip visuals
	var direction := Input.get_axis("move_left", "move_right")
	if direction < 0.0:
		spined_archer.scale.x = -abs(spined_archer.scale.x)
		archer.scale.x = -abs(archer.scale.x)
	elif direction > 0.0:
		spined_archer.scale.x =  abs(spined_archer.scale.x)
		archer.scale.x =  abs(archer.scale.x)

	# Aim rays AFTER flip, then try to grab
	_aim_ledge_rays()
	_check_ledge_grab()

	# Hanging: snap, lock facing, and optional drop on opposite input
	if isGrabbing:
		global_position = _ledge_snap_point
		velocity = Vector2.ZERO

		# Optional: push opposite direction to drop
		var dir := Input.get_axis("move_left", "move_right")
		if dir != 0.0 and dir != _ledge_facing:
			_end_ledge_grab()
			return

		# Climb/jump or drop via actions
		if Input.is_action_just_pressed("jump"):
			_end_ledge_grab()
			velocity.y = JUMP_VELOCITY
			_start_jump_visual()
		elif Input.is_action_just_pressed("ui_down"):
			_end_ledge_grab()
		return

	# Drive Spine only when not using proxy
	if not _using_jump_proxy:
		if is_on_floor():
			if abs(velocity.x) < 5.0:
				_play_anim("Idle", true)
			else:
				_play_anim("Run", true)

	# Horizontal movement
	if direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()

	# On landing, kill jump proxy and snap to loop immediately
	if _using_jump_proxy and is_on_floor():
		if archer_anim:
			archer_anim.stop(true)
			archer_anim.seek(0.0, true)
		_archer_anim_finished = false
		_end_jump_visual()
		_current_anim = ""  # force next _play_anim
		if abs(velocity.x) < 5.0:
			_play_anim("Idle", true)
		else:
			_play_anim("Run", true)

func _play_anim(name: String, loop: bool) -> void:
	if _current_anim == name:
		return
	_current_anim = name
	spined_archer.get_animation_state().set_animation(name, loop, 0)  # your runtime's arg order
