extends SceneTree
## Headless test of the GrabCrab and props. Run with
##   godot --headless --path . -s tests/grab_test.gd
## Env: VERBOSE=n logs the carrier every n ticks.
##
## On a shore by the sea, a GrabCrab is steered by a Player, with a block
## beside it and another crab in front. Before it carries anything the other
## crab can mount it. The ability (shift) picks the block up, marked first
## by the indicator: it should float steadily over the crab's head, and the
## other crab can no longer mount it, though it can still mount the other
## crab, and jump off again, block and all. Walking, the block comes along.
## Thrown out to sea, it should land in the water and float. The rally action
## (U) puts it back where it started. Meanwhile a block slid across a floe
## keeps going, and one slid across the shore stops.

const SHORE_TOP := 0.3

var player: Player
var grabber: GrabCrab
var other: ContactCrab
var block: Grabbable
var slider: Grabbable
var rubber: Grabbable
var frame := 0
var ok := true
var start := Transform3D()
var walk_from := Vector3.ZERO
var worst_hold := 0.0
var saw_throw_target := false


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, SHORE_TOP - 0.65, 0), Vector3(12, 1.3, 12))
	_box(world, Vector3(0, -3.5, 0), Vector3(60, 1, 60))
	var water := Water.new()
	water.extent = 100.0
	water.amplitude = 0.0
	world.add_child(water)
	var ice: IcePatch = (load("res://world/ice_patch.tscn") as PackedScene).instantiate()
	ice.radius = 2.5
	ice.position = Vector3(12, 0, -10)
	world.add_child(ice)

	player = (load("res://player/player.tscn") as PackedScene).instantiate()
	world.add_child(player)
	grabber = _crab(player, "res://crab/grab_crab.tscn", Vector3(0, SHORE_TOP + 0.12, 0))
	other = _crab(player, "res://crab/crab2.tscn", Vector3(0, SHORE_TOP + 0.12, -0.6))
	block = _block(world, Vector3(0.45, SHORE_TOP + 0.1, 0))
	slider = _block(world, Vector3(10.0, 0.13, -10))
	rubber = _block(world, Vector3(-3.0, SHORE_TOP + 0.1, 3.0))


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 110:
		start = block.global_transform
	if frame == 120:
		player._control(grabber)
		slider.linear_velocity = Vector3(1.5, 0, 0)
		rubber.linear_velocity = Vector3(1.5, 0, 0)
	if frame == 125:
		_check("indicator marks the block", grabber.get_ability_marker() != null and player._ability_arrow.visible)
		_check("the other crab can mount it while it's empty-handed", other.can_mount(grabber))
		_press(&"ability")

	if frame == 240:
		_check("picked the block up", grabber.held == block and block.carrier == grabber)
		var off := block.global_position.distance_to(grabber.get_hold_point())
		_check("block floats over its head (%.3fm off)" % off, off < 0.05)
		_check("block is above the shell (%.2fm)" % (block.global_position.y - grabber.global_position.y),
				block.global_position.y - grabber.global_position.y > 0.12)
		_check("crab still stands (body %.3fm over the shore)" % (grabber.global_position.y - SHORE_TOP),
				grabber.global_position.y - SHORE_TOP > 0.07 and grabber.global_basis.y.y > 0.9)
		_check("can't be mounted while carrying", not other.can_mount(grabber))
		_check("but can mount", grabber.can_mount(other))
		_check("slider kept sliding on the ice (%.2f m/s)" % slider.linear_velocity.length(),
				slider.linear_velocity.length() > 1.2)
		_check("block on the shore stopped (%.2f m/s)" % rubber.linear_velocity.length(),
				rubber.linear_velocity.length() < 0.2)
	if frame == 250:
		_check("mounted, carrying", grabber.mount_onto(other))
	if frame == 400:
		_check("rides the other crab, still carrying", grabber.mount == other and grabber.held == block)
		var off := block.global_position.distance_to(grabber.get_hold_point())
		_check("block over its head on the stack (%.3fm off)" % off, off < 0.06)
		grabber.jump_to(other.global_position + Vector3(1.2, -0.1, 0.0))
	if frame == 560:
		_check("jumped off with the block", grabber.mount == null and grabber.held == block)
		walk_from = grabber.global_position
		Input.action_press(&"move_forward")
	if frame > 580 and frame < 800:
		worst_hold = maxf(worst_hold, block.global_position.distance_to(grabber.get_hold_point()))
		saw_throw_target = saw_throw_target or grabber.has_throw_target
	if frame == 800:
		Input.action_release(&"move_forward")
		var walked := _flat(grabber.global_position - walk_from).length()
		_check("walked carrying (%.2fm, block at most %.3fm off)" % [walked, worst_hold],
				walked > 0.8 and worst_hold < 0.15 and grabber.held == block)
		_check("the view gave a throw target", saw_throw_target)
	if frame == 860:
		grabber.throw_to(Vector3(8.0, 0.0, grabber.global_position.z))
		_check("let go of the block", grabber.held == null and block.carrier == null)
	if frame == 1300:
		var p := block.global_position
		_check("block landed out at sea (x %.2f)" % p.x, p.x > 6.5)
		var drift := _flat(block.linear_velocity).length()
		_check("and floats (y %.3f, drifting %.2f m/s)" % [p.y, drift], absf(p.y) < 0.12 and drift < 0.3)
		grabber.grab(rubber)
	if frame == 1320:
		_press(&"rally")
	if frame == 1330:
		var back := block.global_position.distance_to(start.origin)
		_check("rally put the block back (%.3fm off)" % back, back < 0.02)
		_check("and the held one out of the crab", grabber.held == null and rubber.carrier == null)
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true

	if OS.has_environment("VERBOSE") and frame % int(OS.get_environment("VERBOSE")) == 0:
		var p := grabber.global_position
		var b := block.global_position
		print("f=%d crab=(%.2f %.2f %.2f) block=(%.2f %.2f %.2f) held=%s" % [
				frame, p.x, p.y, p.z, b.x, b.y, b.z, grabber.held != null])
	return false


func _press(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


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


func _crab(parent: Node3D, path: String, at: Vector3) -> ContactCrab:
	var c: ContactCrab = (load(path) as PackedScene).instantiate()
	c.position = at
	parent.add_child(c)
	return c


func _block(parent: Node3D, at: Vector3) -> Grabbable:
	var b: Grabbable = (load("res://world/block.tscn") as PackedScene).instantiate()
	b.position = at
	parent.add_child(b)
	return b


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
