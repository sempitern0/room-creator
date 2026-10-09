@tool
class_name DungeonConnectorBuilder
extends RefCounted
## An engine-native roofed corridor spans exactly the free distance between
## differently sized rooms. Both ends terminate at reciprocal door sockets.
## It never mutates RoomPlacementData or the authored configuration.

const EPS := 0.0001

static func build(layout: LevelLayout, edge: RoomConnectionData, from_room: RoomPlacementData, to_room: RoomPlacementData, collisions: bool = true) -> Node3D:
	var size_a: Vector3 = DungeonPlanner.actual_size(layout, from_room)
	var size_b: Vector3 = DungeonPlanner.actual_size(layout, to_room)
	var delta: Vector3 = to_room.world_transform.origin - from_room.world_transform.origin
	var along_x: bool = absf(delta.x) > absf(delta.z)
	var sign_dir: float = signf(delta.x if along_x else delta.z)
	var step: float = absf(delta.x if along_x else delta.z)
	var extent_a: float = size_a.x if along_x else size_a.z
	var extent_b: float = size_b.x if along_x else size_b.z
	var gap: float = step - extent_a * 0.5 - extent_b * 0.5
	if gap <= EPS:
		return null
	var face_a: Vector3 = from_room.world_transform.origin
	var face_b: Vector3 = to_room.world_transform.origin
	if along_x:
		face_a.x += sign_dir * extent_a * 0.5
		face_b.x -= sign_dir * extent_b * 0.5
	else:
		face_a.z += sign_dir * extent_a * 0.5
		face_b.z -= sign_dir * extent_b * 0.5
	var center: Vector3 = (face_a + face_b) * 0.5
	var width: float = edge.clear_width + layout.wall_thickness * 2.0
	var hallway := Node3D.new()
	hallway.name = "Connector_" + edge.stable_id.validate_node_name()
	hallway.position = center
	hallway.set_meta("connection_id", edge.stable_id)
	hallway.set_meta("from_room_id", edge.from_room_id)
	hallway.set_meta("to_room_id", edge.to_room_id)
	var floor_extent := Vector3(gap, layout.floor_thickness, width) if along_x else Vector3(width, layout.floor_thickness, gap)
	_add_box(hallway, "Floor", Vector3(0.0, -layout.floor_thickness * 0.5, 0.0), floor_extent, layout.floor_material, layout, collisions)
	if layout.include_ceiling:
		_add_box(hallway, "Ceiling", Vector3(0.0, layout.room_size.y + layout.ceiling_thickness * 0.5, 0.0),
			Vector3(gap, layout.ceiling_thickness, width) if along_x else Vector3(width, layout.ceiling_thickness, gap), layout.ceiling_material, layout, collisions)
	for direction in [-1, 1]:
		var pos: Vector3 = Vector3.ZERO
		if along_x:
			pos.z = float(direction) * (edge.clear_width + layout.wall_thickness) * 0.5
		else:
			pos.x = float(direction) * (edge.clear_width + layout.wall_thickness) * 0.5
		pos.y = layout.room_size.y * 0.5
		var dims := Vector3(gap, layout.room_size.y, layout.wall_thickness) if along_x else Vector3(layout.wall_thickness, layout.room_size.y, gap)
		_add_box(hallway, "SideWall_%d" % direction, pos, dims, layout.wall_material, layout, collisions)
	return hallway


static func _add_box(root: Node3D, label: String, pos: Vector3, size: Vector3, material: Material, layout: LevelLayout, collisions: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.position = pos
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	root.add_child(mesh)
	if collisions:
		var body := StaticBody3D.new()
		body.name = "StaticBody"
		body.collision_layer = layout.collision_layer
		body.collision_mask = layout.collision_mask
		mesh.add_child(body)
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		var primitive := BoxShape3D.new()
		primitive.size = size
		shape.shape = primitive
		body.add_child(shape)
