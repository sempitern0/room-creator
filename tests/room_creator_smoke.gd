extends SceneTree
## Run after import: godot --headless --path . --script res://tests/room_creator_smoke.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := RoomBlueprint.new()
	source.room_size = Vector3(8.0, 3.5, 8.0)
	var first := RoomOpening.new()
	first.stable_id = "front_door"
	first.wall = RoomOpening.Wall.FRONT
	first.offset = -2.0
	var second := RoomOpening.new()
	second.stable_id = "front_door_2"
	second.wall = RoomOpening.Wall.FRONT
	second.offset = 2.0
	var window := RoomOpening.new()
	window.stable_id = "side_window"
	window.kind = RoomOpening.Kind.WINDOW
	window.wall = RoomOpening.Wall.RIGHT
	window.sill_height = 1.0
	window.height = 1.2
	source.openings = [first, second, window]
	var report := RoomGeometryBuilder.validate(source)
	if not _check(report.is_valid(), report.summary()):
		return
	var geometry := RoomGeometryBuilder.build(source, true)
	if not _check(geometry != null, "Valid rooms must compile."):
		return
	var meshes := geometry.find_children("*", "MeshInstance3D", true, false)
	var bodies := geometry.find_children("*", "StaticBody3D", true, false)
	var sockets := geometry.find_children("Socket_*", "Marker3D", true, false)
	if not _check(meshes.size() > 8 and bodies.size() == meshes.size(), "Static boxes must all have their own primitive colliders."):
		return
	if not _check(sockets.size() == 2, "Only walkable openings expose sockets."):
		return
	for visual in meshes:
		if not visual.name.begins_with("Wall_0"):
			continue
		var mesh := visual as MeshInstance3D
		if absf(mesh.position.y - 1.1) < 1.1 and absf(mesh.position.x + 2.0) < 0.65:
			if not _check(false, "Front wall geometry obstructs the first door."):
				return
		if absf(mesh.position.y - 1.1) < 1.1 and absf(mesh.position.x - 2.0) < 0.65:
			if not _check(false, "Front wall geometry obstructs the second door."):
				return
	var demo := load("res://examples/single_room_door.tscn") as PackedScene
	if not _check(demo != null, "Bundled manual-room example must load."):
		return
	var demo_root := demo.instantiate() as RoomAuthoring3D
	if not _check(demo_root != null and demo_root.blueprint != null and RoomGeometryBuilder.validate(demo_root.blueprint).is_valid(), "Example must have a valid editable blueprint."):
		return
	demo_root.free()
	var authored := RoomAuthoring3D.new()
	authored.blueprint = source
	var untouched := Node3D.new()
	untouched.name = "KeepMe"
	authored.add_child(untouched)
	authored.generate_preview()
	authored.bake()
	authored.clear_preview()
	if not _check(untouched.get_parent() == authored and authored.get_node_or_null("RoomCreatorBake") != null, "Generated cleanup must preserve user nodes and baked output."):
		return
	var invalid := source.duplicate(true) as RoomBlueprint
	invalid.room_size = Vector3(-1.0, 3.0, 8.0)
	if not _check(not RoomGeometryBuilder.validate(invalid).is_valid() and RoomGeometryBuilder.build(invalid) == null, "Invalid sizes must not produce nodes."):
		return
	invalid = source.duplicate(true) as RoomBlueprint
	invalid.openings[1].offset = invalid.openings[0].offset
	if not _check(not RoomGeometryBuilder.validate(invalid).is_valid(), "Overlapping openings must be rejected."):
		return
	if not _check(source.openings[1].offset == 2.0, "Duplicating a blueprint must isolate its opening subresources."):
		return
	var standalone := Node3D.new()
	standalone.name = "StandaloneRoom"
	standalone.add_child(geometry)
	geometry.owner = standalone
	_set_owners(geometry, standalone)
	var scene := PackedScene.new()
	if not _check(scene.pack(standalone) == OK, "Standalone scene must pack."):
		return
	var path := "user://room_creator_smoke.tscn"
	if not _check(ResourceSaver.save(scene, path) == OK, "Standalone scene must save."):
		return
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reloaded != null, "Saved scene must reload."):
		return
	var instance := reloaded.instantiate()
	if not _check(instance.find_children("*", "CollisionShape3D", true, false).size() == meshes.size(), "Round-trip must preserve all primitive collisions."):
		return
	if not _check(instance.find_children("Socket_*", "Marker3D", true, false).size() == 2, "Round-trip must preserve connection markers."):
		return
	instance.free()
	standalone.free()
	authored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("ROOM_CREATOR_SMOKE: PASS")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("ROOM_CREATOR_SMOKE: FAIL: " + message)
		quit(1)
	return condition


func _set_owners(parent: Node, owner: Node) -> void:
	for child in parent.get_children():
		child.owner = owner
		_set_owners(child, owner)
