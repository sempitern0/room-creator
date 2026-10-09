extends SceneTree
## F2.1 regression: silhouettes, socket contracts, deterministic weighted generation,
## editor lifecycle, and actual CharacterBody3D movement across mixed silhouettes.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for shape in [RoomFootprint.Shape.CROSS, RoomFootprint.Shape.L_SHAPE, RoomFootprint.Shape.T_SHAPE]:
		for turns in 4:
			var blueprint := RoomBlueprint.new()
			blueprint.shape = shape
			blueprint.shape_rotation = turns
			var wall: int = -1
			for side in 4:
				if RoomFootprint.supports_wall(shape, turns, side):
					wall = side
					break
			if not _check(wall != -1, "At least one opening wall must be supported."):
				return
			var opening := RoomOpening.new()
			opening.stable_id = "passage"
			opening.wall = wall
			blueprint.openings = [opening]
			if not _check(RoomGeometryBuilder.validate(blueprint).is_valid(), "Valid shape/rotation must accept a centered socket."):
				return
			var geometry := RoomGeometryBuilder.build(blueprint, true)
			if not _check(geometry != null and geometry.find_children("Socket_*", "Marker3D", true, false).size() == 1, "A walkable shape must compile and create its socket."):
				return
			if not _check(geometry.find_children("*", "CollisionShape3D", true, false).size() >= 10, "All silhouette surfaces should have primitive collision."):
				return
			geometry.free()
			var bad := blueprint.duplicate(true) as RoomBlueprint
			var invalid_side: int = -1
			for side in 4:
				if not RoomFootprint.supports_wall(shape, turns, side):
					invalid_side = side
					break
			if invalid_side >= 0:
				bad.openings[0].wall = invalid_side
				if not _check(not RoomGeometryBuilder.validate(bad).is_valid() and RoomGeometryBuilder.build(bad) == null, "No door is allowed on a missing boundary tile."):
					return
			if not _check(blueprint.openings[0].wall == wall, "Local shape edits must not mutate the original blueprint."):
				return

	var profile := DungeonConfig.new()
	profile.grid_size = Vector2i(14, 14)
	profile.critical_path_min = 8
	profile.critical_path_max = 11
	profile.branch_count = 6
	profile.max_attempts = 20
	profile.rectangle_weight = 2
	profile.cross_weight = 9
	profile.l_shape_weight = 8
	profile.t_shape_weight = 8
	var seen: Dictionary = {}
	for seed_number in 60:
		profile.seed = 1200 + seed_number
		var result := DungeonPlanner.generate_layout(profile)
		if not _check(result.success, "Weighted generation failed for seed %d: %s" % [profile.seed, result.report.summary()]):
			return
		var replay := DungeonPlanner.generate_layout(profile)
		if not _check(replay.success and replay.layout.fingerprint() == result.layout.fingerprint(), "Weighted silhouettes must be deterministic."):
			return
		for room in result.layout.rooms:
			seen[room.shape] = true
			if not _check(RoomGeometryBuilder.validate(DungeonPlanner.make_blueprint(result.layout, room)).is_valid(), "Every chosen shape must have valid reciprocal openings."):
				return
	if not _check(seen.has(RoomFootprint.Shape.CROSS) and seen.has(RoomFootprint.Shape.L_SHAPE) and seen.has(RoomFootprint.Shape.T_SHAPE), "The weighted profile must actually generate all three nonrectangular silhouettes."):
		return

	profile.seed = 1232
	var author := DungeonAuthoring3D.new()
	author.config = profile
	var untouched := Node3D.new()
	untouched.name = "UserAuthoredMarker"
	author.add_child(untouched)
	author.generate_new_layout()
	var preview := author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and author.layout != null and preview.get_meta("layout_fingerprint", "") == author.layout.fingerprint(), "Generate Layout must immediately create the current preview."):
		return
	author.bake()
	if not _check(author.get_node_or_null("DungeonBake") != null, "A baked scene should exist."):
		return
	var old_layout_fingerprint := author.layout.fingerprint()
	profile.seed = 1233
	author.generate_new_layout()
	var refreshed := author.get_node_or_null("DungeonPreview")
	if not _check(refreshed != null and author.get_node_or_null("DungeonBake") == null, "Regeneration must remove a stale baked scene."):
		return
	if not _check(refreshed.get_meta("layout_fingerprint", "") == author.layout.fingerprint() and author.layout.fingerprint() != old_layout_fingerprint, "New preview must represent the regenerated layout."):
		return
	if not _check(untouched.get_parent() == author, "Regeneration must never delete manually owned children."):
		return
	author.bake()
	var preserved_layout := author.layout
	var preserved_preview := author.get_node_or_null("DungeonPreview")
	var preserved_bake := author.get_node_or_null("DungeonBake")
	var invalid_config := DungeonConfig.new()
	invalid_config.grid_size = Vector2i.ONE
	invalid_config.critical_path_min = 5
	invalid_config.critical_path_max = 5
	author.config = invalid_config
	author.generate_new_layout()
	if not _check(author.layout == preserved_layout and author.get_node_or_null("DungeonPreview") == preserved_preview and author.get_node_or_null("DungeonBake") == preserved_bake, "A failed generation must preserve valid layout, preview, and bake."):
		return
	author.free()

	var physics_profile := DungeonConfig.new()
	physics_profile.seed = 822
	physics_profile.grid_size = Vector2i(12, 12)
	physics_profile.critical_path_min = 8
	physics_profile.critical_path_max = 8
	physics_profile.branch_count = 8
	physics_profile.loop_count = 1
	physics_profile.max_attempts = 32
	physics_profile.rectangle_weight = 3
	physics_profile.cross_weight = 8
	physics_profile.l_shape_weight = 7
	physics_profile.t_shape_weight = 7
	var tested := DungeonPlanner.generate_layout(physics_profile)
	if not _check(tested.success, "Mixed-silhouette physics dungeon must generate: " + tested.report.summary()):
		return
	var compiled := DungeonSceneCompiler.build(tested.layout, true)
	if not _check(compiled != null, "Mixed shapes must compile as standard Godot geometry."):
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(compiled)
	var player := CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.safe_margin = 0.001
	var shape3d := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = physics_profile.player_radius
	capsule.height = physics_profile.player_height
	shape3d.shape = capsule
	player.add_child(shape3d)
	stage.add_child(player)
	await physics_frame
	await physics_frame
	var lookup: Dictionary = {}
	for room in tested.layout.rooms:
		lookup[room.stable_id] = room
	for edge in tested.layout.connections:
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		player.global_position = a.world_transform.origin + Vector3(0.0, physics_profile.player_height * 0.5 + 0.08, 0.0)
		var end: Vector3 = b.world_transform.origin + Vector3(0.0, physics_profile.player_height * 0.5 + 0.08, 0.0)
		if not _check(not player.test_move(player.global_transform, end - player.global_position), "Capsule could not cross mixed silhouettes at %s" % edge.stable_id):
			return
	stage.free()
	print("ROOM_SHAPES_SMOKE: PASS (12 shape rotations, 60 deterministic seeds, capsule edges and auto-preview lifecycle)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("ROOM_SHAPES_SMOKE: FAIL: " + message)
		quit(1)
	return ok
