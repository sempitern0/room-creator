@tool
class_name DungeonStructuralPrefab
extends Resource
## F2.7: a complete, engine-native room shell with its OWN primitive physics.
## Unlike DungeonRoomModule, this replaces the procedural room geometry.
## Supported placement: unscaled room, grid-cardinal quarter-turn rotations.
## Every authored exterior hole MUST have exactly one meter-space wall socket.

@export var stable_id: String = "structural_room"
@export_range(1, 100, 1) var weight: int = 10
@export var authored_size: Vector3 = Vector3(8.0, 3.5, 8.0)
@export_range(0.5, 5.0, 0.05) var doorway_width: float = 1.6
@export_range(0.5, 6.0, 0.05) var doorway_height: float = 2.3
@export var packed_room: PackedScene

const WALL_SIDES: Array[int] = [
	RoomOpening.Wall.FRONT, RoomOpening.Wall.RIGHT,
	RoomOpening.Wall.BACK, RoomOpening.Wall.LEFT
]
const SOCKET_NAMES: Array[String] = [
	"SocketFront", "SocketRight", "SocketBack", "SocketLeft"
]
const EPS: float = 0.005

func validate() -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if stable_id.is_empty() or weight < 1 or weight > 100:
		report.add_error("PREFAB_PROFILE", "Structural prefab ID and positive bounded weight are required.")
	if not authored_size.is_finite() or authored_size.x <= 1.0 or authored_size.y <= 1.0 or authored_size.z <= 1.0:
		report.add_error("PREFAB_SIZE", "Structural prefab requires positive, finite authored dimensions.")
		return report
	if not is_finite(doorway_width) or not is_finite(doorway_height) or doorway_width <= 0.0 or doorway_height <= 0.0 or doorway_height >= authored_size.y or doorway_width >= minf(authored_size.x, authored_size.z):
		report.add_error("PREFAB_DOOR", "Invalid authored doorway clearance.")
		return report
	if packed_room == null:
		report.add_error("PREFAB_MISSING", "Assign a structural PackedScene.")
		return report
	_inspect(report)
	return report


func compatible_rotations(required_walls: Array[int], actual_size: Vector3, width: float, height: float) -> Array[int]:
	var rotations: Array[int] = []
	if packed_room == null or absf(width - doorway_width) > EPS or absf(height - doorway_height) > EPS:
		return rotations
	var report := validate()
	if not report.is_valid():
		return rotations
	var sockets := _read_sockets(packed_room.get_state(), null)
	if sockets.size() != required_walls.size():
		return rotations
	for turns in 4:
		var rotated_size := Vector3(authored_size.z, authored_size.y, authored_size.x) if turns % 2 == 1 else authored_size
		if rotated_size.distance_to(actual_size) > EPS:
			continue
		var valid := true
		for authored_side in sockets.keys():
			var destination: int = DungeonRoomModule.rotated_wall(int(authored_side), turns)
			if not required_walls.has(destination):
				valid = false
				break
		if valid:
			rotations.append(turns)
	return rotations


## Signed lateral offset in the destination room's wall coordinates after
## a cardinal quarter turn. Reads the immutable SceneState (no instantiation).
func rotated_socket_offset(world_wall: int, turns: int) -> float:
	if packed_room == null:
		return 0.0
	var authored_index: int = posmod(WALL_SIDES.find(world_wall) - turns, 4)
	var source_wall: int = WALL_SIDES[authored_index]
	var sockets: Dictionary = _read_sockets(packed_room.get_state(), null)
	if not sockets.has(source_wall):
		return 0.0
	var transform: Transform3D = sockets[source_wall]
	var rotated: Vector3 = Basis(Vector3.UP, -float(turns) * PI * 0.5) * transform.origin
	return rotated.x if world_wall == RoomOpening.Wall.FRONT or world_wall == RoomOpening.Wall.BACK else rotated.z


