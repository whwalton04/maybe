class_name Grabbable
extends RigidBody3D
## A loose object a GrabCrab can pick up and carry over its head, then throw.
## It's an ordinary rigid body otherwise: water floats it, and it slides on ice
## (whose friction is nothing). The player's rally action (see Player) puts
## every one back where it started, out of whatever crab held it.
##
## Put props on the "props" physics layer (3), so the camera and the
## player's floor rays look through them, and the crabs' feet and the water
## still find them.

const GROUP := &"grabbables"

## The crab holding it, or null. Set by GrabCrab.
var carrier: Node3D

var _start := Transform3D()
var _half_height := 0.0
# Whether to go back to _start at the next physics step.
var _resetting := false


func _ready() -> void:
	add_to_group(GROUP)
	_start = global_transform
	_half_height = _local_bounds().size.y * 0.5


## The top of it, near enough, where the indicator marks it.
func get_top() -> Vector3:
	return global_position + Vector3.UP * _half_height


## How far its centre stands above whatever it rests on, near enough.
func get_half_height() -> float:
	return _half_height


## Out of the crab holding it, and back where it started, still, from the
## next physics step.
func reset() -> void:
	if is_instance_valid(carrier) and carrier.has_method("release"):
		carrier.release()
	carrier = null
	_resetting = true


# Moved here, as the physics engine may ignore a transform set from outside
# its step, such as while handling input.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _resetting:
		return
	_resetting = false
	state.transform = _start
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO


## Its collision shapes' bounding box, in its own frame.
func _local_bounds() -> AABB:
	var box := AABB()
	var first := true
	for owner_id in get_shape_owners():
		var shape_xform := shape_owner_get_transform(owner_id)
		for i in shape_owner_get_shape_count(owner_id):
			var shape_box: AABB = shape_xform * shape_owner_get_shape(owner_id, i).get_debug_mesh().get_aabb()
			box = shape_box if first else box.merge(shape_box)
			first = false
	return box
