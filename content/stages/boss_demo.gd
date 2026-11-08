@tool
extends EditorScript
## Template for a new stage: a short text script that builds its [StageData]
## with [StageBuilder] and saves it. Run from the editor (File > Run).
##
## How it works:
## - [code]formation()[/code], [code]music()[/code], [code]entry()[/code],
##   [code]dives()[/code] and [code]delay()[/code] set sticky defaults that
##   apply to every wave added after the call, until changed again.
## - [code]row()[/code], [code]rows()[/code] and [code]boss()[/code] append
##   waves in call order. Per-wave options go in a dictionary (GDScript has
##   no named arguments); a per-wave option overrides the sticky default.
## - [code]to(path)[/code] overrides the output path (default:
##   [code]res://resources/stages/stage_&lt;name&gt;.tres[/code]);
##   [code]journey(name)[/code] also appends the saved stage to that journey.
## - [code]save()[/code] resolves every name through [ContentLibrary],
##   validates the stage, and prints every problem at once. It refuses to
##   write on lookup/option errors or on [code]validate()[/code] errors
##   (unless [code]save(true)[/code]).
## - Names are normalized (lowercase, spaces/hyphens as underscores,
##   extension ignored) and tried with the file's prefix first, so you can
##   write "decagon" for "foe_decagon.tscn" or "boss_arena" for
##   "formation_boss_arena.tres". Run [code]content/list_content.gd[/code] to
##   see every name you may type.
##
## Example of [code]rows()[/code] and [code]journey()[/code] (commented out):
##
##   builder.delay(2.0)  # sticky: delay 3.0 from here on
##   builder.rows(["star", "decagon", "h"], 1, {
##       "entry": "left_02",
##       "dives": ["left_03"],
##       "fire_in_formation": true,
##   })
##   builder.journey("alpha")
##
## This script rebuilds the hand-made [code]stage_boss_demo.tres[/code] into
## [code]res://resources/stages/generated/stage_boss_demo_gen.tres[/code]
## (the original is never overwritten) and diffs the two: the diff must be
## empty.


## The original, hand-made stage to compare against.
const ORIGINAL_PATH: String = "res://resources/stages/stage_boss_demo.tres"

## The generated output (the original is never overwritten).
const OUTPUT_PATH: String = "res://resources/stages/generated/stage_boss_demo_gen.tres"


func _run() -> void:
	var original: StageData = ResourceLoader.load(ORIGINAL_PATH) as StageData
	var builder: StageBuilder = StageBuilder.new("boss_demo")
	builder.to(OUTPUT_PATH)
	# Sticky defaults: every wave added from here on uses them until changed.
	builder.formation("boss_arena")
	builder.music("neon_drive_-_retro_synth_game_music")
	# Wave 0: the boss (delay stays at its default 0.0 here).
	builder.boss("boss_01", 4, {
		"entry": "left_01",
		"cinematic": "boss_entrance",
	})
	# Sticky from here on: the regular waves are delayed by 3.0 s.
	builder.delay(3.0)
	builder.row("star", 0, {
		"entry": "left_02",
		"dives": ["left_03"],
	})
	builder.row("decagon", 3, {
		"entry": "left_04",
		"dives": ["left_01"],
	})
	builder.row("h", 4, {
		"entry": "left_04",
		"dives": ["left_05"],
	})
	var err: Error = builder.save()
	if err != OK:
		print("boss_demo: build failed (error %s); see the report above." % err)
		return
	var generated: StageData = ResourceLoader.load(OUTPUT_PATH) as StageData
	print("boss_demo diff against %s:" % ORIGINAL_PATH)
	var diffs: PackedStringArray = StageBuilder.diff_stages(original, generated)
	if diffs.is_empty():
		print("  identical: %d waves, no differences" % original.waves.size())
	else:
		for diff: String in diffs:
			print("  DIFFERENT: %s" % diff)
