# AGENTS.md — Room Creator contributor/AI-agent contract

This file is the entry point for coding assistants working on **sempitern0/room-creator**, a Godot **4.7.2 stable** @tool editor addon. Read it before changing any files. Read `docs/ROADMAP.md`, `docs/F2_ACCEPTANCE.md`, `docs/F3_PROGRESS.md`, and `docs/EDITOR_WORKSPACE.md` when working on the dungeon pipeline. **Treat the current `main` HEAD as authoritative, not prior chat summaries or an old checkout.**

## 1. Mission and priority

Create a portable, deterministic, non-destructive Godot room/dungeon authoring tool. The user's own scene, resources, UIDs and commits are real project data. Preserve them. Favor **correct traversable geometry over plausible-looking preview screenshots**, small composable operations, stable resource schemas, and safe failure over speculative features.

Read `README.md` for the current supported feature set. Do not confuse **completed F2 single-floor behavior** with still-partial F3 (persistent manual editing, styling, navigation).

### Before deciding what to implement

1. Fetch `main` HEAD SHA/commit and working tree; review recent user commits, `AGENTS.md`, roadmap and CI. Never assume that a previously reported SHA is still HEAD.
2. Frame the request as concrete acceptance criteria and state **which capability is currently proved, missing, or uncertain**. Verify with implementation paths and tests—not only README assertions.
3. Trace one end-to-end path before editing: `DungeonConfig` → `DungeonPlanner` → `LevelLayout`/`RoomPlacementData`/`RoomConnectionData` → socket/route validation → `DungeonSceneCompiler` → `DungeonAuthoring3D` Inspector/UndoRedo → native PackedScene.
4. Establish the smallest risky behavior and a **failing regression fixture**. Compare alternative designs against: physical doorway alignment, deterministic replay, no generated-source pollution, backward compatibility, and failure rollback.
5. Make additive/transactional changes; reproduce and inspect all CI failures; finish only when the final pushed SHA's CI is green. If CI is red or unfinished, say so and provide the exact failing step.

## 2. Architecture and source of truth

| Responsibility | Implementation |
|---|---|
| Designer inputs, presets | `addons/room_creator/src/next/dungeon/dungeon_config.gd`, `examples/*.tres` |
| Pure topology, seeded rooms, clearance checks | `dungeon_planner.gd` |
| Serializable source and fingerprint | `level_layout.gd`; room `room_placement_data.gd`; edge `room_connection_data.gd` |
| Cardinal spatial layout | `dungeon_spatial_embedder.gd`, `dungeon_room_offset_solver.gd`, `dungeon_corridor_router.gd`, `dungeon_connector_builder.gd` |
| Yaw/off-grid spatial layout | `dungeon_oriented_bounds.gd`, `dungeon_free_yaw_placement.gd`, `dungeon_socket_graph_packer.gd`, `dungeon_free_yaw_router.gd`, `dungeon_free_yaw_corridor_builder.gd` |
| Real physical room art and opening validation | `dungeon_structural_prefab.gd`, `dungeon_structural_room_builder.gd`, `dungeon_room_module.gd`, `RoomGeometryBuilder` |
| F3 protected edits | `dungeon_room_editing.gd`, `dungeon_room_overrides.gd`, `dungeon_room_module_painter.gd` |
| Conversion to native Godot nodes | `dungeon_scene_compiler.gd` |
| Editor buttons, generated node lifecycle, undo/redo, export | `dungeon_authoring_3d.gd` |\n| New dock, viewport modes and ray picking | `addons/room_creator/src/editor/dungeon_editor_dock.gd`, `dungeon_viewport_picker.gd`, `addons/room_creator/plugin.gd` |
| Overhead debugging, semantic routes, locked-room labels | `dungeon_preview_overlay.gd`, `dungeon_preview_palette.gd` |
| Regression and virtual graphical editor | `tests/dungeon_*_smoke.gd`, `tests/editor_integration/plugin.gd`, `.github/workflows/godot-ci.yml` |

Use **one canonical** `examples/dungeon_authoring.tscn` scene. Presets are separate `.tres` resources; the yaw-pair laboratory is an explicitly separate *two-room experiment*, not another canonical dungeon scene. Existing authoring scenes are designer-owned and **may change between commits**; tests must never assume they still contain a particular demo `Config`, seed, or resource list. Build test fixtures independently. In particular, do **not** overwrite `examples/dungeon_authoring.tscn` to “fix” a test.

## 3. Invariants: what every change must prove

- **One physical opening per logical endpoint.** Each graph edge has two reciprocal sockets with stable IDs. Exterior entrance/exit openings must be physically traversable and cannot pierce unconnected room walls. Door offsets and full prefab socket markers are authoritative—not an assumed wall midpoint.
- **Validated playable geometry.** Collision-free OBB footprints alone are insufficient: check rotated room overlap, unrelated corridor intersections, blocked dogleg joints, exact socket/route endpoints, capsule width/height and actual CharacterBody3D crossing whenever geometry changes.
- **Determinism and budgets.** Use a local `RandomNumberGenerator` seeded from config or a documented variation seed. No `randi()`, global RNG, unbounded retries, or unspecified array/dictionary traversal when it changes seeded choices. Re-running with the same inputs must produce the same `LevelLayout.fingerprint()`.
- **No partial mutation.** Construct tentative `LevelLayout.duplicate(true)` and validate before assigning it. Keep old layout, preview, bake and user-owned nodes intact on any error; surface diagnostic codes in `RoomValidationReport`. Locking a room must not silently discard the graph. Failed reroutes cannot leave stale connectors.
- **Resource persistence.** Important authoring inputs must be `@export` resource properties and should survive Ctrl+S, reopen, undo and redo. The fingerprint must change for any persisted geometry-affecting value; lock metadata that changes no geometry can leave the baked fingerprint intact. Do not mutate shared `DungeonConfig`, `PackedScene`, art-module or prefab resources.
- **Source-only scene.** `DungeonPreview` and `DungeonBake` are generated/transient nodes; never give them an edited-scene owner. Native **Save Baked Scene** is the explicit place for compiled nodes. Be careful flattening nested prefab scene ownership; previous regressions duplicated meshes.
- **Compatibility.** Legacy layout resources and additive configs must load. Existing cardinal F2 mode remains default, F2 3D yaw/off-grid modes opt in. Preserve tracked `.gd.uid` and `.tscn.uid` files. Never rename/drop a persisted property or bump `SCHEMA_VERSION` without migration fixtures.

