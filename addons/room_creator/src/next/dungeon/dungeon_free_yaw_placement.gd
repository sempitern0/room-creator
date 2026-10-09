@tool
class_name DungeonFreeYawPlacement
extends RefCounted
## F2: bounded deterministic DFS/backtracking over room yaw and local X/Z
## offsets. The grid is topological only; actual 3D room poses are independent.
## A candidate is admitted only after SAT collision checks and valid yaw routes
## to every already assigned neighbor. Previously placed rooms are never moved
## silently: exhaustion returns false, preserving prior authored scene state.

static func assign(config: DungeonConfig, layout: LevelLayout, rng: RandomNumberGenerator) -> bool:
	layout.free_yaw_enabled = config.enable_free_yaw_dungeons
	layout.maximum_yaw_degrees = config.free_yaw_max_degrees if config.enable_free_yaw_dungeons else 0.0
	layout.maximum_free_yaw_shift = config.free_yaw_shift if config.enable_free_yaw_dungeons else 0.0
	layout.offgrid_socket_packing_enabled = config.enable_offgrid_socket_packing
	layout.maximum_socket_pack_gap = config.socket_pack_max_gap if config.enable_offgrid_socket_packing else 0.0
	if not config.enable_free_yaw_dungeons:
		return true
	var origins: Dictionary = {}
	for room in layout.rooms:
		origins[room.stable_id] = room.world_transform.origin
	var assigned: Dictionary = {}
	var budget: Array[int] = [config.free_yaw_search_budget]
	var succeeded: bool
	if config.enable_offgrid_socket_packing:
		succeeded = DungeonSocketGraphPacker.assign(config, layout, rng)
		if succeeded:
			for room in layout.rooms:
				assigned[room.stable_id] = room
	else:
		succeeded = _search(layout, rng, origins, assigned, 0, budget, config.free_yaw_candidates, config.free_yaw_max_degrees, config.free_yaw_shift)
	if not succeeded:
		for room in layout.rooms:
			room.world_transform = Transform3D(Basis.IDENTITY, origins[room.stable_id])
		return false
	for edge in layout.connections:
		var a: RoomPlacementData = assigned[edge.from_room_id]
		var b: RoomPlacementData = assigned[edge.to_room_id]
		edge.route_points = DungeonFreeYawRouter.build_route(layout, edge, a, b)
	return DungeonFreeYawRouter.validate(layout).is_valid()


static func _search(layout: LevelLayout, rng: RandomNumberGenerator, origins: Dictionary, assigned: Dictionary, index: int, budget: Array[int], candidates: int, max_yaw: float, max_shift: float) -> bool:
	if index >= layout.rooms.size():
		return true
	var current: RoomPlacementData = layout.rooms[index]
	var base: Vector3 = origins[current.stable_id]
	for trial in candidates:
		if budget[0] <= 0:
			return false
		budget[0] -= 1
		var degrees: float = snappedf(rng.randf_range(-max_yaw, max_yaw), 0.5)
		var shift_x: float = snappedf(rng.randf_range(-max_shift, max_shift), 0.25)
		var shift_z: float = snappedf(rng.randf_range(-max_shift, max_shift), 0.25)
		# Baseline is a deterministic safe fallback after exploring real yaw
		# variants; do not use it on the first candidate.
		if trial == candidates - 1:
			degrees = 0.0
			shift_x = 0.0
			shift_z = 0.0
		current.world_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), base + Vector3(shift_x, 0.0, shift_z))
		if not _fits(layout, current, assigned):
			continue
		assigned[current.stable_id] = current
		if _search(layout, rng, origins, assigned, index + 1, budget, candidates, max_yaw, max_shift):
			return true
		assigned.erase(current.stable_id)
	current.world_transform = Transform3D(Basis.IDENTITY, base)
	return false


static func _fits(layout: LevelLayout, candidate: RoomPlacementData, assigned: Dictionary) -> bool:
	var candidate_box := DungeonOrientedBounds.room(candidate, DungeonPlanner.actual_size(layout, candidate))
	for key in assigned:
		var other: RoomPlacementData = assigned[key]
		if DungeonOrientedBounds.overlaps(candidate_box, DungeonOrientedBounds.room(other, DungeonPlanner.actual_size(layout, other))):
			return false
	var segments: Array[Dictionary] = []
	for edge in layout.connections:
		if not assigned.has(edge.from_room_id) and edge.from_room_id != candidate.stable_id:
			continue
		if not assigned.has(edge.to_room_id) and edge.to_room_id != candidate.stable_id:
			continue
		var a: RoomPlacementData = candidate if edge.from_room_id == candidate.stable_id else assigned[edge.from_room_id]
		var b: RoomPlacementData = candidate if edge.to_room_id == candidate.stable_id else assigned[edge.to_room_id]
		var points := DungeonFreeYawRouter.build_route(layout, edge, a, b)
		if not DungeonFreeYawRouter.valid_route(layout, edge, points, a, b):
			return false
		for rectangle in DungeonFreeYawRouter.envelopes(layout, edge, points):
			segments.append({"edge": edge.stable_id, "a": a.stable_id, "b": b.stable_id, "bounds": rectangle})
	for fragment in segments:
		for key in assigned:
			if key == fragment["a"] or key == fragment["b"]:
				continue
			var room: RoomPlacementData = assigned[key]
			if DungeonOrientedBounds.overlaps(fragment["bounds"], DungeonOrientedBounds.room(room, DungeonPlanner.actual_size(layout, room))):
				return false
		if fragment["a"] != candidate.stable_id and fragment["b"] != candidate.stable_id and DungeonOrientedBounds.overlaps(fragment["bounds"], candidate_box):
			return false
	for i in segments.size():
		for j in range(i + 1, segments.size()):
			var aa: Dictionary = segments[i]
			var bb: Dictionary = segments[j]
			if aa["edge"] == bb["edge"] or aa["a"] == bb["a"] or aa["a"] == bb["b"] or aa["b"] == bb["a"] or aa["b"] == bb["b"]:
				continue
			if DungeonOrientedBounds.overlaps(aa["bounds"], bb["bounds"]):
				return false
	return true
