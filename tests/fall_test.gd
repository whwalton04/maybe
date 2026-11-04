extends SceneTree
## Headless fall-through regression. Run with
##   godot --headless --path . -s tests/fall_test.gd
## Drops crabs from 3 m to 30 m onto the real terrain, at a few offsets each
## so they reach it at different points in a physics step, and checks every
## one ends up on top of it. A crab is a thin shell: falling fast enough to
## cross its own height in one step, it would pass through the terrain's
## one-sided collision without continuous collision detection. CRAB_SCENE
## tests another crab.

const SPOT := Vector3(15.6, 0.0, 0.0)
const HEIGHTS := [3.0, 5.0, 7.0, 10.0, 15.0, 20.0, 30.0]
const OFFSETS := 4
const SETTLE_FRAMES := 480

var crabs: Array[ContactCrab] = []
var drops: Array[float] = []
var frame := 0


func _initialize() -> void:
	var world: Node3D = load("res://world/main.tscn").instantiate()
	world.get_node("Player").process_mode = Node.PROCESS_MODE_DISABLED
	for crab in world.find_children("*", "RigidBody3D", true, false):
		if crab is ContactCrab:
			crab.get_parent().remove_child(crab)
			crab.free()
	var scene_path := OS.get_environment("CRAB_SCENE")
	var scene: PackedScene = load(scene_path if scene_path != "" else "res://crab/crab2.tscn")
	for height in HEIGHTS:
		for k in OFFSETS:
			var crab: ContactCrab = scene.instantiate()
			world.add_child(crab)
			crabs.append(crab)
			drops.append(height + k * 0.023)
	root.add_child(world)


func _physics_process(_delta: float) -> bool:
	frame += 1
	# The terrain's collision is in from the second frame.
	if frame == 2:
		for i in crabs.size():
			var at := SPOT + Vector3((i % OFFSETS) * 0.7, 0.0, (i / OFFSETS) * 0.7)
			at.y = _ground(at) + drops[i]
			crabs[i].drop_at(at)
	if frame < 2 + SETTLE_FRAMES:
		return false
	var through := 0
	for i in crabs.size():
		var crab := crabs[i]
		var under := crab.global_position.y < _ground(crab.global_position)
		if under:
			through += 1
		print("%s  dropped %.2fm" % ["FAIL" if under else "ok  ", drops[i]])
	print("RESULT %s (%d of %d fell through)" % ["PASS" if through == 0 else "FAIL", through, crabs.size()])
	return true


## Height of the world under `at`, looking down from well above.
func _ground(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 50.0, at + Vector3.DOWN * 50.0, 1)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else -INF
