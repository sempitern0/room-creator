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
| F2 validation | Automated in Godot 4.7.2 CI | 100 seeds × 3 presets plus 60 mixed-silhouette, 40 varied-size and 70 non-uniform spacing plus 45 independent-position, 36 routed-dogleg and 34 structural-prefab seeds; socket-marked module roundtrips, exterior-door and corridor capsule sweeps, 12 rotations; loop test, door socket alignment, portable scene reload and capsule sweep |
| F2.1 shape variety and editor lifecycle | **Implemented** | Weighted rectangle/cross/L/T orthogonal silhouettes with matched sockets; generating auto-previews and replaces stale bake; bake hides preview, undoable |
| F2.2 path diagnostics | **Implemented** | Preview-only role floor/roof tints, entrance/exit labels, main/branch/alternate-loop links, editable color palette and visibility toggles; no bake contamination |
| F2.3 exterior portals | **Implemented + CI-tested** | Real exit/entry wall holes and socket markers, both verified with CharacterBody3D capsule |
| F2.3 varied dimensions and connectors | **Implemented + CI-tested** | Reproducible per-room widths/depths within grid cells, spatial AABB checks and static corridor segments with real physics |
| F2.3 normalized art modules | **Implemented + CI-tested (v1.5.1 editor regression)** | Optional script-free / collision-free PackedScene with normalized wall sockets, seeded selection and portable baked instances |
| F2.4 axis-aligned spatial embedding | **Implemented + CI-tested** | Reproducible variable separation per row/column, serialized X/Z coordinate arrays, socket-coaxial extended corridors, bounded gaps, AABB and capsule tests |
| F2.5 constrained independent room offsets | **Implemented + CI-tested** | Topology-aware per-group XY-plane offsets, bounded seeded retries, aligned sockets, corridor/room crossing rejection and real capsule sweep |
| F2 authoring scene recovery | **Implemented + CI-tested** | Recovered clean `dungeon_authoring.tscn`, transient generated geometry, merge-marker/source-only fixture guard, editor Ctrl+S/reopen test |
| F2.6 orthogonal route solver | **Implemented + CI-tested** | Optional three-leg doglegs, serialized 4-point routes, bounded non-coaxial socket layout, union envelope corridors, real capsule elbow traversal and preview ribbons |
| F2.7 full structural room prefabs | **Implemented + CI-tested** | Script-free authored PackedScene shell replacement, StaticBody3D/BoxShape3D physics, marker position + orientation checks, exact door-set matching and cardinal quarter-turns, safe fallback, real capsule and editor export tests |
| F2 advanced free packing | **Not implemented** | Arbitrary rotated/offset sockets, non-box/multi-floor prefabs, unconstrained rotated OBB packing and general spatial backtracking |
| F3 locked editing/biomes | **Not implemented** | Locks, incremental regeneration, biomes, reusable profiles, navigation pipeline |
| F4 exterior cities | **Not implemented** | Street graph, parcels, road access, zoning |
| F5 release hardening | Partial (Godot 4.7.2 editor, plus Xvfb graphical regression) | Cross-platform interactive QA, benchmarks, migration fixtures and user acceptance outstanding |

## Remaining work, in order

1. **Interactive F2 QA:** test Undo/Redo with scene saved/reopened in Windows and Linux editor; validate exported gameplay with a controllable character and differing physics profiles.
2. **Full prefab-driven spatial embedding:** extend the new F2.7 structural prefab system beyond cardinal square/rectangular slots and primitive static boxes: arbitrary yaw/socket transforms, nonrectangular or multi-floor collision-bearing rooms, rotated OBB overlap and off-grid bounded spatial backtracking. F2.4 adds variable row/column spacing; F2.5 shifts individual graph-compatible alignment groups independently, but S/dogleg connectors are supported as of F2.6; arbitrary-angle room sockets, free-rotated prefab poses, the new 90° static-prefab replacements exist in F2.7, while unrestricted mesh colliders, offset sockets, multilevel paths and full OBB backtracking remain pending.
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
