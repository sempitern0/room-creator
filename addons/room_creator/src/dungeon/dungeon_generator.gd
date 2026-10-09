@tool
class_name DungeonGenerator extends Node3D

@export_tool_button("Generate dungeon") var generate_dungeon_action: Callable = generate_dungeon
@export_tool_button("Clear dungeon") var clear_dungeon_action: Callable = _clear_dungeon_rooms
@export_tool_button("Toggle ceils visibility") var toggle_ceil_action: Callable = _toggle_ceils
@export_tool_button("Generate final mesh") var generate_final_mesh_action: Callable = _generate_final_mesh
@export_tool_button("Save rooms as scenes") var save_rooms_as_scenes: Callable = _save_rooms_as_scenes
## Dungeon room configuration
@export var room_configuration: RoomConfiguration
## Dimensions in the format Vector2i(column, row)
@export var dungeon_dimension: Vector2i = Vector2i(10, 5)
## Only the rooms that are on the critical path are created in the scene tree
@export var critical_path_length: int = 5
## The number of extra ramifications from the critical path rooms to create secondary paths
@export var branches: int = 2
## This branch length is a vector as a way to hold a range of Vector2i(min, max) values that represents
## the number of rooms of this branch
@export var branch_length: Vector2i = Vector2i(1, 3)
## Set the entrance position manually, this vector must be on the dungeon_dimension size range
@export var entrance_position: Vector2i = Vector2i(0, 0)
## When enabled the entrance room will be randomized on one of the borders of the grid.
## The entrance_position will be ignored when true
@export var randomize_entrance: bool = false:
	set(value):
		randomize_entrance = value
		notify_property_list_changed()
		
@export_group("Mesh generation")
@export var generate_collisions_on_mesh: bool = true
@export_dir var output_scenes_folder: String

@export_group("Materials")
@export var entrance_room_materials: Array[RoomMaterials] = []
@export var exit_room_materials: Array[RoomMaterials] = []
@export var path_room_materials: Array[RoomMaterials] = []
@export var branch_room_materials: Array[RoomMaterials] = []

enum MeshGenerationMode {
	MeshPerRoom,
	OneCombinedMesh
}

var directions_v2: Array[Vector2i]= [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]

var dungeon_grid: Array = []
var entrance: Vector2i
var branch_candidates: Array[Vector2i] = []

var final_mesh_root_node: Dungeon


func _validate_property(property: Dictionary) -> void:
	if property.name == "entrance_position":
		property.usage = PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR if randomize_entrance else PROPERTY_USAGE_EDITOR


func generate_dungeon() -> void:
	assert(room_configuration != null, "DungeonGenerator: This tool needs a RoomConfiguration resource to generate the dungeon")
	
	_clear_dungeon_rooms()
	_clear_meshes()
	dungeon_grid.clear()
	branch_candidates.clear()
	
	assert(entrance_position.x >= 0 \
		and entrance_position.x < dungeon_dimension.x - 1 \
		and entrance_position.y >= 0 \
		and entrance_position.y <= dungeon_dimension.y - 1,
		"The entrance_position is out of bounds for the current dungeon dungeon_dimension"
		)
	
	entrance = border_positions().pick_random() if randomize_entrance else entrance_position
	
	for column in dungeon_dimension.x:
		dungeon_grid.append([])
		
		for row in dungeon_dimension.y:
			var room: CSGRoom = CSGRoom.new()
			room.configuration = room_configuration.duplicate(true)
			room.configuration.use_manual_door_mode = true
			
			var dungeon_room: DungeonRoom = DungeonRoom.new(
				room,
				column,
				row,
				dungeon_dimension
			)
			
			dungeon_room.is_entrance = Vector2i(column, row) == entrance
			dungeon_grid[column].append(dungeon_room)
			
	generate_critical_path(entrance, critical_path_length, critical_path_length)
	generate_branches()
	
	create_dungeon_rooms()
	
	setup_entrance_materials()
	setup_exit_materials()
	setup_path_materials()
	setup_branch_materials()
		

