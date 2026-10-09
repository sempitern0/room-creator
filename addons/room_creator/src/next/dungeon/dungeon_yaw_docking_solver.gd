@tool
class_name DungeonYawDockingSolver
extends RefCounted
## F2.8.2: small, pure docking kernel for future rotated prefab packing.
## A socket's local -Z points out of the room. Docking places the candidate
## with the opposite outward normal, preserving yaw from any authored socket.
## Bounded seeded gap/backtracking tries, full OBB collision and corridor safety.
## This is NOT yet wired into the cardinal DungeonPlanner layout generator.

const EPS: float = 0.002

static func dock(anchor_pose: Transform3D, anchor_socket: Transform3D, candidate_socket: Transform3D, gap: float) -> Transform3D:
	var world_socket: Transform3D = anchor_pose * anchor_socket
	var outward: Vector3 = world_socket.basis * Vector3.FORWARD
	var facing := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var desired := Transform3D(world_socket.basis, world_socket.origin + outward * gap) * facing
	return desired * candidate_socket.affine_inverse()


static func solve(anchor_pose: Transform3D, anchor_size: Vector3, anchor_socket: Transform3D, candidate_size: Vector3, candidate_socket: Transform3D, obstacles: Array[Dictionary], min_gap: float, max_gap: float, attempts: int, rng: RandomNumberGenerator, width: float = 1.6) -> Dictionary:
	if rng == null or attempts < 1 or attempts > 64 or not is_finite(min_gap) or not is_finite(max_gap) or min_gap < 0.5 or max_gap < min_gap or max_gap > 30.0:
		return {"success": false, "reason": "INVALID_LIMITS"}
	if not _rigid_yaw(anchor_pose) or not _rigid_y(anchor_socket) or not _rigid_y(candidate_socket) or not anchor_size.is_finite() or not candidate_size.is_finite() or minf(anchor_size.x, anchor_size.z) <= width or minf(candidate_size.x, candidate_size.z) <= width:
		return {"success": false, "reason": "INVALID_GEOMETRY"}
	var anchor_bounds: Dictionary = DungeonOrientedBounds.rectangle(anchor_pose.origin, Vector2(anchor_size.x, anchor_size.z), anchor_pose.basis)
	var start: Transform3D = anchor_pose * anchor_socket
	for attempt in attempts:
		var gap: float = snappedf(rng.randf_range(min_gap, max_gap), 0.25)
		gap = clampf(gap, min_gap, max_gap)
		var pose: Transform3D = dock(anchor_pose, anchor_socket, candidate_socket, gap)
		if not _rigid_yaw(pose):
			continue
		var finish: Transform3D = pose * candidate_socket
		if start.origin.distance_to(finish.origin) < gap - EPS or (start.basis * Vector3.FORWARD).dot(finish.basis * Vector3.FORWARD) > -0.999:
			continue
		var bounds: Dictionary = DungeonOrientedBounds.rectangle(pose.origin, Vector2(candidate_size.x, candidate_size.z), pose.basis)
		if DungeonOrientedBounds.overlaps(anchor_bounds, bounds):
			continue
		var center: Vector3 = (start.origin + finish.origin) * 0.5
		var bridge_basis: Basis = start.basis
		var corridor: Dictionary = DungeonOrientedBounds.corridor(center, Vector2(width + 0.4, gap), bridge_basis)
		var blocked := false
		for other in obstacles:
			if DungeonOrientedBounds.overlaps(bounds, other) or DungeonOrientedBounds.overlaps(corridor, other):
				blocked = true
				break
		if not blocked:
			return {"success": true, "transform": pose, "gap": gap, "start": start, "finish": finish, "corridor": corridor, "attempts": attempt + 1}
	return {"success": false, "reason": "NO_CLEAR_CANDIDATE", "attempts": attempts}


static func _rigid_yaw(pose: Transform3D) -> bool:
	if not pose.origin.is_finite() or not pose.basis.is_finite():
		return false
	var b: Basis = pose.basis
	return absf(b.x.y) < EPS and absf(b.z.y) < EPS and absf(b.y.x) < EPS and absf(b.y.z) < EPS and absf(b.y.y - 1.0) < EPS and absf(b.x.length() - 1.0) < EPS and absf(b.y.length() - 1.0) < EPS and absf(b.z.length() - 1.0) < EPS and absf(b.x.dot(b.z)) < EPS and b.determinant() > 0.99
