@tool
class_name DungeonRoomOverrides
extends RefCounted
## F3.2: explicit designer-authored room edits. We edit a deep-copied layout,
## update ONLY incident connectors, run the complete F2 geometry validator and
## publish atomically via DungeonAuthoring3D's existing Undo/Redo transaction.
## No topology replacement, prefab scene mutation or scene-tree mutation.

const EPS: float = 0.001
const MAX_TRANSLATION: float = 3.0

static func validate_metadata(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		return report
	for room in layout.rooms:
		if room == null or not room.authored_override_active:
			continue
		var delta: Vector3 = room.world_transform.origin - room.authored_override_origin
		if not room.authored_override_origin.is_finite() or not delta.is_finite() or absf(delta.y) > EPS or maxf(absf(delta.x), absf(delta.z)) > MAX_TRANSLATION + EPS:
			report.add_error("ROOM_OVERRIDE_BOUNDS", "Authored room %s has an invalid or excessive displacement from its saved anchor." % room.stable_id)
	return report


static func apply(source: LevelLayout, room_id: String, translation: Vector3, requested_size: Vector2 = Vector2.ZERO, requested_shape: int = -1, requested_turns: int = -1) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	result.report = DungeonPlanner.validate_layout(source)
	if not result.report.is_valid():
		return result
	if room_id.strip_edges().is_empty():
		result.report.add_error("ROOM_OVERRIDE_ID", "Choose the selected room's stable ID before editing.")
		return result
	if not translation.is_finite() or absf(translation.y) > EPS or maxf(absf(translation.x), absf(translation.z)) > MAX_TRANSLATION or not is_finite(requested_size.x) or not is_finite(requested_size.y) or requested_size.x < 0.0 or requested_size.y < 0.0:
		result.report.add_error("ROOM_OVERRIDE_VALUES", "Offsets must be finite, horizontal and within 3 m per edit. Room size must be nonnegative.")
		return result
	if requested_shape < -1 or requested_shape > RoomFootprint.Shape.T_SHAPE or requested_turns < -1 or requested_turns > 3:
		result.report.add_error("ROOM_OVERRIDE_SHAPE", "Shape/rotation setting is not valid.")
		return result
	var edited := source.duplicate(true) as LevelLayout
	var chosen: RoomPlacementData
	for room in edited.rooms:
		if room.stable_id == room_id.strip_edges():
			chosen = room
			break
	if chosen == null:
		result.report.add_error("ROOM_OVERRIDE_UNKNOWN", "Room %s is not present in the saved layout." % room_id)
		return result
	var before_pose: Transform3D = chosen.world_transform
	var before_size: Vector3 = DungeonPlanner.actual_size(edited, chosen)
	var before_shape: int = int(chosen.shape)
	var before_turns: int = chosen.shape_rotation
	var anchor: Vector3 = chosen.authored_override_origin if chosen.authored_override_active else chosen.world_transform.origin
	var moved: Vector3 = before_pose.origin + translation
	var total_displacement: Vector3 = moved - anchor
	if absf(total_displacement.x) > MAX_TRANSLATION + EPS or absf(total_displacement.z) > MAX_TRANSLATION + EPS:
		result.report.add_error("ROOM_OVERRIDE_LIMIT", "Room %s exceeds the cumulative 3 m manual offset limit from its original anchor." % chosen.stable_id)
		return result
	var new_width: float = requested_size.x if requested_size.x > EPS else before_size.x
	var new_depth: float = requested_size.y if requested_size.y > EPS else before_size.z
	var target_size := Vector3(new_width, before_size.y, new_depth)
	var size_change: bool = not target_size.is_equal_approx(before_size)
	var shape_change: bool = requested_shape >= 0 and requested_shape != before_shape
	var rotation_change: bool = requested_turns >= 0 and requested_turns != before_turns
	var pose_change: bool = not moved.is_equal_approx(before_pose.origin)
	if not pose_change and not size_change and not shape_change and not rotation_change:
		result.report.add_error("ROOM_OVERRIDE_NO_CHANGE", "Provide a displacement, a new width/depth, or a new shape/rotation.")
		return result
	if new_width < source.room_size.x * 0.5 or new_width > source.room_size.x + EPS or new_depth < source.room_size.z * 0.5 or new_depth > source.room_size.z + EPS:
		result.report.add_error("ROOM_OVERRIDE_SIZE", "Edited footprint must remain within 50–100%% of the original room X/Z size.")
		return result
	if chosen.structural_prefab != null and (size_change or shape_change or rotation_change):
		result.report.add_error("ROOM_OVERRIDE_STRUCTURAL", "Physical prefab sizes, wall shapes and internal quarter-turns are fixed by its authored sockets; translation alone is supported.")
		return result
	chosen.world_transform.origin = moved
	chosen.room_size = target_size if size_change else chosen.room_size
	if requested_shape >= 0:
		chosen.shape = requested_shape as RoomFootprint.Shape
	if requested_turns >= 0:
		chosen.shape_rotation = requested_turns
	if chosen.module_profile != null and (chosen.module_profile.shape != chosen.shape or not _module_matches(edited, chosen)):
		result.report.add_error("ROOM_OVERRIDE_MODULE", "Selected room's visual module cannot match the edited silhouette or doors. Change/remove the module explicitly first.")
		return result
	chosen.authored_override_active = true
	chosen.authored_override_origin = anchor
	# Cardinal F2 normally disallows any per-room coordinate deviation.
	# Enable its existing bounded physical offset contract rather than
	# bypassing its graph and capsule collision validation.
	if not edited.free_yaw_enabled and pose_change:
		edited.independent_room_offsets_enabled = true
		edited.dogleg_corridors_enabled = true
		var expected: Vector3 = DungeonSpatialEmbedder.expected_origin(edited, chosen.cell)
		var extent: Vector3 = chosen.world_transform.origin - expected
		edited.maximum_room_offset = minf(6.0, maxf(edited.maximum_room_offset, maxf(absf(extent.x), absf(extent.z)) + EPS))
	elif edited.free_yaw_enabled and not edited.offgrid_socket_packing_enabled and pose_change:
		var expected: Vector3 = DungeonSpatialEmbedder.expected_origin(edited, chosen.cell)
		var extent: Vector3 = chosen.world_transform.origin - expected
		edited.maximum_free_yaw_shift = minf(5.0, maxf(edited.maximum_free_yaw_shift, maxf(absf(extent.x), absf(extent.z)) - edited.maximum_room_offset + EPS))
	var by_id: Dictionary = {}
	for room in edited.rooms:
		by_id[room.stable_id] = room
	var changed_edges: int = 0
	for edge in edited.connections:
		if edge.from_room_id != chosen.stable_id and edge.to_room_id != chosen.stable_id:
			continue
		var from_room: RoomPlacementData = by_id[edge.from_room_id]
		var to_room: RoomPlacementData = by_id[edge.to_room_id]
		if edited.free_yaw_enabled:
			edge.route_points = DungeonFreeYawRouter.build_route(edited, edge, from_room, to_room)
			if not DungeonFreeYawRouter.valid_route(edited, edge, edge.route_points, from_room, to_room):
				result.report.add_error("ROOM_OVERRIDE_ROUTE", "Unable to form a clear world-space route between %s and %s." % [edge.from_room_id, edge.to_room_id])
				return result
		else:
			var lateral: float = (to_room.world_transform.origin.z + edge.to_offset - from_room.world_transform.origin.z - edge.from_offset) if edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.RIGHT else (to_room.world_transform.origin.x + edge.to_offset - from_room.world_transform.origin.x - edge.from_offset)
			if absf(lateral) > EPS or not edge.route_points.is_empty():
				edge.route_points = DungeonCorridorRouter.build_route(edited, edge, from_room, to_room)
				if not DungeonCorridorRouter.validate_route(edited, edge, edge.route_points, from_room, to_room):
					result.report.add_error("ROOM_OVERRIDE_ROUTE", "Cardinal corridor %s cannot accommodate the edited room." % edge.stable_id)
					return result
			else:
				edge.route_points = PackedVector3Array()
		changed_edges += 1
	result.report = DungeonPlanner.validate_layout(edited)
	if not result.report.is_valid():
		result.report.add_error("ROOM_OVERRIDE_CONFLICT", "Physical or socket validation rejected the tentative edit; original layout was not changed.")
		return result
	result.success = true
	result.layout = edited
	result.seed = source.seed
	result.attempts = 1
	result.expansions = changed_edges
	return result


static func _module_matches(layout: LevelLayout, room: RoomPlacementData) -> bool:
	var walls: Array[int] = []
	for opening in DungeonPlanner.make_blueprint(layout, room).openings:
		walls.append(int(opening.wall))
	return room.module_profile.supports(walls, room.shape_rotation)