func setup_entrance_materials() -> void:
	var entrance_dungeon_room: DungeonRoom = entrance_room()
	
	if entrance_dungeon_room:
		if entrance_room_materials.size():
			var room_materials: RoomMaterials = entrance_room_materials.pick_random() as RoomMaterials
			
			entrance_dungeon_room.room.change_ceil_material(room_materials.ceil_material)\
				.change_floor_material(room_materials.floor_material)\
				.change_left_wall_material(room_materials.left_wall_material)\
				.change_right_wall_material(room_materials.right_wall_material)\
				.change_front_wall_material(room_materials.front_wall_material)\
				.change_back_wall_material(room_materials.back_wall_material)\
				.change_doors_material(room_materials.door_material)\
				.change_ceil_columns_material(room_materials.ceil_columns_material)\
				.change_corner_columns_material(room_materials.corner_columns_material)
				

func setup_exit_materials() -> void:
	var exit_dungeon_room: DungeonRoom = exit_room()
	
	if exit_dungeon_room:
		if exit_room_materials.size():
			var room_materials: RoomMaterials = exit_room_materials.pick_random() as RoomMaterials
			
			exit_dungeon_room.room.change_ceil_material(room_materials.ceil_material)\
				.change_floor_material(room_materials.floor_material)\
				.change_left_wall_material(room_materials.left_wall_material)\
				.change_right_wall_material(room_materials.right_wall_material)\
				.change_front_wall_material(room_materials.front_wall_material)\
				.change_back_wall_material(room_materials.back_wall_material)\
				.change_doors_material(room_materials.door_material)\
				.change_ceil_columns_material(room_materials.ceil_columns_material)\
				.change_corner_columns_material(room_materials.corner_columns_material)
			

func setup_path_materials() -> void:
	if path_room_materials.size():
		for dungeon_room: DungeonRoom in path_rooms():
			var room_materials: RoomMaterials = path_room_materials.pick_random() as RoomMaterials
			
			dungeon_room.room.change_ceil_material(room_materials.ceil_material)\
				.change_floor_material(room_materials.floor_material)\
				.change_left_wall_material(room_materials.left_wall_material)\
				.change_right_wall_material(room_materials.right_wall_material)\
				.change_front_wall_material(room_materials.front_wall_material)\
				.change_back_wall_material(room_materials.back_wall_material)\
				.change_doors_material(room_materials.door_material)\
				.change_ceil_columns_material(room_materials.ceil_columns_material)\
				.change_corner_columns_material(room_materials.corner_columns_material)
			

func setup_branch_materials() -> void:
	if branch_room_materials.size():
		for dungeon_room: DungeonRoom in branch_rooms():
			var room_materials: RoomMaterials = branch_room_materials.pick_random() as RoomMaterials
			
			dungeon_room.room.change_ceil_material(room_materials.ceil_material)\
				.change_floor_material(room_materials.floor_material)\
				.change_left_wall_material(room_materials.left_wall_material)\
				.change_right_wall_material(room_materials.right_wall_material)\
				.change_front_wall_material(room_materials.front_wall_material)\
				.change_back_wall_material(room_materials.back_wall_material)\
				.change_doors_material(room_materials.door_material)\
				.change_ceil_columns_material(room_materials.ceil_columns_material)\
				.change_corner_columns_material(room_materials.corner_columns_material)
			

func create_dungeon_rooms() -> void:
	for room: DungeonRoom in RoomCreatorPluginUtilities.flatten(dungeon_grid)\
		.filter(func(room: DungeonRoom): return room.critical_path != -1 or room.branch != -1 or room.is_entrance or room.is_exit):
			
		add_room_to_tree(room)


func generate_branches() -> void:
	var branches_created: int = 0
	
	if branches > 0:
		var candidate: Vector2i
		
		while branches_created < branches and branch_candidates.size():
			candidate = branch_candidates.pick_random()
			
			var current_branch_length: int =  randi_range(branch_length.x, branch_length.y)
			
			if generate_critical_path(candidate, current_branch_length, current_branch_length, true):
				branches_created += 1
			else:
				branch_candidates.erase(candidate)


