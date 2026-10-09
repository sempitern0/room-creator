extends SceneTree
## F2.8 offset-socket structural prefabs, safe fallback, route/physics contract.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := load("res://examples/dungeon_structural_offset_profile.tres") as DungeonStructuralPrefab
	if not _check(profile != null and profile.validate().is_valid(), "Offset structural prefab must validate: " + (profile.validate().summary() if profile != null else "not loaded")):
		return
	if not _check(absf(profile.rotated_socket_offset(RoomOpening.Wall.FRONT, 0) - 0.8) < 0.001 and absf(profile.rotated_socket_offset(RoomOpening.Wall.BACK, 0) + 0.8) < 0.001, "Authored signed wall offsets must be read from actual Marker3D transforms."):
		return
	if not _check(absf(profile.rotated_socket_offset(RoomOpening.Wall.FRONT, 2) - 0.8) < 0.001 and absf(profile.rotated_socket_offset(RoomOpening.Wall.BACK, 2) + 0.8) < 0.001, "180-degree rotated profile must map opposite authored sockets correctly."):
		return
	var config := load("res://examples/dungeon_offset_socket_preset.tres") as DungeonConfig
	if not _check(config != null and DungeonPlanner.validate_config(config).is_valid(), "F2.8 example preset must import and be valid."):
		return
	var picked: int = 0
	var modified_edges: int = 0
	var turns: Dictionary = {}
	var fixture: LevelLayout
	for seed_index in 35:
		config.seed = 27000 + seed_index
		var result := DungeonPlanner.generate_layout(config)
		if not _check(result.success, "Off-center prefab seed %d must compile: %s" % [config.seed, result.report.summary()]):
			return
		var repeat := DungeonPlanner.generate_layout(config)
		if not _check(repeat.success and result.layout.fingerprint() == repeat.layout.fingerprint(), "Door offsets, prefabs and routed connectors must replay exactly with the same seed."):
			return
		if not _check(DungeonPlanner.validate_layout(result.layout).is_valid(), "Serialized asymmetric room layout must pass standalone validation."):
			return
		for room in result.layout.rooms:
			if room.structural_prefab != null:
				picked += 1
				turns[room.structural_turns] = true
		for edge in result.layout.connections:
			if absf(edge.from_offset) > 0.01 or absf(edge.to_offset) > 0.01:
				modified_edges += 1
				if not _check(edge.route_points.size() == 4, "Misaligned offset doors must use a certified elbow route."):
					return
		fixture = result.layout
	if not _check(picked > 12 and modified_edges > 12 and turns.size() >= 2, "Seed sweep must exercise real structural offsets and rotated asymmetric profiles."):
		return
	print("DUNGEON_OFFSET_SOCKET_SMOKE: 35 seeds, %d authored asymmetric rooms and %d rerouted edges" % [picked, modified_edges])
	var baked := DungeonSceneCompiler.build(fixture, true)
	if not _check(baked != null, "Offset room dungeon must export with physical collision."):
		return
	var lookup: Dictionary = {}
	for room in fixture.rooms:
		lookup[room.stable_id] = room
	var owned_sockets: int = 0
	for edge in fixture.connections:
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		var a_root := baked.get_node_or_null(NodePath(a.stable_id)) as Node3D
		var b_root := baked.get_node_or_null(NodePath(b.stable_id)) as Node3D
		var a_socket := a_root.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		var b_socket := b_root.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		if not _check(a_socket != null and b_socket != null, "Each structural/procedural pairing must keep reciprocal stable socket IDs."):
			return
		var p0: Vector3 = a_root.transform * a_socket.position
		var p3: Vector3 = b_root.transform * b_socket.position
		if edge.route_points.size() == 4:
			if not _check(p0.distance_to(edge.route_points[0]) < 0.001 and p3.distance_to(edge.route_points[3]) < 0.001, "The physical prefab sockets must exactly touch the routed corridor endpoints."):
				return
		owned_sockets += 2
	if not _check(owned_sockets == 2 * fixture.connections.size(), "Every graph edge must have two physical markers."):
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(baked)
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
	var player_y: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = lookup[edge.from_room_id]
		var b: RoomPlacementData = lookup[edge.to_room_id]
		var points := PackedVector3Array([a.world_transform.origin])
		if edge.route_points.size() == 4:
			points.append_array(edge.route_points)
		points.append(b.world_transform.origin)
		actor.global_position = points[0] + Vector3.UP * player_y
		for index in range(1, points.size()):
			var desired: Vector3 = points[index] + Vector3.UP * player_y
			if not _check(not actor.test_move(actor.global_transform, desired - actor.global_position), "Real capsule cannot walk through offset doorway/route %s, segment %d." % [edge.stable_id, index]):
				return
			actor.global_position = desired
	stage.remove_child(baked)
	var exported := Node3D.new()
	exported.name = "DungeonOffsetExport"
	exported.add_child(baked)
	baked.owner = exported
	_set_owners(baked, exported)
	var packed := PackedScene.new()
	if not _check(packed.pack(exported) == OK, "Native offset dungeon must pack."):
		return
	var destination := "user://dungeon_offset_export.tscn"
	if not _check(ResourceSaver.save(packed, destination) == OK, "Native offset dungeon must save."):
		return
	var loaded := ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(loaded != null, "Native offset dungeon must reload."):
		return
	var restored := loaded.instantiate()
	if not _check(restored.find_children("StructuralShell", "Node3D", true, false).size() > 0 and restored.find_children("*", "CollisionShape3D", true, false).size() == baked.find_children("*", "CollisionShape3D", true, false).size(), "Export must preserve physics and authored prefab shells."):
		return
	restored.free()
	exported.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
	var tampered := fixture.duplicate(true) as LevelLayout
	var changed := false
	for edge in tampered.connections:
		if absf(edge.from_offset) > 0.01:
			edge.from_offset += 0.4
			changed = true
			break
		elif absf(edge.to_offset) > 0.01:
			edge.to_offset += 0.4
			changed = true
			break
	if not _check(changed and not DungeonPlanner.validate_layout(tampered).is_valid() and DungeonSceneCompiler.build(tampered) == null, "Manual edits that misalign structural prefab door sockets must reject bake."):
		return
	var legacy := DungeonConfig.new()
	legacy.seed = 19
	legacy.structural_prefabs = [profile]
	legacy.structural_prefab_chance = 1.0
	var fallback := DungeonPlanner.generate_layout(legacy)
	if not _check(fallback.success, "Offsets disabled configuration must remain generatable."):
		return
	for room in fallback.layout.rooms:
		if not _check(room.structural_prefab == null, "Incompatible asymmetry must safely fall back to procedural rooms when routing is disabled."):
			return
	print("DUNGEON_OFFSET_SOCKET_SMOKE: PASS (35 seeded layouts, off-center physical sockets, runtime/export and safe fallback)")
	quit(0)


func _set_owners(node: Node, target: Node) -> void:
	for child in node.get_children():
		child.owner = target
		_set_owners(child, target)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_OFFSET_SOCKET_SMOKE: FAIL: " + message)
		quit(1)
	return ok
