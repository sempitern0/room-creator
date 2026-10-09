@tool
class_name RoomBlueprint
extends Resource
## Canonical editable source for a one orthogonal room, not its rendered nodes.

@export var stable_id: String = "room_01"
@export_group("Footprint")
@export var shape: RoomFootprint.Shape = RoomFootprint.Shape.RECTANGLE
@export_range(0, 3, 1) var shape_rotation: int = 0
@export var room_size: Vector3 = Vector3(8.0, 3.5, 8.0)
@export_range(0.05, 2.0, 0.01, "or_greater") var wall_thickness: float = 0.2
@export_range(0.05, 2.0, 0.01, "or_greater") var floor_thickness: float = 0.2
@export_range(0.05, 2.0, 0.01, "or_greater") var ceiling_thickness: float = 0.2
@export var include_ceiling: bool = true
@export var openings: Array[RoomOpening] = []
@export_group("Materials")
@export var wall_material: Material
@export var floor_material: Material
@export var ceiling_material: Material
@export_group("Gameplay clearance")
@export_range(0.05, 3.0, 0.01) var agent_radius: float = 0.35
@export_range(0.2, 5.0, 0.05) var agent_height: float = 1.8
@export_group("Physics")
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
