@tool
class_name RoomGeometryBuilder
extends RefCounted
## Deterministic rectangular-room compiler. No scene nodes are created during validation.
## Each wall is tiled around its openings; no live CSG or convex hull blocks doorways.

const EPSILON := 0.0001

static func validate(blueprint: RoomBlueprint) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if blueprint == null:
		report.add_error("BLUEPRINT_MISSING", "Assign a RoomBlueprint resource.")
		return report
	var size := blueprint.room_size
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		report.add_error("ROOM_SIZE", "Room dimensions must be finite and positive.")
		return report
	if not is_finite(blueprint.wall_thickness) or blueprint.wall_thickness <= 0.0 or blueprint.wall_thickness * 2.0 >= minf(size.x, size.z):
		report.add_error("WALL_THICKNESS", "Wall thickness must fit inside the room.")
	if not is_finite(blueprint.floor_thickness) or blueprint.floor_thickness <= 0.0:
		report.add_error("FLOOR_THICKNESS", "Floor thickness must be positive.")
	if not is_finite(blueprint.ceiling_thickness) or blueprint.ceiling_thickness <= 0.0:
		report.add_error("CEILING_THICKNESS", "Ceiling thickness must be positive.")
	if blueprint.agent_radius <= 0.0 or blueprint.agent_height <= 0.0:
		report.add_error("AGENT_METRICS", "Agent dimensions must be positive.")
	var seen_ids: Dictionary = {}
	for opening in blueprint.openings:
		if opening == null:
			report.add_error("OPENING_NULL", "Remove null entries from openings.")
			continue
		if not opening.enabled:
			continue
		if opening.stable_id.is_empty() or seen_ids.has(opening.stable_id):
			report.add_error("OPENING_ID", "Opening IDs must be nonempty and unique: %s" % opening.stable_id)
		seen_ids[opening.stable_id] = true
		var wall_length: float = size.x if opening.wall == RoomOpening.Wall.FRONT or opening.wall == RoomOpening.Wall.BACK else size.z - 2.0 * blueprint.wall_thickness
		if not is_finite(opening.offset) or not is_finite(opening.width) or not is_finite(opening.height) or not is_finite(opening.sill_height):
			report.add_error("OPENING_FINITE", "Non-finite coordinates in %s" % opening.stable_id)
			continue
		if opening.width <= 0.0 or opening.height <= 0.0 or opening.sill_height < 0.0:
			report.add_error("OPENING_SIZE", "Opening %s has invalid dimensions." % opening.stable_id)
			continue
		if absf(opening.offset) + opening.width * 0.5 > wall_length * 0.5 - blueprint.wall_thickness - EPSILON:
			report.add_error("OPENING_MARGIN", "Opening %s is too near a wall end." % opening.stable_id)
		if opening.sill_height + opening.height > size.y - EPSILON:
			report.add_error("OPENING_TOP", "Opening %s extends beyond the room ceiling." % opening.stable_id)
		if opening.kind == RoomOpening.Kind.DOOR or opening.kind == RoomOpening.Kind.ARCH:
			if absf(opening.sill_height) > EPSILON:
				report.add_error("DOOR_SILL", "Walkable opening %s must start at floor level." % opening.stable_id)
			if opening.width + EPSILON < 2.0 * blueprint.agent_radius:
				report.add_error("DOOR_WIDTH", "Opening %s is narrower than the player diameter." % opening.stable_id)
			if opening.height + EPSILON < blueprint.agent_height:
				report.add_error("DOOR_HEIGHT", "Opening %s has insufficient standing clearance." % opening.stable_id)
	for i in blueprint.openings.size():
		var a := blueprint.openings[i]
		if a == null or not a.enabled:
			continue
		for j in range(i + 1, blueprint.openings.size()):
			var b := blueprint.openings[j]
			if b == null or not b.enabled or a.wall != b.wall:
				continue
			var horizontal_overlap := absf(a.offset - b.offset) < (a.width + b.width) * 0.5 - EPSILON
			var vertical_overlap := a.sill_height < b.sill_height + b.height - EPSILON and b.sill_height < a.sill_height + a.height - EPSILON
			if horizontal_overlap and vertical_overlap:
				report.add_error("OPENINGS_OVERLAP", "Openings %s and %s intersect." % [a.stable_id, b.stable_id])
	return report


