# Room Creator for Godot 4.7

3D room authoring and static export addon, with the original `RoomCreator` and experimental `DungeonGenerator` still available for existing projects.

**Target:** Godot **4.7.2 stable**. The new parametric authoring pipeline is an F0–F1 implementation; it is **not yet a verified procedural dungeon generator**.

## Install

Copy **`addons/ninetailsrabbit.room_creator/`** into the same path under your Godot project's `addons/` directory, then enable **Room Creator** in Project Settings → Plugins. No Barebone, OmniKit, external assets, or player controller is required.

## New workflow: RoomAuthoring3D

1. Create a new 3D scene and add **RoomAuthoring3D** (Create Node or the custom addon type).
2. In **Blueprint**, create a new `RoomBlueprint` resource. Set `room_size` (width, standing height, depth) and thicknesses.
3. In **Openings**, add one or more `RoomOpening` resources. Choose `FRONT` (-Z), `BACK` (+Z), `LEFT` (-X), or `RIGHT` (+X). `offset` is horizontal displacement from that wall's center; all dimensions are in meters. Doors and arches start at floor level; windows may have a sill.
4. Set optional wall, floor, and ceiling materials; configure physics collision layer/mask and agent radius/height.
5. Click **Validate Blueprint**. Invalid openings, insufficient player clearance, invalid dimensions, duplicate IDs, and overlapping holes are reported before scene generation.
6. Click **Generate Preview** to show editable source geometry without physics colliders. This only replaces its own tagged `RoomCreatorPreview` child.
7. Click **Bake Static Room** for standard `MeshInstance3D` + `StaticBody3D` + `BoxShape3D` pieces and `Socket_*` markers. No runtime CSG or script dependency is added to the baked root.
8. Set **Output Scene Path** to a `res://... .tscn` destination and click **Save Baked Scene**. The exported PackedScene uses only standard engine nodes/resources.

**Editing:** Modify the blueprint and bake again; the authored blueprint remains separate from the baked geometry. The generated nodes are tagged so **Clear Preview** and **Clear Bake** never delete arbitrary children. **Generate Preview, Bake, Clear Preview and Clear Bake integrate with the editor's Undo/Redo history.** Advanced viewport gizmos, per-room locks, and incremental regeneration are not yet implemented.

## Godot 4.7 validation

With Godot 4.7.2 installed, from the repository root:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/room_creator_smoke.gd
```

The smoke script exercises multiple door holes, a window, collider counts, sockets, invalid blueprints, non-destructive cleanup, Resource isolation, and PackedScene reload. CI is pinned to Godot 4.7.2.

## Compatibility and limitations

- `RoomCreator` and `DungeonGenerator` are legacy tools. The most critical ownership/shared-resource defects are being addressed, but their procedural dungeon connectivity is **not guaranteed**. Prefer `RoomAuthoring3D` for new rooms.
- F1 supports **rectangular rooms, single floor, axis-aligned walls** and multiple nonoverlapping orthogonal openings. No arbitrary polygon, rotated room assembly, slopes, or navigation bake yet.
- Generated meshes consist of static boxes with per-piece primitive collision: not merged `ArrayMesh`/UV2/LOD, and not a walkable navigation guarantee. Sockets expose local coordinates and clear dimensions for future alignment.
- Baked scene output does not depend on the plugin at runtime. Keep the `RoomBlueprint` authoring scene/resource in source control for regeneration.

## Roadmap

See [development plan](docs/ROADMAP.md) for the F0–F5 milestones, acceptance gates, and the distinction between implementation and verification.

**License:** repository `LICENSE`. This rewrite draws architectural ideas from the supplied design handoff; it does not incorporate third-party source code.
