extends SceneTree
## F2.7: full authored StaticBody3D room replacement with strict socket poses,
## exact doorway topology, rotated prefab matching and real capsule collisions.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var prefab := load("res://examples/dungeon_structural_straight_profile.tres") as DungeonStructuralPrefab
	if not _check(prefab != null and prefab.validate().is_valid(), "Example structural room must validate: " + (prefab.validate().summary() if prefab != null else "missing")):
		return
	if not _check(prefab.compatible_rotations([RoomOpening.Wall.FRONT, RoomOpening.Wall.BACK], Vector3(8, 3.5, 8), 1.6, 2.3).size() == 2, "The straight prefab should fit exactly two orientations for opposite doors."):
		return
	if not _check(prefab.compatible_rotations([RoomOpening.Wall.FRONT], Vector3(8, 3.5, 8), 1.6, 2.3).is_empty(), "No unused, unpaired doorway is permitted."):
		return
	if not _check(prefab.compatible_rotations([RoomOpening.Wall.FRONT, RoomOpening.Wall.BACK], Vector3(7, 3.5, 8), 1.6, 2.3).is_empty(), "Collidable prefab must not silently scale to another size."):
		return
	var invalid_room := prefab.packed_room.instantiate() as Node3D
	(invalid_room.get_node("SocketFront") as Marker3D).position.x += 0.4
	_take_ownership(invalid_room, invalid_room)
	var invalid_packed := PackedScene.new()
	if not _check(invalid_packed.pack(invalid_room) == OK, "Need an editable malformed fixture."):
		return
	invalid_room.free()
	var broken := DungeonStructuralPrefab.new()
	broken.stable_id = "broken_socket"
	broken.packed_room = invalid_packed
	if not _check(not broken.validate().is_valid(), "Off-center structural doorway markers must be rejected."):
		return
	var unsealed_room := prefab.packed_room.instantiate() as Node3D
	var wall_collider := unsealed_room.get_node("RoomPhysics/Collision_WallLeft")
	unsealed_room.get_node("RoomPhysics").remove_child(wall_collider)
	wall_collider.free()
	_take_ownership(unsealed_room, unsealed_room)
	var unsafe_scene := PackedScene.new()
	if not _check(unsafe_scene.pack(unsealed_room) == OK, "Need a doorway without an authored socket for rejection."):
		return
	unsealed_room.free()
	var unsafe_profile := DungeonStructuralPrefab.new()
	unsafe_profile.stable_id = "unsealed_side"
	unsafe_profile.packed_room = unsafe_scene
	if not _check(not unsafe_profile.validate().is_valid(), "An accidental, unpaired exterior opening cannot pass collision validation."):
		return

	var corner := load("res://examples/dungeon_structural_corner_profile.tres") as DungeonStructuralPrefab
	if not _check(corner != null and corner.validate().is_valid(), "Corner structural room must have two turned-out physical socket markers: " + (corner.validate().summary() if corner != null else "resource missing")):
		return
	if not _check(corner.compatible_rotations([RoomOpening.Wall.FRONT, RoomOpening.Wall.RIGHT], Vector3(8, 3.5, 8), 1.6, 2.3).size() == 1, "Corner prefab must admit its unique matching cardinal rotation."):
		return
	var example_preset := load("res://examples/dungeon_structural_preset.tres") as DungeonConfig
	if not _check(example_preset != null and example_preset.structural_prefabs.size() == 2 and DungeonPlanner.validate_config(example_preset).is_valid(), "Single-scene structural preset should import both real collision prefab profiles."):
		return
	var author_scene := load("res://examples/dungeon_authoring.tscn") as PackedScene
	var author := author_scene.instantiate() as DungeonAuthoring3D
	author.config = example_preset
	author.generate_new_layout()
	if not _check(author.layout != null and author.get_node_or_null("DungeonPreview") != null, "Authoring example must accept the structural preset without a duplicate demo scene."):
		return
	var structural_example_count: int = 0
	for room in author.layout.rooms:
		if room.structural_prefab != null:
			structural_example_count += 1
	if not _check(structural_example_count > 0, "Structural example must generate real authored room shells."):
		return
	author.bake()
	if not _check(author.get_node_or_null("DungeonBake") != null and author.get_node_or_null("DungeonPreview") == null, "Structural example must support normal editor bake lifecycle."):
		return
	author.free()

	var config := DungeonConfig.new()
	config.grid_size = Vector2i(14, 14)
	config.critical_path_min = 8
	config.critical_path_max = 10
	config.branch_count = 5
	config.loop_count = 0
	config.max_attempts = 20
	config.rectangle_weight = 10
	config.cross_weight = 0
	config.l_shape_weight = 0
	config.t_shape_weight = 0
	config.generate_exterior_doors = false
	config.structural_prefabs = [prefab, corner]
	config.structural_prefab_chance = 1.0
	var total: int = 0
	var profiles: Dictionary = {}
	var rotations: Dictionary = {}
	var fixture: LevelLayout
	for seed_offset in 34:
		config.seed = 25000 + seed_offset
		var build := DungeonPlanner.generate_layout(config)
		if not _check(build.success, "Structural layout seed %d failed: %s" % [config.seed, build.report.summary()]):
			return
		var rerun := DungeonPlanner.generate_layout(config)
		if not _check(rerun.success and build.layout.fingerprint() == rerun.layout.fingerprint(), "Structural module selection and rotation must be deterministic."):
			return
		for room in build.layout.rooms:
			var openings := DungeonPlanner.make_blueprint(build.layout, room).openings
			if room.structural_prefab != null:
				if not _check((room.structural_prefab == prefab or room.structural_prefab == corner) and room.module_profile == null and openings.size() == 2, "A full room must only use an exact two-door prefab."):
					return
				profiles[room.structural_prefab.stable_id] = int(profiles.get(room.structural_prefab.stable_id, 0)) + 1
				rotations[room.structural_turns] = true
				total += 1
		fixture = build.layout
	if not _check(total > 20 and rotations.size() >= 2 and profiles.has(prefab.stable_id) and profiles.has(corner.stable_id), "Real layouts should use both structural geometries in multiple quarter-turn orientations."):
		return
	print("DUNGEON_STRUCTURAL_SMOKE: 34 seeded dungeons, %d valid structural placements" % total)
	var preview := DungeonSceneCompiler.build(fixture, false)
	if not _check(preview != null, "The mixed authored/procedural preview must compile."):
		return
	for room in fixture.rooms:
		if room.structural_prefab == null:
			continue
		var root_room := preview.get_node_or_null(NodePath(room.stable_id)) as Node3D
		if not _check(root_room != null and root_room.get_node_or_null("StructuralShell") != null, "Structurally authored rooms must replace the procedural shell."):
			return
		if not _check(root_room.find_children("*", "CollisionShape3D", true, false).is_empty(), "Editor preview must not retain runtime physics."):
			return
	preview.free()
	var baked := DungeonSceneCompiler.build(fixture, true)
	if not _check(baked != null, "Compiled prefab rooms must support real physics."):
		return
	var by_id: Dictionary = {}
	for room in fixture.rooms:
		by_id[room.stable_id] = room
	var collision_total: int = baked.find_children("*", "CollisionShape3D", true, false).size()
	for room in fixture.rooms:
		if room.structural_prefab == null:
			continue
		var room_node := baked.get_node_or_null(NodePath(room.stable_id)) as Node3D
		var shell := room_node.get_node_or_null("StructuralShell") as Node3D
		if not _check(shell != null and shell.find_children("*", "CollisionShape3D", true, false).size() == 10, "Full prefab owns its ten physical BoxShape3D surfaces."):
			return
		for opening in DungeonPlanner.make_blueprint(fixture, room).openings:
			var paired := room_node.get_node_or_null(NodePath("Socket_" + opening.stable_id)) as Marker3D
			if not _check(paired != null and paired.get_meta("wall", -1) == opening.wall, "Authored prefab must expose the graph's exact reciprocal socket IDs."):
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
	var y: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		actor.global_position = a.world_transform.origin + Vector3.UP * y
		if not _check(not actor.test_move(actor.global_transform, b.world_transform.origin + Vector3.UP * y - actor.global_position), "Capsule blocked between structural/procedural rooms on %s" % edge.stable_id):
			return
	stage.remove_child(baked)
	var exported := Node3D.new()
	exported.add_child(baked)
	baked.owner = exported
	_take_ownership(baked, exported)
	var scene := PackedScene.new()
	if not _check(scene.pack(exported) == OK, "Structural room collisions must pack as standalone engine geometry."):
		return
	var destination := "user://room_creator_structural_smoke.tscn"
	if not _check(ResourceSaver.save(scene, destination) == OK, "Standalone structural rooms must save."):
		return
	var restored_pack := ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(restored_pack != null, "Standalone structural rooms must reopen."):
		return
	var restored := restored_pack.instantiate()
	if not _check(restored.find_children("StructuralShell", "Node3D", true, false).size() > 0 and restored.find_children("*", "CollisionShape3D", true, false).size() == collision_total, "Reopened export must preserve authored static colliders and prefab shells."):
		return
	restored.free()
	exported.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
	var altered := fixture.duplicate(true) as LevelLayout
	var modified := false
	for room in altered.rooms:
		if room.structural_prefab == null:
			continue
		room.structural_turns = (room.structural_turns + 1) % 4
		modified = true
		break
	if not _check(modified and not DungeonPlanner.validate_layout(altered).is_valid() and DungeonSceneCompiler.build(altered) == null, "Invalidly rotated structural sockets must fail layout validation."):
		return
	var bad_config := DungeonConfig.new()
	bad_config.structural_prefabs = [broken]
	if not _check(not DungeonPlanner.generate_layout(bad_config).success, "Malformed full room prefab must reject generation, not fall back silently."):
		return
	print("DUNGEON_STRUCTURAL_SMOKE: PASS (34 seeds, straight + corner static prefabs, no unpaired holes, physics and export)")
	quit(0)


func _take_ownership(node: Node, target: Node) -> void:
	for child in node.get_children():
		child.owner = target
		_take_ownership(child, target)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_STRUCTURAL_SMOKE: FAIL: " + message)
		quit(1)
	return ok
