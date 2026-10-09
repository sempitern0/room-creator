@tool
class_name DungeonSocketGraphPacker
extends RefCounted
## F2 optional true off-grid graph embedding. Rooms are no longer assigned
## their world's positions from a grid. A tree edge's ACTUAL portal is used
## to grow a new room in arbitrary yaw; bounded DFS backtracks entire branches
## whenever SAT or a routed hallway would collide. The logical cells/graph
## remain stable identifiers and adjacency metadata only.

static func assign(config: DungeonConfig, layout: LevelLayout, rng: RandomNumberGenerator) -> bool:
	var original: Dictionary = {}
	for room in layout.rooms:
		original[room.stable_id] = room.world_transform
	var assigned: Dictionary = {}
	var budget: Array[int] = [config.free_yaw_search_budget]
	if not _search(layout, rng, assigned, 0, budget, config):
		for room in layout.rooms:
			room.world_transform = original[room.stable_id]
		return false
	return true


static func _search(layout: LevelLayout, rng: RandomNumberGenerator, placed: Dictionary, index: int, budget: Array[int], config: DungeonConfig) -> bool:
	if index >= layout.rooms.size():
		return true
	var room: RoomPlacementData = layout.rooms[index]
	var parent: RoomPlacementData
	var link: RoomConnectionData
	var parent_wall: int = -1
	var child_wall: int = -1
	var child_offset: float = 0.0
	var parent_offset: float = 0.0
	if index > 0:
		# Branches are appended after their parent and every critical-path
		# room is appended after its predecessor, so a seeded DFS always has
		# at least one already placed socket to attach to.
		for edge in layout.connections:
			if edge.from_room_id == room.stable_id and placed.has(edge.to_room_id):
				parent = placed[edge.to_room_id]
				link = edge
				parent_wall = edge.to_wall
				parent_offset = edge.to_offset
				child_wall = edge.from_wall
				child_offset = edge.from_offset
				break
			if edge.to_room_id == room.stable_id and placed.has(edge.from_room_id):
				parent = placed[edge.from_room_id]
				link = edge
				parent_wall = edge.from_wall
				parent_offset = edge.from_offset
				child_wall = edge.to_wall
				child_offset = edge.to_offset
				break
		if parent == null or link == null:
			return false
	for trial in config.free_yaw_candidates:
		if budget[0] <= 0:
			return false
		budget[0] -= 1
		var yaw: float
		var position := Vector3.ZERO
		if parent == null:
			yaw = snappedf(rng.randf_range(-config.free_yaw_max_degrees, config.free_yaw_max_degrees), 0.5)
		else:
			var parent_yaw: float = rad_to_deg(parent.world_transform.basis.get_euler().y)
			var relative: float = rng.randf_range(-minf(config.free_yaw_max_degrees, 35.0), minf(config.free_yaw_max_degrees, 35.0))
			yaw = clampf(snappedf(parent_yaw + relative, 0.5), -config.free_yaw_max_degrees, config.free_yaw_max_degrees)
			var world_port := DungeonFreeYawRouter.socket_pose(layout, parent, parent_wall, parent_offset)
			var outward: Vector3 = world_port.basis * Vector3.FORWARD
			var tangent: Vector3 = world_port.basis * Vector3.RIGHT
			var distance := snappedf(rng.randf_range(config.socket_pack_min_gap, config.socket_pack_max_gap), 0.25)
			var sideways := snappedf(rng.randf_range(-config.free_yaw_shift, config.free_yaw_shift), 0.25)
			var desired_port: Vector3 = world_port.origin + outward * distance + tangent * sideways
			var old_transform: Transform3D = room.world_transform
			room.world_transform = Transform3D.IDENTITY
			var local_port: Vector3 = DungeonFreeYawRouter.socket_pose(layout, room, child_wall, child_offset).origin
			room.world_transform = old_transform
			position = desired_port - Basis(Vector3.UP, deg_to_rad(yaw)) * local_port
		room.world_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), position)
		if not DungeonFreeYawPlacement._fits(layout, room, placed):
			continue
		placed[room.stable_id] = room
		if _search(layout, rng, placed, index + 1, budget, config):
			return true
		placed.erase(room.stable_id)
	return false
