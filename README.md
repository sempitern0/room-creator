# Room Creator — Godot 4.7

A self-contained, editor-first plugin for creating manual 3D rooms and **deterministic connected dungeons** with static collisions, doors and portable scene export.

**Supported/tested:** Godot **4.7.2 stable**. Addon version **1.10.0**. Authors: **sempitern0**.

## Install

Copy the directory `addons/room_creator/` to the same path in your Godot project and enable **Room Creator** under Project Settings → Plugins. No Barebone or OmniKit dependency is needed. The built scenes use only stock engine nodes and can be used without the addon.

## Godot editor modular preview hotfix (1.5.1)

If `examples/dungeon_authoring.tscn` previously spammed `Attempting to parent and popup a dialog that already has a parent` on **Generate Layout** or **Preview Layout**, update the addon to **1.5.1** and restart the Godot editor.

The modular path no longer instantiates its `PackedScene` over and over merely to inspect socket compatibility. `DungeonRoomModule` reads node types, validated normalized marker coordinates and script/collision restrictions directly from `PackedScene.get_state()`. Generated module nodes are detached from their source scene-instance path before recursively assigning scene owners, which prevents ambiguous nested `PackedScene` ownership on save/reload. `@export_tool_button` actions execute deferred after the Inspector finishes processing input, avoiding synchronous editor SceneTree mutations.

This was tested in **Godot 4.7.2** with an actual editor instance in both headless mode and a graphical X11 session under Xvfb, including opening the supplied modular example, generation, preview refresh, bake, regeneration, and PackedScene save/reload. The CI explicitly fails if that recurring dialog error occurs. Windows graphical testing remains a manual acceptance check.

If you still see messages in an existing edited scene after upgrading, close/reopen Godot and press **Generate Layout** to replace the old preview; save a backup before manually removing an already damaged `DungeonPreview`/`DungeonBake` tree. If it persists, capture the first error with its Godot file/line and which Inspector action triggers it.

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

Manual `RoomBlueprint` authoring also exposes `shape` and `shape_rotation`, and currently supports **centered** openings on exposed silhouette boundaries. In dungeons, room size and the world-space distances between aligned grid rows/columns can now vary independently; native static corridors connect room sockets. Custom visual modules may declare normalized sockets. Arbitrary room boundaries, collision-bearing prefabs and unconstrained free rotation are not supported.

**Current F2 scope:** single-floor rooms inside a fixed-size cardinal grid, a seeded main path, branches and optional graph cycles. Each connection defines two mirrored door openings with stable IDs, coincident socket centers and opposite normals. No open unpaired doorways are generated. Impossible layouts return a `DungeonBuildResult` with an error report; they are not exported as success.

This is **not** yet arbitrary collision-bearing prefab replacement, free-form rotated spatial packing, multilevel routing, navigation-mesh baking, or partial room-lock regeneration. New hand-authored room prefabs can be added later without changing the graph contract.

## F2.8 — Asymmetric room sockets (first spatial-packing extension)

Full, collision-bearing room prefabs can now have doors **offset from the wall center**. Each connection stores independent `from_offset` and `to_offset` metrics; entrance/exit rooms also store `exterior_offset`. These values are **serialized, fingerprinted, deterministic and independently validated**. Unlike visual-only `DungeonRoomModule` assets, these offsets describe genuine physical cutouts in the full `DungeonStructuralPrefab` shell.

**Test it without duplicating the authoring scene:**

1. Open [`examples/dungeon_authoring.tscn`](examples/dungeon_authoring.tscn).
2. In the `DungeonAuthoring3D` Inspector, replace `config` temporarily with **[`examples/dungeon_offset_socket_preset.tres`](examples/dungeon_offset_socket_preset.tres)**.
3. Click **Generate Layout**. The preset enables nonuniform spacing, independent position offsets and dogleg corridors, so the planner can place rooms with asymmetric doors alongside procedural rooms. Watch the colored roof routes bend between the *actual door positions*.
4. Click **Bake Static Dungeon**, then **Save Baked Scene** to retain full collision and the underlying prefab geometry.

