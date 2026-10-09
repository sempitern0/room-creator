@tool
class_name DungeonSocketRoomStamp
extends RefCounted
## F3.4: first genuinely topology-aware room stamping operation.
## A click adds ONE adjacent BRANCH room, ONE reciprocal socket edge and
## NOTHING ELSE. The existing logical graph, room IDs and baked physics are
## never modified until the complete candidate validates. This deliberately
## cannot place disconnected rooms or auto-move locked neighboring rooms.

static func propose(source: LevelLayout, source_room_id: String, side: int, module: DungeonRoomModule = null) -> DungeonBuildResult:
	var outcome := DungeonBuildResult.new()
	if source == null:
		outcome.report.add_error("STAMP_NO_LAYOUT", "Generate a dungeon before placing more rooms.")
		return outcome
	if side < 0 or side > 3:
		outcome.report.add_error("STAMP_WALL", "Select Front, Right, Back or Left.")
		return outcome
	outcome.report = DungeonPlanner.validate_layout(source)
	if not outcome.report.is_valid():
		return outcome
	var original: RoomPlacementData
	for room in source.rooms:
		if room.stable_id == source_room_id:
			original = room
			break
	if original == null:
		outcome.report.add_error("STAMP_SOURCE", "No room has ID %s." % source_room_id)
		return outcome
	if original.edit_locked:
		outcome.report.add_error("STAMP_LOCKED", "Room %s is locked. Unlock it before adding a new doorway." % original.stable_id)
		return outcome
	if side == original.exterior_wall and source.exterior_doors_enabled:
		outcome.report.add_error("STAMP_EXTERIOR", "That wall contains the protected exterior entrance/exit.")
		return outcome
	for edge in source.connections:
		if (edge.from_room_id == original.stable_id and edge.from_wall == side) or (edge.to_room_id == original.stable_id and edge.to_wall == side):
			outcome.report.add_error("STAMP_WALL_OCCUPIED", "The selected wall already contains a connected doorway.")
			return outcome
	if not RoomFootprint.supports_wall(original.shape, original.shape_rotation, side):
		outcome.report.add_error("STAMP_SILHOUETTE", "The selected wall is not exposed by the source room's silhouette.")
		return outcome
	var delta: Vector2i = DungeonPlanner._delta_for_wall(side)
	var target_cell: Vector2i = original.cell + delta
	if not DungeonPlanner._inside(target_cell, source.grid_size):
		outcome.report.add_error("STAMP_GRID_BORDER", "No adjacent grid cell exists beyond the selected wall.")
		return outcome
	for room in source.rooms:
		if room.cell == target_cell:
			outcome.report.add_error("STAMP_CELL_TAKEN", "The adjacent logical cell is occupied by %s." % room.stable_id)
			return outcome

	var candidate := source.duplicate(true) as LevelLayout
	var base: RoomPlacementData
	for room in candidate.rooms:
		if room.stable_id == source_room_id:
			base = room
			break
	var next_room := RoomPlacementData.new()
	next_room.stable_id = _next_id(candidate.rooms, "room_")
	next_room.cell = target_cell
	next_room.role = RoomPlacementData.Role.BRANCH
	next_room.room_size = candidate.room_size
	next_room.shape = RoomFootprint.Shape.RECTANGLE
	next_room.shape_rotation = 0
	next_room.world_transform = Transform3D(Basis.IDENTITY, DungeonSpatialEmbedder.expected_origin(candidate, target_cell))
	next_room.authored_override_active = true
	var new_wall: int = (side + 2) % 4
	# RoomOpening order is FRONT / RIGHT / BACK / LEFT, opposite is +2.
	var connector := RoomConnectionData.new()
	connector.stable_id = _next_id(candidate.connections, "edge_")
	connector.from_room_id = base.stable_id
	connector.to_room_id = next_room.stable_id
	connector.from_wall = side as RoomOpening.Wall
	connector.to_wall = new_wall as RoomOpening.Wall
	if candidate.connections.is_empty():
		connector.clear_width = candidate.exterior_door_width
		connector.clear_height = candidate.exterior_door_height
	else:
		connector.clear_width = candidate.connections[0].clear_width
		connector.clear_height = candidate.connections[0].clear_height
	if candidate.offgrid_socket_packing_enabled:
		# For off-grid layouts the source's actual OUTWARD socket (not cell
		# center) defines the new room position and yaw. Keep the same room
		# yaw for exactly opposed door normals and straight traversable halls.
		next_room.world_transform.basis = base.world_transform.basis
		var outward_pose: Transform3D = DungeonFreeYawRouter.socket_pose(candidate, base, side, 0.0)
		var dest_pose: Transform3D = DungeonFreeYawRouter.socket_pose(candidate, next_room, new_wall, 0.0)
		var gap: float = maxf(8.0, minf(candidate.maximum_socket_pack_gap, 12.0))
		var target_socket: Vector3 = outward_pose.origin + outward_pose.basis * Vector3.FORWARD * gap
		next_room.world_transform.origin = target_socket - (dest_pose.origin - next_room.world_transform.origin)
	elif candidate.free_yaw_enabled:
		# In yaw grid-guide mode a new authored room may start at 0-degree
		# local yaw, but its full world-space socket route is still validated.
		next_room.world_transform.basis = Basis.IDENTITY
	next_room.authored_override_origin = next_room.world_transform.origin
	if module != null:
		if not module.validate().is_valid() or module.shape != next_room.shape:
			outcome.report.add_error("STAMP_MODULE", "The active room module is not a valid rectangular visual prefab.")
			return outcome
		var doors: Array[int] = [new_wall]
		if not module.supports(doors, next_room.shape_rotation):
			outcome.report.add_error("STAMP_MODULE_SOCKETS", "The selected visual module does not expose the new room's connecting doorway.")
			return outcome
		next_room.module_profile = module
	candidate.rooms.append(next_room)
	candidate.connections.append(connector)
	candidate.expected_room_count += 1
	if candidate.free_yaw_enabled:
		connector.route_points = DungeonFreeYawRouter.build_route(candidate, connector, base, next_room)
	elif candidate.independent_room_offsets_enabled:
		var lateral: float = (next_room.world_transform.origin.z - base.world_transform.origin.z) if side == RoomOpening.Wall.LEFT or side == RoomOpening.Wall.RIGHT else (next_room.world_transform.origin.x - base.world_transform.origin.x)
		if absf(lateral) > 0.001:
			if not candidate.dogleg_corridors_enabled:
				outcome.report.add_error("STAMP_UNROUTABLE", "The chosen room requires a dogleg corridor, which this layout has disabled.")
				return outcome
			connector.route_points = DungeonCorridorRouter.build_route(candidate, connector, base, next_room)
	# For orthogonal cardinal grids no additional route is needed.
	outcome.report = DungeonPlanner.validate_layout(candidate)
	if not outcome.report.is_valid():
		outcome.report.add_error("STAMP_COLLISION", "The candidate could not safely connect at this wall. Nothing has changed.")
		return outcome
	outcome.success = true
	outcome.layout = candidate
	outcome.seed = source.seed
	outcome.attempts = 1
	outcome.expansions = 1
	return outcome


static func _next_id(items: Array, prefix: String) -> String:
	var existing: Dictionary = {}
	for item in items:
		existing[item.stable_id] = true
	var number: int = items.size()
	while existing.has("%s%04d" % [prefix, number]):
		number += 1
	return "%s%04d" % [prefix, number]
