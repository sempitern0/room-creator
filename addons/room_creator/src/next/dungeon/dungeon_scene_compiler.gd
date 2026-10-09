@tool
class_name DungeonSceneCompiler
extends RefCounted
## Compiles a validated LevelLayout to engine-native nodes; never mutates layout.

static func build(layout: LevelLayout, with_collisions: bool = true) -> Node3D:
	if not DungeonPlanner.validate_layout(layout).is_valid():
		return null
	var root := Node3D.new()
	root.name = "DungeonGeometry"
	root.set_meta("room_creator_generated", true)
	root.set_meta("layout_fingerprint", layout.fingerprint())
	root.set_meta("layout_seed", layout.seed)
	root.set_meta("entrance_id", layout.entrance_id)
	root.set_meta("exit_id", layout.exit_id)
	var by_id: Dictionary = {}
	for room in layout.rooms:
		by_id[room.stable_id] = room
	for room in layout.rooms:
		var blueprint := DungeonPlanner.make_blueprint(layout, room)
		var room_root := RoomGeometryBuilder.build(blueprint, with_collisions)
		if room_root == null:
			root.free()
			return null
		room_root.name = room.stable_id
		room_root.transform = room.world_transform
		room_root.set_meta("stable_id", room.stable_id)
		room_root.set_meta("role", room.role)
		if room.module_profile != null:
			var art := room.module_profile.visual_scene.instantiate() as Node3D
			if art == null:
				root.free()
				return null
			art.name = "ModuleDecor"
			# Normalized art is scaled to the actual room extent. Rotations are
			# quarter turns matching the chosen silhouette orientation.
			var size: Vector3 = DungeonPlanner.actual_size(layout, room)
			var turns: int = room.shape_rotation
			art.rotation.y = -float(turns) * PI * 0.5
			art.scale = Vector3(size.z, size.y, size.x) if turns % 2 == 1 else size
			art.set_meta("module_id", room.module_profile.stable_id)
			room_root.add_child(art)
		root.add_child(room_root)
	for edge in layout.connections:
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var corridor := DungeonConnectorBuilder.build(layout, edge, a, b, with_collisions)
		if corridor != null:
			root.add_child(corridor)
	return root
