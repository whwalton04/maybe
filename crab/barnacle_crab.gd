class_name BarnacleCrab
extends SpecialCrab
## Its feet grip barnacles (see BarnaclePatch): a foot planted on them can
## pull toward the surface as well as push, up to `adhesion`, so the crab
## walks up walls and across ceilings covered in them. While at least
## min_grip_feet feet grip, it clings: its body turns to the surface under its
## gripping feet, and the move input turns with it, so walking into a wall
## walks up it and carries on across a ceiling. Feet that step off the
## barnacles don't grip, and once none do it's an ordinary crab again, which
## falls off a wall. Its ability lets go, dropping it off whatever it clings to.
## Clinging, it holds whatever stack rides it on with it, and neither floats
## in water, so barnacles can lead underwater.

@export_group("Barnacles")
## The most each foot on barnacles can pull, in multiples of its share of the
## weight it holds up.
@export_range(0.0, 20.0, 0.1) var adhesion := 6.0
## Speed while clinging, on the flat as well as walls and ceilings, as a
## fraction of move_speed.
@export_range(0.1, 1.0, 0.01) var climb_speed := 0.25
## How much a stack riding it slows it while clinging: it keeps
## (own mass / carried mass)^this of its speed. 0.5 slows it as much as an
## ordinary crab, 0 not at all.
@export_range(0.0, 0.5, 0.01) var carry_slowdown := 0.15
## How many feet must grip before the crab clings to the surface.
@export_range(1, 8) var min_grip_feet := 2
## Seconds the ability lets go for.
@export_range(0.1, 3.0, 0.05) var let_go_time := 0.6

# Seconds clinging lasts with no foot gripping, as feet step.
const CLING_RELEASE := 0.25
# How far round from straight up a surface must face before the input's
# rotation onto it picks its own axis. Nearer straight down it keeps the last.
const POLE_AXIS_MIN := 0.2
# How far past the surface, beyond the ride height and × reach, a foot looks
# back round an edge for a hold.
const WRAP_DEPTH := 0.25
# How far ahead, × leg reach, the crab looks for an edge to go round.
const EDGE_LOOKAHEAD := 0.6
# Turning the body to the surface while clinging, in units of
# _torque_scale(): per radian off, and damping.
const CLING_TORQUE := 0.3
const CLING_DAMPING := 0.06

var _clinging := false
var _cling_normal := Vector3.UP
var _cling_lost := 0.0
var _letting_go := 0.0
var _pole_axis := Vector3.RIGHT


## Whether it's holding on by its gripping feet, turned to their surface.
func is_clinging() -> bool:
	return _clinging


func is_held() -> bool:
	return _clinging or super()


func use_ability() -> void:
	_letting_go = let_go_time
	_clinging = false
	for leg in _legs:
		leg.gripping = false


func get_controls_hint() -> String:
	return "Barnacle crab\nShift  let go\nWalks up barnacle walls"


func can_mount(target: Node3D) -> bool:
	return global_basis.y.y > MOUNT_TIP_Y and super(target)


func drop_at(at: Vector3) -> void:
	_clinging = false
	_cling_normal = Vector3.UP
	_cling_lost = 0.0
	_letting_go = 0.0
	super(at)


func _physics_process(delta: float) -> void:
	_letting_go = maxf(_letting_go - delta, 0.0)
	super(delta)


## Clinging, the legs aren't damped any harder under a stack. Feet that pull
## as well as push damp the body both ways, so the extra damping a load
## brings rocks the body back and forth each tick instead of settling it.
func _update_tuning() -> void:
	super()
	if _clinging:
		_leg_damping = STANCE_DAMPING_RATIO * 2.0 * mass * TAU * stance_hz / _legs.size()


func _grips(at: Vector3, _collider: Object) -> bool:
	return _letting_go <= 0.0 and BarnaclePatch.is_barnacle(get_world_3d().direct_space_state, at)


func _adhesion(leg: Leg) -> float:
	if not leg.gripping:
		return 0.0
	return adhesion * _carried_mass * get_gravity().length() / _legs.size()


func _load_speed() -> float:
	return pow(mass / _carried_mass, carry_slowdown) if _clinging else super()


func _frame_up() -> Vector3:
	return _target_basis.y if _clinging else Vector3.UP


## Clinging, the body turns to the average facing of the gripping feet's
## surfaces. Facing and the move input, given level, are carried onto it.
func _update_target_basis(delta: float) -> void:
	_update_cling(delta)
	if not _clinging:
		super(delta)
		return
	_wall_roll = 0.0
	var up := _cling_normal
	# Turning halfway onto the surface ahead before the feet reach it.
	var ahead := _surface_ahead(up)
	if ahead != Vector3.ZERO:
		up = (up + ahead).normalized()
	_walls_seen = Vector3.ZERO
	var onto := _onto_surface(up)
	var drive := onto * _wish
	drive -= up * drive.dot(up)
	var speed := _wish.length() * climb_speed
	_drive = drive.normalized() * speed if drive.length_squared() > 1e-8 else Vector3.ZERO

	var forward := -_target_basis.z
	forward -= up * forward.dot(up)
	var want := onto * _desired_facing
	want -= up * want.dot(up)
	if forward.length_squared() > 1e-6 and want.length_squared() > 1e-6:
		var turn := forward.signed_angle_to(want, up)
		forward = forward.rotated(up, clampf(turn, -turn_rate * delta, turn_rate * delta))

	var tilt := _target_basis.y.angle_to(up)
	var max_tilt := turn_rate * 0.5 * delta
	if tilt > max_tilt:
		up = _target_basis.y.slerp(up, max_tilt / tilt).normalized()
	var level_forward := forward - up * forward.dot(up)
	if level_forward.length_squared() > 1e-4:
		_target_basis = Basis.looking_at(level_forward, up)


