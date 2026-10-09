extends SceneTree
## Real PhysicsServer3D capsule sweep through every generated connection.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.seed = 822
	config.critical_path_min = 8
	config.critical_path_max = 8
	config.branch_count = 8
	config.loop_count = 1
	config.max_attempts = 32
	var result := DungeonPlanner.generate_layout(config)
	if not result.success:
		push_error("DUNGEON_CAPSULE_SMOKE: generation failed: " + result.report.summary())
		quit(1)
		return
	var dungeon := DungeonSceneCompiler.build(result.layout, true)
	if dungeon == null:
		push_error("DUNGEON_CAPSULE_SMOKE: static dungeon compilation failed.")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(dungeon)
	var player := CharacterBody3D.new()
	player.name = "ReferencePlayerCapsule"
	player.collision_layer = 2
	player.collision_mask = 1
	player.safe_margin = 0.001
	var player_collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = config.player_radius
	capsule.height = config.player_height
	player_collider.shape = capsule
	player.add_child(player_collider)
	stage.add_child(player)
	# Ensure the PhysicsServer has registered every StaticBody3D in the fresh scene.
	await physics_frame
	await physics_frame
	var by_id: Dictionary = {}
	for room in result.layout.rooms:
		by_id[room.stable_id] = room
	for edge in result.layout.connections:
		var from_room: RoomPlacementData = by_id[edge.from_room_id]
		var to_room: RoomPlacementData = by_id[edge.to_room_id]
		var start: Vector3 = from_room.world_transform.origin + Vector3(0.0, config.player_height * 0.5 + 0.08, 0.0)
		var finish: Vector3 = to_room.world_transform.origin + Vector3(0.0, config.player_height * 0.5 + 0.08, 0.0)
		player.global_position = start
		var hit := player.test_move(player.global_transform, finish - start)
		if hit:
			push_error("DUNGEON_CAPSULE_SMOKE: capsule collides crossing %s between %s and %s" % [edge.stable_id, edge.from_room_id, edge.to_room_id])
			stage.free()
			quit(1)
			return
	stage.free()
	print("DUNGEON_CAPSULE_SMOKE: PASS (%d walkable edges)" % result.layout.connections.size())
	quit(0)
