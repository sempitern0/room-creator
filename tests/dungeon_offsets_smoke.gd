extends SceneTree
## F2.5 deterministic independent room offsets. The placement solver is bounded,
## accepts only coaxial sockets and rejects colliding rooms and side corridors.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := DungeonConfig.new()
	cfg.grid_size = Vector2i(14, 14)
	cfg.critical_path_min = 8
	cfg.critical_path_max = 11
	cfg.branch_count = 8
	cfg.loop_count = 1
	cfg.max_attempts = 32
	cfg.rectangle_weight = 4
	cfg.cross_weight = 8
	cfg.l_shape_weight = 7
	cfg.t_shape_weight = 7
	cfg.vary_room_sizes = true
	cfg.min_room_scale = 0.80
	cfg.max_room_scale = 0.95
	cfg.use_variable_grid_spacing = true
	cfg.min_corridor_gap = 2.0
	cfg.max_corridor_gap = 4.0
	cfg.enable_independent_room_offsets = true
	cfg.room_position_jitter = 0.75
	cfg.placement_attempts = 32
	var changed: int = 0
	var independent: bool = false
	var fixture: LevelLayout
	for i in 45:
		cfg.seed = 18300 + i
		var result := DungeonPlanner.generate_layout(cfg)
		if not _check(result.success, "Offset seed %d failed: %s" % [cfg.seed, result.report.summary()]):
			return
		var layout := result.layout
		var repeat := DungeonPlanner.generate_layout(cfg)
		if not _check(repeat.success and repeat.layout.fingerprint() == layout.fingerprint(), "The same seed must produce the same per-room world coordinates."):
			return
		if not _check(layout.independent_room_offsets_enabled and layout.maximum_room_offset == cfg.room_position_jitter and DungeonPlanner.validate_layout(layout).is_valid(), "Persisted offset contract must validate without DungeonConfig."):
			return
		for room in layout.rooms:
			var origin: Vector3 = DungeonSpatialEmbedder.expected_origin(layout, room.cell)
			var displacement: Vector3 = room.world_transform.origin - origin
			if not _check(absf(displacement.x) <= cfg.room_position_jitter + 0.001 and absf(displacement.z) <= cfg.room_position_jitter + 0.001, "Displacement must not exceed the solver bound."):
				return
			if displacement.length() > 0.08:
				changed += 1
		for a in layout.rooms:
			for b in layout.rooms:
				if a == b:
					continue
				var pa: Vector3 = a.world_transform.origin - DungeonSpatialEmbedder.expected_origin(layout, a.cell)
				var pb: Vector3 = b.world_transform.origin - DungeonSpatialEmbedder.expected_origin(layout, b.cell)
				if a.cell.x == b.cell.x and absf(pa.x - pb.x) > 0.10:
					independent = true
		fixture = layout
	if not _check(changed > 80 and independent, "Generated rooms must actually move independently, not merely shift every grid column together."):
		return
	print("DUNGEON_OFFSETS_SMOKE: validated 45 seeded independent room placements")
	var dungeon := DungeonSceneCompiler.build(fixture, true)
	if not _check(dungeon != null, "A valid independently offset dungeon must bake."):
		return
	var by_id: Dictionary = {}
	for room in fixture.rooms:
		by_id[room.stable_id] = room
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(dungeon)
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.safe_margin = 0.001
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = fixture.player_radius
	capsule.height = fixture.player_height
	collision.shape = capsule
	body.add_child(collision)
	stage.add_child(body)
	await physics_frame
	await physics_frame
	var height: float = fixture.player_height * 0.5 + 0.08
	for edge in fixture.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var offset: Vector3 = b.world_transform.origin - a.world_transform.origin
		if edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.RIGHT:
			if not _check(absf(offset.z) < 0.001, "Horizontal edge requires shared Z center."):
				return
		else:
			if not _check(absf(offset.x) < 0.001, "Vertical edge requires shared X center."):
				return
		body.global_position = a.world_transform.origin + Vector3.UP * height
		if not _check(not body.test_move(body.global_transform, b.world_transform.origin + Vector3.UP * height - body.global_position), "Capsule blocked at independent connector %s." % edge.stable_id):
			return
	stage.free()
	var shifted := fixture.duplicate(true) as LevelLayout
	var broken_edge := shifted.connections[0]
	var target_id: String = broken_edge.to_room_id
	for room in shifted.rooms:
		if room.stable_id == target_id:
			room.world_transform.origin.z += 0.3 if broken_edge.from_wall == RoomOpening.Wall.RIGHT or broken_edge.from_wall == RoomOpening.Wall.LEFT else 0.0
			room.world_transform.origin.x += 0.3 if broken_edge.from_wall == RoomOpening.Wall.FRONT or broken_edge.from_wall == RoomOpening.Wall.BACK else 0.0
			break
	if not _check(not DungeonPlanner.validate_layout(shifted).is_valid() and DungeonSceneCompiler.build(shifted) == null, "Misaligned socket offsets must be rejected before geometry compilation."):
		return
	var out_of_bounds := fixture.duplicate(true) as LevelLayout
	out_of_bounds.rooms[0].world_transform.origin += Vector3(cfg.room_position_jitter + 1.0, 0.0, 0.0)
	if not _check(not DungeonPlanner.validate_layout(out_of_bounds).is_valid(), "Over-limit room edits must never pass validation."):
		return
	var disabled := DungeonConfig.new()
	disabled.seed = 901
	var legacy := DungeonPlanner.generate_layout(disabled)
	if not _check(legacy.success and not legacy.layout.independent_room_offsets_enabled and legacy.layout.maximum_room_offset == 0.0, "Legacy room transforms must remain unmodified by default."):
		return
	print("DUNGEON_OFFSETS_SMOKE: PASS (45 seeds, socket alignment, real capsule traversal, invalid pose rejection)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_OFFSETS_SMOKE: FAIL: " + message)
		quit(1)
	return ok
