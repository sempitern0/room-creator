@tool
class_name DungeonPlanner
extends RefCounted
## Pure F2 grid topology/embedding. No SceneTree nodes, no global RNG.
## One logical edge always creates exactly two paired openings during compilation.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN
]
const MAX_GRID_SIDE: int = 64

static func generate_layout(config: DungeonConfig) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	if config == null:
		result.report.add_error("CONFIG_MISSING", "Assign a DungeonConfig.")
		return result
	result.seed = config.seed
	result.report = validate_config(config)
	if not result.report.is_valid():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed
	for attempt in range(config.max_attempts):
		result.attempts = attempt + 1
		var target: int = rng.randi_range(config.critical_path_min, config.critical_path_max)
		var start := Vector2i(rng.randi_range(0, config.grid_size.x - 1), rng.randi_range(0, config.grid_size.y - 1))
		var path: Array[Vector2i] = [start]
		var visited: Dictionary = {start: true}
		var budget: Array[int] = [config.search_budget_per_attempt]
		if not _search_path(path, visited, config.grid_size, target, rng, budget):
			result.expansions += config.search_budget_per_attempt - budget[0]
			continue
		result.expansions += config.search_budget_per_attempt - budget[0]
		var layout := _assemble_path(config, path)
		var occupied: Dictionary = {}
		for i in layout.rooms.size():
			occupied[layout.rooms[i].cell] = i
		if not _add_branches(config, layout, occupied, rng):
			continue
		if not _add_loops(config, layout, occupied, rng):
			continue
		if not _assign_room_shapes(config, layout, rng):
			continue
		var report := validate_layout(layout)
		if report.is_valid():
			result.success = true
			result.layout = layout
			result.report = report
			return result
	# Never expose invalid or partial layouts via BuildResult.
	result.report.add_error("LAYOUT_UNSATISFIABLE", "Unable to satisfy critical path, branches, loops and clearance in %d attempts, with budget %d per attempt (seed %d)." % [config.max_attempts, config.search_budget_per_attempt, config.seed])
	return result


static func validate_config(config: DungeonConfig) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if config == null:
		report.add_error("CONFIG_MISSING", "Assign a DungeonConfig.")
		return report
	var grid := config.grid_size
	if grid.x < 1 or grid.y < 1 or grid.x > MAX_GRID_SIDE or grid.y > MAX_GRID_SIDE:
		report.add_error("GRID_SIZE", "Grid axes must be between 1 and %d." % MAX_GRID_SIDE)
		return report
	var cells: int = grid.x * grid.y
	if config.critical_path_min < 2 or config.critical_path_max < config.critical_path_min or config.critical_path_max > cells:
		report.add_error("CRITICAL_PATH", "Critical path range must fit the grid and contain at least two rooms.")
	if config.branch_count < 0 or config.branch_count + config.critical_path_max > cells:
		report.add_error("BRANCH_CAPACITY", "Requested branches and maximum critical path do not fit the grid.")
	if config.loop_count < 0:
		report.add_error("LOOP_COUNT", "Loop count cannot be negative.")
	if config.max_attempts < 1 or config.max_attempts > 32 or config.search_budget_per_attempt < 1 or config.search_budget_per_attempt > 30000:
		report.add_error("SEARCH_BUDGET", "Search limits must be finite and within safety bounds.")
	if not config.room_size.is_finite() or config.room_size.x <= 0.0 or config.room_size.y <= 0.0 or config.room_size.z <= 0.0:
		report.add_error("ROOM_SIZE", "Room size must be finite and positive.")
		return report
	if not is_finite(config.wall_thickness) or config.wall_thickness <= 0.0 or config.wall_thickness * 2.0 >= minf(config.room_size.x, config.room_size.z):
		report.add_error("WALL_THICKNESS", "Invalid wall thickness.")
	if not is_finite(config.door_width) or not is_finite(config.door_height) or config.door_width <= 0.0 or config.door_height <= 0.0:
		report.add_error("DOOR_DIMENSIONS", "Door dimensions must be finite and positive.")
	else:
		if config.door_width > minf(config.room_size.x, config.room_size.z) - config.wall_thickness * 4.0:
			report.add_error("DOOR_FIT", "Door width exceeds the shortest available wall.")
		if config.door_height >= config.room_size.y:
			report.add_error("DOOR_FIT", "Door height must fit below the ceiling.")
		if config.player_radius <= 0.0 or config.door_width < config.player_radius * 2.0:
			report.add_error("PLAYER_WIDTH", "Door must clear the player capsule diameter.")
		if config.player_height <= 0.0 or config.door_height < config.player_height:
			report.add_error("PLAYER_HEIGHT", "Door must clear the standing player height.")
	if config.floor_thickness <= 0.0 or config.ceiling_thickness <= 0.0:
		report.add_error("SURFACE_THICKNESS", "Floor and ceiling thickness must be positive.")
	if config.rectangle_weight < 0 or config.cross_weight < 0 or config.l_shape_weight < 0 or config.t_shape_weight < 0:
		report.add_error("SHAPE_WEIGHT", "Room shape weights must be nonnegative.")
	if config.rectangle_weight + config.cross_weight + config.l_shape_weight + config.t_shape_weight <= 0:
		report.add_error("SHAPE_POOL_EMPTY", "Enable at least one room silhouette.")
	if config.cross_weight + config.l_shape_weight + config.t_shape_weight > 0:
		if config.door_width > minf(config.room_size.x, config.room_size.z) / 3.0 - config.wall_thickness * 2.0:
			report.add_error("SHAPE_DOOR_WIDTH", "With nonrectangular silhouettes, the door must fit the one-third-wide boundary connector.")
	return report


