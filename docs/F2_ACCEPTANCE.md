# F2 single-floor completion acceptance — Room Creator v1.12.0

F2 is considered **functionally complete for the documented, finite, single-floor dungeon generation scope**. The feature and regression evidence below does **not** imply that the addon can generate unrestricted 3D/multilevel architecture or that Windows interactive acceptance is finished.

## Build and export acceptance

| Requirement | Automated evidence | Status |
|---|---|---|
| Portable addon import, script parse, clean install without unrelated plugins | `.github/workflows/godot-ci.yml` | Passed |
| Seeded stable topology: path, branches, optional loop, entrance/exit and reciprocal local doors | `tests/dungeon_layout_smoke.gd`, `tests/dungeon_capsule_smoke.gd` | Passed |
| Physical exterior doors and walkability | `tests/dungeon_capsule_smoke.gd`, `tests/dungeon_offgrid_socket_smoke.gd` | Passed |
| Rect/L/T/cross footprints and variable room extents | `tests/room_shapes_smoke.gd`, `tests/dungeon_spatial_smoke.gd` | Passed |
| Reproducible nonuniform room positions, true off-grid socket placement and DFS bounds | `tests/dungeon_embedding_smoke.gd`, `tests/dungeon_offsets_smoke.gd`, `tests/dungeon_offgrid_socket_smoke.gd` | Passed |
| Physical S-shaped / arbitrary-yaw angled routes, collision-free corners and stable sockets | `tests/dungeon_dogleg_smoke.gd`, `tests/dungeon_free_yaw_smoke.gd`, `tests/dungeon_f2_combined_smoke.gd` | Passed |
| SAT-oriented room and connector overlap safety with serialized fingerprints | `tests/dungeon_yaw_docking_smoke.gd`, `tests/dungeon_free_yaw_smoke.gd` | Passed |
| Actual authored prefab `StaticBody3D` physics, yaw-rotated rigid primitive boxes, opening matching and safe fallback | `tests/dungeon_structural_smoke.gd`, `tests/dungeon_offset_socket_smoke.gd`, `tests/dungeon_f2_combined_smoke.gd` | Passed |
| Headless capsule sweep and scene-native save/reload | `tests/dungeon_free_yaw_smoke.gd`, `tests/dungeon_offgrid_socket_smoke.gd`, `tests/dungeon_yaw_docking_smoke.gd` | Passed |
| Real graphical-editor Inspector generation, preview, bake, stale-output preservation and small source-only authored scene | `tests/editor_integration/plugin.gd` via virtual X11 and headless editor | Passed |
| User-run Godot Windows interactive project/playtest | Manual | **Pending** |

## How to reproduce

From the repo root with Godot 4.7.2 stable:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/dungeon_free_yaw_smoke.gd
godot --headless --path . --script res://tests/dungeon_f2_combined_smoke.gd
godot --headless --path . --script res://tests/dungeon_offgrid_socket_smoke.gd
```

Or run all GitHub Actions checks from `main`.

In Godot open **`examples/dungeon_authoring.tscn`**. Select the author root; assign either `examples/dungeon_free_yaw_preset.tres` for rotated but grid-guided spatial layout or **`examples/dungeon_offgrid_socket_preset.tres`** for a room graph packed from sockets. Use **Generate Layout**, orbit above to see colored path/branch/loop ribbons over the roofs, **Bake Static Dungeon**, then **Save Baked Scene**. Reopen the exported `.tscn` and inspect its `StaticBody3D` / `CollisionShape3D` / `Socket_*` nodes.

## Windows acceptance checklist

- [ ] Open the project in Godot 4.7.2 stable on Windows with a clean `git status`, generate both F2 yaw presets and switch seeds.
- [ ] Confirm the entrance/exit wall holes and colored overhead path ribbons are visually aligned; walk the dungeon with a real third-person capsule/controller.
- [ ] Undo/Redo layout generation and bake. Close/reopen the editor, regenerate and verify the authoring `.tscn` has no serialised preview or bake child graph.
- [ ] Trigger a deliberately unsatisfiable config (e.g. off-grid enabled but yaw disabled) and confirm the previously valid preview/bake survives.
- [ ] Open the baked scene without the addon. Check physical collisions, all connected doorways, rotated structures, roof continuity and absence of visible seams.

## Explicit exclusions

**No promises of** guaranteed closure for every spatially unconstrained graph loop, native NavMesh bake/path planning, non-rectangular arbitrary-angle door cuts in mesh-authored shells, general collision mesh/convex polyhedron certification, room-lock partial regeneration, multilevel traversal, or true unrestricted 3D (XYZ/pitch/roll) OBB backtracking. These belong in F3+ or a separate expanded spatial-packing project; they are **not** included in the F2 single-floor acceptance boundary.
