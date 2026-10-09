@tool
class_name DungeonConfig
extends Resource
## F2 grid-embedded, single-floor dungeon settings. Distances are meters.

@export var seed: int = 12345
@export var grid_size: Vector2i = Vector2i(12, 12)
@export_range(2, 300, 1) var critical_path_min: int = 8
@export_range(2, 300, 1) var critical_path_max: int = 10
@export_range(0, 300, 1) var branch_count: int = 6
@export_range(0, 300, 1) var loop_count: int = 0
@export_range(1, 32, 1) var max_attempts: int = 12
@export_range(100, 30000, 100) var search_budget_per_attempt: int = 4000
@export_group("Shared room geometry")
@export var room_size: Vector3 = Vector3(8.0, 3.5, 8.0)
@export_range(0.05, 1.0, 0.01) var wall_thickness: float = 0.2
@export_range(0.05, 1.0, 0.01) var floor_thickness: float = 0.2
@export_range(0.05, 1.0, 0.01) var ceiling_thickness: float = 0.2
@export var include_ceiling: bool = true
@export_group("Opening and player clearance")
@export_range(0.5, 5.0, 0.05) var door_width: float = 1.6
@export_range(0.5, 6.0, 0.05) var door_height: float = 2.3
@export_range(0.1, 2.0, 0.05) var player_radius: float = 0.35
@export_range(0.5, 4.0, 0.05) var player_height: float = 1.8
@export_group("Rendering and collision")
@export var wall_material: Material
@export var floor_material: Material
@export var ceiling_material: Material
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
