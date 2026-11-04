@tool
class_name BarnaclePatch
extends Area3D
## A round patch of barnacles stuck to whatever is under it. Anywhere in the
## circle, out to half of grip_depth either side, is barnacle surface, which a
## BarnacleCrab's feet grip (see is_barnacle()). The barnacles are only for
## show: they have no collision, and feet stand on the surface under them.
## They thin out and shrink toward the rim, so overlapping patches blend.
##
## The circle lies in the node's XZ plane, facing +Y. Building the patch drops
## each barnacle onto the surface along -Y, physics bodies on surface_mask or
## a Terrain3D, and leaves out those with nothing under them. In the editor it
## rebuilds itself when moved or its settings change, and the barnacles are
## saved with the scene. Paint patches with the Barnacle Brush
## (addons/barnacle_brush).

## Physics layer 5, "barnacles". Only barnacle patches are on it.
const LAYER := 1 << 4
const MAX_BARNACLES := 5000
# How much of the default sphere is sunk into the surface: enough to sit on
# bumpy ground, little enough to show where the terrain's drawn surface is a
# little above its height data.
const SPHERE_SINK := 0.2
# Floats per barnacle in the MultiMesh buffer: a 3×4 transform by rows, then
# a colour.
const STRIDE := 16
# Bytes per barnacle as saved (see _pack()): its origin as three floats, its
# basis as nine half floats by rows, then its colour as four bytes.
const PACKED_SIZE := 34

## Radius of the circle (m).
@export_range(0.05, 10.0, 0.01, "or_greater") var radius := 0.5:
	set(value):
		radius = maxf(value, 0.01)
		_update_shape()
		_queue_rebuild()
## How much of the radius, in from the rim, the barnacles thin out and shrink
## over.
@export_range(0.0, 1.0, 0.01) var edge_fade := 0.4:
	set(value):
		edge_fade = value
		_queue_rebuild()
## Barnacles per square metre.
@export_range(1.0, 2000.0, 1.0) var density := 250.0:
	set(value):
		density = value
		_queue_rebuild()
## Each barnacle's radius is picked between these (m).
@export_range(0.002, 0.2, 0.001) var min_barnacle_radius := 0.012:
	set(value):
		min_barnacle_radius = value
		_queue_rebuild()
@export_range(0.002, 0.2, 0.001) var max_barnacle_radius := 0.03:
	set(value):
		max_barnacle_radius = value
		_queue_rebuild()
## Height over width of each barnacle.
@export_range(0.1, 2.0, 0.01) var squash := 0.6:
	set(value):
		squash = value
		_queue_rebuild()
## How thick the barnacle surface is, centred on the circle: how far off it a
## foot still grips, and a barnacle looks for a surface to sit on (m).
@export_range(0.01, 1.0, 0.01) var grip_depth := 0.15:
	set(value):
		grip_depth = value
		_update_shape()
		_queue_rebuild()
## What barnacles sit on, besides any Terrain3D.
@export_flags_3d_physics var surface_mask := 1:
	set(value):
		surface_mask = value
		_queue_rebuild()
@export var random_seed := 0:
	set(value):
		random_seed = value
		_queue_rebuild()
## Drawn for each barnacle, one unit across, its origin on the surface and +Y
## out of it. Empty draws a sphere, sunk a fifth of the way in.
@export var mesh: Mesh:
	set(value):
		mesh = value
		if _instance and _instance.multimesh:
			_instance.multimesh.mesh = _get_mesh()
## Each barnacle's tint is picked along this. Needs a mesh whose material uses
## vertex colour as albedo, as the sphere's does.
@export var colors: Gradient:
	set(value):
		colors = value
		_queue_rebuild()
@export_tool_button("Rebuild", "Reload") var _rebuild_button := rebuild

# The built barnacles, packed small (see _pack()): saved with the scene, so
# the game doesn't rebuild them, and kept to about a fifth of the size of the
# MultiMesh buffer they unpack to, so as not to bloat it.
@export_storage var _barnacles := PackedByteArray():
	set(value):
		_barnacles = value
		_floats = _unpack(value)
		_count = _floats.size() / STRIDE
# The built barnacles, as a MultiMesh buffer.
var _floats := PackedFloat32Array()
var _count := 0

static var _sphere: Mesh

var _shape := CollisionShape3D.new()
var _instance := MultiMeshInstance3D.new()
var _rebuild_queued := false


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	_shape.shape = CylinderShape3D.new()
	add_child(_shape, false, INTERNAL_MODE_BACK)
	add_child(_instance, false, INTERNAL_MODE_BACK)


