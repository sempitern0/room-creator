@tool
class_name DungeonConnectorBuilder
extends RefCounted
## An engine-native roofed corridor spans exactly the free distance between
## differently sized rooms. Both ends terminate at reciprocal door sockets.
## It never mutates RoomPlacementData or the authored configuration.

const EPS := 0.0001

static func build(layout: LevelLayout, edge: RoomConnectionData, from_room: RoomPlacementData, to_room: RoomPlacementData, collisions: bool = true) -> Node3D:
	if not edge.route_points.is_empty():
		return _build_dogleg(layout, edge, collisions)
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


## Build the exact union of the 3-legged corridor's rectilinear envelope.
## Partitioning at every rectangle boundary creates disjoint floor/roof tiles
## and exposed outer walls only. In particular, no wall cuts across an elbow.
static func _build_dogleg(layout: LevelLayout, edge: RoomConnectionData, collisions: bool) -> Node3D:
	var rects := DungeonCorridorRouter.rectangles(layout, edge, edge.route_points)
	if rects.is_empty():
		return null
	var corridor := Node3D.new()
	corridor.name = "Connector_" + edge.stable_id.validate_node_name()
	corridor.position = (edge.route_points[0] + edge.route_points[3]) * 0.5
	corridor.set_meta("connection_id", edge.stable_id)
	corridor.set_meta("from_room_id", edge.from_room_id)
	corridor.set_meta("to_room_id", edge.to_room_id)
	corridor.set_meta("route_points", edge.route_points)
	var xs: Array[float] = []
	var zs: Array[float] = []
	for rect in rects:
		var center: Vector3 = rect["center"]
		var half: Vector2 = rect["half"]
		_add_unique(xs, center.x - half.x)
		_add_unique(xs, center.x + half.x)
		_add_unique(zs, center.z - half.y)
		_add_unique(zs, center.z + half.y)
	xs.sort()
	zs.sort()
	var horizontal: bool = edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.RIGHT
	for xi in range(xs.size() - 1):
		for zi in range(zs.size() - 1):
			var left: float = xs[xi]
			var right: float = xs[xi + 1]
			var front: float = zs[zi]
			var back: float = zs[zi + 1]
			if right - left <= 0.001 or back - front <= 0.001:
				continue
			var midpoint := Vector3((left + right) * 0.5, 0.0, (front + back) * 0.5)
			if not _occupied(midpoint, rects):
				continue
			var dims := Vector3(right - left, layout.floor_thickness, back - front)
			var local: Vector3 = midpoint - corridor.position
			_add_box(corridor, "RouteFloor_%d_%d" % [xi, zi], local + Vector3.DOWN * layout.floor_thickness * 0.5, dims, layout.floor_material, layout, collisions)
			if layout.include_ceiling:
				_add_box(corridor, "RouteCeiling_%d_%d" % [xi, zi],
					local + Vector3.UP * (layout.room_size.y + layout.ceiling_thickness * 0.5),
					Vector3(dims.x, layout.ceiling_thickness, dims.z), layout.ceiling_material, layout, collisions)
			for side in 4:
				var probe := midpoint
				var face := local
				var thickness: float = layout.wall_thickness
				var wall_size := Vector3.ZERO
				var is_portal_end := false
				if side == 0 or side == 1:
					probe.x = left - 0.002 if side == 0 else right + 0.002
					face.x = (left if side == 0 else right) - corridor.position.x
					wall_size = Vector3(thickness, layout.room_size.y, dims.z)
					if horizontal:
						is_portal_end = absf((left if side == 0 else right) - edge.route_points[0].x) < 0.001 or absf((left if side == 0 else right) - edge.route_points[3].x) < 0.001
				else:
					probe.z = front - 0.002 if side == 2 else back + 0.002
					face.z = (front if side == 2 else back) - corridor.position.z
					wall_size = Vector3(dims.x, layout.room_size.y, thickness)
					if not horizontal:
						is_portal_end = absf((front if side == 2 else back) - edge.route_points[0].z) < 0.001 or absf((front if side == 2 else back) - edge.route_points[3].z) < 0.001
				if not is_portal_end and not _occupied(probe, rects):
					face.y = layout.room_size.y * 0.5
					_add_box(corridor, "RouteWall_%d_%d_%d" % [xi, zi, side], face, wall_size, layout.wall_material, layout, collisions)
	return corridor


static func _occupied(point: Vector3, rects: Array[Dictionary]) -> bool:
	for rect in rects:
		var center: Vector3 = rect["center"]
		var half: Vector2 = rect["half"]
		if absf(point.x - center.x) < half.x - 0.0001 and absf(point.z - center.z) < half.y - 0.0001:
			return true
	return false


static func _add_unique(values: Array[float], number: float) -> void:
	for item in values:
		if absf(item - number) < 0.001:
			return
	values.append(number)


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
