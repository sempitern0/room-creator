extends SceneTree
## F3.4 acceptance: socket-linked room stamping is a graph transaction,
## never a raw instance/decoration placement. Validates both physical door
## sides, real capsule traverse, locked conflict, deterministic replay and
## portable scene/source export.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.seed = 61140
	cfg.grid_size = Vector2i(12, 12)
	cfg.critical_path_min = 6
	cfg.critical_path_max = 7
	cfg.branch_count = 2
	cfg.loop_count = 0
	cfg.use_variable_grid_spacing = true
	cfg.min_corridor_gap = 10.0
	cfg.max_corridor_gap = 12.0
	var generated := DungeonPlanner.generate_layout(cfg)
	if not _check(generated.success, "Sparse F2 topology must generate."):
		return
	var before: LevelLayout = generated.layout
	var found: DungeonBuildResult
	var first_rejection: String = ""
	var rejection_counts: Dictionary = {}
	var chosen_source: RoomPlacementData
	var chosen_wall: int = -1
	for room in before.rooms:
		for side in 4:
			var proposed := DungeonSocketRoomStamp.propose(before, room.stable_id, side)
			if not proposed.success:
				var label: String = proposed.report.errors[0] if not proposed.report.errors.is_empty() else proposed.report.summary()
				rejection_counts[label] = rejection_counts.get(label, 0) + 1
				if first_rejection.is_empty() and not label.contains("STAMP_EXTERIOR") and not label.contains("STAMP_WALL_OCCUPIED"):
					first_rejection = "%s wall %d: %s" % [room.stable_id, side, proposed.report.summary()]
			if proposed.success:
				found = proposed
				chosen_source = room
				chosen_wall = side
				break
		if found != null:
			break
	if not _check(found != null and chosen_source != null, "At least one wall should offer safe topology-connected room placement. First nontrivial rejection: " + first_rejection + " | reasons: " + str(rejection_counts)):
		return
	var next: LevelLayout = found.layout
	if not _check(next.rooms.size() == before.rooms.size() + 1 and next.connections.size() == before.connections.size() + 1 and next.expected_room_count == before.expected_room_count + 1 and next.expected_loops == before.expected_loops, "Exactly one branching room and exactly one reciprocal edge must be added."):
		return
	if not _check(DungeonPlanner.validate_layout(next).is_valid(), "New branch must pass F2's complete graph, OBB, silhouette and reciprocal doorway validation."):
		return
	var placed: RoomPlacementData = next.rooms[-1]
	var edge: RoomConnectionData = next.connections[-1]
	if not _check(placed.role == RoomPlacementData.Role.BRANCH and placed.authored_override_active and edge.from_room_id == chosen_source.stable_id and edge.to_room_id == placed.stable_id and edge.from_wall == chosen_wall, "Clicked source/wall must author correct graph identities."):
		return
	for i in before.rooms.size():
		if not _check(next.rooms[i].world_transform == before.rooms[i].world_transform and next.rooms[i].stable_id == before.rooms[i].stable_id and next.rooms[i].shape == before.rooms[i].shape and next.rooms[i].edit_locked == before.rooms[i].edit_locked, "All previous room data must remain unchanged."):
			return
	for i in before.connections.size():
		if not _check(next.connections[i].stable_id == before.connections[i].stable_id and next.connections[i].route_points == before.connections[i].route_points, "Previously authored physical corridors may not be rerouted by placing a new branch."):
			return
	var replay := DungeonSocketRoomStamp.propose(before, chosen_source.stable_id, chosen_wall)
	if not _check(replay.success and replay.layout.fingerprint() == next.fingerprint(), "A placement proposal must be pure, seed-independent and exactly reproducible."):
		return
	if not _check(before.rooms.size() + 1 == next.rooms.size() and not before.rooms[-1].authored_override_active, "Source layout resource must remain untouched."):
		return
	if not _check(not DungeonSocketRoomStamp.propose(next, chosen_source.stable_id, chosen_wall).success, "Repeated wall click must not stamp overlapping/unpaired rooms."):
		return
	var locked := DungeonRoomEditing.toggle_lock(before, chosen_source.stable_id, true)
	if not _check(locked.success and not DungeonSocketRoomStamp.propose(locked.layout, chosen_source.stable_id, chosen_wall).success, "Painting a new door over a protected room must fail cleanly."):
		return
	var physical := DungeonSceneCompiler.build(next, true)
	if not _check(physical != null and physical.find_children("*", "CollisionShape3D", true, false).size() > 5, "New graph edge must compile playable native static collider geometry."):
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(physical)
	var player := CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.safe_margin = 0.001
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = next.player_radius
	capsule.height = next.player_height
	col.shape = capsule
	player.add_child(col)
	stage.add_child(player)
	await physics_frame
	await physics_frame
	var offset := Vector3.UP * (next.player_height * 0.5 + 0.08)
	var source_room: RoomPlacementData
	for room in next.rooms:
		if room.stable_id == chosen_source.stable_id:
			source_room = room
			break
	var points := PackedVector3Array([source_room.world_transform.origin])
	var a: Transform3D = DungeonFreeYawRouter.socket_pose(next, source_room, edge.from_wall, edge.from_offset)
	var b: Transform3D = DungeonFreeYawRouter.socket_pose(next, placed, edge.to_wall, edge.to_offset)
	points.append(a.origin)
	if edge.route_points.size() == 4:
		points.append_array(edge.route_points)
	points.append(b.origin)
	points.append(placed.world_transform.origin)
	player.global_position = points[0] + offset
	for k in range(1, points.size()):
		var end := points[k] + offset
		if not _check(not player.test_move(player.global_transform, end - player.global_position), "Gameplay capsule blocked by newly stamped reciprocal doorway, segment %d" % k):
			return
		player.global_position = end
	stage.remove_child(physical)
	physical.free()
	stage.free()
	var author := DungeonAuthoring3D.new()
	author.name = "StampScene"
	author.config = cfg
	author.layout = before
	author.selected_room_id = chosen_source.stable_id
	author.stamp_wall_choice = chosen_wall
	if not _check(author.stamp_selected_room() and author.layout.fingerprint() == next.fingerprint(), "Authoring facade must commit the same validated candidate."):
		return
	var preview := author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and preview.get_node_or_null(NodePath(placed.stable_id)) != null, "New branch must appear in the normal editor preview."):
		return
	var packed := PackedScene.new()
	if not _check(packed.pack(author) == OK and packed.get_state().get_node_count() == 1, "Ctrl+S should contain only the designer's canonical authoring source."):
		return
	var path := "user://stamped_source.tscn"
	if not _check(ResourceSaver.save(packed, path) == OK, "Stamped room source must save."):
		return
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reopened != null and reopened.instantiate() is DungeonAuthoring3D, "Stamped scene should reload in vanilla Godot."):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	author.free()
	print("DUNGEON_ROOM_STAMP_SMOKE: PASS (connected stable-ID placement, room/socket validation, locked-wall failure, real capsule and editor persistence)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_ROOM_STAMP_SMOKE: FAIL: " + message)
		quit(1)
	return ok
