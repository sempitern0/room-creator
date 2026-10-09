extends SceneTree
## Combined F2 acceptance regression: rotated rooms with legacy orthogonal
## silhouettes, loops, mixed sizes and full collision-bearing prefabs.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.grid_size = Vector2i(12, 12)
	cfg.seed = 39000
	cfg.critical_path_min = 7
	cfg.critical_path_max = 9
	cfg.branch_count = 4
	cfg.loop_count = 1
	cfg.max_attempts = 24
	cfg.rectangle_weight = 6
	cfg.cross_weight = 6
	cfg.l_shape_weight = 5
	cfg.t_shape_weight = 5
	cfg.vary_room_sizes = true
	cfg.min_room_scale = 0.85
	cfg.max_room_scale = 1.0
	cfg.use_variable_grid_spacing = true
	cfg.min_corridor_gap = 12.0
	cfg.max_corridor_gap = 15.0
	cfg.enable_free_yaw_dungeons = true
	cfg.free_yaw_max_degrees = 20.0
	cfg.free_yaw_shift = 0.50
	cfg.free_yaw_candidates = 16
	cfg.free_yaw_search_budget = 10000
	var accepted: int = 0
	var exotic_rooms: int = 0
	var rotations: int = 0
	var fixture: LevelLayout
	for n in 12:
		cfg.seed = 39000 + n
		var built := DungeonPlanner.generate_layout(cfg)
		if not built.success:
			continue
		if not _check(DungeonPlanner.validate_layout(built.layout).is_valid(), "All combined-silhouette yaw dungeons must pass full layout validation."):
			return
		var layout: LevelLayout = built.layout
		if not _check(layout.connections.size() - layout.rooms.size() + 1 == 1, "Optional cycles must preserve the requested graph loop."):
			return
		for room in layout.rooms:
			if room.shape != RoomFootprint.Shape.RECTANGLE:
				exotic_rooms += 1
			if absf(rad_to_deg(room.world_transform.basis.get_euler().y)) > 5.0:
				rotations += 1
		if fixture == null:
			fixture = layout
		accepted += 1
	if not _check(accepted >= 5 and exotic_rooms >= 10 and rotations >= 20 and fixture != null, "Free yaw should compose successfully with loops, mixed shapes and room dimensions."):
		return
	var preview := DungeonSceneCompiler.build(fixture, false)
	if not _check(preview != null, "Mixed yaw L/T/cross shapes must compile a preview."):
		return
	DungeonPreviewOverlay.apply(preview, fixture, DungeonPreviewPalette.new())
	if not _check(preview.get_node_or_null("PreviewRoutes") != null, "Free-yaw connections must remain identifiable from overhead diagnostics."):
		return
	preview.free()
	var baked := DungeonSceneCompiler.build(fixture, true)
	if not _check(baked != null, "Combined yaw silhouette dungeon must compile static physics."):
		return
	var rooms: Dictionary = {}
	for room in fixture.rooms:
		rooms[room.stable_id] = room
	var scene_stage := Node3D.new()
	root.add_child(scene_stage)
	scene_stage.add_child(baked)
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.safe_margin = 0.001
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = fixture.player_radius
	capsule.height = fixture.player_height
	collider.shape = capsule
	body.add_child(collider)
	scene_stage.add_child(body)
	await physics_frame
	await physics_frame
	var y: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = rooms[edge.from_room_id]
		var b: RoomPlacementData = rooms[edge.to_room_id]
		var path := PackedVector3Array([a.world_transform.origin])
		path.append_array(edge.route_points)
		path.append(b.world_transform.origin)
		body.global_position = path[0] + Vector3.UP * y
		for i in range(1, path.size()):
			var end: Vector3 = path[i] + Vector3.UP * y
			if not _check(not body.test_move(body.global_transform, end - body.global_position), "Legacy shaped-room yaw path blocked by real collider on %s, segment %d." % [edge.stable_id, i]):
				return
			body.global_position = end
	scene_stage.free()
	# Independent structural-prefab fixture: yaw rotates the full room wrapper
	# AND its authored BoxShape3D bodies, with exactly matched local sockets.
	var structure := DungeonConfig.new()
	structure.grid_size = Vector2i(10, 10)
	structure.critical_path_min = 5
	structure.critical_path_max = 7
	structure.branch_count = 2
	structure.loop_count = 0
	structure.max_attempts = 20
	structure.use_variable_grid_spacing = true
	structure.min_corridor_gap = 12.0
	structure.max_corridor_gap = 15.0
	structure.enable_free_yaw_dungeons = true
	structure.free_yaw_max_degrees = 18.0
	structure.free_yaw_candidates = 14
	structure.free_yaw_search_budget = 8000
	structure.structural_prefab_chance = 1.0
	structure.structural_prefabs = [
		load("res://examples/dungeon_structural_straight_profile.tres"),
		load("res://examples/dungeon_structural_corner_profile.tres")
	]
	var used_prefabs: int = 0
	var structural_layout: LevelLayout
	for n in 8:
		structure.seed = 40000 + n
		var built := DungeonPlanner.generate_layout(structure)
		if not built.success:
			continue
		var count: int = 0
		for room in built.layout.rooms:
			if room.structural_prefab != null:
				count += 1
		if count > 0:
			used_prefabs += count
			if structural_layout == null:
				structural_layout = built.layout
	if not _check(used_prefabs >= 3 and structural_layout != null, "Yaw backtracking must retain some fully collidable structural room prefabs."):
		return
	var structural_bake := DungeonSceneCompiler.build(structural_layout, true)
	if not _check(structural_bake != null and structural_bake.find_children("StructuralShell", "Node3D", true, false).size() > 0, "Mixed procedural/structural yaw geometry must compile real physics."):
		return
	structural_bake.free()
	print("DUNGEON_F2_COMBINED_SMOKE: PASS (%d looped silhouette seeds, %d exotic rooms, %d rotations, %d yaw structural prefabs, real capsule paths)" % [accepted, exotic_rooms, rotations, used_prefabs])
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_F2_COMBINED_SMOKE: FAIL: " + message)
		quit(1)
	return ok
