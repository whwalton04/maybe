@tool
extends EditorPlugin
## Paints ice floes (world/ice_patch.tscn) onto the water in the 3D view: each
## a level disc the toolbar's size across, at the surface of the scene's
## Water where the mouse points, as long as nothing (terrain, or a physics
## body on BLOCK_MASK) stands above the water there. Turn it on with the "Ice"
## button in the 3D toolbar, then left-click or drag to paint, and hold Ctrl
## (Cmd on macOS) to erase the floes under the mouse instead.
##
## Floes go under an "Ice" node at the scene's root, made when first needed.
## Each stroke is one undo step.

const PATCH_SCENE := "res://world/ice_patch.tscn"
const CONTAINER_NAME := "Ice"
## What stops the brush reaching the water, besides any Terrain3D.
const BLOCK_MASK := 1
## How far apart, × the floe size across, a drag lays floes, so they overlap.
const SPACING := 0.6
const CURSOR_SEGMENTS := 48

var _toolbar: HBoxContainer
var _toggle: Button
var _size: SpinBox
var _cursor_mesh: ArrayMesh
var _cursor := RID()

# The stroke under way: whether it erases, where it last laid a floe, and
# what it has changed, to make one undo step of at the end.
var _stroking := false
var _erasing := false
var _last := Vector3.INF
var _added: Array[Node] = []
var _removed: Array[Dictionary] = []
var _new_container: Node3D


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_toggle = Button.new()
	_toggle.text = "Ice"
	_toggle.tooltip_text = "Paint ice floes on the water: click or drag. Ctrl+click or drag erases."
	_toggle.toggle_mode = true
	_toggle.flat = true
	_toggle.toggled.connect(_on_toggled)
	_toolbar.add_child(_toggle)
	_size = SpinBox.new()
	_size.min_value = 0.2
	_size.max_value = 40.0
	_size.step = 0.1
	_size.value = 2.0
	_size.suffix = "m"
	_size.tooltip_text = "Ice floe size across"
	_size.visible = false
	_toolbar.add_child(_size)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_cursor_mesh = _make_cursor_mesh()
	_cursor = RenderingServer.instance_create()
	RenderingServer.instance_set_base(_cursor, _cursor_mesh.get_rid())
	RenderingServer.instance_set_visible(_cursor, false)


func _exit_tree() -> void:
	_end_stroke()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	RenderingServer.free_rid(_cursor)


func _handles(object: Object) -> bool:
	return object is Node


func _on_toggled(on: bool) -> void:
	_size.visible = on
	if not on:
		_end_stroke()
		RenderingServer.instance_set_visible(_cursor, false)
		return
	# The 3D view only passes input to a plugin that handles what's selected.
	var root := EditorInterface.get_edited_scene_root()
	if root and EditorInterface.get_selection().get_selected_nodes().is_empty():
		EditorInterface.edit_node(root)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _toggle.button_pressed or not EditorInterface.get_edited_scene_root():
		return AFTER_GUI_INPUT_PASS
	if not event is InputEventMouse:
		return AFTER_GUI_INPUT_PASS
	var hit := _pick(camera, event.position)
	_show_cursor(hit)
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_stroking = true
			_erasing = button.is_command_or_control_pressed()
			_last = Vector3.INF
			_paint(hit)
		else:
			_end_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _stroking:
		_paint(hit)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## Where the screen point's ray meets the water's surface at rest, or the
## infinite point if there's no Water, the ray doesn't reach it, or terrain
## or a body is in the way. Floes already painted don't get in the way.
func _pick(camera: Camera3D, at: Vector2) -> Vector3:
	var water := _find_water()
	if not water:
		return Vector3.INF
	var from := camera.project_ray_origin(at)
	var dir := camera.project_ray_normal(at)
	var level := water.global_position.y
	if absf(dir.y) < 1e-4:
		return Vector3.INF
	var distance := (level - from.y) / dir.y
	if distance <= 0.0 or distance > camera.far:
		return Vector3.INF
	var point := from + dir * distance
	var query := PhysicsRayQueryParameters3D.create(from, point, BLOCK_MASK, _ice_rids())
	if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return Vector3.INF
	var terrain := _find_terrain()
	if terrain and not BarnaclePatch.intersect_terrain(terrain, from, point,
			float(terrain.get("vertex_spacing")) * 0.5).is_empty():
		return Vector3.INF
	return point


