# Room Creator agent development roadmap

Source: `ROOM_CREATOR_NEXT_AGENT_HANDOFF(1).md` (planning guidance, not a previously implemented feature). Target **Godot 4.7.2 stable**. Source code and distributed documentation use English.

## Migration mapping (legacy to the new core)

| Legacy component | Decision | Reason |
|---|---|---|
| `RoomCreator` | PRESERVE + PATCH (compatibility) | Existing scene nodes and inspector workflows |
| `CSGRoom` | PRESERVE + PATCH | Useful for blockout; no longer final geometry compiler |
| `RoomConfiguration`, `RoomParameters` | PRESERVE | Existing serialized scenes use these classes |
| `DungeonGenerator` | PRESERVE AS EXPERIMENTAL | Grid planning mixed with geometry; future reimplementation needs a separate layout |
| `RoomMesh` | PRESERVE | Existing exports; new pipeline emits native MeshInstance3D nodes |
| `RoomAuthoring3D`, `RoomBlueprint`, `RoomOpening` | NEW | Editor/resource-first workflow with immutable source of truth |
| `RoomGeometryBuilder`, `RoomValidationReport` | NEW | Pure validation precedes geometry and save operations |

## Status and next acceptance gates

- **F0 foundation:** new folder under existing self-contained addon; Godot 4.7.2 project settings; headless CI and smoke test added. Clean-project installation still requires validation by users/CI.
- **F1 manual rooms:** multiple door/window holes, serializable blueprint, surface materials, primitive static collision, sockets, preview/bake/save, validation. Validate in Godot 4.7.2 CI; add viewport undo/redo and gizmos; reference capsule physics test outstanding.
- **F2 deterministic dungeons (NOT IMPLEMENTED):** typed `DungeonConfig`, `LevelLayout`, logical connectivity graph, seeded local `RandomNumberGenerator`, socket transforms, spatial collision checks, bounded backtracking and replayable tests across 100 seeds. **Never** label a grid-connected layout as agent-walkable without geometry checks.
- **F3 editing and biomes:** persistent locked IDs/overrides; `RoomBiome`, `CollisionProfile`, `BakeProfile`, non-destructive regeneration, optional navigation, mesh and material batching.
- **F4 cities:** separate street/parcel/building graph pipeline only after F2 and F3 work reliably.
- **F5 release QA:** fully clean installation, Windows/Linux editor verification, scene pack/reload without plugin, collision capsule crossing, CI regression suite, deterministic layout fixtures, profiling.

## Non-negotiable contracts

1. Invalid or impossible input must not replace the last valid geometry or produce a successful export.
2. Never modify user-owned scene children or shared `.tres` presets as a generation side effect.
3. Keep editable blueprints/layouts independent from generated and baked geometry.
4. Make generated output standard Godot resources, free from plugin scripts at runtime.
5. Preserve source licensing and avoid copying code/visual assets from external references without permissions.
6. Report the exact revision, tests actually run, missing coverage, and limitations for each future iteration.