The [example structural prefab](examples/dungeon_structural_offset_straight.tscn) is an 8 × 3.5 × 8 m room with `SocketFront` at **(0.8, 0, -4)** and `SocketBack` at **(-0.8, 0, 4)**. Its front/back wall meshes and `BoxShape3D` walls have matching physical openings. [Profile](examples/dungeon_structural_offset_profile.tres). You can edit this prefab or make variants. For FRONT/BACK sockets, offset is local **X**; for LEFT/RIGHT, local **Z**. Each `Marker3D` must lie on the wall face at Y=0, point outward via its **local -Z**, and retain enough lateral margin for the full door width.

**New pipeline:** after seed-based topology and room selection, `DungeonSocketOffsetPlacer` reads the prefab's **actual saved socket transforms**, applies cardinal room rotation, and adopts the resulting signed lateral offsets. It recalculates affected F2.6 routes to connect the real doorway positions. Every tentative placement is checked for missing/negative corridor clearance, room/corridor intersections and unaligned sockets. If a prefab cannot be connected safely, it is removed **without altering the existing logical dungeon**, and the certified procedural shell takes its place. This is a bounded, deterministic fallback rather than a blocked opening or partially generated dungeon.

The profile validator also checks interior walkable routes from the room center to each offset opening against authored `BoxShape3D` colliders. A broken socket position or stale physical wall cutout prevents accepting that prefab.

**Limitations:** asymmetric door offsets **do not mean arbitrary room yaw**. The rooms still have axis-aligned rectangular bounding footprints and rotate in 90° increments; corridors remain orthogonal three-leg doglegs with enough clearance to turn. Presets without dogleg routing automatically fall back to procedural rooms whenever a displaced socket cannot make a straight, coaxial connection. Truly free-angle sockets, rotated OBB packing, unconstrained 3D placement, curved tunnels, rotated collision boxes and multilevel rooms are still future work. This distinction is intentional to preserve physical passability.

## F2.7 — Full collision-bearing room prefabs and oriented sockets

Room Creator can now **replace the procedural room shell** with an authored `PackedScene` containing its own meshes, `StaticBody3D` and `BoxShape3D` collision. This is separate from the older `DungeonRoomModule` system (visual-only, no collision). Both remain supported as independent workflows.

### Try real prefab rooms without another duplicated dungeon scene

1. Open the existing **[examples/dungeon_authoring.tscn](examples/dungeon_authoring.tscn)**, select `DungeonAuthoring3D`, and load **[examples/dungeon_structural_preset.tres](examples/dungeon_structural_preset.tres)** into its `config` property.
2. Press **Generate Layout**. The preset combines two full physical room prefabs, a straight passage and a corner, with procedurally generated rooms for other doorway topologies.
3. Observe the cyan/amber/green/red diagnostic floor and roof colors even on prefab rooms. **Bake Static Dungeon** enables the authored physics; **Save Baked Scene** exports standard Godot geometry and collision without requiring the editor plugin at runtime.

The preset is a **config resource, not a second authoring scene**. Your existing example's configuration remains available in its original scene when you reopen it without saving the modified config reference.

### Author your own physical prefab

Create a script-free `Node3D` scene containing meshes and **direct child `StaticBody3D` nodes** with axis-aligned `BoxShape3D` children. The physics bodies must have identity transforms; put box positions on the `CollisionShape3D` nodes. Add direct `Marker3D` children named `SocketFront`, `SocketBack`, `SocketLeft`, and/or `SocketRight` only for **real, open, traversable doors**. These sockets are expressed in authored room **meters**, not normalized coordinates, at wall-face centers (Y=0):

| Marker | Position (for authored 8 × 3.5 × 8 m) | Facing outward |
|---|---|---|
| `SocketFront` | (0, 0, -4) | -Z |
| `SocketBack` | (0, 0, +4) | +Z |
| `SocketLeft` | (-4, 0, 0) | -X |
| `SocketRight` | (+4, 0, 0) | +X |

Marker **local -Z** must point outward. Rotating the entire prefab by **0°, 90°, 180° or 270°** allows the same asset to satisfy corresponding cardinal-facing graph sockets. Example sources: [straight scene](examples/dungeon_structural_straight.tscn) and [corner scene](examples/dungeon_structural_corner.tscn), with accompanying `DungeonStructuralPrefab` resources.

