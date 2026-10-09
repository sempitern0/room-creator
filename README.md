# Room Creator — Godot 4.7

A self-contained, editor-first plugin for creating manual 3D rooms and **deterministic connected dungeons** with static collisions, doors and portable scene export.

**Supported/tested:** Godot **4.7.2 stable**. Addon version **1.5.0**. Authors: **sempitern0**.

## Install

Copy the directory `addons/room_creator/` to the same path in your Godot project and enable **Room Creator** under Project Settings → Plugins. No Barebone or OmniKit dependency is needed. The built scenes use only stock engine nodes and can be used without the addon.

## Create a dungeon (F2)

1. Open **[examples/dungeon_authoring.tscn](examples/dungeon_authoring.tscn)** or add a `DungeonAuthoring3D` Node3D.
2. In the Inspector, assign a new `DungeonConfig` resource to **Config**. Configure `seed`, `grid_size`, `critical_path_min/max`, `branch_count`, `loop_count`, dimensions, door clearance and collision options.
3. Click **Generate Layout**. A valid `LevelLayout` is created and **Preview Layout runs automatically**, replacing any earlier preview **and clearing stale baked geometry** in one Undo/Redo transaction. On failure the previous layout, preview and bake remain unchanged. Toggle **Auto Preview on Generate** off for large layouts when you only want to prepare data.
4. Optionally click **Validate Layout**, or **Preview Layout** again after manual edits.
5. Click **Bake Static Dungeon** to create `MeshInstance3D`, primitive `StaticBody3D`/`CollisionShape3D` and paired `Socket_*` markers. Baking hides the preview automatically to avoid overlapping surfaces; Undo restores the previous preview/bake.
6. Set **Output Scene Path** to a `res://… .tscn` path and press **Save Baked Scene**. The exported scene is an independent, engine-native `PackedScene`.
7. Save your authoring scene to keep the `DungeonConfig` and `LevelLayout` as the source of truth for later regeneration.

Preview, bake, regeneration and clearing generated output are Undo/Redo-enabled in the editor. Regeneration is **non-destructive** to manually owned child nodes. If the source changes after baking, bake again before exporting.

### Path visualization (F2.2)

The authoring Inspector includes **Preview Diagnostics**. **Generate Layout** automatically creates a color-coded preview; **Preview Layout** refreshes colors and toggles after an edit. The optional `DungeonPreviewPalette` resource exposes each color:

| Meaning | Default color | What it indicates |
|---|---|---|
| **Entrance** | Green `#29B86D` | The start room's floor and its `ENTRANCE` label |
| **Exit** | Red `#E45050` | The exit room's floor and its `EXIT` label |
| **Critical path** | Cyan `#38B8DF` | Main-route floors and connections |
| **Branches** | Amber `#E9AB42` | Secondary rooms and non-loop branch links, including dead ends |
| **Alternative loops** | Violet `#A97CFF` | An additional graph connection that closes a cycle and creates another possible route |

The overlay uses actual `critical_path_ids`, room roles, and graph connectivity (spanning-forest classification), **not** randomly assigned colors. Routes are visible thin strips joining room centers and the entrance/exit appear as floating labels.

Controls: `show_room_role_colors`, `show_connection_routes`, and `show_entrance_exit_labels`. You can adjust these independently and click **Preview Layout** to refresh. All diagnostic elements belong only to `DungeonPreview`. They are cleared on bake and **never enter the exported static dungeon**; existing material assets and collision shapes are not modified. Paths indicate **logical topology**, not a guaranteed NavMesh navigation route; physical collision crossing is tested separately.

### Shape variety (F2.1)

In the `DungeonConfig` Inspector, expand **Room silhouettes** and configure four weights: `rectangle_weight`, `cross_weight`, `l_shape_weight`, and `t_shape_weight`. A weight of zero disables that shape. The default is rectangle-only, preserving existing authored scenes. A recommended starter mix is **3 / 8 / 7 / 7**. Every room's silhouette and quarter-turn rotation are selected deterministically from its required connection sides; shapes unable to accommodate all doors are rejected for that room.

