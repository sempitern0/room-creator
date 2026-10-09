@tool
class_name DungeonStructuralRoomBuilder
extends RefCounted
## Compile a validated complete authored room in place of the procedural shell.
## The wrapper preserves the SAME Socket_<stable edge ID> contract used by
## the straight/dogleg corridor builder and by export/physics tests.

static func build(room: RoomPlacementData, blueprint: RoomBlueprint, with_collisions: bool = true) -> Node3D:
	var profile := room.structural_prefab
	if profile == null or not profile.validate().is_valid():
		return null
	var shell := profile.packed_room.instantiate() as Node3D
	if shell == null:
		return null
	shell.scene_file_path = ""  # Flatten nested PackedScene ownership.
	shell.name = "StructuralShell"
	shell.rotation.y = -float(room.structural_turns) * PI * 0.5
	shell.set_meta("structural_prefab_id", profile.stable_id)
	shell.set_meta("quarter_turns", room.structural_turns)
	var wrapper := Node3D.new()
	wrapper.name = room.stable_id
	wrapper.add_child(shell)
	if with_collisions:
		_configure_static_bodies(shell, blueprint)
	else:
		_remove_preview_collision(shell)
	for opening in blueprint.openings:
		# The true authored marker is located on the rotated prefab shell.
		# Check it against the geometry-builder's expected portal pose.
		var authored_side := _inverse_wall(opening.wall, room.structural_turns)
		var authored_name: String = DungeonStructuralPrefab.SOCKET_NAMES[DungeonStructuralPrefab.WALL_SIDES.find(authored_side)]
		var authored_socket := shell.get_node_or_null(NodePath(authored_name)) as Marker3D
		if authored_socket == null:
			wrapper.free()
			return null
		RoomGeometryBuilder._add_socket(wrapper, blueprint, opening)
		var paired_socket := wrapper.get_node_or_null(NodePath("Socket_" + opening.stable_id.validate_node_name())) as Marker3D
		if paired_socket == null:
			wrapper.free()
			return null
		var expected: Transform3D = paired_socket.transform
		var got: Transform3D = shell.transform * authored_socket.transform
		if got.origin.distance_to(expected.origin) > 0.005 or (got.basis * Vector3.FORWARD).distance_to(expected.basis * Vector3.FORWARD) > 0.005:
			wrapper.free()
			return null
	return wrapper


static func _inverse_wall(side: int, turns: int) -> int:
	var index: int = DungeonStructuralPrefab.WALL_SIDES.find(side)
	return DungeonStructuralPrefab.WALL_SIDES[posmod(index - turns, 4)] if index >= 0 else -1


static func _configure_static_bodies(node: Node, blueprint: RoomBlueprint) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			child.collision_layer = blueprint.collision_layer
			child.collision_mask = blueprint.collision_mask
		_configure_static_bodies(child, blueprint)


static func _remove_preview_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			node.remove_child(child)
			child.free()
		else:
			_remove_preview_collision(child)
