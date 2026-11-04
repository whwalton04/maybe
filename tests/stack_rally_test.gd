extends SceneTree
## Headless test of steering a stack and of rallying to a flag. On the test
## terrain, stacks Crab3 and Crab2 on Crab4 and steers Crab2, at the top: the
## stack should walk on Crab4 and stay together while the rest are told to
## wait. Then Crab1 is put by a flag some way off, and takes it, so the flag
## remembers the group of six. Crab5 is then
## sent far off, out of the group, and a stranger joins it. Rallying should
## bring back all six, Crab5 included, and leave the stranger behind. Run with
##   godot --headless --path . -s tests/stack_rally_test.gd

var player: Player
var crabs := {}
var flag: Flag
var stranger: ContactCrab
var frame := 0
var ok := true
var start := {}
var idle := true


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	load("res://tests/group_test.gd").gather_crabs(world)
	root.add_child(world)
	player = world.get_node("Player")
	for crab in player.get_animals():
		crabs[String(crab.name)] = crab


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 240:
		var bottom: ContactCrab = crabs["Crab4"]
		for crab_name in ["Crab3", "Crab2"]:
			crabs[crab_name].global_position = bottom.global_position + Vector3(0.3, 0.0, 0.0)
	if frame == 250:
		_check("stacked", crabs["Crab3"].mount_onto(crabs["Crab4"]) and crabs["Crab2"].mount_onto(crabs["Crab3"]))

	# Steering the top of the stack.
	if frame == 360:
		player._control(crabs["Crab2"])
		for crab_name in crabs:
			start[crab_name] = crabs[crab_name].global_position
		Input.action_press(&"move_forward")
	if frame > 365 and frame < 600:
		for crab_name in ["Crab1", "Crab2", "Crab3", "Crab5", "Crab6"]:
			idle = idle and crabs[crab_name].move_direction == Vector3.ZERO
	if frame == 600:
		Input.action_release(&"move_forward")
		var walked := _across(crabs["Crab4"].global_position - start["Crab4"])
		_check("steering the top walked the bottom (%.2fm)" % walked, walked > 1.0)
		_check("stack still together", crabs["Crab2"].mount == crabs["Crab3"] and crabs["Crab3"].mount == crabs["Crab4"])
		_check("only the bottom was told to walk", idle)
		player._control(null)

	# Crab1 is put by a flag some way off, and takes it.
	if frame == 700:
		flag = load("res://world/flag.tscn").instantiate()
		root.get_child(0).add_child(flag)
		flag.global_position = _floor_under(crabs["Crab4"].global_position + Vector3(0.0, 0.0, 5.0))
		crabs["Crab1"].drop_at(flag.global_position + Vector3(0.0, 0.3, 0.2))
	if frame == 760:
		_check("Crab1 took the flag", Flag.active == flag)
		_check("flag remembers the six (%d)" % flag.crabs.size(),
				flag.crabs.size() == 6 and crabs.values().all(func(c): return c in flag.crabs))
		# Crab5 wanders far off, and a stranger turns up by the group.
		crabs["Crab5"].drop_at(_floor_under(crabs["Crab1"].global_position + Vector3(12.0, 0.0, 0.0)) + Vector3.UP * 0.3)
		stranger = load("res://crab/crab2.tscn").instantiate()
		stranger.name = "Stranger"
		root.get_child(0).add_child(stranger)
		stranger.global_position = _floor_under(crabs["Crab6"].global_position + Vector3(0.6, 0.0, 0.0)) + Vector3.UP * 0.3
	if frame == 900:
		_check("Crab5 left the group", crabs["Crab5"].get_parent() != player)
		_check("the stranger joined it", stranger.get_parent() == player)
		var press := InputEventAction.new()
		press.action = &"rally"
		press.pressed = true
		Input.parse_input_event(press)
	if frame == 1900:
		var far := 0.0
		for crab in crabs.values():
			far = maxf(far, _across(crab.global_position - flag.global_position))
		_check("all six back at the flag (furthest %.2fm)" % far, far < 1.5)
		_check("all six in the group", crabs.values().all(func(c): return c.get_parent() == player))
		var stranger_off := _across(stranger.global_position - flag.global_position)
		_check("stranger left behind (%.2fm off, in group %s)" % [stranger_off, stranger.get_parent() == player],
				stranger_off > 1.5 and stranger.get_parent() != player)
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _across(d: Vector3) -> float:
	return Vector2(d.x, d.z).length()


func _floor_under(at: Vector3) -> Vector3:
	var hit := root.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1))
	return hit.position if not hit.is_empty() else at


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
