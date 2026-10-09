@tool
class_name DungeonCorridorRouter
extends RefCounted
## F2.6: deterministic orthogonal four-point dogleg between facing sockets.
## Every segment stays axis-aligned; no arbitrary room rotation is implied.
## Shared corridor envelopes drive both geometry and overlap validation.

const EPS: float = 0.001

static func build_route(layout: LevelLayout, edge: RoomConnectionData, a: RoomPlacementData, b: RoomPlacementData) -> PackedVector3Array:
	var size_a: Vector3 = DungeonPlanner.actual_size(layout, a)
	var size_b: Vector3 = DungeonPlanner.actual_size(layout, b)
	var x_axis: bool = edge.from_wall == RoomOpening.Wall.RIGHT or edge.from_wall == RoomOpening.Wall.LEFT
	var sign_direction: float = -1.0 if edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.FRONT else 1.0
	var p0: Vector3 = a.world_transform.origin
	var p3: Vector3 = b.world_transform.origin
	if x_axis:
		p0.x += sign_direction * size_a.x * 0.5
		p3.x -= sign_direction * size_b.x * 0.5
	else:
		p0.z += sign_direction * size_a.z * 0.5
		p3.z -= sign_direction * size_b.z * 0.5
	var p1: Vector3 = p0
	var p2: Vector3 = p3
	if x_axis:
		p1.x = (p0.x + p3.x) * 0.5
		p2.x = p1.x
	else:
		p1.z = (p0.z + p3.z) * 0.5
		p2.z = p1.z
	return PackedVector3Array([p0, p1, p2, p3])


static func rectangles(layout: LevelLayout, edge: RoomConnectionData, route: PackedVector3Array) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	if route.size() != 4:
		return shapes
	var half: float = edge.clear_width * 0.5 + layout.wall_thickness
	for i in 3:
		var start: Vector3 = route[i]
		var finish: Vector3 = route[i + 1]
		var span: Vector3 = finish - start
		if span.length() <= EPS:
			continue
		var x_axis: bool = absf(span.x) > absf(span.z)
		shapes.append({"center": (start + finish) * 0.5,
			"half": Vector2(absf(span.x) * 0.5 if x_axis else half, half if x_axis else absf(span.z) * 0.5)})
	# Include each corner's joint clearance so a capsule can actually turn.
	for index in [1, 2]:
		shapes.append({"center": route[index], "half": Vector2(half, half)})
	return shapes


static func validate_route(layout: LevelLayout, edge: RoomConnectionData, route: PackedVector3Array, a: RoomPlacementData, b: RoomPlacementData) -> bool:
	if route.size() != 4:
		return false
	var expected: PackedVector3Array = build_route(layout, edge, a, b)
	for i in 4:
		if not route[i].is_finite() or route[i].distance_to(expected[i]) > EPS:
			return false
	var delta: Vector3 = b.world_transform.origin - a.world_transform.origin
	var x_axis: bool = edge.from_wall == RoomOpening.Wall.RIGHT or edge.from_wall == RoomOpening.Wall.LEFT
	var sign_direction: float = -1.0 if edge.from_wall == RoomOpening.Wall.LEFT or edge.from_wall == RoomOpening.Wall.FRONT else 1.0
	var axial: float = delta.x if x_axis else delta.z
	var sa: Vector3 = DungeonPlanner.actual_size(layout, a)
	var sb: Vector3 = DungeonPlanner.actual_size(layout, b)
	var span: float = (sa.x + sb.x) * 0.5 if x_axis else (sa.z + sb.z) * 0.5
	var gap: float = axial * sign_direction - span
	# Short connectors cannot fit two turning junctions without intersecting
	# their own room walls. Try another seeded position instead.
	if gap < edge.clear_width + 2.0 * layout.wall_thickness + 0.1:
		return false
	var offset: float = absf(delta.z) if x_axis else absf(delta.x)
	if offset < 0.1:
		return false
	return true


static func overlap_xz(a: Dictionary, b: Dictionary) -> bool:
	var ca: Vector3 = a["center"]
	var cb: Vector3 = b["center"]
	var ha: Vector2 = a["half"]
	var hb: Vector2 = b["half"]
	return absf(ca.x - cb.x) < ha.x + hb.x - EPS and absf(ca.z - cb.z) < ha.y + hb.y - EPS