- **Rectangle:** the original full room footprint.
- **Cross:** narrower side wings around a central junction.
- **L-shaped:** a walkable bent room with a recessed corner.
- **T-shaped:** a three-arm junction with a recessed side.

Each nonrectangular room occupies some of the nine thirds of the same bounding grid cell. Floors, ceilings and colliders follow the actual silhouette; missing tiles remain empty. The entry/exit openings always align with reciprocal external sockets. Door width must fit the narrower one-third connector of the cell: by default an 8-meter room supports the standard 1.6-meter door. Invalid configurations fail validation rather than creating inaccessible walls.

Manual `RoomBlueprint` authoring also exposes `shape` and `shape_rotation`, and currently supports **centered** openings on exposed silhouette boundaries. In dungeons, individual room sizes now vary inside **fixed-position grid cells**, with corridor connectors bridging gaps; custom visual-module scenes may declare normalized sockets. Arbitrary room boundaries, unconstrained prefab collisions and fully free rotations are not supported.

**Current F2 scope:** single-floor rooms inside a fixed-size cardinal grid, a seeded main path, branches and optional graph cycles. Each connection defines two mirrored door openings with stable IDs, coincident socket centers and opposite normals. No open unpaired doorways are generated. Impossible layouts return a `DungeonBuildResult` with an error report; they are not exported as success.

This is **not** yet arbitrary collision-bearing prefab replacement, free-form rotated spatial packing, multilevel routing, navigation-mesh baking, or partial room-lock regeneration. New hand-authored room prefabs can be added later without changing the graph contract.

## Exterior doors, top-down colors and modular rooms (F2.3)

### Entrance and exit are now real openings

The former `ENTRANCE` and `EXIT` labels only identified a logical graph endpoint, leaving its exterior walls solid. The planner now selects a **free outside-facing wall** on each endpoint and cuts a real walkable door-sized hole through the generated room wall, plus a dedicated `Socket_exterior_entrance` or `Socket_exterior_exit` marker. The validator rejects blocked, missing or malformed outside access; the builder and exported scene retain both openings. These are **open doorways** with collision-free passages, not an animated swinging door leaf.

Control with `DungeonConfig.generate_exterior_doors` (enabled by default). Existing serialized layouts without exterior metadata keep their previous behavior until you **Generate Layout** again. The entrance/exit color markers are visual diagnostic labels independent of the openings.

### Visibility from above

The preview palette now colors **floors AND ceilings**, including the segmented roofs of L, T and cross rooms. Graph route ribbons are lifted above the ceiling so you can inspect the generated dungeon from an overhead or isometric editor camera. `show_room_role_colors` toggles both floors and roofs; `show_connection_routes` remains independent. Exported scenes and physics materials are not tinted.

### Mixed sizes and connector corridors

Enable `DungeonConfig.vary_room_sizes` and set `min_room_scale` / `max_room_scale` (defaults **0.80–1.00**). The planner assigns reproducible individual horizontal room dimensions, always centered within their own grid cell. Where two door sockets no longer coincide, the geometry compiler automatically builds a native, static roofed **corridor** between them. The corridor has a floor, two walls, optional ceiling and matching primitive collision. Tests include seeded reproducibility, validation of bounding-box overlap and a real capsule sweep through internal **and exterior** doors.

Room heights stay shared; varied sizes do **not** yet mean completely free XZ packing. The room center positions are still on the original grid to retain F2 determinism and reliable connector generation.

### Optional socket-aware decorative prefabs

Open **[examples/dungeon_modular_authoring.tscn](examples/dungeon_modular_authoring.tscn)** and click **Generate Layout** for a complete variable-size example with a supplied custom module. You can also create a `DungeonRoomModule` Resource under `DungeonConfig.room_modules`, assign its `visual_scene` (`PackedScene`), `shape`, `weight` and `stable_id`, then use `module_chance` or `require_room_modules`.