func _ready() -> void:
	_update_shape()
	_show_buffer()
	set_notify_transform(Engine.is_editor_hint())
	if _count == 0:
		_queue_rebuild()


# Scenes saved before _barnacles held the MultiMesh buffer as _buffer, and a
# _count of barnacles in it.
func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"_buffer":
			_barnacles = _pack(value)
			return true
		&"_count":
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_rebuild()


## Whether `point` is on barnacles: inside any patch's circle, within half its
## grip_depth of it.
static func is_barnacle(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = LAYER
	return not space.intersect_point(query, 1).is_empty()


## Whether `point` lies in this patch's circle, within half its grip_depth.
func contains_point(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	return Vector2(local.x, local.z).length() <= radius and absf(local.y) <= grip_depth * 0.5


## Scatters barnacles over the circle on a jittered grid, fewer and smaller
## toward the rim, and drops each onto the surface under it.
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var terrain := _find_terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var area := 4.0 * radius * radius
	var cell := maxf(1.0 / sqrt(density), sqrt(area / MAX_BARNACLES))
	var cells := maxi(1, roundi(2.0 * radius / cell))
	var normal := global_basis.y.normalized()
	var to_local := global_transform.affine_inverse()
	var fade_start := 1.0 - edge_fade

	var buffer := PackedFloat32Array()
	var count := 0
	for i in cells:
		for j in cells:
			# Every roll is made whether or not the barnacle is kept, so the
			# rest stay put when the patch moves a little or its rim changes.
			var spot := Vector3(((i + rng.randf()) / cells - 0.5) * 2.0 * radius, 0.0,
					((j + rng.randf()) / cells - 0.5) * 2.0 * radius)
			var size := rng.randf_range(min_barnacle_radius, maxf(min_barnacle_radius, max_barnacle_radius))
			var twist := rng.randf() * TAU
			var tint := rng.randf()
			var keep := rng.randf()
			var out := Vector2(spot.x, spot.z).length() / radius
			if out > 1.0:
				continue
			var fade := smoothstep(fade_start, 1.0, out) if edge_fade > 0.0 else 0.0
			if keep < fade:
				continue
			size *= lerpf(1.0, 0.5, fade)
			var hit := _surface_at(space, terrain, global_transform * spot, normal)
			if hit.is_empty():
				continue
			var up: Vector3 = hit.normal
			var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
			side = side.rotated(up, twist)
			var basis := Basis(side, up, side.cross(up)).scaled_local(
					Vector3(1.0, squash, 1.0) * size * 2.0)
			_append(buffer, to_local * Transform3D(basis, hit.position),
					colors.sample(tint) if colors else _default_tint(tint))
			count += 1

	_barnacles = _pack(buffer)
	_show_buffer()


## Adds a barnacle to a MultiMesh buffer, as STRIDE floats.
static func _append(buffer: PackedFloat32Array, xform: Transform3D, color: Color) -> void:
	var b := xform.basis
	var o := xform.origin
	buffer.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
			b.x.z, b.y.z, b.z.z, o.z, color.r, color.g, color.b, color.a])


## Packs a MultiMesh buffer into PACKED_SIZE bytes per barnacle. Half floats
## are plenty for a barnacle's few centimetres of basis; its origin, out to
## the patch's radius, keeps full floats.
static func _pack(buffer: PackedFloat32Array) -> PackedByteArray:
	var count := buffer.size() / STRIDE
	var bytes := PackedByteArray()
	bytes.resize(count * PACKED_SIZE)
	for i in count:
		var f := i * STRIDE
		var b := i * PACKED_SIZE
		for row in 3:
			bytes.encode_float(b + row * 4, buffer[f + row * 4 + 3])
			for col in 3:
				bytes.encode_half(b + 12 + (row * 3 + col) * 2, buffer[f + row * 4 + col])
		for c in 4:
			bytes[b + 30 + c] = clampi(roundi(buffer[f + 12 + c] * 255.0), 0, 255)
	return bytes


## Unpacks what _pack() packed into a MultiMesh buffer.
static func _unpack(bytes: PackedByteArray) -> PackedFloat32Array:
	var count := bytes.size() / PACKED_SIZE
	var buffer := PackedFloat32Array()
	buffer.resize(count * STRIDE)
	for i in count:
		var f := i * STRIDE
		var b := i * PACKED_SIZE
		for row in 3:
			buffer[f + row * 4 + 3] = bytes.decode_float(b + row * 4)
			for col in 3:
				buffer[f + row * 4 + col] = bytes.decode_half(b + 12 + (row * 3 + col) * 2)
		for c in 4:
			buffer[f + 12 + c] = bytes[b + 30 + c] / 255.0
	return buffer