static func build(blueprint: RoomBlueprint, with_collisions: bool = true) -> Node3D:
	if not validate(blueprint).is_valid():
		return null
	var root := Node3D.new()
	root.name = "RoomGeometry"
	root.set_meta("room_creator_generated", true)
	var size := blueprint.room_size
	_add_box(root, "Floor", Vector3(0.0, -blueprint.floor_thickness * 0.5, 0.0),
		Vector3(size.x, blueprint.floor_thickness, size.z), blueprint.floor_material, blueprint, with_collisions)
	if blueprint.include_ceiling:
		_add_box(root, "Ceiling", Vector3(0.0, size.y + blueprint.ceiling_thickness * 0.5, 0.0),
			Vector3(size.x, blueprint.ceiling_thickness, size.z), blueprint.ceiling_material, blueprint, with_collisions)
	for side in range(4):
		_build_wall(root, blueprint, side, with_collisions)
	for opening in blueprint.openings:
		if opening != null and opening.enabled and opening.kind != RoomOpening.Kind.WINDOW:
			_add_socket(root, blueprint, opening)
	return root


static func _build_wall(root: Node3D, blueprint: RoomBlueprint, side: int, collisions: bool) -> void:
	var size := blueprint.room_size
	var thickness := blueprint.wall_thickness
	var along_x := side == RoomOpening.Wall.FRONT or side == RoomOpening.Wall.BACK
	var length: float = size.x if along_x else size.z - thickness * 2.0
	var horizontal: Array[float] = [-length * 0.5, length * 0.5]
	var vertical: Array[float] = [0.0, size.y]
	var relevant: Array[RoomOpening] = []
	for opening in blueprint.openings:
		if opening == null or not opening.enabled or opening.wall != side:
			continue
		relevant.append(opening)
		horizontal.append(opening.offset - opening.width * 0.5)
		horizontal.append(opening.offset + opening.width * 0.5)
		vertical.append(opening.sill_height)
		vertical.append(opening.sill_height + opening.height)
	horizontal.sort()
	vertical.sort()
	for x in range(horizontal.size() - 1):
		for y in range(vertical.size() - 1):
			var start := horizontal[x]
			var end := horizontal[x + 1]
			var low := vertical[y]
			var high := vertical[y + 1]
			if end - start <= EPSILON or high - low <= EPSILON:
				continue
			var mid := (start + end) * 0.5
			var mid_y := (low + high) * 0.5
			var void_cell := false
			for opening in relevant:
				if absf(mid - opening.offset) < opening.width * 0.5 - EPSILON and mid_y > opening.sill_height + EPSILON and mid_y < opening.sill_height + opening.height - EPSILON:
					void_cell = true
					break
			if void_cell:
				continue
			var pos := Vector3.ZERO
			var box_size := Vector3.ZERO
			if along_x:
				pos = Vector3(mid, (low + high) * 0.5, (-size.z + thickness) * 0.5 if side == RoomOpening.Wall.FRONT else (size.z - thickness) * 0.5)
				box_size = Vector3(end - start, high - low, thickness)
			else:
				pos = Vector3((-size.x + thickness) * 0.5 if side == RoomOpening.Wall.LEFT else (size.x - thickness) * 0.5, (low + high) * 0.5, mid)
				box_size = Vector3(thickness, high - low, end - start)
			_add_box(root, "Wall_%d_%d_%d" % [side, x, y], pos, box_size, blueprint.wall_material, blueprint, collisions)


static func _add_box(root: Node3D, label: String, pos: Vector3, dimensions: Vector3, material: Material, blueprint: RoomBlueprint, collisions: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = pos
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	if material != null:
		mesh.material = material
	visual.mesh = mesh
	root.add_child(visual)
	if collisions:
		var body := StaticBody3D.new()
		body.name = "StaticBody"
		body.collision_layer = blueprint.collision_layer
		body.collision_mask = blueprint.collision_mask
		visual.add_child(body)
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		var box := BoxShape3D.new()
		box.size = dimensions
		shape.shape = box
		body.add_child(shape)


static func _add_socket(root: Node3D, blueprint: RoomBlueprint, opening: RoomOpening) -> void:
	var half := blueprint.room_size * 0.5
	var t := blueprint.wall_thickness * 0.5
	var pos := Vector3.ZERO
	var yaw := 0.0
	match opening.wall:
		RoomOpening.Wall.FRONT:
			pos = Vector3(opening.offset, opening.sill_height, -half.z + t)
		RoomOpening.Wall.BACK:
			pos = Vector3(opening.offset, opening.sill_height, half.z - t)
			yaw = PI
		RoomOpening.Wall.LEFT:
			pos = Vector3(-half.x + t, opening.sill_height, opening.offset)
			yaw = PI * 0.5
		RoomOpening.Wall.RIGHT:
			pos = Vector3(half.x - t, opening.sill_height, opening.offset)
			yaw = -PI * 0.5
	var marker := Marker3D.new()
	marker.name = "Socket_" + opening.stable_id.validate_node_name()
	marker.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	marker.set_meta("stable_id", opening.stable_id)
	marker.set_meta("wall", opening.wall)
	marker.set_meta("clear_width", opening.width)
	marker.set_meta("clear_height", opening.height)
	root.add_child(marker)
