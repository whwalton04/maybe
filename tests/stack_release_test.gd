extends SceneTree
## Headless test of a stack leaving the group while it slides. Run with
##   godot --headless --path . -s tests/stack_release_test.gd
##
## A two-crab stack jumps off a shore onto a floe and glides away, while the
## Player steers a third crab that stands still. Once the stack is beyond
## leave_radius the Player takes it out of the group, reparenting each crab.
## The rider comes before its carrier in child order, so it's moved first:
## the stack should stay together, gliding on, its rider back at its proper
## height on the one under it.

const ICE_Z := -4.6

var player: Player
var thrower: ContactCrab
var bottom: ContactCrab
var top: ContactCrab
var frame := 0
var ok := true
var rest_gap := 0.0
var released_at := -1
var worst_gap := 0.0
var worst_spread := 0.0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 4.75), Vector3(10, 1, 10.5))
	_box(world, Vector3(0, -3.5, 0), Vector3(40, 1, 40))
	var water := Water.new()
	water.extent = 100.0
	water.amplitude = 0.0
	world.add_child(water)
	var ice: IcePatch = (load("res://world/ice_patch.tscn") as PackedScene).instantiate()
	ice.radius = 4.2
	ice.position = Vector3(0, 0, ICE_Z)
	world.add_child(ice)
	player = (load("res://player/player.tscn") as PackedScene).instantiate()
	world.add_child(player)
	thrower = _crab(player, Vector3(0.6, 0.12, 1.2))
	top = _crab(player, Vector3(-0.4, 0.12, 1.2))
	bottom = _crab(player, Vector3(0, 0.12, 1.2))


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 120:
		_check("stacked", top.mount_onto(bottom))
	if frame == 230:
		rest_gap = (top.global_position - bottom.global_position).length()
	if frame == 240:
		player._control(thrower)
		bottom.jump_to(Vector3(0, 0.02, -1.0))
	if released_at < 0 and bottom.get_parent() != player:
		released_at = frame
		_check("stack left the group together", top.get_parent() == bottom.get_parent())
	if released_at > 0:
		var gap := top.global_position - bottom.global_position
		worst_spread = maxf(worst_spread, Vector2(gap.x, gap.z).length())
		if frame > released_at + 60:
			worst_gap = maxf(worst_gap, absf(gap.length() - rest_gap))
	if frame == 520:
		_check("released while gliding (frame %d)" % released_at, released_at > 0)
		_check("still stacked", top.mount == bottom and bottom.rider == top)
		_check("rider stayed over its carrier (at most %.3fm off)" % worst_spread, worst_spread < 0.05)
		_check("rider back at its height (at most %.3fm off %.3fm)" % [worst_gap, rest_gap], worst_gap < 0.01)
		_check("still gliding (%.2f m/s)" % bottom.linear_velocity.length(), bottom.linear_velocity.length() > 3.0)
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


func _crab(parent: Node3D, at: Vector3) -> ContactCrab:
	var c: ContactCrab = (load("res://crab/crab2.tscn") as PackedScene).instantiate()
	c.position = at
	parent.add_child(c)
	return c


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