Add profiles under `DungeonConfig.structural_prefabs` and set `structural_prefab_chance` (0–1). For each rectangular room, the seeded planner considers a prefab only when **the actual room dimensions, clear door width/height and the entire set of required door walls** match the prefab in a valid quarter-turn orientation. There must be **no extra physical doorways**. Incompatible rooms automatically fall back to the validated procedural shell; this is expected.

The profile validator checks script-free engine-native scene nodes, genuine primitive colliders, rigid body offsets, outward marker directions, walking clearance from the room center to every active doorway, and physical blocking of walls without matching sockets. A prefab is **not** scaled to fit another size; if `vary_room_sizes` is enabled, only rooms that precisely match a prefab's authored dimensions qualify. Use `vary_room_sizes=false` to see more full-prefab rooms in a reproducible dungeon.

The compiler preserves the same logical `Socket_<edge_id>` markers for straight, dogleg and exterior connections regardless of which shell built the room. **Preview omits the authored collision**; bake and export preserve it. Existing F2.0–F2.6 configurations remain valid because `structural_prefabs` defaults to empty.

**F2.7 is not arbitrary 3D prefab packing.** Full prefabs are currently restricted to rectangular bounding footprints, cardinal sockets, exact sizes, quarter-turn rotations and primitive static box colliders. Collision-bearing prefabs with arbitrary yaw or shape, offset/tilted sockets, non-box geometry, multi-floor connections and generalized 3D OBB/backtracking placement remain future priorities.

## F2.6 — Orthogonal dogleg corridors and spatial routing

The canonical **[examples/dungeon_authoring.tscn](examples/dungeon_authoring.tscn)** now demonstrates routed corridors alongside mixed room silhouettes, independent positions, variable sizes, optional artwork modules and exterior entrance/exit doors.

In `DungeonConfig → Routed corridors (F2.6)`, enable **`enable_dogleg_corridors`** and set **`dogleg_frequency`** between 0 and 1. This requires `enable_independent_room_offsets` and a layout with enough room for an elbow; it defaults to **off** for backward compatibility. The example uses a 65% route-selection probability with 32 bounded placement attempts.

For a selected connection, the solver can place the two rooms with **non-coaxial doorway centers**, without rotating the room walls. It stores an orthogonal **four-point / three-leg S-shaped route** in `RoomConnectionData.route_points`:

1. Leave the first room straight through its existing door.
2. Turn 90° at an outer elbow, cross the lateral displacement, and turn again.
3. Continue straight into the reciprocal door of the next room.

The route is derived deterministically from the seed, independent room offsets and fixed-facing sockets. The builder unions the three corridor envelopes and fills corners with contiguous floor/optional roof panels, placing collision walls **only on their exposed outer borders**. The physical `CharacterBody3D` capsule test follows every route segment, including both elbows. Collision validation rejects intersecting unrelated rooms/corridors and negative or reversed door spans. An invalid or edited route cannot be baked.

The editor's **main-path / branch / alternative-loop** color overlay now follows the corridor turns rather than drawing a misleading straight shortcut. Generated geometry remains transient in the authoring scene; **Save Baked Scene** exports standard Godot meshes and primitive physics without editor-only path ribbons.

**Limitations:** these are **planar, orthogonal, S/dogleg** paths between existing cardinal-facing rooms. They do not yet support arbitrary-angle door orientations, free-rotated collision-bearing room prefabs, stairs/multilevel corridors, diagonal or curved connectors, or a general 3D OBB/backtracking packer. For narrow layouts, lower `dogleg_frequency`, increase `min_corridor_gap` or increase `placement_attempts` if the generator reports an unsatisfiable configuration.

## Recovered scene and independent room offsets (F2.5)

### Recover a Git-merge-corrupted authoring example

The canonical `examples/dungeon_authoring.tscn` is now deliberately **source-only**: a `DungeonConfig` resource and a single `DungeonAuthoring3D` node. It must not contain a serialized `DungeonPreview`, `DungeonBake`, or unresolved Git conflict markers. The editor now keeps generated preview and bake geometry as **transient unowned children**, so ordinary Ctrl+S persists the authored configuration and layout, **not thousands of derived mesh nodes**. Click **Generate Layout** or **Preview Layout** to reconstruct the visual output after reopening; **Save Baked Scene** still exports an independent standalone `.tscn` with full static collision.

