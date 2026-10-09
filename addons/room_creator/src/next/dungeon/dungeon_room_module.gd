@tool
class_name DungeonRoomModule
extends Resource
## Optional socket-aware, COLLISION-FREE room art. Procedural walls and doors
## remain authoritative, so artists cannot accidentally seal required portals.
## Authored scene coordinates are normalized: X/Z ±0.5, Y 0..1.

@export var stable_id: String = "room_module"
@export_range(1, 100, 1) var weight: int = 10
@export var shape: RoomFootprint.Shape = RoomFootprint.Shape.RECTANGLE
@export var visual_scene: PackedScene

const SIDES: Array[int] = [
	RoomOpening.Wall.FRONT, RoomOpening.Wall.RIGHT,
	RoomOpening.Wall.BACK, RoomOpening.Wall.LEFT
]
const MARKERS: Array[String] = [
	"SocketFront", "SocketRight", "SocketBack", "SocketLeft"
]

func validate() -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if stable_id.is_empty() or weight <= 0 or not RoomFootprint.is_valid_shape(int(shape)):
		report.add_error("MODULE_SETTINGS", "Module must have a nonempty ID, positive weight and a valid shape.")
	if visual_scene == null:
		report.add_error("MODULE_MISSING_SCENE", "Assign a PackedScene to this module.")
		return report
	var instance := visual_scene.instantiate()
	if not instance is Node3D:
		report.add_error("MODULE_ROOT", "Module scene root must be a Node3D.")
		if instance != null:
			instance.free()
		return report
	_check_node_tree(instance, report)
	var found: int = 0
	for i in SIDES.size():
		var marker := instance.get_node_or_null(NodePath(MARKERS[i])) as Marker3D
		if marker == null:
			continue
		found += 1
		var expected := _socket_point(SIDES[i])
		if marker.position.distance_to(expected) > 0.001:
			report.add_error("MODULE_SOCKET_POSITION", "Marker %s must be at normalized wall midpoint %s." % [MARKERS[i], str(expected)])
	if found == 0:
		report.add_error("MODULE_SOCKETS_MISSING", "Add at least one normalized SocketFront/Right/Back/Left Marker3D.")
	instance.free()
	return report


func supports(walls: Array[int], turns: int) -> bool:
	if visual_scene == null or not RoomFootprint.is_valid_shape(int(shape)):
		return false
	var instance := visual_scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return false
	var compatible := true
	for wall in walls:
		var matched := false
		for i in SIDES.size():
			if rotated_wall(SIDES[i], turns) == wall and instance.get_node_or_null(NodePath(MARKERS[i])) is Marker3D:
				matched = true
				break
		if not matched:
			compatible = false
			break
	instance.free()
	return compatible


static func rotated_wall(original: int, turns: int) -> int:
	var index: int = SIDES.find(original)
	return SIDES[posmod(index + turns, SIDES.size())] if index >= 0 else -1


static func _socket_point(side: int) -> Vector3:
	match side:
		RoomOpening.Wall.FRONT:
			return Vector3(0.0, 0.0, -0.5)
		RoomOpening.Wall.BACK:
			return Vector3(0.0, 0.0, 0.5)
		RoomOpening.Wall.LEFT:
			return Vector3(-0.5, 0.0, 0.0)
	return Vector3(0.5, 0.0, 0.0)


static func _check_node_tree(node: Node, report: RoomValidationReport) -> void:
	if node.get_script() != null:
		report.add_error("MODULE_SCRIPT", "Module visuals must be script-free for portable baked scenes: %s" % node.name)
	if node is CollisionObject3D or node is CollisionShape3D:
		report.add_error("MODULE_COLLISION", "Module visuals cannot contribute unvalidated collision: %s" % node.name)
	for child in node.get_children():
		_check_node_tree(child, report)
