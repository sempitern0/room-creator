@tool
class_name RoomPlacementData
extends Resource
## Stable room identity and transform, independent of the SceneTree.

enum Role { ENTRANCE, MAIN, EXIT, BRANCH }

@export var stable_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
@export var world_transform: Transform3D = Transform3D.IDENTITY
@export var role: Role = Role.MAIN
@export var shape: RoomFootprint.Shape = RoomFootprint.Shape.RECTANGLE
@export_range(0, 3, 1) var shape_rotation: int = 0