func _paint(point: Vector3) -> void:
	if point == Vector3.INF:
		return
	if _erasing:
		_erase_at(point)
		return
	if _last.distance_to(point) < _size.value * SPACING:
		return
	_last = point
	_add_patch(point)


func _add_patch(point: Vector3) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var parent := _container()
	var patch: IcePatch = (load(PATCH_SCENE) as PackedScene).instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE)
	patch.radius = _size.value * 0.5
	patch.transform = parent.global_transform.affine_inverse() * Transform3D(Basis(), point)
	patch.name = "IcePatch"
	parent.add_child(patch, true)
	patch.owner = root
	_added.append(patch)


## The Ice node, made if there's none.
func _container() -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	var container := root.get_node_or_null(CONTAINER_NAME) as Node3D
	if container:
		return container
	container = Node3D.new()
	container.name = CONTAINER_NAME
	root.add_child(container, true)
	container.owner = root
	_new_container = container
	return container


func _ice_patches() -> Array[IcePatch]:
	var patches: Array[IcePatch] = []
	for node in EditorInterface.get_edited_scene_root().find_children("*", "AnimatableBody3D", true, true):
		if node is IcePatch:
			patches.append(node)
	return patches


func _ice_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for patch in _ice_patches():
		rids.append(patch.get_rid())
	return rids


func _erase_at(point: Vector3) -> void:
	for patch in _ice_patches():
		if patch.contains_point(point):
			var parent := patch.get_parent()
			_removed.append({patch = patch, parent = parent, index = patch.get_index()})
			parent.remove_child(patch)


## Makes one undo step of the stroke's changes, already made.
func _end_stroke() -> void:
	_stroking = false
	if _added.is_empty() and _removed.is_empty():
		_new_container = null
		return
	var root := EditorInterface.get_edited_scene_root()
	var undo := get_undo_redo()
	undo.create_action("Erase Ice" if _erasing else "Paint Ice", UndoRedo.MERGE_DISABLE, root)
	if _new_container:
		undo.add_do_method(root, "add_child", _new_container, true)
		undo.add_do_method(_new_container, "set_owner", root)
		undo.add_do_reference(_new_container)
		undo.add_undo_method(root, "remove_child", _new_container)
	for patch in _added:
		var parent := patch.get_parent()
		undo.add_do_method(parent, "add_child", patch, true)
		undo.add_do_method(patch, "set_owner", root)
		undo.add_do_reference(patch)
		undo.add_undo_method(parent, "remove_child", patch)
	# Put back in reverse, so each goes back to its own place among its siblings.
	for i in range(_removed.size() - 1, -1, -1):
		var removed: Dictionary = _removed[i]
		undo.add_do_method(removed.parent, "remove_child", removed.patch)
		undo.add_undo_method(removed.parent, "add_child", removed.patch, true)
		undo.add_undo_method(removed.parent, "move_child", removed.patch, removed.index)
		undo.add_undo_method(removed.patch, "set_owner", root)
		undo.add_undo_reference(removed.patch)
	undo.commit_action(false)
	_added.clear()
	_removed.clear()
	_new_container = null


func _show_cursor(point: Vector3) -> void:
	if point == Vector3.INF:
		RenderingServer.instance_set_visible(_cursor, false)
		return
	var root := EditorInterface.get_edited_scene_root()
	RenderingServer.instance_set_scenario(_cursor, root.get_world_3d().scenario)
	RenderingServer.instance_set_transform(_cursor, Transform3D(Basis.from_scale(Vector3.ONE * _size.value), point))
	RenderingServer.instance_set_visible(_cursor, true)


## A level circle one unit across, drawn over everything.
func _make_cursor_mesh() -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(0.5, 0.85, 1.0)
	var lines := PackedVector3Array()
	for i in CURSOR_SEGMENTS:
		for k: int in [i, i + 1]:
			var angle := TAU * k / CURSOR_SEGMENTS
			lines.append(Vector3(cos(angle), 0.0, sin(angle)) * 0.5)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _find_water() -> Water:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return null
	if root is Water:
		return root
	for node in root.find_children("*", "Node3D", true, false):
		if node is Water:
			return node
	return null


func _find_terrain() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return null
	if root.is_class("Terrain3D"):
		return root
	var found := root.find_children("*", "Terrain3D", true, false)
	return found[0] if not found.is_empty() else null
