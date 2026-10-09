@tool
class_name DungeonFreeYawRouter
extends RefCounted
## Geometric truth for yaw dungeon connections: both doors are in the rooms'
## LOCAL cardinal walls, but world-space normals can face any planar angle.
## A route has two outward stubs and one diagonal middle segment.
## Conservative OBB envelopes are used by the bounded placement solver.

const EPS: float = 0.005

static func socket_pose(layout: LevelLayout, room: RoomPlacementData, wall: int, offset: float) -> Transform3D:
	var size := DungeonPlanner.actual_size(layout, room)
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	match wall:
		RoomOpening.Wall.FRONT:
			point = Vector3(offset, 0.0, -size.z * 0.5)
			normal = Vector3.FORWARD
		RoomOpening.Wall.BACK:
			point = Vector3(offset, 0.0, size.z * 0.5)
			normal = Vector3.BACK
		RoomOpening.Wall.LEFT:
			point = Vector3(-size.x * 0.5, 0.0, offset)
			normal = Vector3.LEFT
		RoomOpening.Wall.RIGHT:
			point = Vector3(size.x * 0.5, 0.0, offset)
			normal = Vector3.RIGHT
	var yaw := atan2(-normal.x, -normal.z)
	return room.world_transform * Transform3D(Basis(Vector3.UP, yaw), point)


static func build_route(layout: LevelLayout, edge: RoomConnectionData, a: RoomPlacementData, b: RoomPlacementData) -> PackedVector3Array:
	var from_pose: Transform3D = socket_pose(layout, a, edge.from_wall, edge.from_offset)
	var to_pose: Transform3D = socket_pose(layout, b, edge.to_wall, edge.to_offset)
	var start: Vector3 = from_pose.origin
	var end: Vector3 = to_pose.origin
	var direction_a: Vector3 = (from_pose.basis * Vector3.FORWARD).normalized()
	var direction_b: Vector3 = (to_pose.basis * Vector3.FORWARD).normalized()
	var stub: float = edge.clear_width * 0.5 + layout.wall_thickness + 1.35
	return PackedVector3Array([start, start + direction_a * stub, end + direction_b * stub, end])


static func valid_route(layout: LevelLayout, edge: RoomConnectionData, route: PackedVector3Array, a: RoomPlacementData, b: RoomPlacementData) -> bool:
	if route.size() != 4 or edge.clear_width < layout.player_radius * 2.0 + 0.1:
		return false
	var expected := build_route(layout, edge, a, b)
	for i in 4:
		if not route[i].is_finite() or route[i].distance_to(expected[i]) > EPS:
			return false
	var dir_first: Vector3 = route[1] - route[0]
	var dir_mid: Vector3 = route[2] - route[1]
	var dir_last: Vector3 = route[3] - route[2]
	if dir_first.length() < edge.clear_width or dir_mid.length() < edge.clear_width * 1.5 or dir_last.length() < edge.clear_width:
		return false
	# Both doorway stubs must move away from their wall into the exterior.
	var from_out: Vector3 = socket_pose(layout, a, edge.from_wall, edge.from_offset).basis * Vector3.FORWARD
	var to_out: Vector3 = socket_pose(layout, b, edge.to_wall, edge.to_offset).basis * Vector3.FORWARD
	if dir_first.normalized().dot(from_out) < 0.999 or (-dir_last).normalized().dot(to_out) < 0.999:
		return false
	# Reject self-folding connectors or hairpins that cannot accommodate a capsule.
	if dir_first.normalized().dot(dir_mid.normalized()) < -0.45 or dir_mid.normalized().dot(dir_last.normalized()) < -0.45:
		return false
	# The corridor must not pierce its OWN source/target through a different
	# wall. The first segment is allowed to touch only its source socket and
	# the last segment only its destination socket. All other envelopes must
	# remain outside both solid room footprints, even when yaw > 90 degrees.
	var a_obb := DungeonOrientedBounds.room(a, DungeonPlanner.actual_size(layout, a))
	var b_obb := DungeonOrientedBounds.room(b, DungeonPlanner.actual_size(layout, b))
	var regions := envelopes(layout, edge, route)
	for i in regions.size():
		if i != 0 and DungeonOrientedBounds.overlaps(regions[i], a_obb):
			return false
		if i != 2 and DungeonOrientedBounds.overlaps(regions[i], b_obb):
			return false
	return true


