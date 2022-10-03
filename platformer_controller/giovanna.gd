extends KinematicBody2D

signal level_day
signal level_night

class_name Giovanna

# Set these to the name of your action (in the Input Map)
export var input_left : String = "left"
export var input_right : String = "right"
export var input_jump : String = "jump"

# The max jump height in pixels (holding jump)
export var max_jump_height = 64 setget set_max_jump_height
# The minimum jump height (tapping jump)
export var min_jump_height = 40 setget set_min_jump_height
# The height of your jump in the air
export var double_jump_height = 100 setget set_double_jump_height
# How long it takes to get to the peak of the jump in seconds
export var jump_duration = 0.3 setget set_jump_duration
# Multiplies the gravity by this while falling
export var falling_gravity_multiplier = 1.3
# Set to 2 for double jump
export var max_jump_amount = 1
export var max_acceleration = 1500
export var friction = 8
export var can_hold_jump : bool = false
# You can still jump this many seconds after falling off a ledge
export var coyote_time : float = 0.1
# Only neccessary when can_hold_jump is off
# Pressing jump this many seconds before hitting the ground will still make you jump
export var jump_buffer : float = 0.1


# Nodes
onready var jump_asp = $Jump_AudioStreamPlayer
onready var walljump_area2d = $WallJump_Area2D
onready var camera: Camera2D = $Camera2D
onready var bg: Node2D = $BG


# not used
var max_speed = 100
var acceleration_time = 10


# These will be calcualted automatically
var default_gravity : float
var jump_velocity : float
var double_jump_velocity : float
# Multiplies the gravity by this when we release jump
var release_gravity_multiplier : float


var jumps_left : int
var holding_jump := false

var vel = Vector2()
var acc = Vector2()

onready var coyote_timer = Timer.new()
onready var jump_buffer_timer = Timer.new()
onready var wall_jump_mouse_disable_timer = Timer.new()

var last_wall_normal: Vector2 = Vector2.ZERO


func _init():
	default_gravity = calculate_gravity(max_jump_height, jump_duration)
	jump_velocity = calculate_jump_velocity(max_jump_height, jump_duration)
	double_jump_velocity = calculate_jump_velocity2(double_jump_height, default_gravity)
	release_gravity_multiplier = calculate_release_gravity_multiplier(
		jump_velocity, min_jump_height, default_gravity)


func _ready():
	owner.set_meta("player", self)
	
	if owner.has_signal("day"):
		owner.connect("day", self, "_on_day")
	if owner.has_signal("night"):
		owner.connect("night", self, "_on_night")
	
	add_child(coyote_timer)
	coyote_timer.wait_time = coyote_time
	coyote_timer.one_shot = true
	
	add_child(jump_buffer_timer)
	jump_buffer_timer.wait_time = jump_buffer
	jump_buffer_timer.one_shot = true
	
	add_child(wall_jump_mouse_disable_timer)
	wall_jump_mouse_disable_timer.wait_time = 0.1
	wall_jump_mouse_disable_timer.one_shot = true
	
	owner.set_meta("player", self)

func _on_day():
	emit_signal("level_day")

func _on_night():
	emit_signal("level_night")

func _physics_process(delta):
	acc.x = 0
	
	if Input.is_action_pressed("right"):
		$AnimatedSprite.play("walk")
		$AnimatedSprite.flip_h = true
	elif Input.is_action_pressed("left"):
		$AnimatedSprite.play("walk")
		$AnimatedSprite.flip_h = false
	else:
		$AnimatedSprite.play("idle")
		
	if not is_on_floor():
		$AnimatedSprite.play("air")
	
	if is_on_floor():
		coyote_timer.start()
	if is_on_wall():
		coyote_timer.start()
		vel.x = 0
	if not coyote_timer.is_stopped():
		jumps_left = max_jump_amount
	
	
	if wall_jump_mouse_disable_timer.is_stopped() or is_on_wall():
		if Input.is_action_pressed(input_left):
			acc.x = -max_acceleration
		if Input.is_action_pressed(input_right):
			acc.x = max_acceleration
	else:
		if not is_on_wall() and not is_on_floor():
			if Input.is_action_pressed(input_left) or Input.is_action_pressed(input_right):
				acc.x = last_wall_normal.x * max_acceleration
	
	
	# Check for ground jumps when we can hold jump
	if can_hold_jump:
		if Input.is_action_pressed(input_jump):
			# Dont use double jump when holding down
			if is_on_floor():
				jump()
	
	# Check for ground jumps when we cannot hold jump
	if not can_hold_jump:
		if not jump_buffer_timer.is_stopped() and is_on_floor():
			jump()
	
	# Check for jumps in the air
	if Input.is_action_just_pressed(input_jump):
		holding_jump = true
		jump_buffer_timer.start()
		
		# Only jump in the air when press the button down, code above already jumps when we are grounded
		if not is_on_floor():
			jump()
		
	
	if Input.is_action_just_released(input_jump):
		holding_jump = false
	
	
	var gravity = default_gravity
	
	if vel.y > 0: # If we are falling
		gravity *= falling_gravity_multiplier
		
	if not holding_jump and vel.y < 0: # if we released jump and are still rising
		if not jumps_left < max_jump_amount - 1: # Always jump to max height when we are using a double jump
			gravity *= release_gravity_multiplier # multiply the gravity so we have a lower jump
	
	if is_on_wall() and vel.y > 0:
		acc.y = -gravity/5
		vel.y = clamp(vel.y, 0, 500)
	else:
		acc.y = -gravity
	vel.x *= 1 / (1 + (delta * friction))
	
	# Wall jump off wall
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor():
		var zero_collision = get_slide_collision(0)
		if zero_collision:
			last_wall_normal = zero_collision.normal
			vel.x += zero_collision.normal.x * 250
			wall_jump_mouse_disable_timer.start()
	
	vel += acc * delta
	
	vel = move_and_slide(vel, Vector2.UP)


