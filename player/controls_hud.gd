class_name ControlsHud
extends CanvasLayer
## Plain text in the bottom corners: the controls that always work on the
## left, and on the right the controlled crab's own (see
## SpecialCrab.get_controls_hint()), shown while one is steered on its own.

const GLOBAL_TEXT := "WASD  move\nMouse  look\n← →  switch crab\nQ  whole group\nSpace  mount / jump off\nU  rally to flag"
const MARGIN := 16.0
const FONT_SIZE := 18

## The player whose controlled crab is shown; its parent by default.
@export var player: Player

var _left: Label
var _right: Label


func _ready() -> void:
	if not player:
		player = get_parent() as Player
	_left = _make_label(Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_left.text = GLOBAL_TEXT
	_right = _make_label(Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)


func _process(_delta: float) -> void:
	var text := ""
	if player and is_instance_valid(player.controlled):
		var crab := player.controlled
		text = crab.get_controls_hint() if crab.has_method("get_controls_hint") else "Crab"
	if _right.text != text:
		_right.text = text


func _make_label(preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	# Grow up and inward from the corner as the text changes size.
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.grow_horizontal = Control.GROW_DIRECTION_END \
			if align == HORIZONTAL_ALIGNMENT_LEFT else Control.GROW_DIRECTION_BEGIN
	return label
