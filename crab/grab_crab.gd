class_name GrabCrab
extends SpecialCrab
## Its ability picks up the nearest Grabbable within grab_range and holds it
## floating over its head, as if by a magnet: the prop is sprung toward a
## spot hold_gap above the shell, turned with the crab, and its weight bears
## on the crab's legs. Used again, the ability throws it in an arc to land on
## throw_target (set by Player from the view, like a jump off a stack).
##
## While carrying, no crab can mount it, but it can still mount others, as
## long as nothing would end up riding it.

@export_group("Grab")
## How near a prop's centre must be to the crab's to pick it up (m).
@export_range(0.1, 3.0, 0.01) var grab_range := 0.6
## How far above the top of the shell the prop's underside floats (m).
@export_range(0.0, 1.0, 0.01) var hold_gap := 0.08
## How quickly the prop springs back to its spot, in bounces per second.
@export_range(0.5, 10.0, 0.1) var hold_hz := 4.0
## Damping of that spring, 1 settling without overshoot.
@export_range(0.1, 2.0, 0.01) var hold_damping := 0.8
## The most the hold can pull, in multiples of the prop's weight. Something
## pressing harder than that pushes the prop out of place.
@export_range(1.0, 20.0, 0.1) var hold_strength := 6.0
## How much further from its spot the prop can be pushed than it's been
## since it was picked up, before the hold lets go (m).
@export_range(0.1, 3.0, 0.01) var break_distance := 0.4

@export_group("Throw")
## How near and far a throw lands, across the ground from the crab (m).
@export_range(0.0, 5.0, 0.01) var min_throw_radius := 0.6
@export_range(0.1, 20.0, 0.1) var max_throw_radius := 3.0
## How high a throw arcs above the higher of where it starts and lands (m).
@export_range(0.0, 3.0, 0.01) var throw_height := 0.3

## The prop it's carrying, or null.
var held: Grabbable
## Where a throw lands, and whether there's anywhere to; set by Player.
var throw_target := Vector3.ZERO
var has_throw_target := false

# The prop's turn relative to the crab's heading, as it was picked up.
var _hold_basis := Basis()
# The nearest the prop has been to its spot since it was picked up.
var _closest := 0.0


## Picks up the nearest prop in reach, or throws the one held: at
## throw_target if there is one, otherwise straight ahead as far as it can.
func use_ability() -> void:
	if is_instance_valid(held):
		if has_throw_target:
			throw_to(throw_target)
		else:
			var ahead := _heading() * max_throw_radius
			throw_to(global_position + ahead - Vector3.UP * _ride_height())
	else:
		grab(grab_candidate())


func get_controls_hint() -> String:
	return "Grab crab\nShift  grab / throw"


## The prop the ability would pick up: the nearest within grab_range that
## nobody holds and the crab isn't standing on (with most of its planted
## feet). Null with something riding it, as the prop would land on the
## rider.
func grab_candidate() -> Grabbable:
	if is_instance_valid(held) or is_instance_valid(rider):
		return null
	var best: Grabbable = null
	var best_distance := grab_range
	for node in get_tree().get_nodes_in_group(Grabbable.GROUP):
		var prop := node as Grabbable
		if not is_instance_valid(prop) or prop.is_queued_for_deletion() \
				or is_instance_valid(prop.carrier) or _standing_on(prop):
			continue
		var distance := prop.global_position.distance_to(global_position)
		if distance < best_distance:
			best = prop
			best_distance = distance
	return best


func grab(prop: Grabbable) -> bool:
	if not is_instance_valid(prop) or is_instance_valid(held):
		return false
	held = prop
	prop.carrier = self
	prop.add_collision_exception_with(self)
	# Feet on it step off, as it rises.
	for leg in _legs:
		if leg.planted and leg.collider == prop:
			leg.planted = false
			leg.has_hold = false
			leg.foot.vel = linear_velocity
		elif leg.has_hold and leg.hold_collider == prop:
			leg.has_hold = false
	_hold_basis = _heading_basis().inverse() * prop.global_basis.orthonormalized()
	_closest = prop.global_position.distance_to(get_hold_point())
	return true


## Lets go of the prop where it is, to fall.
func release() -> void:
	if is_instance_valid(held):
		held.remove_collision_exception_with(self)
		if held.carrier == self:
			held.carrier = null
	held = null


