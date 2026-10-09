@tool
class_name RoomMesh extends MeshInstance3D

@export var room_configuration: RoomConfiguration
@export var door_positions: Array[Vector3]


var room_mesh_shape: ArrayMesh
var sockets: Array[Marker3D]