func generate_critical_path(from: Vector2i, total_length: int, length: int, is_branch: bool = false) -> bool:
	if length == 0:
		return true
	
	var current: Vector2i = from
	
	var direction: Vector2i = directions_v2.pick_random()
	## Avoid negative room position as the dungeon grid only uses positive values where the origin is Vector2i.ZERO
	var target_position: Vector2i = Vector2i(current.x + direction.x, current.y + direction.y)
	
	if target_position.x < 0 or target_position.y < 0:
		direction = direction.abs()
		target_position = Vector2i(current.x + direction.x, current.y + direction.y)
	
	for i in directions_v2.size():
		if target_position.x >= 0 and target_position.x < dungeon_dimension.x \
			and target_position.y >= 0 and target_position.y < dungeon_dimension.y \
			and target_position.x < dungeon_grid.size() and target_position.y < dungeon_grid[target_position.x].size() \
			and (dungeon_grid[target_position.x][target_position.y].critical_path == -1 or (is_branch and dungeon_grid[target_position.x][target_position.y].branch == -1) ):
				
				var room: DungeonRoom = dungeon_grid[target_position.x][target_position.y]
				current = target_position
				
				if is_branch:
					room.branch = total_length - length
				else:
					room.critical_path = total_length - length
					room.is_exit = room.critical_path == critical_path_length - 1
			
				if length > 1:
					branch_candidates.append(current)
					
				if generate_critical_path(current, total_length, length - 1, is_branch):
					return true
				else:
					
					if is_branch:
						room.branch = -1
					else:
						branch_candidates.erase(target_position)
						room.critical_path = -1
						room.is_exit = false
					
					current -= direction
		
		direction = Vector2i(direction.y, -direction.x)
	
	return false


func add_room_to_tree(dungeon_room: DungeonRoom) -> void:
	_setup_room_doors(dungeon_room)
	add_child(dungeon_room.room)
	
	dungeon_room.assign_name()
	dungeon_room.room.create_manual_doors()
	dungeon_room.room.position = Vector3(
		dungeon_room.row * room_configuration.room_size.x, 
		0, 
		-dungeon_room.column * room_configuration.room_size.z
	)
		
	dungeon_room.room.position.z -= (dungeon_room.room.configuration.wall_thickness) * dungeon_room.column
	dungeon_room.room.position.x += (dungeon_room.room.configuration.wall_thickness) * dungeon_room.row


## A helper function to tterate over the dungeon grid and execute a callback callback that receives a DungeonRoom
func iterate_over_grid(grid: Array, callback: Callable) -> void:
	for column in dungeon_dimension.x:
		for row in dungeon_dimension.y:
			callback.call(column, row)


func entrance_room() -> DungeonRoom:
	if dungeon_grid.is_empty():
		return null
		
	return RoomCreatorPluginUtilities.flatten(dungeon_grid).filter(
		func(room: DungeonRoom): return room.is_entrance).front() as DungeonRoom


func exit_room() -> DungeonRoom:
	if dungeon_grid.is_empty():
		return null
		
	return RoomCreatorPluginUtilities.flatten(dungeon_grid).filter(
		func(room: DungeonRoom): return room.is_exit).front() as DungeonRoom


func inside_tree_rooms() -> Array[DungeonRoom]:
	var rooms: Array[DungeonRoom] = []
	rooms.assign(RoomCreatorPluginUtilities\
		.flatten(dungeon_grid)\
		.filter(func(room: DungeonRoom): return room.room.is_inside_tree())
	)
	
	return rooms
	

func border_rooms() -> Array[DungeonRoom]:
	var rooms: Array[DungeonRoom] = []
	rooms.assign(RoomCreatorPluginUtilities\
		.flatten(dungeon_grid)\
		.filter(func(room: DungeonRoom): return room.is_border())
	)
	
	return rooms

	
func branch_rooms() -> Array[DungeonRoom]:
	var rooms: Array[DungeonRoom] = []
	rooms.assign(RoomCreatorPluginUtilities\
		.flatten(dungeon_grid)\
		.filter(
			func(room: DungeonRoom): 
				return room.branch > 0 and not room.is_entrance and not room.is_exit
				)
	)
	
	return rooms
	

func path_rooms() -> Array[DungeonRoom]:
	var result: Array[DungeonRoom] = []
	result.assign(
		RoomCreatorPluginUtilities\
			.flatten(dungeon_grid)\
			.filter(func(room: DungeonRoom): return room.critical_path != -1 and not room.is_entrance and not room.is_exit)
			)
	
	return result
	

func pick_random_border_room() -> Vector2i:
	var dungeon_borders: Array[Vector2i] = border_rooms()\
		.map(func(room: DungeonRoom): return room.grid_position())

	return dungeon_borders.pick_random()
	

func pick_random_branch_room() -> Vector2i:
	var dungeon_borders: Array[Vector2i] = branch_rooms()\
		.map(func(room: DungeonRoom): return room.grid_position())

	return dungeon_borders.pick_random()
	