## Clings once min_grip_feet planted feet grip, until none has for
## CLING_RELEASE.
func _update_cling(delta: float) -> void:
	var sum := Vector3.ZERO
	var count := 0
	for leg in _legs:
		if leg.planted and leg.gripping:
			sum += leg.normal
			count += 1
	# Only takes hold right way up to the surface, so one landed on its back
	# on barnacles rights itself rather than clinging upside down.
	var facing := sum.length_squared() > 1e-6 and global_basis.y.dot(sum) > 0.0
	if mount or _letting_go > 0.0:
		_clinging = false
	elif (count >= min_grip_feet and facing) or (_clinging and count > 0):
		_clinging = true
		_cling_lost = 0.0
		if sum.length_squared() > 1e-6:
			_cling_normal = sum.normalized()
	elif _clinging:
		_cling_lost += delta
		_clinging = _cling_lost < CLING_RELEASE


## The facing of the surface the crab is heading onto, the way it's going
## across the surface `up` faces: a wall it's walking into, as the feet's rays
## saw it, or the face round an edge just ahead. Zero if the surface carries
## on.
func _surface_ahead(up: Vector3) -> Vector3:
	var along := _drive - up * _drive.dot(up)
	if along.length_squared() < 0.01:
		return Vector3.ZERO
	var dir := along.normalized()
	if _walls_seen.length_squared() > 1e-6 and dir.dot(_walls_seen.normalized()) < -0.5:
		return _walls_seen.normalized()
	var reach := _leg_reach_full()
	var depth := _ride_height() + reach * WRAP_DEPTH
	var ahead := global_position + dir * reach * EDGE_LOOKAHEAD
	if not _ray(ahead, ahead - up * depth).is_empty():
		return Vector3.ZERO
	# Back under the body from beyond the edge, and on behind it, so it still
	# finds the edge once the body is past it.
	var hit := _ray(ahead - up * depth, global_position - (dir * reach + up * depth))
	return Vector3.ZERO if hit.is_empty() else hit.normal


## Turns world up to `normal`, so level directions land on the surface:
## level into a wall becomes up it. Near straight down, where the axis is
## unsteady, it keeps the last axis, so the input carries on the same way
## from a wall across a ceiling.
func _onto_surface(normal: Vector3) -> Quaternion:
	var axis := Vector3.UP.cross(normal)
	if axis.length() > POLE_AXIS_MIN:
		_pole_axis = axis.normalized()
	elif normal.y > 0.0:
		return Quaternion(Vector3.UP, normal)
	return Quaternion(_pole_axis, Vector3.UP.angle_to(normal))


func _pushing_into(wall_normal: Vector3) -> bool:
	if not _clinging:
		return super(wall_normal)
	var up := _target_basis.y
	var level := wall_normal - up * wall_normal.dot(up)
	var along := _drive - up * _drive.dot(up)
	if level.length_squared() < 1e-4 or along.length_squared() < 0.01:
		return false
	return along.normalized().dot(-level.normalized()) > 0.5


## Clinging, a foot that finds nothing below its spot, past an edge, looks
## back toward its hip from beyond and below the surface, for the face round
## the edge.
func _wrap_hold(leg: Leg, above: Vector3) -> Dictionary:
	if not _clinging:
		return {}
	var up := global_basis.orthonormalized().y
	var depth := _ride_height() + _leg_reach(leg) * WRAP_DEPTH
	return _ray(above - up * depth, to_global(leg.hip_local) - up * depth)


## Clinging, the weight is shared by the planted feet only: on a wall it
## pulls along the surface, where the legs' springs are soft.
func _weight_legs() -> int:
	if not _clinging:
		return super()
	var planted := 0
	for leg in _legs:
		if leg.planted:
			planted += 1
	return maxi(planted, 1)


## Clinging, turns the body toward the surface's pose, as the legs alone
## can't swing it round onto a wall.
func _apply_wall_roll() -> void:
	if not _clinging:
		super()
		return
	var axis := global_basis.y.cross(_target_basis.y)
	var angle := global_basis.y.angle_to(_target_basis.y)
	if axis.length_squared() > 1e-8:
		axis = axis.normalized() * angle
	var k := _torque_scale()
	apply_torque(axis * CLING_TORQUE * k.x - angular_velocity * CLING_DAMPING * k.y)


## Clinging, a foot stepping round an edge slides over the face it brushes
## on the way rather than planting on it, so it reaches its hold.
func _plants_on_contact(leg: Leg, normal: Vector3) -> bool:
	return not (_clinging and leg.has_hold and normal.dot(leg.hold_normal) < WALL_NORMAL_Y)


func _apply_self_right(delta: float) -> void:
	if _clinging:
		_stuck_time = 0.0
		_righting = false
		return
	super(delta)
