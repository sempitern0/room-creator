extends SceneTree
## F2.4 non-uniform seeded embedding: variable corridor lengths, bounded
## geometry, aligned sockets, complete capsule traversal and legacy migration.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.grid_size = Vector2i(14, 14)
	cfg.critical_path_min = 8
	cfg.critical_path_max = 11
	cfg.branch_count = 7
	cfg.loop_count = 1
	cfg.max_attempts = 32
	cfg.rectangle_weight = 3
	cfg.cross_weight = 8
	cfg.l_shape_weight = 7
	cfg.t_shape_weight = 7
	cfg.vary_room_sizes = true
	cfg.min_room_scale = 0.80
	cfg.max_room_scale = 0.95
	cfg.use_variable_grid_spacing = true
	cfg.min_corridor_gap = 1.0
	cfg.max_corridor_gap = 5.0
	var final_layout: LevelLayout
	var count: int = 0
	for i in 70:
		cfg.seed = 14000 + i
		var build := DungeonPlanner.generate_layout(cfg)
		if not _check(build.success, "Non-uniform layout seed %d failed: %s" % [cfg.seed, build.report.summary()]):
			return
		var replay := DungeonPlanner.generate_layout(cfg)
		if not _check(replay.success and replay.layout.fingerprint() == build.layout.fingerprint(), "Seeded embedding must be reproducible."):
			return
		var layout := build.layout
		if not _check(layout.column_positions.size() == cfg.grid_size.x and layout.row_positions.size() == cfg.grid_size.y, "Every column and row needs a persisted coordinate."):
			return
		if not _check(DungeonPlanner.validate_layout(layout).is_valid(), "Generated non-uniform placement must pass the spatial validator."):
			return
		var variation: Dictionary = {}
		for col in range(1, cfg.grid_size.x):
			var step: float = layout.column_positions[col] - layout.column_positions[col - 1]
			if not _check(step >= cfg.room_size.x + cfg.min_corridor_gap - 0.001 and step <= cfg.room_size.x + cfg.max_corridor_gap + 0.001, "Horizontal spacing exceeds configured limits."):
				return
			variation[snappedf(step, 0.25)] = true
		if not _check(variation.size() > 1, "Column spacing must really vary in this fixture."):
			return
		for row in range(1, cfg.grid_size.y):
			var step: float = layout.row_positions[row] - layout.row_positions[row - 1]
			if not _check(step >= cfg.room_size.z + cfg.min_corridor_gap - 0.001 and step <= cfg.room_size.z + cfg.max_corridor_gap + 0.001, "Vertical spacing exceeds configured limits."):
				return
		for room in layout.rooms:
			if not _check(room.world_transform.origin.distance_to(DungeonSpatialEmbedder.expected_origin(layout, room.cell)) < 0.001, "Room transform must exactly follow persisted world axes."):
				return
		count += 1
		final_layout = layout
	print("DUNGEON_EMBEDDING_SMOKE: validated %d spatial seeds" % count)
	if not _check(final_layout != null, "At least one layout must exist."):
		return
	var geometry := DungeonSceneCompiler.build(final_layout, true)
	if not _check(geometry != null, "Non-uniform spacing must bake native static geometry."):
		return
	var by_id: Dictionary = {}
	for room in final_layout.rooms:
		by_id[room.stable_id] = room
	var corridor_lengths: Dictionary = {}
	for edge in final_layout.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var ar := geometry.get_node_or_null(NodePath(a.stable_id)) as Node3D
		var br := geometry.get_node_or_null(NodePath(b.stable_id)) as Node3D
		var left_socket := ar.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		var right_socket := br.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		if not _check(left_socket != null and right_socket != null, "Every graph connection must have reciprocal sockets."):
			return
		var pos_a: Vector3 = ar.transform * left_socket.position
		var pos_b: Vector3 = br.transform * right_socket.position
		var gap: float = pos_a.distance_to(pos_b)
		if not _check(gap > cfg.min_corridor_gap, "Non-uniform fixture needs a real corridor on every edge."):
			return
		var corridor := geometry.get_node_or_null(NodePath("Connector_" + edge.stable_id)) as Node3D
		if not _check(corridor != null and corridor.position.distance_to((pos_a + pos_b) * 0.5) < 0.001, "Corridor must join exact socket midpoints."):
			return
		var corridor_floor := corridor.get_node_or_null("Floor") as MeshInstance3D
		var box: BoxMesh = corridor_floor.mesh as BoxMesh
		var extent: float = box.size.x if a.cell.x != b.cell.x else box.size.z
		if not _check(absf(extent - gap) < 0.001, "Corridor floor must span precise socket gap."):
			return
		corridor_lengths[snappedf(gap, 0.25)] = true
	if not _check(corridor_lengths.size() > 2, "Dynamic embedding must produce visually diverse corridor lengths."):
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(geometry)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = final_layout.player_radius
	capsule.height = final_layout.player_height
	col.shape = capsule
	actor.add_child(col)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var player_y: float = final_layout.player_height * 0.5 + 0.08
	for edge in final_layout.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		actor.global_position = a.world_transform.origin + Vector3.UP * player_y
		var destination: Vector3 = b.world_transform.origin + Vector3.UP * player_y
		if not _check(not actor.test_move(actor.global_transform, destination - actor.global_position), "Real capsule traversal failed on stretched connector %s." % edge.stable_id):
			return
	stage.free()
	var edited := final_layout.duplicate(true) as LevelLayout
	edited.column_positions[1] = edited.column_positions[0] + final_layout.room_size.x * 0.50
	if not _check(not DungeonPlanner.validate_layout(edited).is_valid() and DungeonSceneCompiler.build(edited) == null, "Overlapping/invalid spatial axis must be rejected."):
		return
	var tampered := final_layout.duplicate(true) as LevelLayout
	tampered.rooms[0].world_transform.origin.x += 2.0
	if not _check(not DungeonPlanner.validate_layout(tampered).is_valid(), "World transform cannot diverge from the serialized spatial contract."):
		return
	var legacy := DungeonConfig.new()
	legacy.seed = 3
	var old_layout := DungeonPlanner.generate_layout(legacy)
	if not _check(old_layout.success and old_layout.layout.column_positions.is_empty() and old_layout.layout.row_positions.is_empty(), "Legacy zero-gap layout contract must remain unchanged."):
		return
	print("DUNGEON_EMBEDDING_SMOKE: PASS (70 seeds, corridor variety, real physics and invalid-geometry rejection)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_EMBEDDING_SMOKE: FAIL: " + message)
		quit(1)
	return ok