## 4. Grounded debugging and hypothesis discipline

Use an evidence ladder:

1. **Observation** — exact Godot output, reproduction seed/preset, file path, version, and failing CI action/step.
2. **Contract** — locate expected behavior in resource schema, geometry builder, socket helper and test.
3. **Hypotheses** — list likely causes **ranked by evidence**: e.g., stale editor snapshot, mismatched socket direction/offset, invalid physics hull, route endpoint generated from the wrong size, duplicate `PackedScene` ownership, user-modified example config.
4. **Discriminating check** — the smallest test that would falsify each top hypothesis. Prefer a fixture constructed in memory to editing the user's scene.
5. **Implementation** — change a single source of truth; do not patch unrelated systems to silence one error. Preserve provenance between generated data, derived preview, and saved source.
6. **Counterexamples** — test rotation 0°/90°/arbitrary, center/offset doors, loops/branches, structural vs procedural rooms, absent/invalid resource, very short corridor, a locked neighbor, user-owned generated-node names, and export after editing.
7. **Result** — record exact passing/failing tests, unsupported scenarios, new `main` SHA and CI run. A passed *import* is not a passed *physics* test, and a green preceding commit is not proof for the new HEAD.

If analysis is inconclusive, identify the missing evidence instead of claiming a bug is fixed. Avoid mixing experimental two-room yaw physics with the production multiroom guarantee.

## 5. How to test efficiently

Start with import/parse, then targeted suite, then full CI. Godot engine is pinned to **4.7.2** for repository CI. From the project root with a compatible binary:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/dungeon_f3_room_edit_smoke.gd
godot --headless --path . --script res://tests/dungeon_f3_override_smoke.gd
godot --headless --path . --script res://tests/dungeon_editor_ui_smoke.gd
godot --headless --path . --script res://tests/dungeon_f2_combined_smoke.gd
godot --headless --path . --script res://tests/dungeon_offgrid_socket_smoke.gd
```

Inspect `.github/workflows/godot-ci.yml` for the complete suite and graphical X11 tests; **never bypass a failing check** or remove coverage to make CI green. A new capability needs a new independent test fixture under `tests/` and the workflow step must fail on `SCRIPT ERROR`, `Parse Error` and the feature's `FAIL` marker. When physics is changed, test a `CharacterBody3D` capsule over the intended route and a saved/reloaded native `PackedScene`.

Use GitHub status **for the pushed SHA**. If source files are updated through GitHub actions, use current-HEAD CAS/expected SHA; stop and reconcile when the branch advances. Prefer one cohesive commit per verified behavior rather than many speculative patches.

## 6. Guidelines for scoped F3 development

- Current F3.1: room locks persist and protect topology; `Regenerate Unlocked Rooms` rerolls only procedural silhouette and visual module without changing room positions, door graph or structural prefab. These are limitations, not defects.
- For F3.2 overrides, consult `DungeonRoomOverrides.apply()`: treat a designer edit as a **transaction**. Freeze the selected room identity and all unrelated rooms, update only sockets and incident corridors, run whole-layout validation and only then commit through the editor UndoRedo lifecycle. Locked rooms are editable **explicitly by the designer**, but not silently by procedural regeneration. Reject impossible manual changes with a specific conflict code.
- For later NavMesh/biome features: keep these separate from the physical topology source; test they never alter the wall cutout contract or shared Resource instances.

## 7. Reporting

Use concise Spanish for user-facing progress and delivery. Describe **what is demonstrably implemented** vs planned; mention whether a mode is opt-in, its restrictions and a quick Godot Inspector test. Provide links to actual commits and the *latest* green CI. Do not mark all F3 “done” when only an iteration is implemented. Do not claim a full Windows manual playtest from Linux CI. Never claim the user's personalized `dungeon_authoring.tscn` was restored or changed unless the exact diff supports it.

## 8. F3.3 editor UX contracts

Read `docs/EDITOR_WORKSPACE.md` before editing the dock/viewport. The **dock is a controller**, not a second data model. It only selects IDs or forwards requests to `DungeonAuthoring3D`; painting modules uses `DungeonRoomModulePainter.paint()` and full physics validation before UndoRedo commit. Geometry decisions never live in the dock.

Do not reinterpret visual module `PackedScene` as a physical structural prefab; it is **collision-free and socket validated**. Never create a new room on raw left-click without connecting its graph-edge sockets first. For future placement, use a ghost preview and reject before committing; test UndoRedo, native export and capsule walking along every newly joined edge.

Selection raycasts against layout OBB, not preview physics. A tool mode must be explicitly enabled (Room Tool top 3D toolbar); Esc exits, Ctrl/Alt/Shift preserve regular camera/editor behavior. The original Inspector remains functional if the dock is not visible.