static func _search_path(path: Array[Vector2i], occupied: Dictionary, grid: Vector2i, target: int, rng: RandomNumberGenerator, budget: Array[int]) -> bool:
	if path.size() >= target:
		return true
	var directions := _shuffled_directions(rng)
	for direction in directions:
		if budget[0] <= 0:
			return false
		budget[0] -= 1
		var next: Vector2i = path.back() + direction
		if not _inside(next, grid) or occupied.has(next):
			continue
		path.append(next)
		occupied[next] = true
		if _search_path(path, occupied, grid, target, rng, budget):
			return true
		path.pop_back()
		occupied.erase(next)
	return false


static func _assemble_path(config: DungeonConfig, path: Array[Vector2i]) -> LevelLayout:
	var layout := LevelLayout.new()
	layout.seed = config.seed
	layout.grid_size = config.grid_size
	layout.room_size = config.room_size
	layout.wall_thickness = config.wall_thickness
	layout.floor_thickness = config.floor_thickness
	layout.ceiling_thickness = config.ceiling_thickness
	layout.include_ceiling = config.include_ceiling
	layout.player_radius = config.player_radius
	layout.player_height = config.player_height
	layout.wall_material = config.wall_material
	layout.floor_material = config.floor_material
	layout.ceiling_material = config.ceiling_material
	layout.collision_layer = config.collision_layer
	layout.collision_mask = config.collision_mask
	layout.minimum_critical_rooms = config.critical_path_min
	layout.expected_room_count = path.size() + config.branch_count
	layout.expected_loops = config.loop_count
	for i in path.size():
		var role: RoomPlacementData.Role = RoomPlacementData.Role.MAIN
		if i == 0:
			role = RoomPlacementData.Role.ENTRANCE
		elif i == path.size() - 1:
			role = RoomPlacementData.Role.EXIT
		var room := _make_room(layout, path[i], role)
		layout.rooms.append(room)
		layout.critical_path_ids.append(room.stable_id)
	layout.entrance_id = layout.rooms[0].stable_id
	layout.exit_id = layout.rooms[path.size() - 1].stable_id
	for i in range(path.size() - 1):
		layout.connections.append(_make_connection(config, layout.rooms[i], layout.rooms[i + 1], layout.connections.size()))
	return layout


static func _make_room(layout: LevelLayout, cell: Vector2i, role: RoomPlacementData.Role) -> RoomPlacementData:
	var room := RoomPlacementData.new()
	room.stable_id = "room_%04d" % layout.rooms.size()
	room.cell = cell
	room.world_transform = Transform3D(Basis.IDENTITY, Vector3(float(cell.x) * layout.room_size.x, 0.0, float(cell.y) * layout.room_size.z))
	room.role = role
	return room


