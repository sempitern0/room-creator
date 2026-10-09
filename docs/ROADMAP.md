# Room Creator — Agent engineering roadmap

Architecture derived from `ROOM_CREATOR_NEXT_AGENT_HANDOFF(1).md` (design proposal, not code). Godot **4.7.2 stable**, addon path `addons/room_creator/`. Source, APIs and documentation are written in English.

## Current architecture

| Area | Status | Contract |
|---|---|---|
| F0 independent addon | Implemented and CI-tested | Clean project copies `addons/room_creator` only; no OmniKit |
| F1 manual rooms | Implemented; interactive QA remains | Typed `RoomBlueprint`, openings, primitive colliders, preview/bake, scene export |
| F2 seeded layout | **Feature-complete for supported single-floor domain** | `DungeonConfig`, `LevelLayout`, deterministic topology plus cardinal/grid-yaw/off-grid socket-based world embedding, stable IDs, capped backtracking and agent-space physics checks |
| F2 graph/geometry validation | **Implemented + CI-tested** | BFS reachability, critical path floor, reciprocal door orientations, matched openings, occupancy, schema checks |
| F2 editor/export | Implemented | `DungeonAuthoring3D` generates/validates/previews/bakes/exports; Undo/Redo for generated nodes; baked scenes are engine-native |
| F2 validation | Automated in Godot 4.7.2 CI | 100 seeds × 3 presets plus 60 mixed-silhouette, 40 varied-size and 70 non-uniform spacing plus 45 independent-position, 36 routed-dogleg, 34 structural-prefab and 35 offset-socket seeds; socket-marked module roundtrips, exterior-door and corridor capsule sweeps, 12 rotations; loop test, door socket alignment, portable scene reload and capsule sweep |
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
| F2.8 offset prefab sockets (first slice) | **Implemented + CI-tested** | Signed independent lateral doorway offsets derived from authored Marker3D poses, deterministic route regeneration, collision-bounded prefab rollback, physical capsule traversal, seeded export and graphical editor regression |
| F2.8.2 free-yaw docking kernel + editor lab | **Implemented + CI-tested (limited scope)** | Separating-axis OBB validation throughout the production spatial validator, pure seed-bounded transform docking between two arbitrary-yaw sockets, physical rotated straight bridge, source-only experimental Godot Inspector lab, capsule and Xvfb editor tests |
| F2.9 production free-yaw multiroom dungeons | **Implemented + CI-tested** | Independent yaw per room, graph-compatible 3-leg world routes, union floor/roof collision, boundary walls, SAT corridor checks, bounded positional DFS and portable capsule traversals |
| F2.10 true off-grid socket packing | **Implemented + CI-tested** | Attach a new room from a previously authored socket rather than grid coordinates, bounded seeded world-space DFS/backtracking, SAT clearance, real entrance/exit and graph-edge capsule sweeps, native export |
| F2 completed single-floor acceptance | **Implemented + CI-tested** | Old F2 path seeds plus full-yaw, loop/mixed-silhouette/size, structural rotated-collider and true off-grid socket regression, graphical Editor Inspector and source-only save |
| Unrestricted multi-floor 3D packing / arbitrary mesh prefabs | **Out of F2 single-floor scope** | Multi-floor rotated 3D OBBs, diagonal door cuts within arbitrary mesh shells, navigation baking and guaranteed off-grid loop closure are not certified |
| F3 locked editing/biomes | **Not implemented** | Locks, incremental regeneration, biomes, reusable profiles, navigation pipeline |
| F4 exterior cities | **Not implemented** | Street graph, parcels, road access, zoning |
| F5 release hardening | Partial (Godot 4.7.2 editor, plus Xvfb graphical regression) | Cross-platform interactive QA, benchmarks, migration fixtures and user acceptance outstanding |

## Remaining work, in order

1. **Windows interactive F2 acceptance (manual):** validate source-only Ctrl+S, Inspector Undo/Redo, exported gameplay in a Windows Godot 4.7.2 installation with varying physics setups. Linux headless and Xvfb editor CI are green; Windows is not independently tested.
2. **F3 locked editing and navigation:** per-room persistent edits, incremental regeneration and room-lock conflicts; optional NavMesh generation and independent agent path verification.
3. **Refinements outside certified F2 scope:** guaranteed closure of arbitrary off-grid cycles, true authored oblique door cutouts, arbitrary mesh colliders, 3D/multilevel rotated packing and non-planar connectors.
4. **F3 style/data layer:** separate RoomBiome and BakeProfile from geometry; measure then batch meshes by room/chunk/material with no shared Resource mutation.
5. **F4–F5:** independent city authoring, 20/100/300-room performance targets, migration tools and release hardening.

## Contracts

- Do not mutate designer-owned SceneTree nodes or shared `.tres` resources during generation.
- Failed generations are explicit and preserve the last valid layout.
- Regenerate derived geometry from `LevelLayout`, never from a detached baked mesh.
- Do not save a stale bake when its source geometry differs from the last baked layout fingerprint.
- All authored rooms/connectors have stable identities; their paired door openings are derived from a single logical edge.
- No use of globally seeded random functions in the new planner.
- Baked output must open without this addon installed.
- Do not claim full agent navigation, rotated multi-floor packing or low-poly/PSX biome support until tested.
