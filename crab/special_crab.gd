class_name SpecialCrab
extends ContactCrab
## A crab with an ability of its own, used by the ability action (shift)
## while it's steered on its own. Each kind of special crab extends this and
## overrides use_ability(), and can_walk() if the ability holds it still.


## Called by Player when the ability action is pressed.
func use_ability() -> void:
	pass


## Its name and controls for the controls HUD (see ControlsHud), one per
## line, plus a few words on anything it does by itself.
func get_controls_hint() -> String:
	return "Crab"
