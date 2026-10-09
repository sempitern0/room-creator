# F3 engineering progress — Room Creator v1.14.0

## F3.1 — implemented

- Persistent `RoomPlacementData.edit_locked` and `lock_topology_signature` stored in the actual `LevelLayout`. Signatures capture the stable ID, grid cell, role, exterior wall and all incident graph/socket IDs and physical doorway metrics.
- Three new inspector actions on the existing `DungeonAuthoring3D`: **Lock Selected Room**, **Unlock Selected Room**, and **Regenerate Unlocked Rooms**. The target is the persisted `selected_room_id` stable identity, and the deterministic reroll is seeded by `appearance_variation_seed`.
- Local regeneration operates on a deep copy; it keeps every room world pose/extent, every graph edge, every corridor and all locked room shape/module bindings. Only unlocked **procedural** rooms may change silhouette/shape rotation or optional normalized visual module. Physical `DungeonStructuralPrefab` replacements remain unchanged until a graph-aware spatial solver can handle their modified socket contracts.
- Room/corridor geometry is independently validated before transaction commit. Failures never remove the last valid layout, preview or bake. Successful geometry rerolls clear the stale bake; lock/unlock metadata preserves an otherwise valid bake.
- Explicit lock topology conflict reports and safe unlocking of stale locks. The full **Generate Layout** action refuses to destroy any locked design.
- Editor-only golden `LOCKED` labels above room roofs. No preview or helper nodes are serialized into native bakes.
- CI: `tests/dungeon_f3_room_edit_smoke.gd` covers deterministic rerolls, graph invariants, lock conflict/recovery, authoring PackedScene save/reopen, physics bake and diagnostics; graphical `tests/editor_integration/plugin.gd` tests Inspector + Undo/Redo.

## F3.2 — implemented (bounded local overrides)

- Inspector: `manual_translation`, `manual_room_size`, `manual_shape_choice`, `manual_shape_rotation`, and **Apply Selected Room Override** on the same `DungeonAuthoring3D`. The user still chooses by persistent stable room ID.
- `DungeonRoomOverrides.apply()` operates transactionally on `LevelLayout.duplicate(true)`, without mutating shared Resources or the user's canonical scene. F2 full physical validation runs before applying the editor Undo/Redo action; failures keep old source, preview and bake intact.
- Size X/Z constrained to 50–100% of the base room footprint, manual movement limited to 3 meters/axis from the captured `authored_override_origin`; Y remains fixed. Every successful edit records `authored_override_active` and protects it from automatic F3.1 rerolls.
- Only edges incident to the edited room are rerouted, using the original F2 cardinal dogleg or free-yaw socket path solvers. Nonincident edges and unrelated room transforms remain unchanged. The entire result is checked against SAT OBB collision, wall sockets and shapes.
- Full structural prefab shells can be translated without altering their fixed authored opening profiles, but size/silhouette changes to an existing physical prefab (or incompatible visual module) return specific errors.
- Geometry-changing edits invalidate stale baked geometry. Cyan `EDITED` and gold `LOCKED` labels are preview-only; saved `LevelLayout` and exported native static scene remain independent.
- `tests/dungeon_f3_override_smoke.gd` covers cardinal and yaw overrides, locks, reproduction, cumulative position limits, untouched nonincident paths, physics compilation, source save/reload and conflict rollback; `tests/editor_integration/plugin.gd` drives the deferred Inspector button and the scene's real Undo/Redo history.

### F3.2 supported-scope limitations

This is a **bounded local** override, **not** globally optimized re-embedding: it never silently moves adjacent rooms, alters the original graph topology or swaps collision prefab sockets. Edits that cannot fit existing neighboring positions fail with actionable validation errors. Preview/bake meshes are still fully recompiled from the validated layout rather than incrementally updated by triangle/mesh region. Arbitrary viewport gizmos remain later.

## Remaining F3 phases

1. **F3.3 advanced spatial authoring:** neighbor repositioning with bounded backtracking around locked/manual anchors, user-controlled material overrides and explicit prefab replacement compatibility. F3.2 basic bounded room position/size/silhouette overrides are already delivered.
2. **F3.4 manual viewport gizmos:** selected room and door/socket controls in the Godot editor; Undo/Redo and conflict diagnostics integrated into Inspector.
3. **F3.5 styling:** `RoomBiome` and `BakeProfile` as resources separate from structural geometry, seeded aesthetic variation and never changing shared designer resources.
4. **F3.6 navigation/validation:** optional NavigationMesh bake + independent agent-radius/height validation, room-level and global traversal across all connected doors.
5. **F3.7 performance, regression and release:** profile room-local compilation and exports (20/100/300), legacy layout migration fixtures and Windows acceptance.

### Scope boundary

F3.2 supports explicit bounded moves and size edits of selected rooms, including protected rooms, but not full new topology generation over locked geometry. Adjacent-room position re-embedding, prefab swaps with socket changes, subgraph edits and NavMesh baking are *not currently implemented*; they remain distinct milestones.

Use the same canonical `examples/dungeon_authoring.tscn` scene and do not overwrite saved user layouts or UID attachments in future iterations.
