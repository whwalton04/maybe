@tool
extends EditorPlugin
## Paints barnacle patches (world/barnacle_patch.tscn) onto whatever is under
## the mouse in the 3D view: physics bodies on SURFACE_MASK in the edited
## scene, or a Terrain3D, which has no collision in the editor and is found
## from its height data. Turn it on with the "Barnacles" button in the 3D
## toolbar, then left-click or drag to paint, and hold Ctrl (Cmd on macOS) to
## erase the patches under the mouse instead. Each patch is a circle the
## toolbar's size across, facing out of the surface.
##
## A patch painted on a moving body (rigid, animatable or character) is put
## under it, so it moves with it. Any other goes under a "Barnacles" node at
## the scene's root, made when first needed. Each stroke is one undo step.

const PATCH_SCENE := "res://world/barnacle_patch.tscn"
const CONTAINER_NAME := "Barnacles"
## What the brush paints on, besides any Terrain3D: the world, not animals.
const SURFACE_MASK := 1
## How far apart, × the patch size across, a drag lays patches. Their rims
## thin out, so they overlap.
const SPACING := 0.6
const CURSOR_SEGMENTS := 48

var _toolbar: HBoxContainer
var _toggle: Button
var _size: SpinBox
var _cursor_mesh: ArrayMesh
var _cursor := RID()

# The stroke under way: whether it erases, where it last laid a patch, and
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
	_toggle.text = "Barnacles"
	_toggle.tooltip_text = "Paint barnacle patches: click or drag on a surface. Ctrl+click or drag erases."
	_toggle.toggle_mode = true
	_toggle.flat = true
	_toggle.toggled.connect(_on_toggled)
	_toolbar.add_child(_toggle)
	_size = SpinBox.new()
	_size.min_value = 0.1
	_size.max_value = 10.0
	_size.step = 0.05
	_size.value = 1.0
	_size.suffix = "m"
	_size.tooltip_text = "Barnacle patch size across"
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
	_show_cursor(camera, hit)
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_stroking = true
			_erasing = button.is_command_or_control_pressed()
			_last = Vector3.INF
			_paint(camera, hit)
		else:
			_end_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _stroking:
		_paint(camera, hit)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## The nearest surface under the screen point: {position, normal, collider},
## or empty.
func _pick(camera: Camera3D, at: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(at)
	var dir := camera.project_ray_normal(at)
	var far := camera.far
	var hit := {}
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * far, SURFACE_MASK)
	var body := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not body.is_empty():
		hit = {position = body.position, normal = body.normal, collider = body.collider}
	var terrain := _find_terrain()
	if terrain:
		var to: Vector3 = from + dir * far if hit.is_empty() else hit.position
		var ground := BarnaclePatch.intersect_terrain(terrain, from, to,
				float(terrain.get("vertex_spacing")) * 0.5)
		if not ground.is_empty():
			hit = {position = ground.position, normal = ground.normal, collider = terrain}
	return hit


func _paint(camera: Camera3D, hit: Dictionary) -> void:
	if hit.is_empty():
		return
	if _erasing:
		_erase_at(hit.position)
		return
	if _last.distance_to(hit.position) < _size.value * SPACING:
		return
	_last = hit.position
	_add_patch(camera, hit)


func _add_patch(camera: Camera3D, hit: Dictionary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var parent := _parent_for(hit.collider)
	var patch: BarnaclePatch = (load(PATCH_SCENE) as PackedScene).instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE)
	patch.radius = _size.value * 0.5
	patch.random_seed = randi()
	patch.transform = parent.global_transform.affine_inverse() * _patch_transform(camera, hit)
	patch.name = "BarnaclePatch"
	parent.add_child(patch, true)
	patch.owner = root
	_added.append(patch)


## On the surface, facing out of it, its X squared up to the view.
func _patch_transform(camera: Camera3D, hit: Dictionary) -> Transform3D:
	var up: Vector3 = (hit.normal as Vector3).normalized()
	var side := camera.global_basis.x
	side -= up * side.dot(up)
	if side.length_squared() < 1e-4:
		side = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT)
	side = side.normalized()
	return Transform3D(Basis(side, up, side.cross(up)), hit.position)


## The moving body painted on, if it's in the edited scene, or else the
## Barnacles node, made if there's none.
func _parent_for(collider: Object) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if (collider is RigidBody3D or collider is AnimatableBody3D or collider is CharacterBody3D) \
			and (collider == root or root.is_ancestor_of(collider)):
		return collider
	var container := root.get_node_or_null(CONTAINER_NAME) as Node3D
	if container:
		return container
	container = Node3D.new()
	container.name = CONTAINER_NAME
	root.add_child(container, true)
	container.owner = root
	_new_container = container
	return container


func _erase_at(point: Vector3) -> void:
	var root := EditorInterface.get_edited_scene_root()
	for node in root.find_children("*", "Area3D", true, true):
		var patch := node as BarnaclePatch
		if patch and patch.contains_point(point):
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
	undo.create_action("Erase Barnacles" if _erasing else "Paint Barnacles", UndoRedo.MERGE_DISABLE, root)
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


func _show_cursor(camera: Camera3D, hit: Dictionary) -> void:
	if hit.is_empty():
		RenderingServer.instance_set_visible(_cursor, false)
		return
	var xform := _patch_transform(camera, hit)
	xform.basis = xform.basis.scaled_local(Vector3.ONE * _size.value)
	RenderingServer.instance_set_scenario(_cursor, camera.get_world_3d().scenario)
	RenderingServer.instance_set_transform(_cursor, xform)
	RenderingServer.instance_set_visible(_cursor, true)


## A circle one unit across in XZ with a tick out along +Y, drawn over
## everything.
func _make_cursor_mesh() -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.85, 0.2)
	var lines := PackedVector3Array()
	for i in CURSOR_SEGMENTS:
		for k: int in [i, i + 1]:
			var angle := TAU * k / CURSOR_SEGMENTS
			lines.append(Vector3(cos(angle), 0.0, sin(angle)) * 0.5)
	lines.append(Vector3.ZERO)
	lines.append(Vector3(0, 0.15, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _find_terrain() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return null
	if root.is_class("Terrain3D"):
		return root
	var found := root.find_children("*", "Terrain3D", true, false)
	return found[0] if not found.is_empty() else null
