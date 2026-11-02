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
@export var fire_pulse_enabled: bool = false
@export var god_mode: bool = false