static func _make_connection(config: DungeonConfig, from_room: RoomPlacementData, to_room: RoomPlacementData, index: int) -> RoomConnectionData:
	var edge := RoomConnectionData.new()
	edge.stable_id = "edge_%04d" % index
	edge.from_room_id = from_room.stable_id
	edge.to_room_id = to_room.stable_id
	var direction: Vector2i = to_room.cell - from_room.cell
	edge.from_wall = _wall_for_delta(direction)
	edge.to_wall = _wall_for_delta(-direction)
	edge.clear_width = config.door_width
	edge.clear_height = config.door_height
	return edge


static func _add_branches(config: DungeonConfig, layout: LevelLayout, occupied: Dictionary, rng: RandomNumberGenerator) -> bool:
	for _branch in config.branch_count:
		var options: Array[Dictionary] = []
		for index in layout.rooms.size():
			var source := layout.rooms[index]
			for direction in DIRECTIONS:
				var cell: Vector2i = source.cell + direction
				if _inside(cell, config.grid_size) and not occupied.has(cell):
					options.append({"from": index, "cell": cell})
		if options.is_empty():
			return false
		var chosen: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var cell: Vector2i = chosen["cell"]
		var origin: RoomPlacementData = layout.rooms[chosen["from"]]
		var branch_room := _make_room(layout, cell, RoomPlacementData.Role.BRANCH)
		occupied[cell] = layout.rooms.size()
		layout.rooms.append(branch_room)
		layout.connections.append(_make_connection(config, origin, branch_room, layout.connections.size()))
	return true


static func _add_loops(config: DungeonConfig, layout: LevelLayout, occupied: Dictionary, rng: RandomNumberGenerator) -> bool:
	var existing: Dictionary = {}
	for edge in layout.connections:
		existing[_edge_key(edge.from_room_id, edge.to_room_id)] = true
	for _loop in config.loop_count:
		var candidates: Array[Dictionary] = []
		for room in layout.rooms:
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var cell: Vector2i = room.cell + direction
				if not occupied.has(cell):
					continue
				var other: RoomPlacementData = layout.rooms[occupied[cell]]
				if not existing.has(_edge_key(room.stable_id, other.stable_id)):
					candidates.append({"from": room, "to": other})
		if candidates.is_empty():
			return false
		var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var from_room: RoomPlacementData = chosen["from"]
		var to_room: RoomPlacementData = chosen["to"]
		existing[_edge_key(from_room.stable_id, to_room.stable_id)] = true
		layout.connections.append(_make_connection(config, from_room, to_room, layout.connections.size()))
	return true


## Match every actual doorway to an occupied, centered boundary tile.
## Choosing a shape never alters graph edges; incompatible profiles cannot
## silently create unpaired openings or discontinuous passageways.
static func _assign_room_shapes(config: DungeonConfig, layout: LevelLayout, rng: RandomNumberGenerator) -> bool:
	var weights: Array[int] = [
		config.rectangle_weight, config.cross_weight,
		config.l_shape_weight, config.t_shape_weight
	]
	for room in layout.rooms:
		var needed: Array[int] = []
		for edge in layout.connections:
			if edge.from_room_id == room.stable_id:
				needed.append(edge.from_wall)
			elif edge.to_room_id == room.stable_id:
				needed.append(edge.to_wall)
		var candidates: Array[Dictionary] = []
		var total: int = 0
		for kind in weights.size():
			if weights[kind] <= 0:
				continue
			var compatible_rotations: Array[int] = []
			for turns in 4:
				var compatible := true
				for side in needed:
					if not RoomFootprint.supports_wall(kind as RoomFootprint.Shape, turns, side):
						compatible = false
						break
				if compatible:
					compatible_rotations.append(turns)
			if not compatible_rotations.is_empty():
				candidates.append({"shape": kind, "weight": weights[kind], "rotations": compatible_rotations})
				total += weights[kind]
		if total == 0:
			return false
		var ticket: int = rng.randi_range(0, total - 1)
		for option in candidates:
			ticket -= int(option["weight"])
			if ticket < 0:
				room.shape = option["shape"]
				var rotations: Array[int] = option["rotations"]
				room.shape_rotation = rotations[rng.randi_range(0, rotations.size() - 1)]
				break
	return true