func border_positions(dungeon_dungeon_dimension: Vector2i = dungeon_dimension) -> Array[Vector2i]:
	var borders: Array[Vector2i] = []
	var detect_border = func(column: int, row: int):
		if row == 0 or column == 0 or row == dungeon_dungeon_dimension.y - 1 or column == dungeon_dungeon_dimension.x - 1:
			borders.append(Vector2i(column, row))
	
	iterate_over_grid(dungeon_grid, detect_border)
	
	return borders


func _toggle_ceils() -> void:
	for room: DungeonRoom in RoomCreatorPluginUtilities\
		.flatten(dungeon_grid)\
		.filter(func(dungeon_room: DungeonRoom): return dungeon_room.room.is_inside_tree()):
		
		room.room.toggle_ceil_visibility()
	
	
func _clear_dungeon_rooms() -> void:
	for child in get_children():
		child.free()
		
		
func _clear_meshes() -> void:
	if final_mesh_root_node:
		final_mesh_root_node.free()
		final_mesh_root_node = null


func _setup_room_doors(dungeon_room: DungeonRoom) -> void:
	var column: int = dungeon_room.column
	var row: int = dungeon_room.row
	
	var right_room: DungeonRoom = dungeon_grid[column + 1][row] if column + 1 < dungeon_dimension.x else null
	var left_room: DungeonRoom =  dungeon_grid[column - 1][row] if column - 1 >= 0 else null
	var top_room: DungeonRoom = dungeon_grid[column][row - 1] if row - 1 >= 0 else null
	var bottom_room: DungeonRoom = dungeon_grid[column][row + 1] if row + 1 < dungeon_dimension.y else null
	
	dungeon_room.room.configuration.door_in_front_wall = right_room \
		and dungeon_room.critical_path_neighbour_of(right_room) or dungeon_room.branch_path_neighbour_of(right_room)
	dungeon_room.room.configuration.door_in_back_wall = left_room \
		and dungeon_room.critical_path_neighbour_of(left_room) or dungeon_room.branch_path_neighbour_of(left_room)
	dungeon_room.room.configuration.door_in_left_wall = top_room \
		and dungeon_room.critical_path_neighbour_of(top_room) or dungeon_room.branch_path_neighbour_of(top_room)
	dungeon_room.room.configuration.door_in_right_wall = bottom_room \
		and dungeon_room.critical_path_neighbour_of(bottom_room) or dungeon_room.branch_path_neighbour_of(bottom_room)


func _generate_final_mesh() -> void:
	var rooms: Array[DungeonRoom] = inside_tree_rooms()
	
	if rooms.size():
		if final_mesh_root_node:
			final_mesh_root_node.free()
			final_mesh_root_node = null
		
		final_mesh_root_node = Dungeon.new()
		final_mesh_root_node.name = "DungeonRoomMesh"
		add_child(final_mesh_root_node)
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(final_mesh_root_node)
		
		for dungeon_room: DungeonRoom in rooms:
			dungeon_room.room.show_ceil()
			await get_tree().physics_frame
			var room_mesh_instance: RoomMesh = dungeon_room.room.generate_mesh_instance() as RoomMesh
		
			if room_mesh_instance:
				if dungeon_room.is_entrance:
					final_mesh_root_node.entrance = room_mesh_instance
			
				elif dungeon_room.is_exit:
					final_mesh_root_node.exit = room_mesh_instance
					
				final_mesh_root_node.add_child(room_mesh_instance)
				RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_mesh_instance)
				
				room_mesh_instance.room_configuration = room_configuration.duplicate()
				room_mesh_instance.door_positions = dungeon_room.room.door_positions().duplicate()
				
				name_surfaces_on_room_mesh(dungeon_room.room, room_mesh_instance)
				
				if generate_collisions_on_mesh:
					generate_collisions_on_room_mesh(room_mesh_instance)


func name_surfaces_on_room_mesh(room: CSGRoom, room_mesh_instance: MeshInstance3D) -> void:
	for shape: CSGShape3D in room.materials_by_room_part:
		room_mesh_instance.mesh.surface_set_name(room.materials_by_room_part[shape], shape.name)


func generate_collisions_on_room_mesh(room_mesh_instance: RoomMesh) -> void:
	var trimesh_collision = CollisionShape3D.new()
	trimesh_collision.name = "%sTrimeshCollision" % room_mesh_instance.name
	trimesh_collision.shape = room_mesh_instance.mesh.create_trimesh_shape()

	var body = StaticBody3D.new()
	body.name = "%sStaticBody3D" % room_mesh_instance.name
	room_mesh_instance.add_child(body)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(body)
	body.add_child(trimesh_collision)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(trimesh_collision)