func _inspect(report: RoomValidationReport) -> void:
	var state := packed_room.get_state()
	if state == null or state.get_node_count() < 4:
		report.add_error("PREFAB_EMPTY", "Expected a Node3D root, sockets, visual meshes and static collision.")
		return
	var root_type: StringName = state.get_node_type(0)
	if root_type != &"Node3D":
		report.add_error("PREFAB_ROOT", "Structural prefab root must be a Node3D.")
	var sockets := _read_sockets(state, report)
	if sockets.is_empty():
		report.add_error("PREFAB_SOCKETS", "Add at least one valid, direct child Marker3D socket.")
	var physics_bodies: Dictionary = {}
	var solid_boxes: Array[Dictionary] = []
	var has_mesh := false
	var has_box := false
	for i in state.get_node_count():
		var kind: StringName = state.get_node_type(i)
		var node_path: String = str(state.get_node_path(i))
		if kind == &"MeshInstance3D":
			has_mesh = true
		if kind == &"StaticBody3D":
			if node_path.trim_prefix("./").contains("/"):
				report.add_error("PREFAB_BODY_PARENT", "StaticBody3D must be a direct child of the prefab root.")
			for j in state.get_node_property_count(i):
				if state.get_node_property_name(i, j) == &"transform":
					var body_pose: Transform3D = state.get_node_property_value(i, j)
					if not body_pose.is_equal_approx(Transform3D.IDENTITY):
						report.add_error("PREFAB_BODY_TRANSFORM", "StaticBody3D children must have identity transforms; place BoxShape3D children instead.")
			physics_bodies[str(state.get_node_name(i))] = true
		elif kind == &"CollisionShape3D":
			var parent_path: String = node_path.get_base_dir().trim_prefix("./")
			if not physics_bodies.has(parent_path):
				report.add_error("PREFAB_COLLISION_PARENT", "CollisionShape3D must be under a direct StaticBody3D.")
			var box: BoxShape3D = null
			var transform := Transform3D.IDENTITY
			for j in state.get_node_property_count(i):
				var prop := state.get_node_property_name(i, j)
				if prop == &"shape":
					box = state.get_node_property_value(i, j) as BoxShape3D
				elif prop == &"transform":
					transform = state.get_node_property_value(i, j)
			if box == null or not DungeonYawDockingSolver._rigid_yaw(transform):
				report.add_error("PREFAB_PRIMITIVE", "Static room colliders must be rigid, horizontal-yaw BoxShape3D instances (no scaling, pitch or roll).")
				continue
			has_box = true
			solid_boxes.append({"center": transform.origin, "half": box.size * 0.5,
				"footprint": DungeonOrientedBounds.rectangle(transform.origin, Vector2(box.size.x, box.size.z), transform.basis)})
			if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
				report.add_error("PREFAB_BOX_SIZE", "All collision boxes must have positive dimensions.")
			_check_box_clearance(box, transform, sockets, report)
		elif kind != &"Node3D" and kind != &"Marker3D" and kind != &"MeshInstance3D" and kind != &"StaticBody3D":
			report.add_error("PREFAB_NODE_TYPE", "Unsupported structural prefab node type: %s." % kind)
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"script" and state.get_node_property_value(i, j) != null:
				report.add_error("PREFAB_SCRIPT", "Structural prefab scenes must be script-free.")
	if not has_mesh or not has_box:
		report.add_error("PREFAB_GEOMETRY", "Room must provide visual mesh and real BoxShape3D physics.")
	for side in WALL_SIDES:
		if sockets.has(side):
			continue
		var face: Vector3 = _expected_position(side)
		# Unpaired central exits must be physically sealed. Check several
		# standing heights, so a missing lintel/partial wall cannot turn into
		# a second accidental door with no logical graph connection.
		for height in [0.4, doorway_height * 0.5, doorway_height - 0.1]:
			var probe := Vector3(face.x, height, face.z)
			var blocked := false
			for bounds in solid_boxes:
				var center: Vector3 = bounds["center"]
				var half: Vector3 = bounds["half"]
				if absf(probe.y - center.y) <= half.y + EPS and DungeonOrientedBounds.contains_point(bounds["footprint"], probe):
					blocked = true
					break
			if not blocked:
				report.add_error("PREFAB_UNPAIRED_EXIT", "The center of a wall without a socket must be sealed by collision: side %d." % side)
				break


