@tool
class_name DungeonRoomOffsetSolver
extends RefCounted
## F2.5: move room centers independently where graph topology allows it.
## Horizontal edges lock their two Z coordinates; vertical edges lock X.
## A bounded stochastic solver repositions these constrained components,
## accepting only collision-free, socket-coaxial static corridor placements.
## It never mutates a source DungeonConfig or touches the SceneTree.

const EPS: float = 0.001

static func assign(config: DungeonConfig, layout: LevelLayout, rng: RandomNumberGenerator) -> bool:
	layout.independent_room_offsets_enabled = config.enable_independent_room_offsets
	layout.maximum_room_offset = config.room_position_jitter if config.enable_independent_room_offsets else 0.0
	layout.dogleg_corridors_enabled = config.enable_dogleg_corridors
	if not config.enable_independent_room_offsets:
		return true
	# Route selection is seeded once per layout (not once per attempt).
	# Straight edges still enforce coaxial placement; routed edges may bend.
	var routed_edges: Dictionary = {}
	for edge in layout.connections:
		routed_edges[edge.stable_id] = config.enable_dogleg_corridors and rng.randf() < config.dogleg_frequency
	var x_groups: Dictionary = {}
	var z_groups: Dictionary = {}
	for room in layout.rooms:
		x_groups[room.stable_id] = room.stable_id
		z_groups[room.stable_id] = room.stable_id
	for edge in layout.connections:
		if routed_edges.get(edge.stable_id, false):
			continue
		if edge.from_wall == RoomOpening.Wall.FRONT or edge.from_wall == RoomOpening.Wall.BACK:
			_join(x_groups, edge.from_room_id, edge.to_room_id)
		else:
			_join(z_groups, edge.from_room_id, edge.to_room_id)
	for attempt in config.placement_attempts:
		var x_offsets: Dictionary = {}
		var z_offsets: Dictionary = {}
		for room in layout.rooms:
			var x_id: String = _find(x_groups, room.stable_id)
			var z_id: String = _find(z_groups, room.stable_id)
			if not x_offsets.has(x_id):
				x_offsets[x_id] = snappedf(rng.randf_range(-config.room_position_jitter, config.room_position_jitter), 0.05)
			if not z_offsets.has(z_id):
				z_offsets[z_id] = snappedf(rng.randf_range(-config.room_position_jitter, config.room_position_jitter), 0.05)
			var center: Vector3 = DungeonSpatialEmbedder.expected_origin(layout, room.cell)
			center.x += x_offsets[x_id]
			center.z += z_offsets[z_id]
			room.world_transform.origin = center
		for edge in layout.connections:
			edge.route_points = PackedVector3Array()
			if not routed_edges.get(edge.stable_id, false):
				continue
			var from_room: RoomPlacementData = null
			var to_room: RoomPlacementData = null
			for room in layout.rooms:
				if room.stable_id == edge.from_room_id:
					from_room = room
				elif room.stable_id == edge.to_room_id:
					to_room = room
			if from_room == null or to_room == null:
				continue
			var route := DungeonCorridorRouter.build_route(layout, edge, from_room, to_room)
			if DungeonCorridorRouter.validate_route(layout, edge, route, from_room, to_room):
				edge.route_points = route
		if validate(layout).is_valid():
			return true
	return false