func _save_rooms_as_scenes() -> void:
	if final_mesh_root_node == null:
		push_warning("DungeonGenerator ⚠️: No generated meshes found to save as scene files")
		return
		
	if not DirAccess.dir_exists_absolute(output_scenes_folder):
		
		if DirAccess.make_dir_recursive_absolute(output_scenes_folder) != OK:
			push_error("DungeonGenerator ❌: An error %d ocurred when creating output folder %s " % output_scenes_folder)
			return
	
	var local_folder: String = output_scenes_folder + "/dungeon_rooms_%d" % DirAccess.get_directories_at(output_scenes_folder).size()
	
	if DirAccess.make_dir_recursive_absolute(local_folder) != OK:
			push_error("DungeonGenerator ❌: An error %d ocurred when creating output folder %s " % local_folder)
			return
			
	for room: RoomMesh in final_mesh_root_node.get_children():
		var target_room: RoomMesh = room.duplicate()
		target_room.position = Vector3.ZERO
		
		for child: Node in RoomCreatorPluginUtilities.get_all_children(target_room):
			child.owner = target_room
			
		var scene: PackedScene = PackedScene.new()
		var result = scene.pack(target_room)
	
		if result == OK:
			var error = ResourceSaver.save(scene, "%s/%s.tscn" % [local_folder, room.name.to_snake_case()])
			if error != OK:
				push_error("RoomCreator ❌: An error %d occurred while saving the scene %s to %s" % [error, room.name, output_scenes_folder])
		
	EditorInterface.get_resource_filesystem().scan()
	

class DungeonRoom:
	var is_entrance: bool = false:
		set(value):
			is_entrance = value
			critical_path = 0 if is_entrance else -1
	var is_exit: bool = false
	var room: CSGRoom
	var column: int
	var row: int
	var dungeon_dimension: Vector2i ## The dungeon_dimension of the grid it belows
	var critical_path: int = -1
	var branch: int = -1
	
	func _init(_room: CSGRoom, _column: int, _row: int, _dungeon_dimension: Vector2i) -> void:
		room = _room
		column = _column
		row = _row
		dungeon_dimension = _dungeon_dimension
	
	
	func room_name() -> String:
		if is_entrance:
			return "DungeonRoomEntrance"
		elif is_exit:
			return "DungeonRoomExit"
		elif critical_path and branch == -1:
			return "DungeonRoom%d" % critical_path
		elif branch != -1:
			return "DungeonRoomBranch%d" % branch
		else:
			return "DungeonRoom"
	
	
	func assign_name() -> void:
		if room:
			room.name = room_name()
	
	func grid_position() -> Vector2i:
		return Vector2i(column, row)
	
	
	func critical_path_neighbour_of(other_room: DungeonRoom):
		return other_room \
			and critical_path != -1 \
			and other_room.critical_path != -1 \
			and other_room.critical_path in [maxi(0, critical_path - 1), critical_path + 1]
	
	
	func branch_path_neighbour_of(other_room: DungeonRoom):
		return other_room \
			and branch != -1 \
			and other_room.branch != -1 \
			and other_room.branch in [maxi(0, branch - 1), branch + 1]
	
	#region Grid related
	func is_border() -> bool:
		return is_top_border() or is_bottom_border() or is_right_border() or is_left_border()
		
	func is_top_border() -> bool:
		return row == 0

	func is_bottom_border() -> bool:
		return row == dungeon_dimension.y - 1

	func is_right_border() -> bool:
		return column == dungeon_dimension.x - 1

	func is_left_border() -> bool:
		return column == 0
		
	func is_corner() -> bool:
		return is_top_left_corner() or is_top_right_corner() or is_bottom_left_corner() or is_bottom_right_corner()
		
	func is_top_left_corner() -> bool:
		return row == 0 and column == 0

	func is_bottom_left_corner() -> bool:
		return column == 0 and row == dungeon_dimension.y - 1

	func is_top_right_corner() -> bool:
		return row == 0 and column == dungeon_dimension.x - 1

	func is_bottom_right_corner() -> bool:
		return row == dungeon_dimension.y - 1 and column == dungeon_dimension.x - 1
	#endregion
