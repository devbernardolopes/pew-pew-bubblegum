extends Node2D
## Test level: spawns one placeholder wave of foes that enter along a shared
## [Curve2D] and settle into the [Formation].

const FOE_SCENE: PackedScene = preload("res://scenes/entities/foe_01.tscn")
## Delay between two foes of the same side entering, in seconds.
const ENTRY_SPACING: float = 0.25
## Number of foes launched from each side; placeholder until waves are authored.
const COLUMNS_PER_SIDE: int = 4

@onready var formation: Formation = $Formation
@onready var entry_path: Path2D = $EntryPath


func _ready() -> void:
	var left_slots: Array[Marker2D] = []
	var right_slots: Array[Marker2D] = []
	for col: int in COLUMNS_PER_SIDE:
		left_slots.append(formation.get_slot(0, col))
		right_slots.append(formation.get_slot(0, col + COLUMNS_PER_SIDE))
	spawn_wave(FOE_SCENE, entry_path.curve, false, left_slots, ENTRY_SPACING)
	spawn_wave(FOE_SCENE, entry_path.curve, true, right_slots, ENTRY_SPACING)


## Instantiates one foe per slot and starts it along [param curve].
## Each foe enters [param spacing] seconds after the previous one.
func spawn_wave(foe_scene: PackedScene, curve: Curve2D, mirror: bool, slots: Array[Marker2D], spacing: float) -> void:
	for index: int in slots.size():
		var foe: Entity = foe_scene.instantiate() as Entity
		add_child(foe)
		var brain: FoeBrain = foe.get_node(^"FoeBrain") as FoeBrain
		brain.setup(curve, mirror, slots[index], index * spacing)
