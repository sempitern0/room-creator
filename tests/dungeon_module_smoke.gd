extends SceneTree
## F2.3 socket-aware decorative module profiles: replay, validation and packing.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var module_profile := load("res://examples/dungeon_room_module_profile.tres") as DungeonRoomModule
	if not _check(module_profile != null and module_profile.validate().is_valid(), "Bundled module must be a valid script-free normalized socket prefab."):
		return
	var config := DungeonConfig.new()
	config.seed = 891
	config.grid_size = Vector2i(12, 12)
	config.critical_path_min = 7
	config.critical_path_max = 9
	config.branch_count = 5
	config.rectangle_weight = 10
	config.cross_weight = 0
	config.l_shape_weight = 0
	config.t_shape_weight = 0
	config.vary_room_sizes = true
	config.room_modules = [module_profile]
	config.require_room_modules = true
	var build := DungeonPlanner.generate_layout(config)
	if not _check(build.success, "Required prefabs should match socket graph: " + build.report.summary()):
		return
	for room in build.layout.rooms:
		if not _check(room.module_profile == module_profile, "Every rect room must use the required module."):
			return
	var replay := DungeonPlanner.generate_layout(config)
	if not _check(replay.success and build.layout.fingerprint() == replay.layout.fingerprint(), "Prefab selection must be deterministic."):
		return
	var geometry := DungeonSceneCompiler.build(build.layout, true)
	if not _check(geometry != null, "Prefab modules must compile with the certified static shell."):
		return
	for room in build.layout.rooms:
		var root_room := geometry.get_node_or_null(NodePath(room.stable_id)) as Node3D
		var decor := root_room.get_node_or_null("ModuleDecor") as Node3D
		if not _check(decor != null and decor.get_meta("module_id", "") == module_profile.stable_id, "Each authored room should have its visual module instance."):
			return
		for edge in build.layout.connections:
			var wall: int = -1
			if edge.from_room_id == room.stable_id:
				wall = edge.from_wall
			elif edge.to_room_id == room.stable_id:
				wall = edge.to_wall
			if wall < 0:
				continue
			var marker_name := ""
			for canonical in DungeonRoomModule.SIDES:
				if DungeonRoomModule.rotated_wall(canonical, room.shape_rotation) == wall:
					marker_name = DungeonRoomModule.MARKERS[DungeonRoomModule.SIDES.find(canonical)]
					break
			var module_socket := decor.get_node_or_null(NodePath(marker_name)) as Marker3D
			var physical_socket := root_room.get_node_or_null(NodePath("Socket_" + edge.stable_id)) as Marker3D
			var module_location: Vector3 = decor.transform * module_socket.position
			if not _check(module_location.distance_to(physical_socket.position) < 0.001, "Authored marker and physical door socket must coincide after normalized scaling and quarter rotation."):
				return
	var stage := Node3D.new()
	stage.add_child(geometry)
	geometry.owner = stage
	_owners(geometry, stage)
	var packed := PackedScene.new()
	if not _check(packed.pack(stage) == OK, "Custom module geometry must pack."):
		return
	var save_path := "user://room_prefab_smoke.tscn"
	if not _check(ResourceSaver.save(packed, save_path) == OK, "Custom module scene must save."):
		return
	var imported := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(imported != null, "Saved module scene must reload."):
		return
	var restored := imported.instantiate()
	if not _check(restored.find_children("ModuleDecor", "Node3D", true, false).size() == build.layout.rooms.size(), "Visual prefab instances must survive export."):
		return
	restored.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var invalid_scene := PackedScene.new()
	var missing := Node3D.new()
	missing.name = "NoSockets"
	invalid_scene.pack(missing)
	missing.free()
	var broken := DungeonRoomModule.new()
	broken.stable_id = "invalid"
	broken.visual_scene = invalid_scene
	if not _check(not broken.validate().is_valid(), "A prefab without any socket marker must be rejected."):
		return
	var blocked := DungeonConfig.new()
	blocked.room_modules = [broken]
	blocked.require_room_modules = true
	if not _check(not DungeonPlanner.generate_layout(blocked).success, "Invalid module must not produce an exported layout."):
		return
	print("DUNGEON_MODULE_SMOKE: PASS (socket-aware module selection, placement, export and validation)")
	quit(0)


func _owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_owners(child, owner)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_MODULE_SMOKE: FAIL: " + message)
		quit(1)
	return ok