CI verifies that the example has a single authored node and rejects merge-conflict markers in tracked Godot assets. If a local copy still has the conflict, first back up any personal edits, then use:

```bash
git fetch origin
git restore --source=origin/main --staged --worktree -- examples/dungeon_authoring.tscn
```

This overwrites only the **local working-tree and staged changes to that one file**; it does not discard changes to other project files. Run `git status` to inspect other pending merges before pulling.

### F2.5 bounded, compatible independent room placements

Enable `DungeonConfig → Independent room offsets (F2.5) → enable_independent_room_offsets`; tune `room_position_jitter` (up to 6 m) and `placement_attempts` (1–64). The recovered example enables **0.50 m** per-axis jitter with **32 attempts**, supporting dogleg routing.

The solver groups rooms according to their real connection constraints: east/west-linked rooms share a Z coordinate and north/south-linked rooms share an X coordinate. Other groups may shift independently relative to the F2.4 non-uniform base grid. This moves some individual rooms without ever breaking paired straight-line sockets. Candidate placements are deterministic, bounded and checked for reversed walls, negative corridor spans, unrelated room collisions and intersections between unrelated corridors. The accepted world transforms and bounds live in the serialized `LevelLayout`; impossible configurations fail explicitly.

This is a **constrained off-grid placement step**, not arbitrary per-room 3D rotation, L-turning hallways or complete OBB/backtracking assembly with collision-bearing prefab shells. Those remain upcoming work.

## Non-uniform spatial embedding (F2.4)

The unified `examples/dungeon_authoring.tscn` now demonstrates **all three features in one scene**: mixed orthogonal silhouettes, optional socket-aware decorative modules, and **non-uniform room spacing**. There is no separate `dungeon_modular_authoring.tscn`.

In `DungeonConfig → Spatial embedding (F2.4)`, enable `use_variable_grid_spacing`. Set `min_corridor_gap` and `max_corridor_gap` (meters, range 0–30). The planner uses its private seeded RNG to assign a distinct separation between each adjacent column and row. As a result, the X/Z positions of rooms are **nonuniform** and dynamically linked by corridors of differing lengths; the central coordinate of each column/row remains shared so opposed door sockets never drift sideways.

The resulting `LevelLayout.column_positions` and `row_positions` are **serialized source data**. The validator rejects missing arrays, invalid ordering, intersections or room transforms that disagree with the persisted embedding. Previously authored layouts omit these arrays and continue to use the original uniform grid. Spatial variations, room silhouettes and compatible modules remain repeatable with the same seed.

**Scope:** this is a first *non-uniform, axis-aligned spatial embedding*, **not** unrestricted room-by-room off-grid placement with arbitrary rotations, 3D OBB packing or backtracking. Unrestricted 3D spatial embedding and arbitrary rotated collision-bearing prefab placement remain roadmap work. For longer connectors, remember that more static meshes increase scene cost.

## Exterior doors, top-down colors and modular rooms (F2.3)

The **single canonical dungeon example** is `examples/dungeon_authoring.tscn`. It includes optional module presets and per-room sizing; adjust `rectangle_weight/cross_weight/l_shape_weight/t_shape_weight` and `room_modules` in the Inspector. The older `examples/dungeon_modular_authoring.tscn` has been removed because both scenes use the exact same `DungeonAuthoring3D` implementation.

### Entrance and exit are now real openings

The former `ENTRANCE` and `EXIT` labels only identified a logical graph endpoint, leaving its exterior walls solid. The planner now selects a **free outside-facing wall** on each endpoint and cuts a real walkable door-sized hole through the generated room wall, plus a dedicated `Socket_exterior_entrance` or `Socket_exterior_exit` marker. The validator rejects blocked, missing or malformed outside access; the builder and exported scene retain both openings. These are **open doorways** with collision-free passages, not an animated swinging door leaf.

