class_name StagePreview
extends Node
## Play one stage inside the real [code]scenes/universe.tscn[/code], without
## touching any resource on disk: open `scenes/stage_preview.tscn`, drop a
## [StageData] on [member stage], press F6.
##
## [member start_wave] makes the first stage begin at that wave (the boss
## cinematic is skipped when its wave is skipped too). When [member god_mode]
## is on, the hero's [EntityData] — the shared cached
## [code]res://resources/entities/hero_data.tres[/code] — is made
## invulnerable in memory only ([method Entity.take_damage] returns early for
## god mode heroes), so the normal game keeps its damage rules and the file
## on disk is never written.


## The stage to preview, played alone in the universe.
@export var stage: StageData = null
## First wave of the previewed stage.
@export_range(0, 64, 1) var start_wave: int = 0
## When on, the hero cannot be damaged (in memory only; see above).
@export var god_mode: bool = false


func _ready() -> void:
	if stage == null:
		push_error("StagePreview: no stage assigned. Open scenes/stage_preview.tscn, drop a StageData on `stage` in the inspector, and press F6 to preview it.")
		get_tree().quit()
		return
	var universe_packed: PackedScene = ResourceLoader.load("res://scenes/universe.tscn") as PackedScene
	var universe: Node = universe_packed.instantiate()
	var director: StageDirector = universe.get_node("StageDirector") as StageDirector
	if director == null:
		push_error("StagePreview: scenes/universe.tscn has no StageDirector.")
		return
	var journey_data := JourneyData.new()
	journey_data.stages = [stage]
	director.journey = journey_data
	director.debug_start_wave = start_wave
	if god_mode:
		var hero_data: EntityData = ResourceLoader.load("res://resources/entities/hero_data.tres") as EntityData
		hero_data.god_mode = true
	add_child(universe)
