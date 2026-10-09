@tool
class_name DungeonSocketOffsetPlacer
extends RefCounted
## F2.8: adopt collision-prefab socket offsets only after a seeded topology and
## base placement exist. Tentative adaptations are transactional: unrouteable
## prefabs fall back to the certified procedural room, preserving connectivity.
## No SceneTree instances are created here.

const EPS: float = 0.001

static func resolve(layout: LevelLayout) -> void:
	var original_routes: Dictionary = {}
	for edge in layout.connections:
		original_routes[edge.stable_id] = edge.route_points.duplicate()
		edge.from_offset = 0.0
		edge.to_offset = 0.0
	for room in layout.rooms:
		room.exterior_offset = 0.0
	# No behavioral change for existing F2.7 scenes using centered prefabs.
	for room in layout.rooms:
		if room.structural_prefab == null:
			continue
		_set_profile_offsets(layout, room)
		if not _rebuild_routes(layout, original_routes) or not DungeonRoomOffsetSolver.validate(layout).is_valid():
			# Do not output a prefab that would create a diagonal straight
			# corridor, collide with a neighbor, or fail a required dogleg.
			room.structural_prefab = null
			room.structural_turns = 0
			_set_profile_offsets(layout, room)
			_rebuild_routes(layout, original_routes)


static func _set_profile_offsets(layout: LevelLayout, room: RoomPlacementData) -> void:
	var profile: DungeonStructuralPrefab = room.structural_prefab
	room.exterior_offset = profile.rotated_socket_offset(room.exterior_wall, room.structural_turns) if profile != null and room.exterior_wall >= 0 else 0.0
	for edge in layout.connections:
		if edge.from_room_id == room.stable_id:
			edge.from_offset = profile.rotated_socket_offset(edge.from_wall, room.structural_turns) if profile != null else 0.0
		elif edge.to_room_id == room.stable_id:
			edge.to_offset = profile.rotated_socket_offset(edge.to_wall, room.structural_turns) if profile != null else 0.0


static func _rebuild_routes(layout: LevelLayout, original_routes: Dictionary) -> bool:
	var rooms: Dictionary = {}
	for room in layout.rooms:
		rooms[room.stable_id] = room
	for edge in layout.connections:
		var a: RoomPlacementData = rooms[edge.from_room_id]
		var b: RoomPlacementData = rooms[edge.to_room_id]
		var lateral: float = b.world_transform.origin.z - a.world_transform.origin.z + edge.to_offset - edge.from_offset if edge.from_wall == RoomOpening.Wall.RIGHT or edge.from_wall == RoomOpening.Wall.LEFT else b.world_transform.origin.x - a.world_transform.origin.x + edge.to_offset - edge.from_offset
		var original: PackedVector3Array = original_routes[edge.stable_id]
		if original.is_empty() and absf(lateral) <= EPS:
			edge.route_points = PackedVector3Array()
		else:
			if not layout.dogleg_corridors_enabled:
				return false
			var route := DungeonCorridorRouter.build_route(layout, edge, a, b)
			if not DungeonCorridorRouter.validate_route(layout, edge, route, a, b):
				return false
			edge.route_points = route
	return true
