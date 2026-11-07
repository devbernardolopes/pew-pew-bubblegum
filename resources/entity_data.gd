class_name EntityData
extends Resource

@export var id: StringName = &""
@export var visual: Helpers.VISUAL = Helpers.VISUAL.TRIANGLE
@export var color: Color = Color.WHITE
@export var team: Helpers.TEAM = Helpers.TEAM.FOE
@export var max_health: int = 1
@export var base_speed: float = 256.0
## Damage dealt to an opposing Entity on contact.
@export var contact_damage: int = 1
## Points awarded when this Entity is destroyed by a hero bullet.
@export var score_value: int = 0
## Scale factor for this entity's explosion shards and duration.
@export var explosion_scale: float = 0.50
@export var sound_profile: SoundProfile = null
@export var tilt_enabled: bool = false
@export var trail_enabled: bool = false
## Whether firing flashes this Entity's sprite (see [method Entity.play_fire_feedback]).
@export var fire_pulse_enabled: bool = false
## Whether firing also shakes the camera. It only has an effect when
## [member fire_pulse_enabled] is on too.
@export var shake_on_fire_enabled: bool = false
## Whether touching an opposing Entity destroys this one. Bosses turn it off.
@export var dies_on_contact: bool = true
## Center the polygon by its bounding box instead of assuming the 128 x 128
## box. Needed by shapes larger than that box, like bosses. Tilt is not
## supported together with this, because the roll assumes the 128 box.
@export var center_on_bounds: bool = false
@export var god_mode: bool = false
@export var god_mode_effect: bool = false

## Whether this foe can trigger a tractor beam capture during its dive.
@export_group("Tractor Beam")
## Whether tractor beam capture is enabled for this entity.
@export var tractor_beam_enabled: bool = false
## Probability (0..1) that a dive becomes a tractor dive, rolled at dive start.
@export_range(0.0, 1.0) var tractor_beam_chance: float = 0.3
## How long the tractor beam cone stays fully open (seconds).
@export var tractor_beam_open_duration: float = 3.0
## Maximum cone height/length, in pixels.
@export var tractor_beam_height: float = 400.0
## Cone width at the far end, in pixels.
@export var tractor_beam_width: float = 80.0
## Seconds to extend the cone; retract takes the same time.
@export var tractor_beam_grow_duration: float = 1.0
## Pixels per second the captured hero slides horizontally under the foe.
@export var tractor_beam_align_speed: float = 120.0
## Pixels per second the captured hero is pulled upward.
@export var tractor_beam_pull_speed: float = 90.0
## Score awarded for killing a carrier whose ship was committed.
@export var tractor_beam_rescue_bonus: int = 1000

@export_group("Tilt")
## Roll angle at full horizontal speed, in degrees.
@export_range(0.0, 70.0, 0.5, "suffix:°") var tilt_max_angle: float = 50.5
## How strongly the lowered wing shrinks and the raised wing grows.
@export_range(0.0, 0.01, 0.0005) var tilt_perspective: float = 0.004
## How quickly the roll follows the motion, per second (higher is snappier).
@export_range(1.0, 40.0) var tilt_response: float = 15.0
## Whether the collision polygon is deformed too. Off keeps the hitbox fixed.
@export var tilt_affects_collision: bool = false

@export_group("Trail")
## Distance travelled between two ghosts, in pixels.
@export_range(2.0, 64.0) var trail_spacing: float = 32.0
## Seconds a ghost takes to fade out.
@export_range(0.05, 1.0) var trail_lifetime: float = 0.25
## Opacity of a ghost when it appears.
@export_range(0.0, 1.0) var trail_alpha: float = 0.15

@export_group("Dash")
## Whether this Entity can perform a dash. Off for every Entity by default.
@export var dash_enabled: bool = false
## Dash distance measured in ship widths. Zero means the fleet's maximum
## number of ships ([constant Fleet.MAX_SHIPS]).
@export_range(0.0, 16.0, 0.5) var dash_distance_ships: float = 0.0
## Seconds the dash takes to cover its distance.
@export var dash_duration: float = 0.12
## Opacity of the visual while dashing.
@export_range(0.0, 1.0) var dash_alpha: float = 0.35
## Seconds that must pass after a dash before the next one. Zero allows an
## immediate re-dash.
@export var dash_cooldown: float = 0.0
## How long a dash press is remembered while no direction is held. Zero
## disables the input buffer.
@export var dash_input_buffer: float = 0.08


## Returns the problems found in this Entity's dash data, each prefixed with
## [code][warning][/code] and naming [param where]. [param speed_multiplier]
## and [param scale_aux] come from the Entity that owns this data, because the
## dash speed is derived from the ship width and the normal movement speed.
## It has its own name so that subclasses keep their own [code]validate[/code]
## signatures (see [method BossData.validate]).
func validate_dash(where: String = "", speed_multiplier: float = 1.0, scale_aux: float = 1.0) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not dash_enabled:
		return issues
	var label: String = where if not where.is_empty() else "(unsaved entity data)"
	if dash_duration <= 0.0:
		issues.append("[warning] %s: dash is enabled with a dash_duration of %.2f s." % [
				label, dash_duration])
		return issues
	var ships: float = dash_distance_ships
	if ships <= 0.0:
		ships = float(Fleet.MAX_SHIPS)
	var dash_speed: float = ships * Helpers.ENTITY_WIDTH * scale_aux / dash_duration
	var normal_speed: float = base_speed * speed_multiplier
	if dash_speed <= normal_speed:
		issues.append("[warning] %s: the derived dash speed %.1f is not greater than the normal speed %.1f." % [
				label, dash_speed, normal_speed])
	return issues
