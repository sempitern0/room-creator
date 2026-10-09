extends SceneTree
## F3.2: targeted manual override acceptance. A designer may reposition,
## resize and change a procedural room shape WITHOUT changing graph topology,
## original user resources, or protected neighbors. Invalid edits roll back.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.seed = 19850
	config.grid_size = Vector2i(12, 12)
	config.critical_path_min = 7
	config.critical_path_max = 9
	config.branch_count = 5
	config.max_attempts = 24
	config.use_variable_grid_spacing = true
	config.min_corridor_gap = 10.0
	config.max_corridor_gap = 13.0
	var base := DungeonPlanner.generate_layout(config)
	if not _check(base.success, "F3 override fixture must build: " + base.report.summary()):
		return
	var lock := DungeonRoomEditing.toggle_lock(base.layout, base.layout.rooms[0].stable_id, true)
	if not _check(lock.success, "A room lock should be a valid first step."):
		return
	var before: LevelLayout = lock.layout
	var target: RoomPlacementData = before.rooms[before.rooms.size() - 1]
	if not _check(not target.edit_locked and target.structural_prefab == null, "The edited target must be unlocked procedural geometry."):
		return
	var moved := DungeonRoomOverrides.apply(before, target.stable_id, Vector3(0.25, 0, 0.25), Vector2(7.2, 7.6), RoomFootprint.Shape.CROSS, 0)
	if not _check(moved.success, "Cardinal target room must move, resize, change silhouette and reroute valid physical sockets: " + moved.report.summary()):
		return
	var updated: LevelLayout = moved.layout
	if not _check(updated != before and DungeonPlanner.validate_layout(updated).is_valid(), "Manual override must commit only a fully valid deep-copied layout."):
		return
	var original: RoomPlacementData = before.rooms[-1]
	var edited: RoomPlacementData = updated.rooms[-1]
	if not _check(edited.authored_override_active and edited.authored_override_origin.distance_to(original.world_transform.origin) < 0.001 and edited.shape == RoomFootprint.Shape.CROSS and edited.room_size == Vector3(7.2, original.room_size.y if original.room_size.y > 0 else before.room_size.y, 7.6), "Authored shape, extent and stable anchor must be persisted."):
		return
	if not _check(not original.authored_override_active and original.room_size == Vector3.ZERO and updated.rooms[0].edit_locked and updated.rooms[0].world_transform == before.rooms[0].world_transform, "Manual override must not mutate input or protected rooms."):
		return
	var rerouted: int = 0
	for i in updated.connections.size():
		var old_edge: RoomConnectionData = before.connections[i]
		var new_edge: RoomConnectionData = updated.connections[i]
		if old_edge.from_room_id == target.stable_id or old_edge.to_room_id == target.stable_id:
			if new_edge.route_points != old_edge.route_points:
				rerouted += 1
		elif not _check(new_edge.route_points == old_edge.route_points, "Nonincident corridor data must remain bit-exact."):
			return
	if not _check(rerouted > 0, "At least one incident physical corridor must be locally rerouted."):
		return
	var replay := DungeonRoomOverrides.apply(before, target.stable_id, Vector3(0.25, 0, 0.25), Vector2(7.2, 7.6), RoomFootprint.Shape.CROSS, 0)
	if not _check(replay.success and replay.layout.fingerprint() == updated.fingerprint(), "Identical manual override must be deterministic."):
		return
	var invalid := DungeonRoomOverrides.apply(updated, target.stable_id, Vector3(3.0, 0.0, 0.0))
	if not _check(not invalid.success and updated.fingerprint() == replay.layout.fingerprint(), "A second edit exceeding the cumulative anchor displacement must roll back."):
		return
	var unknown := DungeonRoomOverrides.apply(updated, "no_such_room", Vector3(0.2, 0, 0))
	if not _check(not unknown.success, "An unknown room ID must fail without modifying user resources."):
		return
	var protected_edit := DungeonRoomOverrides.apply(updated, updated.rooms[0].stable_id, Vector3.ZERO, Vector2(7.4, 7.4), RoomFootprint.Shape.CROSS, 0)
	if not _check(protected_edit.success and protected_edit.layout.rooms[0].edit_locked, "An explicit designer edit may modify a protected room while retaining its lock."):
		return
	var reroll := DungeonRoomEditing.regenerate_unlocked(updated, config, 8440)
	if not _check(reroll.success and reroll.layout.rooms[-1].room_size == edited.room_size and reroll.layout.rooms[-1].shape == edited.shape, "Future procedural rerolls must preserve explicit F3 authored overrides."):
		return
	var author := DungeonAuthoring3D.new()
	author.name = "F3OverrideAuthoring"
	author.config = config
	author.layout = before
	author.selected_room_id = target.stable_id
	author.manual_translation = Vector3(0.25, 0, 0.25)
	author.manual_room_size = Vector2(7.2, 7.6)
	author.manual_shape_choice = 2 # Cross.
	author.manual_shape_rotation = 0
	if not _check(author.apply_selected_room_override(), "Authoring facade must accept a selected-room override."):
		return
	var preview := author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and preview.find_children("Edited_*", "Label3D", true, false).size() == 1, "Overhead preview must distinguish hand-edited rooms."):
		return
	var physical := DungeonSceneCompiler.build(author.layout, true)
	if not _check(physical != null and physical.find_children("*", "CollisionShape3D", true, false).size() > 10, "Manual geometry overrides must compile real native collision."):
		return
	# Walk each locally rebuilt edge with the actual gameplay collision
	# capsule. OBB-only checks would miss a wall blocking the first doorway.
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(physical)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var capsule_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = author.layout.player_radius
	capsule.height = author.layout.player_height
	capsule_node.shape = capsule
	actor.add_child(capsule_node)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var room_ids: Dictionary = {}
	for current_room in author.layout.rooms:
		room_ids[current_room.stable_id] = current_room
	var height: float = author.layout.player_height * 0.5 + 0.08
	for edge in author.layout.connections:
		if edge.from_room_id != target.stable_id and edge.to_room_id != target.stable_id:
			continue
		var first: RoomPlacementData = room_ids[edge.from_room_id]
		var last: RoomPlacementData = room_ids[edge.to_room_id]
		var points := PackedVector3Array([first.world_transform.origin])
		if edge.route_points.size() == 4:
			points.append_array(edge.route_points)
		else:
			# Straight connectors use the exact source/target door socket.
			var one := DungeonFreeYawRouter.socket_pose(author.layout, first, edge.from_wall, edge.from_offset)
			var two := DungeonFreeYawRouter.socket_pose(author.layout, last, edge.to_wall, edge.to_offset)
			points.append(one.origin)
			points.append(two.origin)
		points.append(last.world_transform.origin)
		actor.global_position = points[0] + Vector3.UP * height
		for k in range(1, points.size()):
			var target_pos: Vector3 = points[k] + Vector3.UP * height
			if not _check(not actor.test_move(actor.global_transform, target_pos - actor.global_position), "Real player capsule cannot traverse rerouted F3 doorway %s leg %d." % [edge.stable_id, k]):
				return
			actor.global_position = target_pos
	stage.free()
	author.bake()
	if not _check(author.get_node_or_null("DungeonBake") != null, "F3 edited rooms must bake normally."):
		return
	var saved_fp := author.layout.fingerprint()
	var baked_node := author.get_node_or_null("DungeonBake")
	author.manual_translation = Vector3(3.0, 0, 0)
	if not _check(not author.apply_selected_room_override() and author.layout.fingerprint() == saved_fp and author.get_node_or_null("DungeonBake") == baked_node, "Rejected second edit must preserve authored layout and previous static bake."):
		return
	var packed := PackedScene.new()
	if not _check(packed.pack(author) == OK and packed.get_state().get_node_count() == 1, "Authored scene must preserve only the source node."):
		return
	var path := "user://f3_override_save.tscn"
	if not _check(ResourceSaver.save(packed, path) == OK, "F3 overridden layout must save."):
		return
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reopened != null, "F3 scene must reopen."):
		return
	var restored := reopened.instantiate() as DungeonAuthoring3D
	if not _check(restored.layout.rooms[-1].authored_override_active and restored.layout.rooms[-1].room_size == edited.room_size and restored.layout.fingerprint() == updated.fingerprint(), "Reopening must preserve geometry, authored anchor, lock and all rerouted sockets."):
		return
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	author.free()
	# Real yaw graph branch: move one room slightly and recompute ONLY its
	# incident angled sockets, still passing full SAT & corridor validator.
	var yaw := DungeonConfig.new()
	yaw.seed = 36000
	yaw.grid_size = Vector2i(8, 8)
	yaw.critical_path_min = 5
	yaw.critical_path_max = 7
	yaw.branch_count = 2
	yaw.max_attempts = 16
	yaw.use_variable_grid_spacing = true
	yaw.min_corridor_gap = 10.0
	yaw.max_corridor_gap = 13.0
	yaw.enable_free_yaw_dungeons = true
	yaw.free_yaw_max_degrees = 22.0
	yaw.free_yaw_candidates = 18
	yaw.free_yaw_search_budget = 12000
	var yaw_base := DungeonPlanner.generate_layout(yaw)
	if not _check(yaw_base.success, "Free-yaw F3 fixture must generate."):
		return
	var successful_yaw: DungeonBuildResult
	for i in range(yaw_base.layout.rooms.size() - 1, -1, -1):
		for dir in [Vector3(0.125, 0, 0), Vector3(-0.125, 0, 0), Vector3(0, 0, 0.125), Vector3(0, 0, -0.125)]:
			var candidate := DungeonRoomOverrides.apply(yaw_base.layout, yaw_base.layout.rooms[i].stable_id, dir)
			if candidate.success:
				successful_yaw = candidate
				break
		if successful_yaw != null:
			break
	if not _check(successful_yaw != null and successful_yaw.layout.free_yaw_enabled and DungeonPlanner.validate_layout(successful_yaw.layout).is_valid(), "A modest, manually rerouted yaw-room edit must be supported."):
		return
	print("DUNGEON_F3_OVERRIDE_SMOKE: PASS (cardinal and yaw pose edits, size+silhouette, locks, local socket reroutes, rollback, physics and source reload)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_F3_OVERRIDE_SMOKE: FAIL: " + message)
		quit(1)
	return ok
