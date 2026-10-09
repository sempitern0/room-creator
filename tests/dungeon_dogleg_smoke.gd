extends SceneTree
## F2.6: deterministic three-leg dogleg corridor geometry, a capsule turning
## both elbows, rejection of tampered routes and source-only scene preservation.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.grid_size = Vector2i(15, 15)
	config.critical_path_min = 8
	config.critical_path_max = 11
	config.branch_count = 7
	config.loop_count = 1
	config.max_attempts = 32
	config.rectangle_weight = 3
	config.cross_weight = 8
	config.l_shape_weight = 7
	config.t_shape_weight = 7
	config.vary_room_sizes = true
	config.min_room_scale = 0.80
	config.max_room_scale = 0.95
	config.use_variable_grid_spacing = true
	config.min_corridor_gap = 2.0
	config.max_corridor_gap = 4.0
	config.enable_independent_room_offsets = true
	config.room_position_jitter = 1.0
	config.placement_attempts = 32
	config.enable_dogleg_corridors = true
	config.dogleg_frequency = 0.75
	var total_turns: int = 0
	var fixture: LevelLayout
	for seed_offset in 36:
		config.seed = 21000 + seed_offset
		var result := DungeonPlanner.generate_layout(config)
		if not _check(result.success, "Route generation seed %d failed: %s" % [config.seed, result.report.summary()]):
			return
		var replay := DungeonPlanner.generate_layout(config)
		if not _check(replay.success and result.layout.fingerprint() == replay.layout.fingerprint(), "Dogleg placement must replay deterministically."):
			return
		var layout: LevelLayout = result.layout
		if not _check(layout.dogleg_corridors_enabled and DungeonPlanner.validate_layout(layout).is_valid(), "Routed layouts must validate from serialized resources."):
			return
		var by_id: Dictionary = {}
		for room in layout.rooms:
			by_id[room.stable_id] = room
		for edge in layout.connections:
			if edge.route_points.is_empty():
				continue
			if not _check(edge.route_points.size() == 4 and DungeonCorridorRouter.validate_route(layout, edge, edge.route_points, by_id[edge.from_room_id], by_id[edge.to_room_id]), "Every dogleg must preserve its two reciprocal socket positions."):
				return
			var delta: Vector3 = edge.route_points[2] - edge.route_points[1]
			if delta.length() > 0.15:
				total_turns += 1
		fixture = layout
	if not _check(total_turns > 40, "Dogleg mode must generate a meaningful number of real turning corridors."):
		return
	print("DUNGEON_DOGLEG_SMOKE: 36 reproducible layouts, %d turning connections" % total_turns)
	var preview := DungeonSceneCompiler.build(fixture, false)
	if not _check(preview != null, "Routed dungeons need a buildable preview."):
		return
	DungeonPreviewOverlay.apply(preview, fixture, DungeonPreviewPalette.new())
	var route_group := preview.get_node_or_null("PreviewRoutes")
	if not _check(route_group != null and route_group.find_children("Route_*", "MeshInstance3D", true, false).size() == fixture.connections.size(), "The editor must show one primary route per logical connection."):
		return
	var routed_lines := route_group.find_children("RoutePart_*", "MeshInstance3D", true, false)
	if not _check(routed_lines.size() > 0, "Doglegs must be visible as multiple color-coded pieces from an overhead camera."):
		return
	var edge_ids: Dictionary = {}
	for edge in fixture.connections:
		edge_ids[edge.stable_id] = true
	for segment in routed_lines:
		if not _check(edge_ids.has(segment.get_meta("connection_id", "")), "Every drawn elbow segment must refer to its original graph edge."):
			return
	preview.free()
	var geometry := DungeonSceneCompiler.build(fixture, true)
	if not _check(geometry != null, "Turning corridors must compile native Godot collision."):
		return
	var lookup: Dictionary = {}
	for room in fixture.rooms:
		lookup[room.stable_id] = room
	var rendered_turns: int = 0
	for edge in fixture.connections:
		if edge.route_points.is_empty():
			continue
		var connector := geometry.get_node_or_null(NodePath("Connector_" + edge.stable_id)) as Node3D
		if not _check(connector != null and connector.get_meta("route_points", PackedVector3Array()).size() == 4, "The baked corridor must persist its routed geometry metadata."):
			return
		if not _check(connector.find_children("RouteFloor_*", "MeshInstance3D", true, false).size() > 3, "Elbow floors must use the actual joined corridor envelope."):
			return
		rendered_turns += 1
	if not _check(rendered_turns > 0, "Compiled dungeon should include routed connections."):
		return
	var physics_stage := Node3D.new()
	root.add_child(physics_stage)
	physics_stage.add_child(geometry)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = fixture.player_radius
	capsule.height = fixture.player_height
	shape.shape = capsule
	actor.add_child(shape)
	physics_stage.add_child(actor)
	await physics_frame
	await physics_frame
	var y: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		actor.global_position = a.world_transform.origin + Vector3.UP * y
		var points := PackedVector3Array([a.world_transform.origin])
		if edge.route_points.is_empty():
			points.append(b.world_transform.origin)
		else:
			points.append_array(edge.route_points)
			points.append(b.world_transform.origin)
		for j in range(1, points.size()):
			var end_position: Vector3 = points[j] + Vector3.UP * y
			var travel: Vector3 = end_position - actor.global_position
			if travel.length() <= 0.01:
				continue
			if not _check(not actor.test_move(actor.global_transform, travel), "Player capsule collides on %s, segment %d of %d." % [edge.stable_id, j, points.size()]):
				return
			actor.global_position = end_position
	physics_stage.free()
	var exported := DungeonSceneCompiler.build(fixture, true)
	var static_count: int = exported.find_children("*", "CollisionShape3D", true, false).size()
	var wrapper := Node3D.new()
	wrapper.name = "ExportedDoglegDungeon"
	wrapper.add_child(exported)
	exported.owner = wrapper
	_set_owners(exported, wrapper)
	var packed := PackedScene.new()
	if not _check(packed.pack(wrapper) == OK, "Native routed dungeon must pack without plugin runtime nodes."):
		return
	var file_name := "user://dogleg_smoke.tscn"
	if not _check(ResourceSaver.save(packed, file_name) == OK, "Native routed dungeon must save."):
		return
	var reloaded := ResourceLoader.load(file_name, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reloaded != null, "Native routed dungeon must reload."):
		return
	var restored := reloaded.instantiate()
	if not _check(restored.find_children("*", "CollisionShape3D", true, false).size() == static_count, "Exported dogleg must retain every primitive collider."):
		return
	var saved_elbows: int = 0
	for edge in fixture.connections:
		if edge.route_points.size() != 4:
			continue
		var node := restored.get_node_or_null(NodePath("DungeonGeometry/Connector_" + edge.stable_id))
		if node != null and node.get_meta("route_points", PackedVector3Array()).size() == 4:
			saved_elbows += 1
	if not _check(saved_elbows == rendered_turns, "The exported scene must preserve all routed connectors and their identities."):
		return
	restored.free()
	wrapper.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_name))
	var modified := fixture.duplicate(true) as LevelLayout
	for edge in modified.connections:
		if edge.route_points.size() == 4:
			var points := edge.route_points
			points[1].x += 0.25
			edge.route_points = points
			break
	if not _check(not DungeonPlanner.validate_layout(modified).is_valid() and DungeonSceneCompiler.build(modified) == null, "Tampering with an authored elbow path must be rejected before baking."):
		return
	var invalid := DungeonConfig.new()
	invalid.enable_dogleg_corridors = true
	if not _check(not DungeonPlanner.generate_layout(invalid).success, "Dogleg mode without an offset solver must report an invalid config."):
		return
	print("DUNGEON_DOGLEG_SMOKE: PASS (seed replay, bent collision geometry, capsule corner sweeps and route contract)")
	quit(0)


func _set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners(child, owner)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_DOGLEG_SMOKE: FAIL: " + message)
		quit(1)
	return ok
