@tool
class_name LevelLayout
extends Resource
## Serializable source of truth: layout, edges, identities, and selected constraints.

const SCHEMA_VERSION: int = 1
@export var schema_version: int = SCHEMA_VERSION
@export var seed: int
@export var grid_size: Vector2i
@export var room_size: Vector3
@export var wall_thickness: float = 0.2
@export var floor_thickness: float = 0.2
@export var ceiling_thickness: float = 0.2
@export var include_ceiling: bool = true
@export var player_radius: float = 0.35
@export var player_height: float = 1.8
@export var collision_layer: int = 1
@export var collision_mask: int = 1
@export var wall_material: Material
@export var floor_material: Material
@export var ceiling_material: Material
@export var entrance_id: String = ""
@export var exit_id: String = ""
@export var minimum_critical_rooms: int = 2
@export var expected_room_count: int = 0
@export var expected_loops: int = 0
@export var critical_path_ids: PackedStringArray = PackedStringArray()
@export var rooms: Array[RoomPlacementData] = []
@export var connections: Array[RoomConnectionData] = []

func fingerprint() -> String:
	## Stable across sessions: do not use Dictionary.hash() or SceneTree order.
	var parts: PackedStringArray = PackedStringArray()
	parts.append("schema:%d seed:%d grid:%d,%d" % [schema_version, seed, grid_size.x, grid_size.y])
	parts.append("size:%.4f,%.4f,%.4f" % [room_size.x, room_size.y, room_size.z])
	parts.append("rooms:%d edges:%d" % [rooms.size(), connections.size()])
	for room in rooms:
		parts.append("%s:%d,%d:%d:%.4f,%.4f,%.4f" % [room.stable_id, room.cell.x, room.cell.y, room.role, room.world_transform.origin.x, room.world_transform.origin.y, room.world_transform.origin.z])
	for edge in connections:
		parts.append("%s:%s:%s:%d:%d:%.4f:%.4f" % [edge.stable_id, edge.from_room_id, edge.to_room_id, edge.from_wall, edge.to_wall, edge.clear_width, edge.clear_height])
	return "|".join(parts).md5_text()
