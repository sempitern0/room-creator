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
@export_group("Room silhouettes")
## Set a weight to zero to exclude that shape. Rectangle-only preserves older scenes.
@export_range(0, 100, 1) var rectangle_weight: int = 10
@export_range(0, 100, 1) var cross_weight: int = 0
@export_range(0, 100, 1) var l_shape_weight: int = 0
@export_range(0, 100, 1) var t_shape_weight: int = 0
@export_group("Shared room geometry")
@export var room_size: Vector3 = Vector3(8.0, 3.5, 8.0)
@export_range(0.05, 1.0, 0.01) var wall_thickness: float = 0.2
@export_range(0.05, 1.0, 0.01) var floor_thickness: float = 0.2
@export_range(0.05, 1.0, 0.01) var ceiling_thickness: float = 0.2
@export var include_ceiling: bool = true
@export_group("Socket-aware room modules")
## Optional normalized art scenes with Marker3D connectors; physics shell stays procedural.
@export var room_modules: Array[DungeonRoomModule] = []
@export var require_room_modules: bool = false
@export_range(0.0, 1.0, 0.05) var module_chance: float = 1.0
@export_group("Structural room prefabs (F2.7)")
## Full collision-bearing static room shells; only exact room sizes and
## precisely matching door sockets are accepted. Never silently add doors.
@export var structural_prefabs: Array[DungeonStructuralPrefab] = []
@export_range(0.0, 1.0, 0.05) var structural_prefab_chance: float = 0.70
@export_group("Variable room sizes")
## Rooms stay centered in fixed grid cells; smaller rooms use short connector corridors.
@export var vary_room_sizes: bool = false
@export_range(0.5, 1.0, 0.05) var min_room_scale: float = 0.80
@export_range(0.5, 1.0, 0.05) var max_room_scale: float = 1.00
@export_group("Spatial embedding (F2.4)")
## Reproducible non-uniform room column/row positions. Graph sockets remain
## axis-aligned, so all generated corridors remain physically traversable.
@export var use_variable_grid_spacing: bool = false
@export_range(0.0, 30.0, 0.25) var min_corridor_gap: float = 1.0
@export_range(0.0, 30.0, 0.25) var max_corridor_gap: float = 4.0
@export_group("Independent room offsets (F2.5)")
## A bounded spatial solver moves rooms independently only where graph
## connectivity allows a straight, coaxial connector; no arbitrary yaw.
@export var enable_independent_room_offsets: bool = false
@export_range(0.0, 6.0, 0.05) var room_position_jitter: float = 0.75
@export_range(1, 64, 1) var placement_attempts: int = 16
@export_group("Routed corridors (F2.6)")
## Allows S/dogleg passages between offset room doorways, rather than
## requiring the door centers to be coaxial. Uses a bounded collision solver.
@export var enable_dogleg_corridors: bool = false
@export_range(0.0, 1.0, 0.05) var dogleg_frequency: float = 0.65
@export_group("Free-yaw multiroom placement (F2)")
## Optional seeded backtracking. The logical grid remains a topology guide,
## but actual room yaw/position and world-space routes can be non-cardinal.
@export var enable_free_yaw_dungeons: bool = false
@export_range(0.0, 180.0, 0.5) var free_yaw_max_degrees: float = 24.0
@export_range(0.0, 3.0, 0.25) var free_yaw_shift: float = 0.75
@export_range(4, 32, 1) var free_yaw_candidates: int = 12
@export_range(100, 20000, 100) var free_yaw_search_budget: int = 3000
@export_group("Off-grid socket packing (F2 full)")
## Instead of deriving room centers from cell indices, grow the dungeon
## through physically authored sockets using a bounded spatial DFS.
@export var enable_offgrid_socket_packing: bool = false
@export_range(7.0, 30.0, 0.25) var socket_pack_min_gap: float = 9.0
@export_range(7.0, 30.0, 0.25) var socket_pack_max_gap: float = 13.0
@export_group("Opening and player clearance")
@export_range(0.5, 5.0, 0.05) var door_width: float = 1.6
@export_range(0.5, 6.0, 0.05) var door_height: float = 2.3
@export_range(0.1, 2.0, 0.05) var player_radius: float = 0.35
@export_range(0.5, 4.0, 0.05) var player_height: float = 1.8
@export_group("Exterior entrances")
## Cut actual walkable outside doorways in the start and finish rooms.
@export var generate_exterior_doors: bool = true
@export_group("Rendering and collision")
@export var wall_material: Material
@export var floor_material: Material
@export var ceiling_material: Material
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