static func validate(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		report.add_error("MISSING_LAYOUT", "Missing level layout.")
		return report
	if not layout.independent_room_offsets_enabled:
		if layout.dogleg_corridors_enabled:
			report.add_error("OFFSET_REQUIRED", "Dogleg corridors require independent room offsets.")
		for edge in layout.connections:
			if not edge.route_points.is_empty():
				report.add_error("UNEXPECTED_ROUTE", "Routed corridor requires independent room offsets.")
		return report
	if not is_finite(layout.maximum_room_offset) or layout.maximum_room_offset < 0.0 or layout.maximum_room_offset > 6.0:
		report.add_error("ROOM_OFFSET_LIMIT", "Persisted maximum room offset is outside safe bounds.")
		return report
	var by_id: Dictionary = {}
	for room in layout.rooms:
		if room == null:
			report.add_error("NULL_ROOM", "Null room in spatial embedding.")
			return report
		by_id[room.stable_id] = room
		var expected: Vector3 = DungeonSpatialEmbedder.expected_origin(layout, room.cell)
		var displaced: Vector3 = room.world_transform.origin - expected
		if not displaced.is_finite() or absf(displaced.x) > layout.maximum_room_offset + EPS or absf(displaced.z) > layout.maximum_room_offset + EPS or absf(displaced.y) > EPS or not room.world_transform.basis.is_equal_approx(Basis.IDENTITY):
			report.add_error("ROOM_OFFSET_BOUNDS", "%s has an invalid independent placement." % room.stable_id)
	var corridors: Array[Dictionary] = []
	for edge in layout.connections:
		if not by_id.has(edge.from_room_id) or not by_id.has(edge.to_room_id):
			report.add_error("MISSING_EDGE_ENDPOINT", "Edge %s refers to an absent room." % edge.stable_id)
			continue
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var delta: Vector3 = b.world_transform.origin - a.world_transform.origin
		var x_direction: bool = edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.RIGHT
		if not edge.route_points.is_empty():
			if not layout.dogleg_corridors_enabled or not DungeonCorridorRouter.validate_route(layout, edge, edge.route_points, a, b):
				report.add_error("INVALID_DOGLEG", "Invalid route or disabled routing on %s." % edge.stable_id)
				continue
			for rect in DungeonCorridorRouter.rectangles(layout, edge, edge.route_points):
				rect["id"] = edge.stable_id
				rect["a"] = edge.from_room_id
				rect["b"] = edge.to_room_id
				corridors.append(rect)
			continue
		var lateral: float = (delta.z + edge.to_offset - edge.from_offset) if x_direction else (delta.x + edge.to_offset - edge.from_offset)
		if absf(lateral) > EPS:
			report.add_error("UNALIGNED_PORTAL", "Door sockets on edge %s are no longer coaxial." % edge.stable_id)
			continue
		var expected_sign: float = -1.0 if edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.FRONT else 1.0
		var axial: float = delta.x if x_direction else delta.z
		var size_a: Vector3 = DungeonPlanner.actual_size(layout, a)
		var size_b: Vector3 = DungeonPlanner.actual_size(layout, b)
		var extent_a: float = size_a.x if x_direction else size_a.z
		var extent_b: float = size_b.x if x_direction else size_b.z
		var gap: float = absf(axial) - 0.5 * (extent_a + extent_b)
		if axial * expected_sign < -EPS or gap < -EPS:
			report.add_error("NEGATIVE_CORRIDOR_GAP", "Edge %s would reverse or overlap its connected room walls." % edge.stable_id)
			continue
		if gap <= EPS:
			continue
		var p0: Vector3 = a.world_transform.origin
		var p1: Vector3 = b.world_transform.origin
		if x_direction:
			p0.z += edge.from_offset
			p1.z += edge.to_offset
		else:
			p0.x += edge.from_offset
			p1.x += edge.to_offset
		var signed_axis: float = 1.0 if axial >= 0.0 else -1.0
		if x_direction:
			p0.x += signed_axis * extent_a * 0.5
			p1.x -= signed_axis * extent_b * 0.5
		else:
			p0.z += signed_axis * extent_a * 0.5
			p1.z -= signed_axis * extent_b * 0.5
		var half_width: float = edge.clear_width * 0.5 + layout.wall_thickness
		var width: float = gap * 0.5 if x_direction else half_width
		var depth: float = half_width if x_direction else gap * 0.5
		corridors.append({"id": edge.stable_id, "a": edge.from_room_id, "b": edge.to_room_id, "center": (p0 + p1) * 0.5, "half": Vector2(width, depth)})
	for corridor in corridors:
		for room in layout.rooms:
			if room.stable_id == corridor["a"] or room.stable_id == corridor["b"]:
				continue
			var size: Vector3 = DungeonPlanner.actual_size(layout, room)
			if DungeonCorridorRouter.overlap_xz(corridor, {"center": room.world_transform.origin, "half": Vector2(size.x * 0.5, size.z * 0.5)}):
				report.add_error("CORRIDOR_ROOM_OVERLAP", "Connector %s crosses an unrelated room %s." % [corridor["id"], room.stable_id])
				break
	for i in corridors.size():
		for j in range(i + 1, corridors.size()):
			var a: Dictionary = corridors[i]
			var b: Dictionary = corridors[j]
			if a["a"] == b["a"] or a["a"] == b["b"] or a["b"] == b["a"] or a["b"] == b["b"]:
				continue
			if DungeonCorridorRouter.overlap_xz(a, b):
				report.add_error("CORRIDOR_CROSSING", "Unconnected corridors %s and %s physically intersect." % [a["id"], b["id"]])
	return report


static func _overlaps_xz(a: Vector3, half_a: Vector2, b: Vector3, half_b: Vector2) -> bool:
	return absf(a.x - b.x) < half_a.x + half_b.x - EPS and absf(a.z - b.z) < half_a.y + half_b.y - EPS


static func _find(parent: Dictionary, room_id: String) -> String:
	var candidate: String = parent[room_id]
	while candidate != parent[candidate]:
		candidate = parent[candidate]
	return candidate


static func _join(parent: Dictionary, a: String, b: String) -> void:
	var x: String = _find(parent, a)
	var y: String = _find(parent, b)
	if x != y:
		parent[y] = x
