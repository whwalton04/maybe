extends SceneTree
## Headless test of a BarnacleCrab's hold. Run with
##   godot --headless --path . -s tests/barnacle_carry_test.gd
## Env: VERBOSE=n logs the carrier and its rider every n ticks.
##
## On a barnacle floor a BarnacleCrab walks no faster than its climb speed. A
## second carries an ordinary crab up a barnacle wall and out under a slab:
## the rider should stay on all the way, upside down too, and neither should
## shake. A third clings to a barnacle floor as water rises over it: it
## shouldn't float until it lets go, when it should, like the ordinary crab
## beside it. A fourth paces a barnacle floor under the water carrying a
## rider: neither should float, shake or lean.

const WALL_TOP := 1.2
const SLAB_DEPTH := 0.2
const WALL_FACE_Z := -1.5
const SLAB_END_Z := 0.5
const CARRY_X := 6.0
const WATER_X := -6.0
const WATER_LEVEL := 1.0
const WATER_AT := 2.0
const LET_GO_AT := 6.0
const END := 14.0

var flat: BarnacleCrab
var carrier: BarnacleCrab
var rider: ContactCrab
var diver: BarnacleCrab
var floater: ContactCrab
var water: Water
var frame := 0
var ok := true
var flat_from := Vector3.INF
var flat_speed := 0.0
var flat_clung := true
var mounted := false
var fell_off_at := -1.0
var best_wall_y := 0.0
var ceiling_frames := 0
var diver_top := 0.0
var diver_clung := true
var floater_top := 0.0
var diver_after := 0.0
var deep: BarnacleCrab
var deep_rider: ContactCrab
var deep_top := 0.0
var deep_lean := 1.0
var deep_stayed := true
# Summed spin (rad/s) and ticks: carrying, and carrying underwater.
var carry_spin := Vector2.ZERO
var deep_spin := Vector2.ZERO


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))

	# A wide barnacle floor.
	_patch(world, Vector3(0, 0, -1.0), Vector3.UP, 3.0)
	flat = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(0, 0.11, 0.5))

	# The barnacle wall with a slab out from its top, as in barnacle_test.
	_box(world, Vector3(CARRY_X, WALL_TOP * 0.5, WALL_FACE_Z - 0.25), Vector3(3, WALL_TOP, 0.5))
	_box(world, Vector3(CARRY_X, WALL_TOP + SLAB_DEPTH * 0.5, (WALL_FACE_Z - 0.5 + SLAB_END_Z) * 0.5),
			Vector3(3, SLAB_DEPTH, SLAB_END_Z - WALL_FACE_Z + 0.5))
	_patch(world, Vector3(CARRY_X, 0, WALL_FACE_Z + 0.5), Vector3.UP, 1.5)
	_patch(world, Vector3(CARRY_X, WALL_TOP * 0.5, WALL_FACE_Z), Vector3.BACK, 1.5)
	_patch(world, Vector3(CARRY_X, WALL_TOP, (WALL_FACE_Z + SLAB_END_Z) * 0.5), Vector3.DOWN, 1.5)
	carrier = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(CARRY_X, 0.11, 0.5))
	rider = _crab(world, load("res://crab/crab2.tscn"), Vector3(CARRY_X + 0.5, 0.11, 0.5))

	# A barnacle floor that the water rises over. Only these two are on the
	# layer the water floats, so it leaves the others be.
	_patch(world, Vector3(WATER_X, 0, 0), Vector3.UP, 1.5)
	diver = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(WATER_X, 0.11, 0.0))
	floater = _crab(world, load("res://crab/crab2.tscn"), Vector3(WATER_X + 3.0, 0.11, 0.0))
	_patch(world, Vector3(WATER_X, 0, -5.0), Vector3.UP, 1.5)
	deep = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(WATER_X, 0.11, -5.0))
	deep_rider = _crab(world, load("res://crab/crab2.tscn"), Vector3(WATER_X + 0.5, 0.11, -5.0))
	for c: ContactCrab in [diver, floater, deep, deep_rider]:
		c.collision_layer = 1 << 2
	water = Water.new()
	water.extent = 100.0
	water.amplitude = 0.0
	water.body_mask = 1 << 2
	water.position.y = -10.0
	world.add_child(water)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var into_wall := Vector3(0, 0, -1)
	for c: ContactCrab in [flat, carrier, diver, deep]:
		c.facing_direction = into_wall
		c.move_direction = into_wall if t > 0.5 else Vector3.ZERO
	# Out under the slab far enough: it stops there, holding the rider.
	if ceiling_frames > 120:
		carrier.move_direction = Vector3.ZERO
	if t > LET_GO_AT:
		diver.move_direction = Vector3.ZERO
	# The diver paces back and forth, staying on its patch.
	elif fmod(t, 2.0) > 1.0:
		diver.move_direction = -into_wall
		diver.facing_direction = -into_wall
	if fmod(t, 2.0) > 1.0:
		deep.move_direction = -into_wall
		deep.facing_direction = -into_wall

	if is_equal_approx(t, 0.3):
		mounted = rider.mount_onto(carrier)
		_check("rider mounted the carrier", mounted)
		_check("rider mounted the deep crab", deep_rider.mount_onto(deep))

	# Flat: speed over each second, once it has got going.
	if t > 1.5 and t < 4.5:
		flat_clung = flat_clung and flat.is_clinging()
		if frame % roundi(1.0 / delta) == 0:
			if flat_from != Vector3.INF:
				var moved := flat.global_position - flat_from
				flat_speed = maxf(flat_speed, Vector2(moved.x, moved.z).length())
			flat_from = flat.global_position

	# Carrying.
	var pos := carrier.global_position
	var up := carrier.global_basis.y
	if mounted and fell_off_at < 0.0 and rider.mount != carrier:
		fell_off_at = t
	if pos.z < WALL_FACE_Z + 0.4 and absf(up.z) > 0.8:
		best_wall_y = maxf(best_wall_y, pos.y)
	if up.y < -0.8 and pos.y > WALL_TOP - 0.4 and carrier.is_clinging() and rider.mount == carrier:
		ceiling_frames += 1
	if t > 1.0:
		carry_spin += Vector2(carrier.angular_velocity.length() + rider.angular_velocity.length(), 2)
	if OS.has_environment("VERBOSE") and frame % int(OS.get_environment("VERBOSE")) == 0:
		var rp := rider.global_position
		print("t=%.2f carrier=(%.2f %.2f %.2f) up=(%.2f %.2f %.2f) cling=%s rider=(%.2f %.2f %.2f) on=%s diver.y=%.2f floater.y=%.2f" % [
			t, pos.x, pos.y, pos.z, up.x, up.y, up.z, carrier.is_clinging(), rp.x, rp.y, rp.z,
			rider.mount == carrier, diver.global_position.y, floater.global_position.y])

	# Underwater.
	if is_equal_approx(t, WATER_AT):
		_check("diver clings before the water rises", diver.is_clinging())
		water.position.y = WATER_LEVEL
	if t > WATER_AT + 0.5 and t < LET_GO_AT:
		diver_top = maxf(diver_top, diver.global_position.y)
		diver_clung = diver_clung and diver.is_clinging()
		floater_top = maxf(floater_top, floater.global_position.y)
	if t > WATER_AT + 0.5:
		deep_top = maxf(deep_top, deep.global_position.y)
		deep_lean = minf(deep_lean, deep_rider.global_basis.y.y)
		deep_stayed = deep_stayed and deep.is_clinging() and deep_rider.mount == deep
		deep_spin += Vector2(deep.angular_velocity.length() + deep_rider.angular_velocity.length(), 2)
	if is_equal_approx(t, LET_GO_AT):
		diver.use_ability()
	if t > LET_GO_AT:
		diver_after = maxf(diver_after, diver.global_position.y)

	if t >= END:
		var most := flat.move_speed * flat.climb_speed
		_check("walked the barnacle floor at climb speed (%.2f m/s, at most %.2f)" % [flat_speed, most],
				flat_clung and flat_speed > most * 0.5 and flat_speed < most * 1.15)
		_check("carried the rider up the wall (to y=%.2f)" % best_wall_y, best_wall_y > WALL_TOP * 0.6)
		_check("carried the rider out under the slab (%d frames)" % ceiling_frames, ceiling_frames > 60)
		_check("rider stayed on (fell off at %.2fs)" % fell_off_at, fell_off_at < 0.0)
		_check("carrying didn't shake (mean spin %.2f rad/s)" % (carry_spin.x / carry_spin.y),
				carry_spin.x / carry_spin.y < 2.0)
		_check("stack stayed down and together underwater (top y=%.2f, held=%s)" % [deep_top, deep_stayed],
				deep_top < 0.25 and deep_stayed)
		_check("underwater stack didn't shake or lean (mean spin %.2f rad/s, rider up.y >= %.2f)" % [
				deep_spin.x / deep_spin.y, deep_lean], deep_spin.x / deep_spin.y < 2.0 and deep_lean > 0.9)
		_check("diver stayed down underwater (top y=%.2f, clung=%s)" % [diver_top, diver_clung],
				diver_clung and diver_top < 0.25)
		_check("ordinary crab floated (to y=%.2f)" % floater_top, floater_top > WATER_LEVEL - 0.3)
		_check("diver floated once it let go (to y=%.2f)" % diver_after, diver_after > WATER_LEVEL - 0.3)
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _box(parent: Node3D, at: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = box_size
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


func _patch(parent: Node3D, at: Vector3, normal: Vector3, radius: float) -> BarnaclePatch:
	var patch := BarnaclePatch.new()
	patch.transform = Transform3D(Basis(Vector3.RIGHT, normal, Vector3.RIGHT.cross(normal)), at)
	patch.radius = radius
	parent.add_child(patch)
	return patch


func _crab(parent: Node3D, scene: PackedScene, at: Vector3) -> ContactCrab:
	var c: ContactCrab = scene.instantiate()
	c.position = at
	parent.add_child(c)
	return c


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
