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
- `Weapon` is a child node of the shooter and stays team-agnostic (the projectile takes the shooter's `data.team`). `Projectile`s are built in code and spawned into the node in the `projectiles` group; the projectile is the monitoring side, so its mask lists the target Entity layer and Entities never list projectile layers.
- Entry paths are shared `Curve2D` resources under `resources/curves/`, wrapped in a `Path2D` in the level so they can be reshaped in the editor; gameplay reads the curve, never the `Path2D`.
- `FoeBrain`s register in the `foe_brains` group; a `DiveDirector` in the level decides who dives and when (`FoeBrain` never schedules its own dives). Dive curves are anchored at the foe's position at dive start, so one curve serves every slot.
- Formations are built once per `FormationData` per stage and never rebuilt or freed mid-stage: `StageDirector` owns them under the level's `Formations` node, caches one instance per distinct `FormationData` (waves sharing the resource sway in unison), and only frees them when the next stage begins. The slot a foe receives in `FoeBrain.setup()` is therefore valid for the foe's whole life, and a foe never looks its slot up again.
- Gameplay logic can be checked headlessly without opening the game: run a throwaway `extends SceneTree` script with `godot --headless --path . --script res://tools/name.gd`, instantiate the level there, then delete the script.

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
