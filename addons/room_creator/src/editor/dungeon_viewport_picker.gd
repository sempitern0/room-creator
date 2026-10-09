@tool
extends RefCounted
## Viewport room hit testing without physics dependency: the generated preview
## is transient, so use canonical Layout rooms and exact world transforms.
## Returns a stable ID and never changes a layout.

static func pick_room(layout: LevelLayout, ray_origin: Vector3, ray_direction: Vector3) -> String:
	if layout == null or not ray_origin.is_finite() or not ray_direction.is_finite():
		return ""
	if ray_direction.length_squared() < 0.000001:
		return ""
	var direction := ray_direction.normalized()
	var best_distance := INF
	var best_id := ""
	for room in layout.rooms:
		if room == null:
			continue
		var size: Vector3 = DungeonPlanner.actual_size(layout, room)
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		var inverse: Transform3D = room.world_transform.affine_inverse()
		var local_origin: Vector3 = inverse * ray_origin
		var local_dir: Vector3 = inverse.basis * direction
		var extent := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		var hit: Variant = extent.intersects_ray(local_origin, local_dir)
		if hit == null:
			continue
		var world_hit: Vector3 = room.world_transform * (hit as Vector3)
		var distance: float = ray_origin.distance_to(world_hit)
		if distance < best_distance:
			best_distance = distance
			best_id = room.stable_id
	return best_id


static func room_corners(layout: LevelLayout, room: RoomPlacementData) -> PackedVector3Array:
	var points := PackedVector3Array()
	if layout == null or room == null:
		return points
	var size: Vector3 = DungeonPlanner.actual_size(layout, room)
	for local in [
		Vector3(-size.x * 0.5, size.y + 0.08, -size.z * 0.5),
		Vector3(size.x * 0.5, size.y + 0.08, -size.z * 0.5),
		Vector3(size.x * 0.5, size.y + 0.08, size.z * 0.5),
		Vector3(-size.x * 0.5, size.y + 0.08, size.z * 0.5)
	]:
		points.append(room.world_transform * local)
	return points
