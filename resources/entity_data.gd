class_name EntityData
extends Resource

@export var id: StringName = &""
@export var visual: Helpers.VISUAL = Helpers.VISUAL.TRIANGLE
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
@export var god_mode: bool = false