func jump():
	if jumps_left == max_jump_amount and coyote_timer.is_stopped():
		# Your first jump must be used when on the ground
		# If you fall off the ground and then jump you will be using you second jump
		jumps_left -= 1
		
	if jumps_left > 0:
		if jumps_left < max_jump_amount: # If we are double jumping
			vel.y = -double_jump_velocity
		else:
			vel.y = -jump_velocity
		jumps_left -= 1
		jump_asp.play()
	
	coyote_timer.stop()


func calculate_gravity(p_max_jump_height, p_jump_duration):
	# Calculates the desired gravity by looking at our jump height and jump duration
	# Formula is from this video https://www.youtube.com/watch?v=hG9SzQxaCm8
	return (-2 *p_max_jump_height) / pow(p_jump_duration, 2)


func calculate_jump_velocity(p_max_jump_height, p_jump_duration):
	# Calculates the desired jump velocity by lookihg at our jump height and jump duration
	return (2 * p_max_jump_height) / (p_jump_duration)


func calculate_jump_velocity2(p_max_jump_height, p_gravity):
	# Calculates jump velocity from jump height and gravity
	# formula from 
	# https://sciencing.com/acceleration-velocity-distance-7779124.html#:~:text=in%20every%20step.-,Starting%20from%3A,-v%5E2%3Du
	return sqrt(-2 * p_gravity * p_max_jump_height)


func calculate_release_gravity_multiplier(p_jump_velocity, p_min_jump_height, p_gravity):
	# Calculates the gravity when the key is released based on the minimum jump height and jump velocity
	# Formula is from this website https://sciencing.com/acceleration-velocity-distance-7779124.html
	var release_gravity = 0 - pow(p_jump_velocity, 2) / (2 * p_min_jump_height)
	return release_gravity / p_gravity


func calculate_friction(time_to_max):
	# Formula from https://www.reddit.com/r/gamedev/comments/bdbery/comment/ekxw9g4/?utm_source=share&utm_medium=web2x&context=3
	# this friction will hit 90% of max speed after the accel time
	return 1 - (2.30259 / time_to_max)


func calculate_speed(p_max_speed, p_friction):
	# Formula from https://www.reddit.com/r/gamedev/comments/bdbery/comment/ekxw9g4/?utm_source=share&utm_medium=web2x&context=3	
	return (p_max_speed / p_friction) - p_max_speed


func set_max_jump_height(value):
	max_jump_height = value
	
	default_gravity = calculate_gravity(max_jump_height, jump_duration)
	jump_velocity = calculate_jump_velocity(max_jump_height, jump_duration)
	double_jump_velocity = calculate_jump_velocity2(double_jump_height, default_gravity)
	release_gravity_multiplier = calculate_release_gravity_multiplier(
		jump_velocity, min_jump_height, default_gravity)


func set_jump_duration(value):
	jump_duration = value
	
	default_gravity = calculate_gravity(max_jump_height, jump_duration)
	jump_velocity = calculate_jump_velocity(max_jump_height, jump_duration)
	double_jump_velocity = calculate_jump_velocity2(double_jump_height, default_gravity)
	release_gravity_multiplier = calculate_release_gravity_multiplier(
		jump_velocity, min_jump_height, default_gravity)


func set_min_jump_height(value):
	min_jump_height = value
	release_gravity_multiplier = calculate_release_gravity_multiplier(
		jump_velocity, min_jump_height, default_gravity)


func set_double_jump_height(value):
	double_jump_height = value
	double_jump_velocity = calculate_jump_velocity2(double_jump_height, default_gravity)

	