## The origin of barnacle `index`, in the patch's space.
func get_barnacle_position(index: int) -> Vector3:
	var at := index * STRIDE
	return Vector3(_floats[at + 3], _floats[at + 7], _floats[at + 11])


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_node_ready() or not Engine.is_editor_hint() and _count > 0:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _update_shape() -> void:
	var cylinder := _shape.shape as CylinderShape3D
	cylinder.radius = radius
	cylinder.height = grip_depth


func _show_buffer() -> void:
	var multimesh := _make_multimesh(_count)
	if _count > 0:
		multimesh.buffer = _floats
	else:
		multimesh.instance_count = 0
	_instance.multimesh = multimesh


func _make_multimesh(count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _get_mesh()
	multimesh.instance_count = count
	return multimesh


## Where a ray along -normal through `point`, out to half grip_depth either
## side, meets a physics body, or failing that a Terrain3D's surface, which
## has no collision in the editor.
func _surface_at(space: PhysicsDirectSpaceState3D, terrain: Node, point: Vector3,
		normal: Vector3) -> Dictionary:
	var reach := normal * grip_depth * 0.5
	var query := PhysicsRayQueryParameters3D.create(point + reach, point - reach, surface_mask)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return {position = hit.position, normal = hit.normal}
	return intersect_terrain(terrain, point + reach, point - reach, grip_depth * 0.125)


## Where the segment `from`-`to` first passes into a Terrain3D's ground from
## above it, from its height data: {position, normal}, or empty. Steps along
## no further than `step` at a time, further while high above the ground, then
## narrows down on the crossing. Unlike Terrain3D.get_intersection(), which
## can stop well inside a steep slope.
static func intersect_terrain(terrain: Node, from: Vector3, to: Vector3, step: float) -> Dictionary:
	var data: Object = terrain.get("data") if terrain else null
	if not data:
		return {}
	var length := from.distance_to(to)
	if length < 1e-6:
		return {}
	var dir := (to - from) / length
	var travelled := 0.0
	var last := from
	var last_above := _height_above(data, from)
	while travelled < length:
		var stride := step
		if not is_nan(last_above) and last_above > step * 4.0:
			stride = minf(last_above * 0.5, step * 16.0)
		travelled = minf(travelled + stride, length)
		var point := from + dir * travelled
		var above := _height_above(data, point)
		if not is_nan(above) and above <= 0.0:
			if is_nan(last_above):
				# Came in over the edge of a hole, or of the terrain.
				return {position = point, normal = _terrain_normal(data, point)}
			if last_above > 0.0:
				var a := last
				var b := point
				for i in 20:
					var mid := (a + b) * 0.5
					var mid_above := _height_above(data, mid)
					if is_nan(mid_above) or mid_above > 0.0:
						a = mid
					else:
						b = mid
				return {position = b, normal = _terrain_normal(data, b)}
		last = point
		last_above = above
	return {}


static func _height_above(data: Object, point: Vector3) -> float:
	var height: float = data.get_height(point)
	return point.y - height


static func _terrain_normal(data: Object, point: Vector3) -> Vector3:
	var normal: Vector3 = data.get_normal(point)
	return normal if normal.is_finite() and normal.length_squared() > 0.5 else Vector3.UP


func _find_terrain() -> Node:
	var tree := get_tree()
	var root := tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
	if not root:
		return null
	if root.is_class("Terrain3D"):
		return root
	var found := root.find_children("*", "Terrain3D", true, false)
	return found[0] if not found.is_empty() else null


func _get_mesh() -> Mesh:
	if mesh:
		return mesh
	if not _sphere:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.9
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 8
		sphere.rings = 4
		# Raised, so only its bottom SPHERE_SINK is under the surface.
		var arrays := sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for k in vertices.size():
			vertices[k].y += 0.5 - SPHERE_SINK
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var raised := ArrayMesh.new()
		raised.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		raised.surface_set_material(0, material)
		_sphere = raised
	return _sphere


## Chalky whites to barnacle greys and browns.
func _default_tint(t: float) -> Color:
	return Color(0.86, 0.84, 0.78).lerp(Color(0.45, 0.42, 0.38), t)
