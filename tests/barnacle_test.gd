extends SceneTree
## Headless test of the barnacle crab. Run with
##   godot --headless --path . -s tests/barnacle_test.gd
## Env: VERBOSE=n logs the crab every n ticks; LEGS=t logs its legs for
## 0.6s from t seconds; WHO=over logs the crab going over the top instead.
##
## A wall 1.2m high faces +Z with a slab sticking out from its top, all of it
## covered in barnacle patches, floor in front too. A BarnacleCrab walks into
## the wall: it should climb it, go round onto the underside of the slab and
## walk out along it upside down, then let go with its ability and land on
## its feet. Another climbs a deeper wall with barnacles on its top, and
## should go over the edge and stand on top. A plain wall has no barnacles:
## a BarnacleCrab shouldn't get far up that, and neither should an ordinary
## crab up barnacles.

const WALL_TOP := 1.2
const SLAB_DEPTH := 0.2
const WALL_FACE_Z := -1.5
const SLAB_END_Z := 0.5
const PLAIN_X := 6.0
const OVER_X := 12.0
const OVER_DEPTH := 1.0

var crab: BarnacleCrab
var plain: BarnacleCrab
var ordinary: ContactCrab
var over: BarnacleCrab
var wall_patch: BarnaclePatch
var frame := 0
var ok := true
var best_wall_y := 0.0
var ceiling_frames := 0
var ceiling_best_z := -INF
var let_go_at := -1.0
var plain_best_y := 0.0
var ordinary_best_y := 0.0
var on_top_at := -1.0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	# The barnacle wall, with the slab out from its top, and the plain wall.
	_box(world, Vector3(0, WALL_TOP * 0.5, WALL_FACE_Z - 0.25), Vector3(3, WALL_TOP, 0.5))
	_box(world, Vector3(0, WALL_TOP + SLAB_DEPTH * 0.5, (WALL_FACE_Z - 0.5 + SLAB_END_Z) * 0.5),
			Vector3(3, SLAB_DEPTH, SLAB_END_Z - WALL_FACE_Z + 0.5))
	_box(world, Vector3(PLAIN_X, WALL_TOP * 0.5, WALL_FACE_Z - 0.25), Vector3(3, WALL_TOP, 0.5))

	# Floor in front of the wall, the wall's face, and the slab's underside.
	_patch(world, Vector3(0, 0, WALL_FACE_Z + 0.5), Vector3.UP)
	wall_patch = _patch(world, Vector3(0, WALL_TOP * 0.5, WALL_FACE_Z), Vector3.BACK)
	_patch(world, Vector3(0, WALL_TOP, (WALL_FACE_Z + SLAB_END_Z) * 0.5), Vector3.DOWN)
	# The same floor and wall for the ordinary crab.
	_patch(world, Vector3(-PLAIN_X, 0, WALL_FACE_Z + 0.5), Vector3.UP)
	_patch(world, Vector3(-PLAIN_X, WALL_TOP * 0.5, WALL_FACE_Z), Vector3.BACK)
	_box(world, Vector3(-PLAIN_X, WALL_TOP * 0.5, WALL_FACE_Z - 0.25), Vector3(3, WALL_TOP, 0.5))
	# A deeper wall with barnacles up its face and over its top.
	_box(world, Vector3(OVER_X, WALL_TOP * 0.5, WALL_FACE_Z - OVER_DEPTH * 0.5),
			Vector3(3, WALL_TOP, OVER_DEPTH))
	_patch(world, Vector3(OVER_X, 0, WALL_FACE_Z + 0.5), Vector3.UP)
	_patch(world, Vector3(OVER_X, WALL_TOP * 0.5, WALL_FACE_Z), Vector3.BACK)
	_patch(world, Vector3(OVER_X, WALL_TOP, WALL_FACE_Z - OVER_DEPTH * 0.5), Vector3.UP)

	crab = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(0, 0.11, 0.5))
	plain = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(PLAIN_X, 0.11, 0.5))
	ordinary = _crab(world, load("res://crab/crab2.tscn"), Vector3(-PLAIN_X, 0.11, 0.5))
	over = _crab(world, load("res://crab/barnacle_crab.tscn"), Vector3(OVER_X, 0.11, 0.5))


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var into_wall := Vector3(0, 0, -1)
	for c: ContactCrab in [crab, plain, ordinary, over]:
		c.facing_direction = into_wall
		c.move_direction = into_wall if t > 0.5 else Vector3.ZERO
	if let_go_at >= 0.0:
		crab.move_direction = Vector3.ZERO
	# Over the top edge and standing on it: stop there.
	var top := over.global_position
	if on_top_at < 0.0 and top.y > WALL_TOP and top.z < WALL_FACE_Z - 0.2 and over.global_basis.y.y > 0.9:
		on_top_at = t
	if on_top_at >= 0.0:
		over.move_direction = Vector3.ZERO
	if is_equal_approx(t, 1.0):
		var n := wall_patch._count
		# On the wall's face, inside the circle, and none past the wall's top
		# or bottom, where there's nothing to sit on.
		var on_face := 0
		for k in n:
			var local := wall_patch.get_barnacle_position(k)
			var world_y := wall_patch.to_global(local).y
			if absf(local.y) < 0.01 and Vector2(local.x, local.z).length() <= wall_patch.radius \
					and world_y > -0.01 and world_y < WALL_TOP + 0.01:
				on_face += 1
		_check("barnacles built on the wall (%d, %d on its face)" % [n, on_face], n > 100 and on_face == n)

	var pos := crab.global_position
	var up := crab.global_basis.y
	if pos.z < WALL_FACE_Z + 0.4 and absf(up.z) > 0.8:
		best_wall_y = maxf(best_wall_y, pos.y)
	var gripping := crab._legs.filter(func(l): return l.planted and l.gripping).size()
	if up.y < -0.8 and pos.y > WALL_TOP - 0.4 and crab.is_clinging() and gripping >= 3:
		ceiling_frames += 1
		ceiling_best_z = maxf(ceiling_best_z, pos.z)
	plain_best_y = maxf(plain_best_y, plain.global_position.y)
	ordinary_best_y = maxf(ordinary_best_y, ordinary.global_position.y)

	var log_crab: BarnacleCrab = over if OS.get_environment("WHO") == "over" else crab
	var crab_pos := pos
	var crab_up := up
	pos = log_crab.global_position
	up = log_crab.global_basis.y
	gripping = log_crab._legs.filter(func(l): return l.planted and l.gripping).size()
	if OS.has_environment("VERBOSE") and frame % int(OS.get_environment("VERBOSE")) == 0:
		var planted := log_crab._legs.filter(func(l): return l.planted).size()
		print("t=%.2f pos=(%.2f %.2f %.2f) up=(%.2f %.2f %.2f) cling=%s grip=%d/%d" % [
			t, pos.x, pos.y, pos.z, up.x, up.y, up.z, log_crab.is_clinging(), gripping, planted])

	if OS.has_environment("LEGS") and frame % 3 == 0 and t > float(OS.get_environment("LEGS")) \
			and t < float(OS.get_environment("LEGS")) + 0.6:
		var line := "  t=%.3f air=%s tgt_up=(%.2f %.2f %.2f) cn=(%.2f %.2f %.2f)" % [t, log_crab._airborne,
			log_crab._target_basis.y.x, log_crab._target_basis.y.y, log_crab._target_basis.y.z,
			log_crab._cling_normal.x, log_crab._cling_normal.y, log_crab._cling_normal.z]
		for leg in log_crab._legs:
			var hip: Vector3 = log_crab.to_global(leg.hip_local)
			line += " | %s%s n=(%.1f %.1f %.1f) d=%.2f" % ["P" if leg.planted else ("S" if leg.has_hold else "L"),
				"g" if leg.gripping else "-", leg.normal.x, leg.normal.y, leg.normal.z,
				hip.distance_to(leg.foot.pos) / log_crab._leg_reach(leg)]
		print(line)
	pos = crab_pos
	up = crab_up
	# Out along the ceiling far enough: let go.
	if let_go_at < 0.0 and crab.is_clinging() and up.y < -0.8 and ceiling_frames > 60 \
			and pos.z > WALL_FACE_Z + 0.9:
		let_go_at = t
		crab.use_ability()
		_check("walked out along the ceiling, upside down (to z=%.2f)" % pos.z, true)
	if let_go_at >= 0.0 and is_equal_approx(t, snappedf(let_go_at + 3.0, delta)):
		_check("let go and fell (y=%.2f)" % pos.y, pos.y < 0.3)
		_check("landed on its feet (up.y=%.2f)" % up.y, up.y > 0.9)
	if t >= 20.0 or (let_go_at >= 0.0 and t > let_go_at + 3.1 and on_top_at >= 0.0 and t > on_top_at + 2.0):
		var still := over.global_position
		_check("went over the top edge and stands on top (at %.2fs, y=%.2f up.y=%.2f)" % [
				on_top_at, still.y, over.global_basis.y.y],
				on_top_at >= 0.0 and still.y > WALL_TOP and over.global_basis.y.y > 0.9)
		_check("climbed the barnacle wall (to y=%.2f)" % best_wall_y, best_wall_y > WALL_TOP * 0.6)
		_check("clung to the ceiling (%d frames)" % ceiling_frames, ceiling_frames > 60)
		if let_go_at < 0.0:
			_check("walked out along the ceiling (best z=%.2f)" % ceiling_best_z, false)
		_check("didn't climb the plain wall (best y=%.2f)" % plain_best_y, plain_best_y < 0.5)
		_check("ordinary crab didn't climb barnacles (best y=%.2f)" % ordinary_best_y,
				ordinary_best_y < 0.5)
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


## A circle of barnacles 1.5m across the crab's path.
func _patch(parent: Node3D, at: Vector3, normal: Vector3) -> BarnaclePatch:
	var patch := BarnaclePatch.new()
	# Width along X; every normal here is square to it.
	patch.transform = Transform3D(Basis(Vector3.RIGHT, normal, Vector3.RIGHT.cross(normal)), at)
	patch.radius = 1.5
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