Author module scenes in **normalized coordinates**: X/Z in -0.5…+0.5 and Y in 0…1. Place `Marker3D` children at the supported wall midpoints:

| Marker | Normalized position |
|---|---|
| `SocketFront` | `(0, 0, -0.5)` |
| `SocketBack` | `(0, 0, +0.5)` |
| `SocketLeft` | `(-0.5, 0, 0)` |
| `SocketRight` | `(+0.5, 0, 0)` |

The generator selects modules deterministically **only when their markers, shape and rotation match all required wall connections**, including outside doors. Modules must be **script-free and collision-free**: they provide visual detail inside a procedurally validated, walkable room shell. Module instances are scaled to the chosen room dimensions, and sockets align with the actual procedural door markers. The exported `.tscn` contains engine-native geometry and the selected art scene dependencies.

**Still future work:** replacing the *entire* parametric shell with arbitrary collision-bearing prefabs; arbitrary yaw/socket offsets; genuine free-form spatial placement with rotated OBB and bounded spatial backtracking; multilevel dungeons and automatic navigation meshes. The current implementation offers validated **custom visual modules and varying dimensions within the grid**, not these advanced placement modes.

## Create a manual room (F1)

1. Open **[examples/single_room_door.tscn](examples/single_room_door.tscn)** or add `RoomAuthoring3D` to a 3D scene.
2. Create a `RoomBlueprint` and configure room dimensions (width/height/depth), thicknesses and optional materials.
3. Under **Openings**, create one or more `RoomOpening` resources and choose a wall: `FRONT` (-Z), `BACK` (+Z), `LEFT` (-X), `RIGHT` (+X). Use `offset`, `width`, `height`, and `sill_height`. Walkable doors/arches must start at floor level.
4. Use **Validate Blueprint → Generate Preview → Bake Static Room → Save Baked Scene**. You can keep the blueprint and re-bake without editing the generated meshes destructively.

## API

```gdscript
var config := DungeonConfig.new()
config.seed = 12345
config.critical_path_min = 7
config.critical_path_max = 9
config.branch_count = 5
var result: DungeonBuildResult = DungeonPlanner.generate_layout(config)
if result.success:
    var layout: LevelLayout = result.layout  # No SceneTree nodes yet
    var geometry: Node3D = DungeonSceneCompiler.build(layout, true)
    add_child(geometry)
else:
    push_warning(result.report.summary())
```

`DungeonPlanner.validate_layout(layout)` checks IDs, degree, reachability, min shortest path, grid embedding, reciprocal wall orientations, paired clearances and opening geometry. `LevelLayout.fingerprint()` provides a stable geometric/topological signature for repeated builds; changing a referenced Material in place still requires a manual re-bake.

## Tests

From a working Godot 4.7.2 project, run:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/room_creator_smoke.gd
godot --headless --path . --script res://tests/dungeon_layout_smoke.gd
godot --headless --path . --script res://tests/dungeon_capsule_smoke.gd
godot --headless --path . --script res://tests/room_shapes_smoke.gd
godot --headless --path . --script res://tests/dungeon_diagnostics_smoke.gd
godot --headless --path . --script res://tests/dungeon_spatial_smoke.gd
godot --headless --path . --script res://tests/dungeon_module_smoke.gd
```

GitHub Actions additionally verifies **clean addon-only installation**, 300 baseline + 60 weighted-silhouette + 40 variable-size seed cases; exterior doorway/corridor capsule tests, custom module sockets and editor path-color classification, graph cycles, reciprocal world-space sockets, scene-pack/reload with collisions and a real PhysicsServer3D capsule-sweep across all connected doors of a representative dungeon.

The older `RoomCreator` and `DungeonGenerator` nodes remain for compatibility but the legacy dungeon path is not claimed to have the same F2 validation guarantees. Use `DungeonAuthoring3D` for new dungeons.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for remaining F2/F3 features, interactive editor QA, biome integration, mesh batching and the later city pipeline.

**License:** see [LICENSE](LICENSE). External repositories in the architectural handoff were considered as design references; no third-party source code is included in this implementation.