static func validate_layout(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		report.add_error("LAYOUT_MISSING", "No layout was generated.")
		return report
	if layout.schema_version != LevelLayout.SCHEMA_VERSION:
		report.add_error("SCHEMA", "Unsupported layout schema version.")
	if layout.grid_size.x < 1 or layout.grid_size.y < 1 or not layout.room_size.is_finite() or layout.room_size.x <= 0.0 or layout.room_size.y <= 0.0 or layout.room_size.z <= 0.0:
		report.add_error("GEOMETRY", "Invalid grid/room size.")
		return report
	if layout.rooms.is_empty():
		report.add_error("EMPTY_LAYOUT", "No rooms exist.")
		return report
	if layout.expected_room_count != layout.rooms.size():
		report.add_error("ROOM_COUNT", "Missing or surplus placed rooms.")
	if layout.connections.size() - layout.rooms.size() + 1 != layout.expected_loops:
		report.add_error("LOOP_COUNT", "Cycle count differs from requested loops.")
	var by_id: Dictionary = {}
	var by_cell: Dictionary = {}
	var adjacency: Dictionary = {}
	for room in layout.rooms:
		if room == null:
			report.add_error("NULL_ROOM", "Null room placement.")
			continue
		if room.stable_id.is_empty() or by_id.has(room.stable_id):
			report.add_error("DUPLICATE_ROOM", "Duplicate or empty room ID: %s" % room.stable_id)
		if by_cell.has(room.cell) or not _inside(room.cell, layout.grid_size):
			report.add_error("SPATIAL_OVERLAP", "Duplicate or out-of-bounds cell: %s" % str(room.cell))
		if not room.world_transform.basis.is_equal_approx(Basis.IDENTITY) or not room.world_transform.origin.is_equal_approx(Vector3(float(room.cell.x) * layout.room_size.x, 0.0, float(room.cell.y) * layout.room_size.z)):
			report.add_error("ROOM_TRANSFORM", "Room transform disagrees with the grid footprint: %s" % room.stable_id)
		if not RoomFootprint.is_valid_shape(int(room.shape)) or room.shape_rotation < 0 or room.shape_rotation > 3:
			report.add_error("ROOM_SHAPE", "Invalid shape or rotation in %s." % room.stable_id)
		by_id[room.stable_id] = room
		by_cell[room.cell] = room
		adjacency[room.stable_id] = PackedStringArray()
	if not by_id.has(layout.entrance_id) or not by_id.has(layout.exit_id) or layout.entrance_id == layout.exit_id:
		report.add_error("ENDPOINTS", "Entrance and exit must reference different valid rooms.")
		return report
	if by_id[layout.entrance_id].role != RoomPlacementData.Role.ENTRANCE or by_id[layout.exit_id].role != RoomPlacementData.Role.EXIT:
		report.add_error("ENDPOINT_ROLES", "Endpoint roles do not match entrance/exit IDs.")
	var seen_edges: Dictionary = {}
	for edge in layout.connections:
		if edge == null:
			report.add_error("NULL_EDGE", "Null connection.")
			continue
		if edge.stable_id.is_empty() or seen_edges.has(edge.stable_id):
			report.add_error("EDGE_ID", "Duplicate or empty edge ID: %s" % edge.stable_id)
		if not by_id.has(edge.from_room_id) or not by_id.has(edge.to_room_id) or edge.from_room_id == edge.to_room_id:
			report.add_error("BAD_EDGE", "Edge %s has a missing/identical endpoint." % edge.stable_id)
			continue
		var pair := _edge_key(edge.from_room_id, edge.to_room_id)
		if seen_edges.has(pair):
			report.add_error("DUPLICATE_EDGE", "Connection appears more than once: %s" % pair)
		seen_edges[edge.stable_id] = true
		seen_edges[pair] = true
		var a: RoomPlacementData = by_id[edge.from_room_id]
		var b: RoomPlacementData = by_id[edge.to_room_id]
		var delta: Vector2i = b.cell - a.cell
		if absi(delta.x) + absi(delta.y) != 1:
			report.add_error("NONADJACENT_EDGE", "Connection %s does not join face-adjacent rooms." % edge.stable_id)
			continue
		if edge.from_wall != _wall_for_delta(delta) or edge.to_wall != _wall_for_delta(-delta):
			report.add_error("SOCKET_RECIPROCITY", "Connection %s has incorrect wall normals." % edge.stable_id)
		if edge.clear_width <= 0.0 or edge.clear_height <= 0.0 or not is_finite(edge.clear_width) or not is_finite(edge.clear_height):
			report.add_error("CLEARANCE", "Invalid opening metrics: %s" % edge.stable_id)
		adjacency[a.stable_id].append(b.stable_id)
		adjacency[b.stable_id].append(a.stable_id)
	for id in adjacency:
		if adjacency[id].size() > 4:
			report.add_error("ROOM_DEGREE", "More than four doorways on %s." % id)
	var reached: Dictionary = {layout.entrance_id: 0}
	var queue: Array[String] = [layout.entrance_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in adjacency[current]:
			if not reached.has(neighbor):
				reached[neighbor] = reached[current] + 1
				queue.append(neighbor)
	if reached.size() != by_id.size() or not reached.has(layout.exit_id):
		report.add_error("DISCONNECTED", "Not every room is reachable from the entrance.")
	elif reached[layout.exit_id] + 1 < layout.minimum_critical_rooms:
		report.add_error("SHORTCUT", "Shortest entrance-to-exit path is shorter than critical_path_min.")
	if layout.critical_path_ids.size() < layout.minimum_critical_rooms or layout.critical_path_ids[0] != layout.entrance_id or layout.critical_path_ids[layout.critical_path_ids.size() - 1] != layout.exit_id:
		report.add_error("CRITICAL_PATH_IDS", "Recorded main path is missing/invalid.")
	else:
		for index in range(layout.critical_path_ids.size() - 1):
			var a_id: String = layout.critical_path_ids[index]
			var b_id: String = layout.critical_path_ids[index + 1]
			if not adjacency.has(a_id) or not adjacency[a_id].has(b_id):
				report.add_error("CRITICAL_PATH_EDGE", "Recorded main path contains a disconnected segment.")
				break
	if report.is_valid():
		# Validate the exact authored reciprocal openings used by the real compiler.
		for room in layout.rooms:
			var blueprint := make_blueprint(layout, room)
			var geometry_report := RoomGeometryBuilder.validate(blueprint)
			for error in geometry_report.errors:
				report.add_error("ROOM_GEOMETRY", "%s: %s" % [room.stable_id, error])
	return report


static func make_blueprint(layout: LevelLayout, room: RoomPlacementData) -> RoomBlueprint:
	var blueprint := RoomBlueprint.new()
	blueprint.stable_id = room.stable_id
	blueprint.room_size = layout.room_size
	blueprint.shape = room.shape
	blueprint.shape_rotation = room.shape_rotation
	blueprint.wall_thickness = layout.wall_thickness
	blueprint.floor_thickness = layout.floor_thickness
	blueprint.ceiling_thickness = layout.ceiling_thickness
	blueprint.include_ceiling = layout.include_ceiling
	blueprint.agent_radius = layout.player_radius
	blueprint.agent_height = layout.player_height
	blueprint.wall_material = layout.wall_material
	blueprint.floor_material = layout.floor_material
	blueprint.ceiling_material = layout.ceiling_material
	blueprint.collision_layer = layout.collision_layer
	blueprint.collision_mask = layout.collision_mask
	for edge in layout.connections:
		if edge.from_room_id == room.stable_id or edge.to_room_id == room.stable_id:
			var opening := RoomOpening.new()
			opening.stable_id = edge.stable_id
			opening.kind = RoomOpening.Kind.DOOR
			opening.wall = edge.from_wall if edge.from_room_id == room.stable_id else edge.to_wall
			opening.width = edge.clear_width
			opening.height = edge.clear_height
			blueprint.openings.append(opening)
	return blueprint


static func _wall_for_delta(delta: Vector2i) -> RoomOpening.Wall:
	if delta.x == 1:
		return RoomOpening.Wall.RIGHT
	if delta.x == -1:
		return RoomOpening.Wall.LEFT
	if delta.y == 1:
		return RoomOpening.Wall.BACK
	return RoomOpening.Wall.FRONT


static func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _inside(cell: Vector2i, grid: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid.x and cell.y < grid.y


static func _shuffled_directions(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var directions: Array[Vector2i] = DIRECTIONS.duplicate()
	for i in range(directions.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var original: Vector2i = directions[i]
		directions[i] = directions[j]
		directions[j] = original
	return directions