static func envelopes(layout: LevelLayout, edge: RoomConnectionData, route: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if route.size() != 4:
		return result
	var width: float = edge.clear_width + layout.wall_thickness * 2.0
	for i in 3:
		var delta: Vector3 = route[i + 1] - route[i]
		var yaw := atan2(-delta.x, -delta.z)
		result.append(DungeonOrientedBounds.rectangle((route[i] + route[i + 1]) * 0.5, Vector2(width, delta.length()), Basis(Vector3.UP, yaw)))
	for i in [1, 2]:
		# Enclose the turn swept by the capsule between angled segments.
		result.append(DungeonOrientedBounds.rectangle(route[i], Vector2(width * 1.45, width * 1.45)))
	return result


static func validate(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		report.add_error("MISSING_LAYOUT", "No free-yaw layout supplied.")
		return report
	if not layout.free_yaw_enabled:
		return report
	if not is_finite(layout.maximum_yaw_degrees) or layout.maximum_yaw_degrees < 0.0 or layout.maximum_yaw_degrees > 180.0 or not is_finite(layout.maximum_free_yaw_shift) or layout.maximum_free_yaw_shift < 0.0 or layout.maximum_free_yaw_shift > 5.0:
		report.add_error("FREE_YAW_CONTRACT", "Persisted yaw or placement bounds are invalid.")
		return report
	var by_id: Dictionary = {}
	for room in layout.rooms:
		if room == null:
			report.add_error("NULL_ROOM", "Null room in free-yaw layout.")
			return report
		by_id[room.stable_id] = room
		var expected: Vector3 = DungeonSpatialEmbedder.expected_origin(layout, room.cell)
		var delta: Vector3 = room.world_transform.origin - expected
		var max_offset: float = layout.maximum_room_offset + layout.maximum_free_yaw_shift + EPS
		if not room.world_transform.origin.is_finite() or absf(delta.x) > max_offset or absf(delta.z) > max_offset or absf(delta.y) > EPS or not DungeonYawDockingSolver._rigid_yaw(room.world_transform):
			report.add_error("FREE_YAW_POSE", "Room has invalid off-grid transform: %s." % room.stable_id)
		var radians: float = room.world_transform.basis.get_euler().y
		if absf(rad_to_deg(radians)) > layout.maximum_yaw_degrees + 0.05:
			report.add_error("FREE_YAW_BOUND", "Room yaw exceeds the configured limit: %s." % room.stable_id)
	var walls: Array[Dictionary] = []
	for edge in layout.connections:
		if not by_id.has(edge.from_room_id) or not by_id.has(edge.to_room_id):
			report.add_error("FREE_YAW_ENDPOINT", "Missing room endpoint.")
			continue
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		if not valid_route(layout, edge, edge.route_points, a, b):
			report.add_error("FREE_YAW_ROUTE", "Physical rotated socket route invalid: %s." % edge.stable_id)
			continue
		for rect in envelopes(layout, edge, edge.route_points):
			walls.append({"shape": rect, "edge": edge.stable_id, "from": edge.from_room_id, "to": edge.to_room_id})
	for room in layout.rooms:
		var size := DungeonPlanner.actual_size(layout, room)
		var obb := DungeonOrientedBounds.room(room, size)
		for rect in walls:
			if rect["from"] == room.stable_id or rect["to"] == room.stable_id:
				continue
			if DungeonOrientedBounds.overlaps(obb, rect["shape"]):
				report.add_error("FREE_YAW_ROOM_CROSSING", "Unrelated connector %s crosses %s." % [rect["edge"], room.stable_id])
				break
	for i in walls.size():
		for j in range(i + 1, walls.size()):
			if walls[i]["edge"] == walls[j]["edge"]:
				continue
			if walls[i]["from"] == walls[j]["from"] or walls[i]["from"] == walls[j]["to"] or walls[i]["to"] == walls[j]["from"] or walls[i]["to"] == walls[j]["to"]:
				continue
			if DungeonOrientedBounds.overlaps(walls[i]["shape"], walls[j]["shape"]):
				report.add_error("FREE_YAW_CORRIDOR_CROSSING", "Unrelated angled corridors collide: %s / %s." % [walls[i]["edge"], walls[j]["edge"]])
	return report
