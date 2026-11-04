# AGENTS.md

This is a Godot 2D space shooter game being developed inspired by the early 1980s game "Galaga" by NAMCO for the MSX home computer.

## Requirements

- Godot 4.7 using GDScript and following Godot's own code style guidelines.

## Testing

All **gameplay** testing is manual by the human after every iteration: do not run the main game scene.
The testing device is:

1. Samsung Odyssey laptop running Omarchy Quattro in 1920 x 1080 @ 60 Hz.

## Agent Workflow Notes

- While the agent writes files, keep those files **closed** in the Godot script editor: an open buffer can silently revert external writes on focus/undo/save.
- After every script write, **read the file back from disk** — never trust the write receipt alone.
- `node_set_property` cannot coerce strings to bool/int — set non-string properties in GDScript instead.
- `input_map` calls must be **sequential** (parallel bursts wedge the backend lock); `project_manage settings_set` accepts invalid keys without complaint (verify setting names against engine docs).
- Godot 4 API differs from Godot 3 memory (e.g. `ScrollContainer.horizontal_scroll_mode`). When unsure about a property or method, check the Godot 4.7 docs instead of guessing.
- Editor-log ghosts: the log buffer re-emits stale diagnostics on scans — confirm errors against current file contents (grep) before treating them as live.
- Never reference `EditorInterface` directly from a script that is shipped in a game: editor classes are stripped from export templates and the script then fails to load. Access it only under `Engine.is_editor_hint()` through `Engine.get_singleton(&"EditorInterface")`.
- Godot generates `.gd.uid` sidecars; keep them tracked so scenes and references stay stable.
- `Entity` origin sits at the **center** of its shape (both axes), and the shapes are built in `_refresh_shape()`. Hand-placed entity positions assume that: changing the shape offset means shifting `y` by `Helpers.ENTITY_HALF_WIDTH * scale_aux` in the scenes, or the visual moves.
- Physics layers live in `PhysicsLayers` and are assigned by `Entity._apply_layers()` from `data.team`, not in scenes. For each pair of interacting things, exactly one side lists the other in its mask (otherwise every hit fires twice): foes mask `FRIEND` for ramming, projectiles are the monitoring side.
- A foe's `global_position` and `rotation` belong to its `FoeBrain` child, never to an `EntityController`; `Entity` leaves uncontrolled entities alone, so do not give a foe a controller.
- `Weapon` is a child node of the shooter and stays team-agnostic (the projectile takes the shooter's `data.team`). `Projectile`s are built in code and spawned into the node in the `projectiles` group; the projectile is the monitoring side, so its mask lists the target Entity layer and Entities never list projectile layers. A successful shot calls `Entity.play_fire_feedback()`, which pulses the sprite when `fire_pulse_enabled` is on and shakes the camera only when `shake_on_fire_enabled` is on too, so fire feedback is per `EntityData`, not per team.
- Entry paths are shared `Curve2D` resources under `resources/curves/`, wrapped in a `Path2D` in the level so they can be reshaped in the editor; gameplay reads the curve, never the `Path2D`.
- `FoeBrain`s register in the `foe_brains` group; a `DiveDirector` in the level decides who dives and when (`FoeBrain` never schedules its own dives). Dive curves live on `WaveData.dive_curves`, the only source of truth (`DiveDirector` has none of its own); a foe picks one at random per dive, and curves are anchored at the foe's position at dive start, so one curve serves every slot.
- Formations are built once per `FormationData` per stage and never rebuilt or freed mid-stage: `StageDirector` owns them under the level's `Formations` node, caches one instance per distinct `FormationData` (waves sharing the resource sway in unison), and only frees them when the next stage begins. The slot a foe receives in `FoeBrain.setup()` is therefore valid for the foe's whole life, and a foe never looks its slot up again.
- Gameplay logic can be checked headlessly without opening the game: run a throwaway `extends SceneTree` script with `godot --headless --path . --script res://tools/name.gd`, instantiate the level there, then delete the script.

- **Fleet**: `Universe` owns a `Fleet` (a plain `Node` in the `fleet` group) that owns one or two hero `Entity`s: it sets their **global** positions, clamps the block by the combined width and calls `Entity.drive()` on each, so both move and fire as one. Members have no effective controller (`Entity.externally_driven`). Lives are `GameManager.reserve_ships` (the HUD icons) plus the ships in play: losing one of two changes nothing, and a reserve ship is spent only when the fleet empties (or the game ends). A ship grabbed by a beam leaves the fleet; the survivor keeps its x and becomes the leader in place. The dock side is whichever position fits and is closest to the freed ship. A freed ship (`Entity.begin_return()`) is `returning` (no input, no damage, `is_capturable()` false) and the `Fleet` flies it to its slot — or to `HeroSpawn` when the fleet is empty — in `RETURN_DURATION`, which replaces the respawn delay at no life cost. While it flies, `Universe` freezes `$Entities`, `$Projectiles`, `$Formations`, `$DiveDirector` and `$StageDirector` with `process_mode`, so backgrounds, effects, HUD and audio keep running. `Entity.is_capturable()` is the single filter for beams, foe aim and rescue.
- **Tractor beam**: The capture lock lives on `FoeBrain._capturer` (validated with `is_instance_valid`); the life is committed only when the carrier reaches formation (`Carry.COMMITTED`), while before that the hero is only "parked" (hidden, frozen, non-monitorable). A released ship calls `begin_return()` and `FoeBrain` looks up the `fleet` group to `recruit()` it; a committed capture frees the old hero and `recruit_new()` spawns its replacement at the rider. The beam (`TractorBeam`) is the monitoring side of the physics layers (`collision_mask = FRIEND`, `monitorable = false`), and the rider (`Polygon2D`) is top-level and follows the foe (`rotation = foe.rotation + PI`). No capture sound or effect plays until the beam actually captures (`get_touching_hero()`), and `FoeBrain` only creates the `TractorBeam` node when `data.tractor_beam_enabled` is true.

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
