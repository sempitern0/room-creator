# Room Creator — Editor Workspace UX Plan (F3.3+)

**Status:** F3.3 first vertical slice implemented in Room Creator v1.15.0.
**Target:** Godot 4.7.2 stable, the canonical `DungeonAuthoring3D` scene; no separate editor application, duplicate authoring scene or third-party addon dependency.

## Analysis: Asset Placer and Terrain3D patterns

- [Godot Asset Placer](https://github.com/levinzonr/godot-asset-placer) uses a dedicated asset dock, collections/palettes, explicit placement modes and immediate in-viewport preview followed by a click to confirm.
- [Terrain3D editor UI](https://terrain3d.readthedocs.io/en/stable/docs/user_interface.html) separates toolbar mode, active tool settings and asset dock. Painting modifies authored terrain data and is only active while the editor tool is engaged.
- **Room Creator is not a scene instance painter.** Each physical room belongs to a connected graph with reciprocal doors, stable IDs, SAT footprint clearance, capsule walkability and persistent per-room locks. A single click cannot safely “place a room” until an adjacent wall socket and its connecting corridor have been chosen and validated.

### Current user workflow pain points

Previous F3.2 required opening a resource array, copying stable room IDs, changing numeric Inspector fields and pressing scattered buttons, with no obvious indication of active mode. That workflow is error-prone when switching between many rooms, especially for beginners. The replacement must preserve the Inspector as the advanced source of truth while making basic room actions discoverable in the viewport.

## Delivered: F3.3 first slice

- **Right-hand Room Creator dock** (only active for `DungeonAuthoring3D`): `Build` tab for generation/validation/preview/bake/export, `Rooms` tab for browsing and editing.
- **Searchable room list** with ID and role, locked/edited filters, current room dimensions and incident link count; selected room syncs with `DungeonAuthoring3D.selected_room_id`.
- **Spatial editor toolbar:** `Room Tool` toggle. 3D mouse click selects the actual oriented room bounds, not an unreliable transient collider. Blue projected viewport outline highlights the selected room; hold Ctrl/Alt/Shift to keep ordinary editor interactions; Esc exits the tool.
- **Mode selector:** `Select room`, `Paint locks`, `Erase locks`, and **`Paint visual modules`**. Lock painting is one action per click; no mutation occurs merely from hovering/moving the pointer.
- **Art palette** sourced from the designer's `Config.room_modules` (including an erase option), applies only validated `DungeonRoomModule` visual-only `PackedScene` resources. Prevents painting over structural collision prefabs and rejects mismatch between shape, quarter turns and wall markers. Explicitly painted art persists and survives procedural rerolls.
- **Contextual F3.2 fields:** X/Z translation, width/depth, room silhouette and rotation; one **Apply safe override** button calls the same transactional planner as the Inspector. Impossible room edits preserve source layout and last valid bake.
- **Editor semantics:** every room edit calls `DungeonAuthoring3D` via its deferred Inspector operations and existing scene Undo/Redo transaction; no direct modifications to generated nodes. Preview labels, selected outlines and dock widgets are editor-only and absent from exported scenes.
- **Tests:** `tests/dungeon_editor_ui_smoke.gd` confirms rotated-OBB ray picking, browse/filter/select, lock painting and painting module art; `tests/editor_integration/plugin.gd` verifies the actual live Godot editor dock, modes and scene-history Undo/Redo using X11 and headless editor runs.

### Quick test

1. Pull `main`, open your regular **`examples/dungeon_authoring.tscn`** and select the `DungeonAuthoring3D` scene root. Ensure the **Room Creator** plugin is enabled.
2. Open the **Room Creator** right dock, choose `Rooms`. Enable **Room Tool** in the 3D viewport toolbar.
3. Click a room in the viewport; see it outlined in blue, then edit with lock/unlock, dimensions or the palette. Choose **Paint visual modules**, select a compatible resource in the palette (from `Config.room_modules`), and click several rooms. **None / erase art** removes the art.
4. Try an illegal offset: it is rejected with a diagnostic and old geometry remains unchanged. Test Ctrl+Z/Ctrl+Y; bake/export after successful edits.
5. Press **Esc** or turn off **Room Tool** to return to regular Godot selection/navigation. Use `Build` tab to validate or export.

## Roadmap — make placement genuinely painter-like without faking the graph

**F3.4 — safe socket-linked room stamping (next):** browse physical room profile/preset palette with thumbnails and socket affordances; select an existing compatible boundary socket; show translucent *valid/invalid* ghost for the prospective room/corridor; mouse movement snaps to authored socket plane; click confirms only a fully validated graph/geometry transaction, Esc cancels. Re-use `DungeonRoomOverrides` and the topology placement solver; rejected placements must never add a half-connected node.

**F3.5 — viewport editing and batching:** manipulators/drag handles for repositioning a room with grid/surface snap, consistent modifiers, multi-select, grouped UndoRedo brush strokes, and visible affected-corridor preview. Potential neighbors are never silently moved when locked.

**F3.6 — pro asset library and appearance workflow:** thumbnail palette, favorites/collections, per-room material and biome resources, style brush with stable variation seeds; avoid modifying shared `Resource` values.

**F3.7+ — navigation and scale:** optional independent NavMesh path validation plus performance targets for 20/100/300 rooms, scene save/load regression and Windows interactive UX/keyboard acceptance.

## Architecture requirements for future agent work

- UI code belongs in `addons/room_creator/src/editor/` and the existing `addons/room_creator/plugin.gd`, **never in the topology planner**.
- `dungeon_viewport_picker.gd` performs camera ray → oriented room AABB intersection using `LevelLayout`, not `PhysicsDirectSpaceState3D` of generated meshes; it must work when preview is absent and world yaw is non-cardinal.
- The dock emits intent, tracks scene changes, and dispatches `DungeonAuthoring3D` authoring actions. `DungeonRoomModulePainter.paint()` owns validation and deep-copy commit for visual modules. Geometry/layout pipelines, `DungeonPlanner.validate_layout()`, scene Undo/Redo and export remain the authority.
- A UI mode must be visible and explicitly enabled. Do not intercept 3D camera orbit, normal editor commands or all scene mouse events. Clean up controls on plugin disable and unbind when switching scenes.
- Paint modules are **collision-free**: never mistake visual-only PackedScenes for collision-authoritative structural room shells. New room placement needs topology and physics checks, not merely `PackedScene.instantiate()`.
- Build headless UI tests plus real Xvfb graphical-editor integration. Later validate visual layout manually on Windows, smaller dock widths and high-DPI monitors. Current automated tests prove API/semantics, **not visual pixel polish**.
