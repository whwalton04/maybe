@tool
class_name IcePatch
extends AnimatableBody3D
## A round, level floe of ice floating at the water's surface. Its origin is
## on the surface: painted at the water's rest height, and in the game it
## rises and falls with the surface under its centre, staying level. Without
## a Water in the scene it stays put.
##
## Crabs stand on it, but it's completely slick: their feet can't push
## across it, so a crab that gets on slides on at the speed it had. It can
## only bend its slide by steer_deg a second (see ContactCrab._apply_ice()),
## and one that stops on it is stuck. Paint floes with the Ice Brush
## (addons/ice_brush).

## Radius of the floe (m).
@export_range(0.1, 20.0, 0.01, "or_greater") var radius := 1.0:
	set(value):
		radius = maxf(value, 0.05)
		_update_shape()
## How thick the floe is (m).
@export_range(0.01, 1.0, 0.01) var thickness := 0.1:
	set(value):
		thickness = value
		_update_shape()
## How far its top stands above the water (m).
@export_range(0.0, 0.5, 0.005) var freeboard := 0.02:
	set(value):
		freeboard = value
		_update_shape()
## How fast a crab sliding on it can turn its slide (degrees a second).
@export_range(0.0, 360.0, 1.0) var steer_deg := 15.0
@export var color := Color(0.55, 0.8, 1.0):
	set(value):
		color = value
		if _material:
			_material.albedo_color = color

## How fast the floe is moving, as it rides the waves.
var velocity := Vector3.ZERO

var _shape := CollisionShape3D.new()
var _mesh := MeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _water: Water


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	# Feet can't push across it, and nor does anything slide on it slowed.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	_shape.shape = CylinderShape3D.new()
	_mesh.mesh = CylinderMesh.new()
	_material.albedo_color = color
	_material.roughness = 0.15
	_mesh.material_override = _material
	add_child(_shape, false, INTERNAL_MODE_BACK)
	add_child(_mesh, false, INTERNAL_MODE_BACK)


func _ready() -> void:
	_update_shape()
	if not Engine.is_editor_hint():
		_water = _find_water()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(_water):
		velocity = Vector3.ZERO
		return
	var at := global_position
	at.y = _water.height_at(at)
	velocity = (at - global_position) / delta
	global_transform = Transform3D(Basis(Vector3.UP, global_basis.get_euler().y), at)


## Height of its top, which crabs stand on.
func top_height() -> float:
	return global_position.y + freeboard


## Whether `point` is over or under the floe, inside its circle.
func contains_point(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() <= radius


func _update_shape() -> void:
	var cylinder := _shape.shape as CylinderShape3D
	cylinder.radius = radius
	cylinder.height = thickness
	var mesh := _mesh.mesh as CylinderMesh
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = clampi(roundi(radius * 32.0), 24, 128)
	mesh.rings = 1
	var center := Vector3(0.0, freeboard - thickness * 0.5, 0.0)
	_shape.position = center
	_mesh.position = center


func _find_water() -> Water:
	var tree := get_tree()
	var root: Node = tree.current_scene if tree.current_scene else tree.root
	for node in root.find_children("*", "Node3D", true, false):
		if node is Water:
			return node
	return null
