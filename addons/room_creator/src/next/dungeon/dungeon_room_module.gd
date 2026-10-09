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

## SceneState lets us inspect all socket declarations without instantiating a
## PackedScene during editor inspector actions. Repeated instantiation here used
## to cause hundreds of editor-side scene notifications for a single layout.
func validate() -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if stable_id.is_empty() or weight <= 0 or not RoomFootprint.is_valid_shape(int(shape)):
		report.add_error("MODULE_SETTINGS", "Module must have a nonempty ID, positive weight and a valid shape.")
	if visual_scene == null:
		report.add_error("MODULE_MISSING_SCENE", "Assign a PackedScene to this module.")
		return report
	var available := _inspect_sockets(report)
	if available.is_empty():
		report.add_error("MODULE_SOCKETS_MISSING", "Add at least one normalized SocketFront/Right/Back/Left Marker3D.")
	return report


func supports(walls: Array[int], turns: int) -> bool:
	if visual_scene == null or not RoomFootprint.is_valid_shape(int(shape)):
		return false
	var report := RoomValidationReport.new()
	var available := _inspect_sockets(report)
	if not report.is_valid():
		return false
	for wall in walls:
		var found := false
		for original_side in available:
			if rotated_wall(original_side, turns) == wall:
				found = true
				break
		if not found:
			return false
	return true


func _inspect_sockets(report: RoomValidationReport) -> Array[int]:
	var sides: Array[int] = []
	var state := visual_scene.get_state()
	if state == null or state.get_node_count() == 0:
		report.add_error("MODULE_EMPTY", "The visual scene has no nodes.")
		return sides
	var root_type: StringName = state.get_node_type(0)
	if root_type != &"Node3D" and not ClassDB.is_parent_class(root_type, &"Node3D"):
		report.add_error("MODULE_ROOT", "Module root must be Node3D or a 3D-derived node.")
		return sides
	for index in state.get_node_count():
		var node_type: StringName = state.get_node_type(index)
		var node_name: StringName = state.get_node_name(index)
		if index > 0 and (node_type == &"CollisionShape3D" or ClassDB.is_parent_class(node_type, &"CollisionObject3D")):
			report.add_error("MODULE_COLLISION", "Visual-only module cannot include colliders: %s" % node_name)
		for prop_index in state.get_node_property_count(index):
			if state.get_node_property_name(index, prop_index) == &"script" and state.get_node_property_value(index, prop_index) != null:
				report.add_error("MODULE_SCRIPT", "Module visual nodes must be script-free: %s" % node_name)
		if index == 0 or node_type != &"Marker3D":
			continue
		# Only direct children represent normalized doorway sockets.
		var direct_path: String = str(state.get_node_path(index))
		var socket_index: int = MARKERS.find(str(node_name))
		if socket_index < 0 or (direct_path != str(node_name) and direct_path != "./" + str(node_name)):
			continue
		var position: Vector3 = Vector3.ZERO
		for prop_index in state.get_node_property_count(index):
			var property_name: StringName = state.get_node_property_name(index, prop_index)
			if property_name == &"transform":
				position = (state.get_node_property_value(index, prop_index) as Transform3D).origin
			elif property_name == &"position":
				position = state.get_node_property_value(index, prop_index)
		if position.distance_to(_socket_point(SIDES[socket_index])) > 0.001:
			report.add_error("MODULE_SOCKET_POSITION", "%s must be placed at its normalized wall midpoint." % node_name)
		else:
			sides.append(SIDES[socket_index])
	return sides


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


