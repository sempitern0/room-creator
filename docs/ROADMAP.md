# Room Creator — Agent engineering roadmap

Architecture derived from `ROOM_CREATOR_NEXT_AGENT_HANDOFF(1).md` (design proposal, not code). Godot **4.7.2 stable**, addon path `addons/room_creator/`. Source, APIs and documentation are written in English.

## Current architecture

| Area | Status | Contract |
|---|---|---|
| F0 independent addon | Implemented and CI-tested | Clean project copies `addons/room_creator` only; no OmniKit |
| F1 manual rooms | Implemented; interactive QA remains | Typed `RoomBlueprint`, openings, primitive colliders, preview/bake, scene export |
| F2 seeded layout | Implemented for cardinal-grid rooms | `DungeonConfig`, `LevelLayout`, `RoomPlacementData`, `RoomConnectionData`, stable IDs, local RNG, bounded path search |
| F2 graph/geometry validation | Implemented for this subset | BFS reachability, critical path floor, reciprocal door orientations, matched openings, occupancy, schema checks |
| F2 editor/export | Implemented | `DungeonAuthoring3D` generates/validates/previews/bakes/exports; Undo/Redo for generated nodes; baked scenes are engine-native |
| F2 validation | Automated in Godot 4.7.2 CI | 100 seeds × 3 presets plus 60 mixed-silhouette seeds and 12 rotations; loop test, door socket alignment, portable scene reload and capsule sweep |
| F2.1 shape variety and editor lifecycle | **Implemented** | Weighted rectangle/cross/L/T orthogonal silhouettes with matched sockets; generating auto-previews and replaces stale bake; bake hides preview, undoable |
| F2.2 path diagnostics | **Implemented** | Preview-only role floor tints, entrance/exit labels, main/branch/alternate-loop links, editable color palette and visibility toggles; no bake contamination |
| F2 advanced packing | **Not implemented** | Variable-size prefabs, arbitrary rotated sockets, explicit spatial broadphase and bounded backtracking for 3D overlaps |
| F3 locked editing/biomes | **Not implemented** | Locks, incremental regeneration, biomes, reusable profiles, navigation pipeline |
| F4 exterior cities | **Not implemented** | Street graph, parcels, road access, zoning |
| F5 release hardening | Partial | Cross-platform interactive QA, benchmarks, migration fixtures and user acceptance outstanding |

## Remaining work, in order

1. **Interactive F2 QA:** test Undo/Redo with scene saved/reopened in Windows and Linux editor; validate exported gameplay with a controllable character and differing physics profiles.
2. **Prefab-driven spatial embedding and true variable size:** read authored sockets from `PackedScene` templates, match facing transforms and clearance, handle differing footprints and transforms (OBB, backtracking), avoid unpaired doors.
3. **Agent-space validation:** optional NavigationMesh generation and independent path verification (graph connectivity alone is insufficient for full navigation).
4. **F3 persistent overrides:** stable per-room locks, local overrides, invalid-connection conflict reports, incremental regeneration and undoable viewport gizmos.
5. **Style/data layer:** separate RoomBiome and BakeProfile from geometry; meshes by room/chunk/material when measured; no shared Resource mutation.
6. **F4–F5:** independent city authoring, performance targets at 20/100/300 rooms, migration tools, release checks.

## Contracts

- Do not mutate designer-owned SceneTree nodes or shared `.tres` resources during generation.
- Failed generations are explicit and preserve the last valid layout.
- Regenerate derived geometry from `LevelLayout`, never from a detached baked mesh.
- Do not save a stale bake when its source geometry differs from the last baked layout fingerprint.
- All authored rooms/connectors have stable identities; their paired door openings are derived from a single logical edge.
- No use of globally seeded random functions in the new planner.
- Baked output must open without this addon installed.
- Do not claim full agent navigation, rotated multi-floor packing or low-poly/PSX biome support until tested.
