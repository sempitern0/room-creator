@tool
class_name RoomPlacementData
extends Resource
## Stable room identity and transform, independent of the SceneTree.

enum Role { ENTRANCE, MAIN, EXIT, BRANCH }

@export var stable_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
## Optional actual geometry extent; ZERO preserves pre-1.5 layouts.
@export var room_size: Vector3 = Vector3.ZERO
@export var world_transform: Transform3D = Transform3D.IDENTITY
@export var role: Role = Role.MAIN
@export var module_profile: DungeonRoomModule
## Full authored collision room; null preserves the procedural shell.
@export var structural_prefab: DungeonStructuralPrefab
@export_range(0, 3, 1) var structural_turns: int = 0
## Exterior doorway is independent from the internal room-connection graph.
## -1 means no exterior opening. Uses the same outward-facing wall convention.
@export var exterior_wall: int = -1
@export var exterior_id: String = ""
@export var shape: RoomFootprint.Shape = RoomFootprint.Shape.RECTANGLE
@export_range(0, 3, 1) var shape_rotation: int = 0
