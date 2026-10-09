extends SceneTree
## F2 true socket-guided off-grid geometry: no world-space cell anchoring.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.grid_size = Vector2i(9, 9)
	cfg.critical_path_min = 6
	cfg.critical_path_max = 8
	cfg.branch_count = 3
	cfg.loop_count = 0
	cfg.max_attempts = 24
	cfg.enable_free_yaw_dungeons = true
	cfg.enable_offgrid_socket_packing = true
	cfg.free_yaw_max_degrees = 70.0
	cfg.free_yaw_shift = 1.5
	cfg.free_yaw_candidates = 20
	cfg.free_yaw_search_budget = 16000
	cfg.socket_pack_min_gap = 10.0
	cfg.socket_pack_max_gap = 13.0
	var success: int = 0
	var offgrid: int = 0
	var yaw_count: int = 0
	var fixture: LevelLayout
	for i in 22:
		cfg.seed = 47000 + i
		var result := DungeonPlanner.generate_layout(cfg)
		if not result.success:
			continue
		var duplicate := DungeonPlanner.generate_layout(cfg)
		if not _check(duplicate.success and result.layout.fingerprint() == duplicate.layout.fingerprint(), "Socket-packed multiroom transforms and routes must be replayable from the same seed."):
			return
		var layout: LevelLayout = result.layout
		if not _check(layout.free_yaw_enabled and layout.offgrid_socket_packing_enabled and DungeonPlanner.validate_layout(layout).is_valid(), "A completed off-grid layout must validate without its source DungeonConfig."):
			return
		for room in layout.rooms:
			var expected: Vector3 = DungeonSpatialEmbedder.expected_origin(layout, room.cell)
			if room.world_transform.origin.distance_to(expected) > 5.0:
				offgrid += 1
			if absf(rad_to_deg(room.world_transform.basis.get_euler().y)) > 15.0:
				yaw_count += 1
		if fixture == null:
			fixture = layout
		success += 1
	if not _check(success >= 8 and offgrid >= 25 and yaw_count >= 15, "True socket-packing must produce several genuinely non-grid, rotated, reachable dungeons."):
		return
	print("DUNGEON_OFFGRID_SMOKE: %d deterministic layouts, %d off-grid rooms, %d rotated" % [success, offgrid, yaw_count])
	var scene := DungeonSceneCompiler.build(fixture, true)
	if not _check(scene != null, "Full off-grid multiroom dungeon must compile native primitive/concave physics."):
		return
	var by_id: Dictionary = {}
	for room in fixture.rooms:
		by_id[room.stable_id] = room
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(scene)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = fixture.player_radius
	capsule.height = fixture.player_height
	collision.shape = capsule
	actor.add_child(collision)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var stand_y: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var path := PackedVector3Array([a.world_transform.origin])
		path.append_array(edge.route_points)
		path.append(b.world_transform.origin)
		actor.global_position = path[0] + Vector3.UP * stand_y
		for k in range(1, path.size()):
			var end: Vector3 = path[k] + Vector3.UP * stand_y
			if not _check(not actor.test_move(actor.global_transform, end - actor.global_position), "Off-grid world-space socket connector blocked: %s segment %d." % [edge.stable_id, k]):
				return
			actor.global_position = end
	for endpoint_id in [fixture.entrance_id, fixture.exit_id]:
		var room: RoomPlacementData = by_id[endpoint_id]
		var outer: Transform3D = DungeonFreeYawRouter.socket_pose(fixture, room, room.exterior_wall, room.exterior_offset)
		var outward: Vector3 = outer.basis * Vector3.FORWARD
		actor.global_position = room.world_transform.origin + Vector3.UP * stand_y
		for target in [outer.origin + Vector3.UP * stand_y, outer.origin + outward * 1.5 + Vector3.UP * stand_y]:
			if not _check(not actor.test_move(actor.global_transform, target - actor.global_position), "Rotated exterior entrance or exit must remain physically open."):
				return
			actor.global_position = target
	stage.remove_child(scene)
	var root_export := Node3D.new()
	root_export.add_child(scene)
	scene.owner = root_export
	_owners(scene, root_export)
	var packed := PackedScene.new()
	if not _check(packed.pack(root_export) == OK, "Standalone off-grid dungeon must pack."):
		return
	var filename := "user://offgrid_dungeon_smoke.tscn"
	if not _check(ResourceSaver.save(packed, filename) == OK, "Off-grid dungeon must export."):
		return
	var loaded := ResourceLoader.load(filename, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(loaded != null, "Off-grid dungeon must reload without editor resources."):
		return
	var restored := loaded.instantiate()
	if not _check(restored.find_children("*", "CollisionShape3D", true, false).size() == root_export.find_children("*", "CollisionShape3D", true, false).size(), "All world-space physical shapes must survive native scene export."):
		return
	restored.free()
	root_export.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	var altered := fixture.duplicate(true) as LevelLayout
	altered.rooms[0].world_transform.origin.x += 7.0
	if not _check(not DungeonPlanner.validate_layout(altered).is_valid(), "Moving a socket-connected room without rerouting must fail validation."):
		return
	var invalid := DungeonConfig.new()
	invalid.enable_offgrid_socket_packing = true
	if not _check(not DungeonPlanner.generate_layout(invalid).success, "Off-grid mode must require the corresponding yaw pipeline."):
		return
	print("DUNGEON_OFFGRID_SMOKE: PASS (seeded bounded backtracking, non-grid geometry, real entrance/exit capsule, full graph paths and native export)")
	quit(0)


func _owners(n: Node, target: Node) -> void:
	for child in n.get_children():
		child.owner = target
		_owners(child, target)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("DUNGEON_OFFGRID_SMOKE: FAIL: " + message)
		quit(1)
	return condition
