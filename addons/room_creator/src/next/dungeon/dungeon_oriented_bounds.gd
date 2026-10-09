@tool
class_name DungeonOrientedBounds
extends RefCounted
## F2.8.2: lightweight SAT 2D oriented boxes. All geometry uses Godot X/Z;
## runtime room height remains shared. No scene instances or physics queries.

const EPS: float = 0.0001

static func rectangle(center: Vector3, size: Vector2, basis: Basis = Basis.IDENTITY) -> Dictionary:
	var x := Vector2(basis.x.x, basis.x.z).normalized()
	var z := Vector2(basis.z.x, basis.z.z).normalized()
	return {"center": Vector2(center.x, center.z), "half": size * 0.5, "x_axis": x, "z_axis": z}


static func room(room_data: RoomPlacementData, extent: Vector3) -> Dictionary:
	return rectangle(room_data.world_transform.origin, Vector2(extent.x, extent.z), room_data.world_transform.basis)


static func corridor(center: Vector3, half_extent: Vector2, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return rectangle(center, half_extent * 2.0, basis)


static func overlaps(a: Dictionary, b: Dictionary, clearance: float = 0.0) -> bool:
	# Separating-axis theorem: four normals suffice for rectangles. Tangency
	# counts as clear, avoiding false positive at deliberate socket seams.
	var d: Vector2 = b["center"] - a["center"]
	for axis in [a["x_axis"], a["z_axis"], b["x_axis"], b["z_axis"]]:
		var radius_a: float = _radius(a, axis)
		var radius_b: float = _radius(b, axis)
		if absf(d.dot(axis)) >= radius_a + radius_b + clearance - EPS:
			return false
	return true


static func contains_point(rect: Dictionary, point: Vector3, inset: float = 0.0) -> bool:
	var delta := Vector2(point.x, point.z) - (rect["center"] as Vector2)
	var x: Vector2 = rect["x_axis"]
	var z: Vector2 = rect["z_axis"]
	var half: Vector2 = rect["half"]
	return absf(delta.dot(x)) <= half.x - inset + EPS and absf(delta.dot(z)) <= half.y - inset + EPS


static func _radius(rect: Dictionary, axis: Vector2) -> float:
	var half: Vector2 = rect["half"]
	var x: Vector2 = rect["x_axis"]
	var z: Vector2 = rect["z_axis"]
	return absf(x.dot(axis)) * half.x + absf(z.dot(axis)) * half.y