## Lets go of the prop with the speed to arc over to land on `target`.
func throw_to(target: Vector3) -> void:
	if not is_instance_valid(held):
		return
	var prop := held
	release()
	var g := prop.get_gravity().length()
	var start := prop.global_position
	var landing := target + Vector3.UP * prop.get_half_height()
	var peak := maxf(start.y, landing.y) + throw_height
	var rise := sqrt(2.0 * (peak - start.y) / g)
	var fall := sqrt(2.0 * (peak - landing.y) / g)
	var across := Vector3(landing.x - start.x, 0.0, landing.z - start.z)
	prop.linear_velocity = across / maxf(rise + fall, 1e-3) + Vector3.UP * g * rise
	prop.angular_velocity = Vector3.ZERO


## Where the ability's indicator goes: over the prop it would pick up, or
## where the one it holds would land. Null for none.
func get_ability_marker() -> Variant:
	if is_instance_valid(held):
		return throw_target if has_throw_target else null
	var prop := grab_candidate()
	return prop.get_top() if prop else null


## Where the held prop floats, its centre over the crab's.
func get_hold_point() -> Vector3:
	var lift := BODY_HALF_HEIGHT * _size + hold_gap
	if is_instance_valid(held):
		lift += held.get_half_height()
	return global_position + Vector3.UP * lift


func can_be_mounted() -> bool:
	return not is_instance_valid(held)


## Carrying, it only mounts the top of a stack, so nothing lands on it.
func can_mount(target: Node3D) -> bool:
	if is_instance_valid(held) and target is ContactCrab and is_instance_valid(target.rider):
		return false
	return super(target)


## Brings the prop along to its spot over the crab's new place.
func mount_onto(target: Node3D) -> bool:
	if not super(target):
		return false
	if is_instance_valid(held):
		held.global_position = get_hold_point()
		held.linear_velocity = linear_velocity
		held.angular_velocity = Vector3.ZERO
	return true


## A fresh crab carries nothing.
func drop_at(at: Vector3) -> void:
	release()
	super(at)


func _load_mass() -> float:
	return mass + (held.mass if is_instance_valid(held) else 0.0)


func _physics_process(delta: float) -> void:
	if is_instance_valid(held) and (held.carrier != self or held.is_queued_for_deletion()):
		release()
	if is_instance_valid(held):
		_hold(delta)
	super(delta)


## Springs the prop toward its spot, moving with the crab, and turns it with
## the crab's heading. What holds it up pushes the crab down as much.
func _hold(_delta: float) -> void:
	var target := get_hold_point()
	var error := target - held.global_position
	_closest = minf(_closest, error.length())
	if error.length() > _closest + break_distance:
		release()
		return
	var omega := TAU * hold_hz
	var weight := held.get_gravity() * held.mass
	var force := held.mass * (error * omega * omega
			+ (linear_velocity - held.linear_velocity) * 2.0 * hold_damping * omega) - weight
	force = force.limit_length(hold_strength * weight.length())
	held.apply_central_force(force)
	apply_central_force(-force)

	var want := _heading_basis() * _hold_basis
	var turn := (want * held.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	var angle := turn.get_angle()
	if angle > PI:
		angle -= TAU
	var axis: Vector3 = turn.get_axis() if angle != 0.0 else Vector3.ZERO
	var spin := Vector3.UP * angular_velocity.y
	var accel: Vector3 = axis * angle * omega * omega + (spin - held.angular_velocity) * 2.0 * hold_damping * omega
	held.apply_torque(held.get_inverse_inertia_tensor().inverse() * accel)


## The crab's heading across the ground.
func _heading() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 1e-6 else _desired_facing


## Upright, turned to the crab's heading.
func _heading_basis() -> Basis:
	return Basis.looking_at(_heading(), Vector3.UP)


func _standing_on(prop: Grabbable) -> bool:
	var on := 0
	var planted := 0
	for leg in _legs:
		if leg.planted:
			planted += 1
			if leg.collider == prop:
				on += 1
	return on * 2 > planted


## The feet and belly don't see the prop it holds.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var exclude: Array[RID] = [get_rid()]
	if is_instance_valid(held):
		exclude.append(held.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, foot_mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)