func _read_sockets(state: SceneState, report: RoomValidationReport) -> Dictionary:
	var sockets: Dictionary = {}
	for i in range(1, state.get_node_count()):
		var name: String = str(state.get_node_name(i))
		if not name.begins_with("Socket"):
			continue
		var index := SOCKET_NAMES.find(name)
		if state.get_node_type(i) != &"Marker3D" or index < 0 or not ["./" + name, name].has(str(state.get_node_path(i))):
			if report != null:
				report.add_error("PREFAB_SOCKET_NODE", "Sockets must be direct Marker3D nodes with recognized cardinal names.")
			continue
		var transform := Transform3D.IDENTITY
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"transform":
				transform = state.get_node_property_value(i, j)
		var side: int = WALL_SIDES[index]
		var expected := _expected_position(side)
		var outward := _normal(side)
		var lateral: float = transform.origin.x if side == RoomOpening.Wall.FRONT or side == RoomOpening.Wall.BACK else transform.origin.z
		var wall_width: float = authored_size.x if side == RoomOpening.Wall.FRONT or side == RoomOpening.Wall.BACK else authored_size.z
		# Door opening must remain inside the face after a conservative 0.2 m
		# wall-end margin. Vertical position stays anchored to the floor.
		var limit: float = wall_width * 0.5 - doorway_width * 0.5 - 0.2
		var off_axis: float = transform.origin.z - expected.z if side == RoomOpening.Wall.FRONT or side == RoomOpening.Wall.BACK else transform.origin.x - expected.x
		if absf(off_axis) > EPS or absf(transform.origin.y) > EPS or not is_finite(lateral) or absf(lateral) > limit + EPS or (transform.basis * Vector3.FORWARD).distance_to(outward) > EPS:
			if report != null:
				report.add_error("PREFAB_SOCKET_POSE", "%s must face outwards, remain on its wall face and leave room for a full-width door." % name)
			continue
		if sockets.has(side) and report != null:
			report.add_error("PREFAB_SOCKET_DUPLICATE", "Duplicate socket side %s." % name)
		sockets[side] = transform
	return sockets


func _expected_position(wall: int) -> Vector3:
	match wall:
		RoomOpening.Wall.FRONT:
			return Vector3(0.0, 0.0, -authored_size.z * 0.5)
		RoomOpening.Wall.BACK:
			return Vector3(0.0, 0.0, authored_size.z * 0.5)
		RoomOpening.Wall.LEFT:
			return Vector3(-authored_size.x * 0.5, 0.0, 0.0)
	return Vector3(authored_size.x * 0.5, 0.0, 0.0)


static func _normal(wall: int) -> Vector3:
	match wall:
		RoomOpening.Wall.FRONT:
			return Vector3.FORWARD
		RoomOpening.Wall.BACK:
			return Vector3.BACK
		RoomOpening.Wall.LEFT:
			return Vector3.LEFT
	return Vector3.RIGHT


func _check_box_clearance(box: BoxShape3D, pose: Transform3D, sockets: Dictionary, report: RoomValidationReport) -> void:
	var center: Vector3 = pose.origin
	var half: Vector3 = box.size * 0.5
	if not center.is_finite() or not box.size.is_finite():
		report.add_error("PREFAB_COLLIDER_BOUNDS", "Collision collider must have finite dimensions.")
		return
	var footprint: Dictionary = DungeonOrientedBounds.rectangle(center, Vector2(box.size.x, box.size.z), pose.basis)
	var corner_x: Vector3 = pose.basis.x * half.x
	var corner_z: Vector3 = pose.basis.z * half.z
	for sign_x in [-1, 1]:
		for sign_z in [-1, 1]:
			var corner: Vector3 = center + float(sign_x) * corner_x + float(sign_z) * corner_z
			if absf(corner.x) > authored_size.x * 0.5 + EPS or absf(corner.z) > authored_size.z * 0.5 + EPS:
				report.add_error("PREFAB_COLLIDER_BOUNDS", "The oriented static box must remain inside the authored rectangular room footprint.")
				return
	# Conservative capsule clearance along two orthogonal interior legs.
	# A yaw-rotated physics obstacle is evaluated by SAT (not its AABB).
	var radius: float = doorway_width * 0.5 - EPS
	var bottom: float = 0.0
	var top: float = doorway_height - EPS
	if center.y + half.y <= bottom + EPS or center.y - half.y >= top - EPS:
		return
	for side in sockets.keys():
		var start := Vector3.ZERO
		var target: Transform3D = sockets[side]
		var finish: Vector3 = target.origin
		var elbow: Vector3 = Vector3(finish.x, 0.0, 0.0) if int(side) == RoomOpening.Wall.FRONT or int(side) == RoomOpening.Wall.BACK else Vector3(0.0, 0.0, finish.z)
		for segment in [[start, elbow], [elbow, finish]]:
			var p0: Vector3 = segment[0]
			var p1: Vector3 = segment[1]
			var length: float = p0.distance_to(p1)
			var tunnel: Dictionary
			if length < EPS:
				tunnel = DungeonOrientedBounds.rectangle(p0, Vector2(radius * 2.0, radius * 2.0))
			else:
				var direction := p1 - p0
				var yaw := atan2(-direction.x, -direction.z)
				tunnel = DungeonOrientedBounds.rectangle((p0 + p1) * 0.5, Vector2(radius * 2.0, length), Basis(Vector3.UP, yaw))
			if DungeonOrientedBounds.overlaps(tunnel, footprint):
				report.add_error("PREFAB_WALKWAY_BLOCKED", "A rotated authored static box blocks an interior route to a socket.")
				return
