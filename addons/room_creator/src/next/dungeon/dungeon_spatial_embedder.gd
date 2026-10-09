@tool
class_name DungeonSpatialEmbedder
extends RefCounted
## F2.4: seed-controlled embedding of the logical grid into non-uniform X/Z
## room-center coordinates. Sharing one coordinate per column and per row
## guarantees opposed sockets remain perfectly coaxial. No scene mutations.

const EPS: float = 0.001

static func embed(config: DungeonConfig, layout: LevelLayout, rng: RandomNumberGenerator) -> void:
	layout.column_positions = PackedFloat32Array()
	layout.row_positions = PackedFloat32Array()
	if not config.use_variable_grid_spacing:
		return
	layout.column_positions = _make_axis(layout.grid_size.x, layout.room_size.x, config.min_corridor_gap, config.max_corridor_gap, rng)
	layout.row_positions = _make_axis(layout.grid_size.y, layout.room_size.z, config.min_corridor_gap, config.max_corridor_gap, rng)
	for room in layout.rooms:
		room.world_transform.origin = expected_origin(layout, room.cell)


static func expected_origin(layout: LevelLayout, cell: Vector2i) -> Vector3:
	var x: float = float(cell.x) * layout.room_size.x
	var z: float = float(cell.y) * layout.room_size.z
	if layout.column_positions.size() == layout.grid_size.x and cell.x >= 0 and cell.x < layout.column_positions.size():
		x = layout.column_positions[cell.x]
	if layout.row_positions.size() == layout.grid_size.y and cell.y >= 0 and cell.y < layout.row_positions.size():
		z = layout.row_positions[cell.y]
	return Vector3(x, 0.0, z)


static func validate(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		report.add_error("MISSING_LAYOUT", "No level layout supplied.")
		return report
	var columns: int = layout.column_positions.size()
	var rows: int = layout.row_positions.size()
	if columns == 0 and rows == 0:
		# Legacy scenes store no embedding arrays and imply a regular grid.
		return report
	if columns != layout.grid_size.x or rows != layout.grid_size.y:
		report.add_error("AXIS_COUNT", "Spatial arrays must each have one position per respective grid coordinate.")
		return report
	_validate_axis(layout.column_positions, layout.room_size.x, "X", report)
	_validate_axis(layout.row_positions, layout.room_size.z, "Z", report)
	return report


static func _make_axis(size: int, cell_size: float, min_gap: float, max_gap: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.append(0.0)
	for i in range(1, size):
		var gap: float = clampf(snappedf(rng.randf_range(min_gap, max_gap), 0.25), min_gap, max_gap)
		values.append(values[-1] + cell_size + gap)
	return values


static func _validate_axis(values: PackedFloat32Array, cell_size: float, name: String, report: RoomValidationReport) -> void:
	if values.is_empty() or not is_finite(values[0]) or absf(values[0]) > EPS:
		report.add_error("AXIS_START", "%s spacing array must start at world coordinate zero." % name)
		return
	for i in range(1, values.size()):
		if not is_finite(values[i]) or values[i] - values[i - 1] < cell_size - EPS:
			report.add_error("AXIS_ORDER", "%s grid columns/rows overlap or contain non-finite positions at index %d." % [name, i])
			return
