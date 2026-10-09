extends SceneTree
## Full F2 free-yaw multiroom regression: seeded backtracking, SAT non-overlap,
## authored socket alignment, 3-leg real capsule navigation and packed export.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.seed = 36000
	cfg.grid_size = Vector2i(8, 8)
	cfg.critical_path_min = 5
	cfg.critical_path_max = 7
	cfg.branch_count = 2
	cfg.loop_count = 0
	cfg.max_attempts = 16
	cfg.rectangle_weight = 10
	cfg.cross_weight = 0
	cfg.l_shape_weight = 0
	cfg.t_shape_weight = 0
	cfg.use_variable_grid_spacing = true
	cfg.min_corridor_gap = 10.0
	cfg.max_corridor_gap = 13.0
	cfg.enable_free_yaw_dungeons = true
	cfg.free_yaw_max_degrees = 22.0
	cfg.free_yaw_shift = 0.5
	cfg.free_yaw_candidates = 18
	cfg.free_yaw_search_budget = 12000
	var successes: int = 0
	var rotated: int = 0
	var total_edges: int = 0
	var fixture: LevelLayout
	for i in 20:
		cfg.seed = 36000 + i
		var built := DungeonPlanner.generate_layout(cfg)
		if not built.success:
			print("DUNGEON_FREE_YAW_SMOKE: skipped unsatisfiable seeded placement %d" % cfg.seed)
			continue
		var second := DungeonPlanner.generate_layout(cfg)
		if not _check(second.success and second.layout.fingerprint() == built.layout.fingerprint(), "Seeded yaw DFS must replay every position and basis."):
			return
		var layout := built.layout
		if not _check(layout.free_yaw_enabled and DungeonPlanner.validate_layout(layout).is_valid(), "Standalone generated yaw layout must validate."):
			return
		for room in layout.rooms:
			if absf(rad_to_deg(room.world_transform.basis.get_euler().y)) > 4.0:
				rotated += 1
			for other in layout.rooms:
				if other == room:
					continue
				if not _check(not DungeonOrientedBounds.overlaps(DungeonOrientedBounds.room(room, DungeonPlanner.actual_size(layout, room)), DungeonOrientedBounds.room(other, DungeonPlanner.actual_size(layout, other))), "Free-yaw rooms must not overlap."):
					return
		for edge in layout.connections:
			if not _check(edge.route_points.size() == 4, "Every non-cardinal connection needs four physical route points."):
				return
			total_edges += 1
		if fixture == null and rotated >= 3:
			fixture = layout
		successes += 1
	if not _check(successes >= 10 and rotated >= 15 and total_edges >= 40 and fixture != null, "Seed sweep should deliver many reproducible genuinely rotated multiroom dungeons."):
		return
	print("DUNGEON_FREE_YAW_SMOKE: %d passing seeds, %d rotated rooms, %d accepted edges" % [successes, rotated, total_edges])
	var geometry := DungeonSceneCompiler.build(fixture, true)
	if not _check(geometry != null, "Multiple yaw rooms and merged roofs/walls must compile in one native scene."):
		return
	var lookup: Dictionary = {}
	for room in fixture.rooms:
		lookup[room.stable_id] = room
	for edge in fixture.connections:
		var corridor := geometry.get_node_or_null(NodePath("Connector_" + edge.stable_id)) as Node3D
		if not _check(corridor != null and corridor.get_node_or_null("Floor") != null and corridor.get_node_or_null("Ceiling") != null and corridor.find_children("WallMesh", "MeshInstance3D", true, false).size() >= 2, "Each connector must have a polygon-union floor/roof and boundary collision walls."):
			return
		if not _check(corridor.get_meta("route_points", PackedVector3Array()).size() == 4, "Compiled angled connector keeps its route fingerprint."):
			return
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		var a_socket: Transform3D = DungeonFreeYawRouter.socket_pose(fixture, a, edge.from_wall, edge.from_offset)
		var b_socket: Transform3D = DungeonFreeYawRouter.socket_pose(fixture, b, edge.to_wall, edge.to_offset)
		if not _check(a_socket.origin.distance_to(edge.route_points[0]) < 0.001 and b_socket.origin.distance_to(edge.route_points[3]) < 0.001, "Real sockets and corridor endpoints must align exactly after arbitrary yaw."):
			return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(geometry)
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	walker.safe_margin = 0.001
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = fixture.player_radius
	capsule.height = fixture.player_height
	col.shape = capsule
	walker.add_child(col)
	stage.add_child(walker)
	await physics_frame
	await physics_frame
	var walking_height: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		var path := PackedVector3Array([a.world_transform.origin])
		path.append_array(edge.route_points)
		path.append(b.world_transform.origin)
		walker.global_position = path[0] + Vector3.UP * walking_height
		for k in range(1, path.size()):
			var end: Vector3 = path[k] + Vector3.UP * walking_height
			if not _check(not walker.test_move(walker.global_transform, end - walker.global_position), "Real capsule blocked on rotated connector %s leg %d." % [edge.stable_id, k]):
				return
			walker.global_position = end
	stage.remove_child(geometry)
	var top := Node3D.new()
	top.name = "PortableYawDungeon"
	top.add_child(geometry)
	geometry.owner = top
	_own(geometry, top)
	var baked := PackedScene.new()
	if not _check(baked.pack(top) == OK, "Full multiroom rotated dungeon must pack into native scene."):
		return
	var dest := "user://multiroom_free_yaw_smoke.tscn"
	if not _check(ResourceSaver.save(baked, dest) == OK, "Free-yaw native dungeon must export."):
		return
	var restored_packed := ResourceLoader.load(dest, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(restored_packed != null, "Baked native yaw dungeon must reopen."):
		return
	var restored := restored_packed.instantiate()
	if not _check(restored.find_children("*", "CollisionShape3D", true, false).size() == top.find_children("*", "CollisionShape3D", true, false).size(), "Native multiroom yaw collision must persist through export."):
		return
	restored.free()
	top.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dest))
	var invalid := fixture.duplicate(true) as LevelLayout
	invalid.rooms[0].world_transform.basis = Basis(Vector3.UP, deg_to_rad(90))
	if not _check(not DungeonPlanner.validate_layout(invalid).is_valid() and DungeonSceneCompiler.build(invalid) == null, "Tampered unrestricted yaw must be rejected before compilation."):
		return
	var disabled := DungeonConfig.new()
	disabled.enable_free_yaw_dungeons = true
	if not _check(not DungeonPlanner.generate_layout(disabled).success, "Free yaw must reject insufficient clearance configuration."):
		return
	print("DUNGEON_FREE_YAW_SMOKE: PASS (multiroom DFS, OBB SAT, capsule across every angled elbow, physics export and invalid-pose rejection)")
	quit(0)


func _own(n: Node, owner: Node) -> void:
	for child in n.get_children():
		child.owner = owner
		_own(child, owner)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("DUNGEON_FREE_YAW_SMOKE: FAIL: " + message)
		quit(1)
	return condition