Control with `DungeonConfig.generate_exterior_doors` (enabled by default). Existing serialized layouts without exterior metadata keep their previous behavior until you **Generate Layout** again. The entrance/exit color markers are visual diagnostic labels independent of the openings.

### Visibility from above

The preview palette now colors **floors AND ceilings**, including the segmented roofs of L, T and cross rooms. Graph route ribbons are lifted above the ceiling so you can inspect the generated dungeon from an overhead or isometric editor camera. `show_room_role_colors` toggles both floors and roofs; `show_connection_routes` remains independent. Exported scenes and physics materials are not tinted.

### Mixed sizes and connector corridors

Enable `DungeonConfig.vary_room_sizes` and set `min_room_scale` / `max_room_scale` (defaults **0.80–1.00**). The planner assigns reproducible individual horizontal room dimensions, always centered within their own grid cell. Where two door sockets no longer coincide, the geometry compiler automatically builds a native, static roofed **corridor** between them. The corridor has a floor, two walls, optional ceiling and matching primitive collision. Tests include seeded reproducibility, validation of bounding-box overlap and a real capsule sweep through internal **and exterior** doors.

Room heights stay shared. F2.4 uses non-uniform aligned grid rows/columns; F2.5 additionally shifts graph-compatible groups of rooms independently. Unrestricted rotated-room 3D packing remains future work.

### Optional socket-aware decorative prefabs

Open **[examples/dungeon_authoring.tscn](examples/dungeon_authoring.tscn)** and click **Generate Layout** for a complete variable-size example with a supplied custom module. You can also create a `DungeonRoomModule` Resource under `DungeonConfig.room_modules`, assign its `visual_scene` (`PackedScene`), `shape`, `weight` and `stable_id`, then use `module_chance` or `require_room_modules`.

Author module scenes in **normalized coordinates**: X/Z in -0.5…+0.5 and Y in 0…1. Place `Marker3D` children at the supported wall midpoints:

| Marker | Normalized position |
|---|---|
| `SocketFront` | `(0, 0, -0.5)` |
| `SocketBack` | `(0, 0, +0.5)` |
| `SocketLeft` | `(-0.5, 0, 0)` |
| `SocketRight` | `(+0.5, 0, 0)` |

The generator selects modules deterministically **only when their markers, shape and rotation match all required wall connections**, including outside doors. Modules must be **script-free and collision-free**: they provide visual detail inside a procedurally validated, walkable room shell. Module instances are scaled to the chosen room dimensions, and sockets align with the actual procedural door markers. The exported `.tscn` contains engine-native geometry and the selected art scene dependencies.

**Still future work:** arbitrary yaw or non-cardinal angled sockets, fully unbounded spatial placement with rotated OBB and backtracking, non-box collision-bearing prefabs, multilevel dungeons and automatic navigation meshes. F2.7 supports collision-bearing **rectangular** replacement shells with exact cardinal sockets, alongside visual-only art modules.

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
godot --headless --path . --script res://tests/dungeon_embedding_smoke.gd
godot --headless --path . --script res://tests/dungeon_offsets_smoke.gd
godot --headless --path . --script res://tests/dungeon_dogleg_smoke.gd
godot --headless --path . --script res://tests/dungeon_structural_smoke.gd
godot --headless --path . --script res://tests/dungeon_offset_socket_smoke.gd
```

GitHub Actions additionally verifies **clean addon-only installation**, 300 baseline + 60 weighted-silhouette + 40 variable-size + 70 variable-spacing + 45 constrained-room-offset + 36 routed-dogleg + 34 structural-prefab + 35 asymmetric-socket seed cases; exterior doorway/corridor capsule tests, custom module sockets and editor path-color classification, graph cycles, reciprocal world-space sockets, scene-pack/reload with collisions and a real PhysicsServer3D capsule-sweep across all connected doors of a representative dungeon.

The older `RoomCreator` and `DungeonGenerator` nodes remain for compatibility but the legacy dungeon path is not claimed to have the same F2 validation guarantees. Use `DungeonAuthoring3D` for new dungeons.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for remaining F2/F3 features, interactive editor QA, biome integration, mesh batching and the later city pipeline.

**License:** see [LICENSE](LICENSE). External repositories in the architectural handoff were considered as design references; no third-party source code is included in this implementation.
