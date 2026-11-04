extends SceneTree
## Headless test of ice floes. Run with
##   godot --headless --path . -s tests/ice_test.gd
## Env: VERBOSE=n logs the slider every n ticks.
##
## A crab runs off a shore onto a floe on the water. Once all its feet are on
## the ice its input stops: it should slide on at about the speed it had.
## Then it's steered across: its slide should bend, but no faster than the
## ice's steer_deg. Another crab, put down still on the floe and steered,
## shouldn't move or turn. The floe should rise and fall with the waves.

const ICE_Z := -4.6
const ICE_RADIUS := 4.2

var slider: ContactCrab
var creeper: ContactCrab
var ice: IcePatch
var frame := 0
var ok := true
var on_at := -1.0
var v0 := Vector3.ZERO
var v1 := Vector3.ZERO
var ice_low := INF
var ice_high := -INF
var stuck_from := Transform3D()


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	# Shore at the water's level, ending where the floe starts, and a sea bed.
	_box(world, Vector3(0, -0.5, 4.75), Vector3(10, 1, 10.5))
	_box(world, Vector3(0, -3.5, 0), Vector3(40, 1, 40))
	var water := Water.new()
	water.extent = 100.0
	water.amplitude = 0.04
	water.period = 3.0
	world.add_child(water)
	ice = (load("res://world/ice_patch.tscn") as PackedScene).instantiate()
	ice.radius = ICE_RADIUS
	ice.position = Vector3(0, 0, ICE_Z)
	world.add_child(ice)
	slider = _crab(world, Vector3(0, 0.12, 3.0))
	creeper = _crab(world, Vector3(2.0, 0.14, ICE_Z))


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	ice_low = minf(ice_low, ice.global_position.y)
	ice_high = maxf(ice_high, ice.global_position.y)

	var flat := _flat(slider.linear_velocity)
	if on_at < 0.0 and t > 0.5 and _all_on_ice(slider):
		on_at = t
		v0 = flat
	if on_at < 0.0:
		slider.move_direction = Vector3(0, 0, -1) if t > 0.5 else Vector3.ZERO
		slider.facing_direction = Vector3(0, 0, -1)
	elif t < on_at + 0.5:
		slider.move_direction = Vector3.ZERO
	elif t < on_at + 1.0:
		slider.move_direction = Vector3(1, 0, 0)
	else:
		slider.move_direction = Vector3.ZERO
	if on_at >= 0.0 and is_equal_approx(t, snappedf(on_at + 0.5, delta)):
		v1 = flat
		_check("ran onto the ice at %.2f m/s" % v0.length(), v0.length() > 2.0)
		_check("slid on with no input (%.2f -> %.2f m/s, turned %.1f°)" % [
				v0.length(), v1.length(), rad_to_deg(v0.angle_to(v1))],
				v1.length() > v0.length() * 0.9 and rad_to_deg(v0.angle_to(v1)) < 2.0)
	if on_at >= 0.0 and is_equal_approx(t, snappedf(on_at + 1.0, delta)):
		var turned := rad_to_deg(v1.signed_angle_to(flat, Vector3.UP))
		var most := ice.steer_deg * 0.5
		_check("steered the slide a little (%.1f°, at most %.1f°, still %.2f m/s)" % [-turned, most, flat.length()],
				-turned > most * 0.5 and -turned < most + 1.5 and flat.length() > v0.length() * 0.85)
		_check("still on the ice", _all_on_ice(slider))

	# The creeper waits to settle, then is steered across the floe and round.
	if t > 1.5:
		creeper.move_direction = Vector3(1, 0, 0)
		creeper.facing_direction = Vector3(1, 0, 0)
	if is_equal_approx(t, 1.5):
		stuck_from = creeper.global_transform
		_check("creeper stands on the ice", _all_on_ice(creeper))

	if OS.has_environment("VERBOSE") and frame % int(OS.get_environment("VERBOSE")) == 0:
		var p := slider.global_position
		print("t=%.2f slider=(%.2f %.2f %.2f) v=(%.2f %.2f) on_ice=%s creeper.x=%.2f ice.y=%.3f" % [
				t, p.x, p.y, p.z, flat.x, flat.z, _all_on_ice(slider), creeper.global_position.x,
				ice.global_position.y])

	if t >= 4.0:
		var moved := _flat(creeper.global_position - stuck_from.origin).length()
		var turned := rad_to_deg(_flat(-stuck_from.basis.z).angle_to(_flat(-creeper.global_basis.z)))
		_check("creeper stuck where it stopped (moved %.3fm, turned %.1f°)" % [moved, turned],
				moved < 0.05 and turned < 5.0 and _all_on_ice(creeper))
		_check("ice rode the waves (y %.3f to %.3f)" % [ice_low, ice_high], ice_high - ice_low > 0.05)
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _all_on_ice(c: ContactCrab) -> bool:
	var planted := 0
	for leg in c._legs:
		if leg.planted:
			if not leg.collider is IcePatch:
				return false
			planted += 1
	return planted > 0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _box(parent: Node3D, at: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = box_size
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


func _crab(parent: Node3D, at: Vector3) -> ContactCrab:
	var c: ContactCrab = (load("res://crab/crab2.tscn") as PackedScene).instantiate()
	c.position = at
	parent.add_child(c)
	return c


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
