# F3 engineering progress — Room Creator v1.13.0

## F3.1 — implemented

- Persistent `RoomPlacementData.edit_locked` and `lock_topology_signature` stored in the actual `LevelLayout`. Signatures capture the stable ID, grid cell, role, exterior wall and all incident graph/socket IDs and physical doorway metrics.
- Three new inspector actions on the existing `DungeonAuthoring3D`: **Lock Selected Room**, **Unlock Selected Room**, and **Regenerate Unlocked Rooms**. The target is the persisted `selected_room_id` stable identity, and the deterministic reroll is seeded by `appearance_variation_seed`.
- Local regeneration operates on a deep copy; it keeps every room world pose/extent, every graph edge, every corridor and all locked room shape/module bindings. Only unlocked **procedural** rooms may change silhouette/shape rotation or optional normalized visual module. Physical `DungeonStructuralPrefab` replacements remain unchanged until a graph-aware spatial solver can handle their modified socket contracts.
- Room/corridor geometry is independently validated before transaction commit. Failures never remove the last valid layout, preview or bake. Successful geometry rerolls clear the stale bake; lock/unlock metadata preserves an otherwise valid bake.
- Explicit lock topology conflict reports and safe unlocking of stale locks. The full **Generate Layout** action refuses to destroy any locked design.
- Editor-only golden `LOCKED` labels above room roofs. No preview or helper nodes are serialized into native bakes.
- CI: `tests/dungeon_f3_room_edit_smoke.gd` covers deterministic rerolls, graph invariants, lock conflict/recovery, authoring PackedScene save/reopen, physics bake and diagnostics; graphical `tests/editor_integration/plugin.gd` tests Inspector + Undo/Redo.

## Remaining F3 phases

1. **F3.2 precise geometry/position overrides:** stable authored `RoomOverride` data for position, size, silhouette and socket constraints; joint local re-embedding and reroute with bounded backtracking around locked locations, no topology loss.
2. **F3.3 manual viewport gizmos:** selected room and door/socket controls in the Godot editor; Undo/Redo and conflict diagnostics integrated into Inspector.
3. **F3.4 styling:** `RoomBiome` and `BakeProfile` as resources separate from structural geometry, seeded aesthetic variation and never changing shared designer resources.
4. **F3.5 navigation/validation:** optional NavigationMesh bake + independent agent-radius/height validation, room-level and global traversal across all connected doors.
5. **F3.6 performance, regression and release:** profile room-local compilation and exports (20/100/300), legacy layout migration fixtures and Windows acceptance.

### Scope boundary

F3.1 is **not** a solution for relocating or resizing locked rooms during a full new topology generation. Locked-world re-embedding, prefab-swapping with socket changes, subgraph edits and NavMesh baking are *not currently implemented*; they remain distinct milestones.

Use the same canonical `examples/dungeon_authoring.tscn` scene and do not overwrite saved user layouts or UID attachments in future iterations.
