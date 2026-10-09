extends SceneTree
## F2.3: real external access portals, per-room size variation, corridor
## socket alignment, physical traversal and engine-only scene export.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.grid_size = Vector2i(14, 14)
	config.critical_path_min = 9
	config.critical_path_max = 11
	config.branch_count = 7
	config.loop_count = 1
	config.max_attempts = 32
	config.rectangle_weight = 4
	config.cross_weight = 8
	config.l_shape_weight = 7
	config.t_shape_weight = 7
	config.vary_room_sizes = true
	config.min_room_scale = 0.80
	config.max_room_scale = 0.95
	var layout: LevelLayout
	for seed_number in 40:
		config.seed = 9000 + seed_number
		var result := DungeonPlanner.generate_layout(config)
		if not _check(result.success, "Varying-size seed %d: %s" % [config.seed, result.report.summary()]):
			return
		var rerun := DungeonPlanner.generate_layout(config)
		if not _check(rerun.success and rerun.layout.fingerprint() == result.layout.fingerprint(), "Spatial placements must replay exactly for a seed."):
			return
		if not _check(DungeonPlanner.validate_layout(result.layout).is_valid(), "All variable sizes must be valid and nonoverlapping."):
			return
		for room in result.layout.rooms:
			if not _check(room.room_size.x < config.room_size.x + 0.0001 and room.room_size.z < config.room_size.z + 0.0001, "Individual rooms must remain inside their grid footprints."):
				return
		layout = result.layout
	print("DUNGEON_SPATIAL_SMOKE: 40 variable-size deterministic seeds verified")
	if not _check(layout != null and layout.exterior_doors_enabled, "F2.3 default provides outside entrance and exit."):
		return
	var dungeon := DungeonSceneCompiler.build(layout, true)
	if not _check(dungeon != null, "Variable room dungeon must compile to native geometry."):
		return
	var by_id: Dictionary = {}
	for room in layout.rooms:
		by_id[room.stable_id] = room
	var connection_count: int = 0
	for edge in layout.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var a_node := dungeon.get_node_or_null(NodePath(a.stable_id)) as Node3D
		var b_node := dungeon.get_node_or_null(NodePath(b.stable_id)) as Node3D
		if not _check(a_node != null and b_node != null, "Each connector must have both rooms."):
			return
		var socket_a := a_node.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		var socket_b := b_node.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		if not _check(socket_a != null and socket_b != null, "Each door pair must have two sockets."):
			return
		var world_a: Vector3 = a_node.transform * socket_a.position
		var world_b: Vector3 = b_node.transform * socket_b.position
		var gap: float = world_a.distance_to(world_b)
		if gap > 0.001:
			var connector := dungeon.get_node_or_null(NodePath("Connector_" + edge.stable_id)) as Node3D
			if not _check(connector != null and connector.position.distance_to((world_a + world_b) * 0.5) < 0.001, "A connector must span the exact socket separation."):
				return
			var corridor_floor := connector.get_node_or_null("Floor") as MeshInstance3D
			var dim: Vector3 = (corridor_floor.mesh as BoxMesh).size
			if not _check(absf((dim.x if a.cell.x != b.cell.x else dim.z) - gap) < 0.001, "Corridor length must match the physical gap."):
				return
			connection_count += 1
	if not _check(connection_count > 0, "Varying room sizes must actually create at least one corridor."):
		return
	var body_count: int = dungeon.find_children("*", "CollisionShape3D", true, false).size()
	if not _check(body_count > 0, "All generated static surfaces must have collision."):
		return
	for label in [layout.entrance_id, layout.exit_id]:
		var room: RoomPlacementData = by_id[label]
		if not _check(room.exterior_wall >= 0 and not room.exterior_id.is_empty(), "Entry/exit must have a real outward wall opening."):
			return
		var root_room := dungeon.get_node_or_null(NodePath(room.stable_id)) as Node3D
		var socket := root_room.get_node_or_null(NodePath("Socket_" + room.exterior_id)) as Marker3D
		if not _check(socket != null and socket.get_meta("clear_width", 0.0) >= layout.player_radius * 2.0, "External doorway must have a real walkable socket with capsule clearance."):
			return

	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(dungeon)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = layout.player_radius
	capsule.height = layout.player_height
	collision.shape = capsule
	actor.add_child(collision)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var center_height: float = layout.player_height * 0.5 + 0.08
	for edge in layout.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		actor.global_position = a.world_transform.origin + Vector3.UP * center_height
		var goal: Vector3 = b.world_transform.origin + Vector3.UP * center_height
		if not _check(not actor.test_move(actor.global_transform, goal - actor.global_position), "Capsule blocked between variable-sized rooms at %s." % edge.stable_id):
			return
	for label in [layout.entrance_id, layout.exit_id]:
		var room: RoomPlacementData = by_id[label]
		var outward := Vector3.ZERO
		match room.exterior_wall:
			RoomOpening.Wall.FRONT: outward = Vector3.FORWARD
			RoomOpening.Wall.BACK: outward = Vector3.BACK
			RoomOpening.Wall.LEFT: outward = Vector3.LEFT
			RoomOpening.Wall.RIGHT: outward = Vector3.RIGHT
		var size: Vector3 = DungeonPlanner.actual_size(layout, room)
		var wall_distance: float = size.z * 0.5 if room.exterior_wall == RoomOpening.Wall.FRONT or room.exterior_wall == RoomOpening.Wall.BACK else size.x * 0.5
		actor.global_position = room.world_transform.origin + Vector3.UP * center_height
		if not _check(not actor.test_move(actor.global_transform, outward * (wall_distance + 0.5)), "Capsule cannot pass real %s exterior doorway." % room.exterior_id):
			return
	stage.remove_child(dungeon)
	var export_root := Node3D.new()
	export_root.name = "ExportedDungeon"
	export_root.add_child(dungeon)
	dungeon.owner = export_root
	_set_owners(dungeon, export_root)
	var packed := PackedScene.new()
	if not _check(packed.pack(export_root) == OK, "Generated scene must pack without editor code."):
		return
	var path := "user://dungeon_spatial_smoke.tscn"
	if not _check(ResourceSaver.save(packed, path) == OK, "Generated scene must save."):
		return
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(scene != null, "Generated scene must reload."):
		return
	var imported := scene.instantiate()
	if not _check(imported.find_children("*", "CollisionShape3D", true, false).size() == body_count, "Export must preserve all collision."):
		return
	if not _check(imported.find_children("Socket_*", "Marker3D", true, false).size() == 2 * layout.connections.size() + 2, "Export must preserve internal and both exterior sockets."):
		return
	imported.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	export_root.free()
	stage.free()
	var bad := layout.duplicate(true) as LevelLayout
	bad.rooms[0].room_size.x = layout.room_size.x * 1.3
	if not _check(not DungeonPlanner.validate_layout(bad).is_valid() and DungeonSceneCompiler.build(bad) == null, "Oversized/overlapping edited room must be rejected."):
		return
	var outside_bad := layout.duplicate(true) as LevelLayout
	outside_bad.rooms[0].exterior_wall = -1
	if not _check(not DungeonPlanner.validate_layout(outside_bad).is_valid(), "Missing outside access must reject layout validation."):
		return
	print("DUNGEON_SPATIAL_SMOKE: PASS (40 seeds, exterior doors, corridor geometry, physics and export)")
	quit(0)


func _set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners(child, owner)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_SPATIAL_SMOKE: FAIL: " + message)
		quit(1)
	return ok
