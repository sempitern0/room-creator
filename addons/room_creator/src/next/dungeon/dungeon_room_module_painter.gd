@tool
class_name DungeonRoomModulePainter
extends RefCounted
## F3.3 palette painting: visual-only modules, not physical prefab swapping.
## Only the room's explicit appearance changes; door topology and solid walls
## remain authored by the validated procedural room. Transactional and seeded
## layout-independent: users can paint/remove art on specific rooms.

static func paint(source: LevelLayout, room_id: String, profile: DungeonRoomModule) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	result.report = DungeonPlanner.validate_layout(source)
	if not result.report.is_valid():
		return result
	if room_id.strip_edges().is_empty():
		result.report.add_error("ROOM_PAINT_ID", "Select an existing stable room ID.")
		return result
	var fresh := source.duplicate(true) as LevelLayout
	var room: RoomPlacementData
	for item in fresh.rooms:
		if item.stable_id == room_id:
			room = item
			break
	if room == null:
		result.report.add_error("ROOM_PAINT_UNKNOWN", "No room with ID %s." % room_id)
		return result
	if room.structural_prefab != null:
		result.report.add_error("ROOM_PAINT_STRUCTURAL", "A collision-bearing structural room cannot be overlaid with a visual-only module.")
		return result
	if room.module_profile == profile:
		result.report.add_error("ROOM_PAINT_UNCHANGED", "Room already has the selected visual module.")
		return result
	if profile != null:
		var valid := profile.validate()
		if not valid.is_valid():
			result.report.add_error("ROOM_PAINT_MODULE", valid.summary())
			return result
		if profile.shape != room.shape:
			result.report.add_error("ROOM_PAINT_SHAPE", "Module %s requires a different room silhouette." % profile.stable_id)
			return result
		var required: Array[int] = []
		for opening in DungeonPlanner.make_blueprint(fresh, room).openings:
			required.append(int(opening.wall))
		if not profile.supports(required, room.shape_rotation):
			result.report.add_error("ROOM_PAINT_SOCKETS", "Module %s lacks the rotated sockets required by %s." % [profile.stable_id, room.stable_id])
			return result
	room.module_profile = profile
	# Explicitly painted art is designer-owned and should not be erased by
	# Regenerate Unlocked Rooms, even when the selected room is not locked.
	if not room.authored_override_active:
		room.authored_override_origin = room.world_transform.origin
	room.authored_override_active = true
	result.report = DungeonPlanner.validate_layout(fresh)
	if not result.report.is_valid():
		result.report.add_error("ROOM_PAINT_REJECTED", "Selected module failed final layout validation; no user scene was modified.")
		return result
	result.success = true
	result.seed = source.seed
	result.layout = fresh
	result.expansions = 1
	return result
