extends SceneTree
## F3.1: persist room locks in authoring PackedScene, reject stale locks,
## reroll only unlocked room visuals on a fixed graph, and keep native export.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.seed = 5120
	cfg.grid_size = Vector2i(13, 13)
	cfg.critical_path_min = 8
	cfg.critical_path_max = 10
	cfg.branch_count = 5
	cfg.loop_count = 1
	cfg.max_attempts = 32
	cfg.rectangle_weight = 10
	cfg.cross_weight = 8
	cfg.l_shape_weight = 6
	cfg.t_shape_weight = 7
	var initial := DungeonPlanner.generate_layout(cfg)
	if not _check(initial.success, "F3 editing fixture needs a valid seeded layout: " + initial.report.summary()):
		return
	var author := DungeonAuthoring3D.new()
	author.name = "PersistentRoomEditor"
	author.config = cfg
	author.layout = initial.layout
	author.selected_room_id = initial.layout.rooms[0].stable_id
	if not _check(author.lock_selected_room(), "A valid room must be lockable by its stable ID."):
		return
	var locked := author.layout
	if not _check(locked.rooms[0].edit_locked and not locked.rooms[0].lock_topology_signature.is_empty() and DungeonPlanner.validate_layout(locked).is_valid(), "Room lock must capture the immutable graph/socket contract."):
		return
	if not _check(locked.fingerprint() == initial.layout.fingerprint(), "Locking metadata must not invalidate an otherwise unchanged physical bake."):
		return
	if not _check(not initial.layout.rooms[0].edit_locked, "A lock must not mutate the previous Resource snapshot."):
		return
	var locked_signature := locked.rooms[0].lock_topology_signature
	var locked_original := locked.rooms[0].duplicate(true) as RoomPlacementData
	var originals: Dictionary = {}
	var original_edges: Dictionary = {}
	for room in locked.rooms:
		originals[room.stable_id] = [room.cell, room.world_transform, room.exterior_wall, room.structural_prefab, room.edit_locked]
	for edge in locked.connections:
		original_edges[edge.stable_id] = [edge.from_room_id, edge.to_room_id, edge.from_wall, edge.to_wall, edge.route_points.duplicate(), edge.clear_width]
	var locked_snapshot := author.layout
	author.generate_new_layout()
	if not _check(author.layout == locked_snapshot, "A full topology regeneration must not silently erase locked rooms."):
		return
	author.appearance_variation_seed = 7733
	if not _check(author.regenerate_unlocked_rooms(), "Local geometry reroll must succeed with fixed graph and protected room."):
		return
	var rerolled := author.layout
	if not _check(rerolled != locked and rerolled.fingerprint() != locked.fingerprint() and DungeonPlanner.validate_layout(rerolled).is_valid(), "A local reroll must produce a validated, genuinely different appearance."):
		return
	if not _check(rerolled.rooms[0].edit_locked and rerolled.rooms[0].lock_topology_signature == locked_signature and rerolled.rooms[0].shape == locked_original.shape and rerolled.rooms[0].shape_rotation == locked_original.shape_rotation and rerolled.rooms[0].world_transform == locked_original.world_transform, "Locked room geometry, position and physical openings must be unchanged."):
		return
	var changed: int = 0
	for room in rerolled.rooms:
		var original: RoomPlacementData
		for former in locked.rooms:
			if former.stable_id == room.stable_id:
				original = former
				break
		if not _check(original != null and room.cell == original.cell and room.world_transform == original.world_transform and room.exterior_wall == original.exterior_wall and room.structural_prefab == original.structural_prefab, "Room local reroll cannot move physical positions or alter structural prefabs."):
			return
		if not _check(originals[room.stable_id][4] == room.edit_locked, "Room lock state must survive the reroll."):
			return
		if room.shape != original.shape or room.shape_rotation != original.shape_rotation:
			changed += 1
	for edge in rerolled.connections:
		var saved: Array = original_edges[edge.stable_id]
		if not _check(edge.from_room_id == saved[0] and edge.to_room_id == saved[1] and edge.from_wall == saved[2] and edge.to_wall == saved[3] and edge.route_points == saved[4] and absf(edge.clear_width - saved[5]) < 0.0001, "Local reroll must retain every graph connection and corridor."):
			return
	if not _check(changed >= 3, "At least three unlocked procedural rooms should change shape/rotation."):
		return
	var preview := author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and preview.find_children("Locked_*", "Label3D", true, false).size() == 1, "Overhead editor preview must show exactly the rooms locked by designer."):
		return
	var redo := DungeonRoomEditing.regenerate_unlocked(locked, cfg, 7733)
	if not _check(redo.success and redo.layout.fingerprint() == rerolled.fingerprint(), "F3 local edits must be reproducible with the same variation seed."):
		return
	author.bake()
	var baked := author.get_node_or_null("DungeonBake")
	if not _check(baked != null and baked.find_children("*", "CollisionShape3D", true, false).size() > 10, "Locally rerolled geometry must be physically baked."):
		return
	# Serialized source-only authoring roundtrip with persistent room lock.
	var packed := PackedScene.new()
	if not _check(packed.pack(author) == OK and packed.get_state().get_node_count() == 1, "F3 source scene must not embed preview or baked children."):
		return
	var filename := "user://f3_room_edit_source.tscn"
	if not _check(ResourceSaver.save(packed, filename) == OK, "F3 authored source must save."):
		return
	var loaded := ResourceLoader.load(filename, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(loaded != null, "Source scene must reopen."):
		return
	var restored := loaded.instantiate() as DungeonAuthoring3D
	if not _check(restored != null and restored.layout != null and restored.layout.rooms[0].edit_locked and restored.layout.rooms[0].lock_topology_signature == locked_signature and restored.layout.fingerprint() == rerolled.fingerprint(), "Ctrl+S and reopen must persist exact F3 authoring locks and local room changes."):
		return
	if not _check(restored.get_node_or_null("DungeonPreview") == null and restored.get_node_or_null("DungeonBake") == null, "Reopened authoring scene must remain source-only."):
		return
	restored.preview_layout()
	if not _check(restored.get_node_or_null("DungeonPreview").find_children("Locked_*", "Label3D", true, false).size() == 1, "Reopened source must regenerate locked-room overhead labels."):
		return
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	# A broken signature must have a clear conflict but its unlock action must
	# remain usable: otherwise the designer cannot recover a stale lock.
	var corrupted := rerolled.duplicate(true) as LevelLayout
	corrupted.rooms[0].lock_topology_signature = "stale"
	var invalid := DungeonPlanner.validate_layout(corrupted)
	if not _check(not invalid.is_valid() and invalid.summary().contains("ROOM_LOCK"), "A stale lock must be an explicit validation conflict, never silently discarded."):
		return
	var recovered := DungeonRoomEditing.toggle_lock(corrupted, corrupted.rooms[0].stable_id, false)
	if not _check(recovered.success and not recovered.layout.rooms[0].edit_locked and DungeonPlanner.validate_layout(recovered.layout).is_valid(), "Unlock must recover from an invalid/stale stored lock signature."):
		return
	var unknown := DungeonRoomEditing.toggle_lock(rerolled, "no_such_room", true)
	if not _check(not unknown.success and rerolled.rooms[0].edit_locked, "Unknown room IDs must never mutate a user-owned layout."):
		return
	if not _check(author.unlock_selected_room() and not author.layout.rooms[0].edit_locked, "Unlock should explicitly remove the protection."):
		return
	print("DUNGEON_F3_ROOM_EDIT_SMOKE: PASS (persisted locks, stable graph, deterministic unlocked reroll, conflicts, native physics and authoring source reload)")
	author.free()
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("DUNGEON_F3_ROOM_EDIT_SMOKE: FAIL: " + message)
		quit(1)
	return condition
