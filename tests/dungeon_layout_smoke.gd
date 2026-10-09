extends SceneTree
## F2 regression matrix: 300 seeds plus geometry/serialization/invalid-state checks.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cases: Array[Dictionary] = [
		{"size": Vector2i(10, 10), "min": 5, "max": 7, "branches": 3},
		{"size": Vector2i(14, 14), "min": 9, "max": 11, "branches": 7},
		{"size": Vector2i(20, 20), "min": 14, "max": 18, "branches": 12}
	]
	var count: int = 0
	for preset in cases:
		for index in 100:
			var config := DungeonConfig.new()
			config.grid_size = preset["size"]
			config.critical_path_min = preset["min"]
			config.critical_path_max = preset["max"]
			config.branch_count = preset["branches"]
			config.loop_count = 0
			config.seed = index * 101 + 17
			var result := DungeonPlanner.generate_layout(config)
			if not _check(result.success, "Seed %d, preset %s: %s" % [config.seed, str(preset), result.report.summary()]):
				return
			if not _check(result.layout != null and result.layout.rooms.size() >= config.critical_path_min + config.branch_count, "Room count mismatch."):
				return
			var again := DungeonPlanner.generate_layout(config)
			if not _check(again.success and result.layout.fingerprint() == again.layout.fingerprint(), "Seed repetition must yield the identical serialized layout."):
				return
			if not _check(DungeonPlanner.validate_layout(result.layout).is_valid(), "Generated layout must pass validator."):
				return
			count += 1
	print("DUNGEON_LAYOUT_SMOKE: verified %d deterministic seeds" % count)

	var config := DungeonConfig.new()
	config.seed = 822
	config.grid_size = Vector2i(12, 12)
	config.critical_path_min = 8
	config.critical_path_max = 8
	config.branch_count = 8
	config.loop_count = 1
	config.max_attempts = 32
	var result := DungeonPlanner.generate_layout(config)
	if not _check(result.success, "One requested cycle should be constructible: " + result.report.summary()):
		return
	if not _check(result.layout.connections.size() == result.layout.rooms.size(), "A single loop requires exactly N graph edges."):
		return
	var compiled := DungeonSceneCompiler.build(result.layout, true)
	if not _check(compiled != null and compiled.get_child_count() == result.layout.rooms.size(), "All rooms should compile with static geometry."):
		return
	var shape_count: int = compiled.find_children("*", "CollisionShape3D", true, false).size()
	if not _check(shape_count > result.layout.rooms.size() * 5, "Generated walls/floors must include primitive collision."):
		return
	for edge in result.layout.connections:
		var a := compiled.get_node_or_null(NodePath(edge.from_room_id)) as Node3D
		var b := compiled.get_node_or_null(NodePath(edge.to_room_id)) as Node3D
		if not _check(a != null and b != null, "Edge must have two room nodes."):
			return
		var first := a.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		var second := b.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
		if not _check(first != null and second != null, "Every logical edge must have two physical sockets."):
			return
		var a_transform: Transform3D = a.transform * first.transform
		var b_transform: Transform3D = b.transform * second.transform
		if not _check(a_transform.origin.distance_to(b_transform.origin) < 0.001, "Socket centers must coincide: " + edge.stable_id):
			return
		var a_normal: Vector3 = a_transform.basis * Vector3.FORWARD
		var b_normal: Vector3 = b_transform.basis * Vector3.FORWARD
		if not _check(a_normal.dot(b_normal) < -0.999, "Socket normals must face opposite directions."):
			return
	var scene_root := Node3D.new()
	scene_root.name = "StandaloneDungeon"
	scene_root.add_child(compiled)
	compiled.owner = scene_root
	_set_owners(compiled, scene_root)
	var scene := PackedScene.new()
	if not _check(scene.pack(scene_root) == OK, "PackedScene must pack complete dungeon."):
		return
	var path := "user://dungeon_layout_smoke.tscn"
	if not _check(ResourceSaver.save(scene, path) == OK, "PackedScene must save."):
		return
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(saved != null, "Saved dungeon must load without authoring plugin scripts."):
		return
	var reloaded := saved.instantiate()
	if not _check(reloaded.find_children("*", "CollisionShape3D", true, false).size() == shape_count, "Reload must retain static colliders."):
		return
	if not _check(reloaded.find_children("Socket_*", "Marker3D", true, false).size() == 2 * result.layout.connections.size(), "Reload must retain both sockets per edge."):
		return
	reloaded.free()
	scene_root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var invalid := result.layout.duplicate(true) as LevelLayout
	invalid.connections[0].to_wall = invalid.connections[0].from_wall
	if not _check(not DungeonPlanner.validate_layout(invalid).is_valid() and DungeonSceneCompiler.build(invalid) == null, "Nonreciprocal connections must be rejected without publishing scene nodes."):
		return
	var impossible := DungeonConfig.new()
	impossible.grid_size = Vector2i(2, 2)
	impossible.critical_path_min = 5
	impossible.critical_path_max = 5
	if not _check(not DungeonPlanner.generate_layout(impossible).success, "Impossible constraints must return a failure."):
		return
	var author := DungeonAuthoring3D.new()
	author.config = config
	author.generate_new_layout()
	if not _check(author.layout != null, "Editor facade should store a valid layout."):
		return
	var user_child := Node3D.new()
	user_child.name = "DesignerNotes"
	author.add_child(user_child)
	author.preview_layout()
	author.bake()
	var baked := author.get_node_or_null("DungeonBake")
	if not _check(baked != null, "Authoring bake should create static geometry."):
		return
	author.clear_preview()
	if not _check(author.get_node_or_null("DesignerNotes") == user_child and author.get_node_or_null("DungeonBake") != null, "Clearing preview must preserve designer nodes and bake."):
		return
	author.layout = impossible_layout()
	if not _check(author.save_scene() != OK and author.get_node_or_null("DungeonBake") != null, "Invalid layout must not export or destroy a previously good bake."):
		return
	author.free()
	print("DUNGEON_LAYOUT_SMOKE: PASS")
	quit(0)


func impossible_layout() -> LevelLayout:
	var result := LevelLayout.new()
	result.grid_size = Vector2i(1, 1)
	result.room_size = Vector3.ONE
	return result


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_LAYOUT_SMOKE: FAIL: " + message)
		quit(1)
	return ok


func _set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners(child, owner)
