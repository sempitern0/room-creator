@tool
class_name RoomCreator extends Node3D

signal created_csg_rooms(csg_rooms: Array[CSGRoom])
signal created_rooms(rooms: Array[RoomMesh])

# Tool buttons parsed from the inspector plugin script
@export var button_Generate_Rooms: String
@export var button_Generate_Final_Mesh: String
@export var button_Save_Rooms_As_Scenes: String
@export var button_Clear_All: String
@export var button_Clear_Last_Generated_Rooms: String

@export_group("Save")
@export_dir var output_folder: String = "res://room_creator/rooms"
@export_group("Generation")
@export var display_mode: DisplayMode = DisplayMode.Connected
@export var grid_columns: int = 4
@export_range(1, 1000, 1) var number_of_rooms_per_generation: int = 1
@export_range(1, 4, 1) var doors_per_room: int = 2
@export var generate_mesh_mode: MeshGenerationMode = MeshGenerationMode.MeshPerRoom
@export var generate_materials: bool = true
@export var include_ceil : bool = true
@export var include_ceil_columns : bool = false
@export var include_floor : bool = true
@export var include_right_wall : bool = true
@export var include_left_wall : bool = true
@export var include_front_wall : bool = true
@export var include_back_wall : bool = true
@export var include_corner_columns : bool = false
@export_group("Collisions")
@export var generate_collisions: bool = true
@export var type_of_collision: AvailableCollisions = AvailableCollisions.Trimesh
@export var create_static_body: bool = true
@export var clean_collision: bool = true
@export var simplified_collision: bool = false
@export_group("Bridge connector size")
@export var use_bridge_connector_between_rooms : bool = false
@export var min_bridge_connector_size: Vector3 = Vector3(2.0, 3.0, 4.0)
@export var max_bridge_connector_size: Vector3 = Vector3(2.0, 3.0, 10.0)
@export_group("Room Parameters")
@export var room_parameters: RoomParameters

enum DisplayMode {
	Connected,
	Grid
}

enum MeshGenerationMode {
	MeshPerRoom,
	OneCombinedMesh
}

enum AvailableCollisions {
	Convex, # Basic shapes
	Trimesh, # More complex shapes that contains csg operations as substraction
}

static var wall_rotations: Dictionary = {
	"FrontWall": {"FrontWall": PI, "BackWall": 0, "RightWall": PI / 2, "LeftWall": -PI / 2},
	"BackWall": {"FrontWall": 0, "BackWall": PI, "RightWall": -PI / 2, "LeftWall": PI / 2},
	"RightWall": {"FrontWall": -PI / 2, "BackWall": PI / 2, "RightWall": PI, "LeftWall": 0},
	"LeftWall": {"FrontWall": PI / 2, "BackWall": -PI / 2, "RightWall": 0, "LeftWall": PI},
}

var csg_rooms_created: Array[CSGRoom] = []
var rooms_created: Array[RoomMesh] = []
var csg_rooms_output_node: Node3D
var room_meshes_output_node: Node3D


func _on_tool_button_pressed(text: String) -> void:
	match text:
		"Generate Rooms":
			create_csg_rooms()
		"Generate Final Mesh":
			generate_room_meshes()
		"Save Rooms As Scenes":
			save_generated_meshes()
		"Clear All":
			clear_rooms_in_scene_tree()
		"Clear Last Generated Rooms":
			clear_last_generated_rooms_in_scene_tree()
	

func save_generated_meshes() -> void:
	if rooms_created.is_empty():
		push_warning("RoomCreator ⚠️: No generated meshes found to save them as scene files")
		return
		
	var index: int = 0
	
	if not DirAccess.dir_exists_absolute(output_folder):
		var folder_creation_result = DirAccess.make_dir_recursive_absolute(output_folder)
		if folder_creation_result != OK:
			push_error("RoomCreator ❌: An error %d ocurred when creating output folder %s " % output_folder)
			return
			
	for room: RoomMesh in rooms_created:
		var target_room: MeshInstance3D = room.duplicate()
		
		for child: Node in RoomCreatorPluginUtilities.get_all_children(target_room):
			child.owner = target_room
			
		var scene: PackedScene = PackedScene.new()
		var result = scene.pack(target_room)
	
		if result == OK:
			var error = ResourceSaver.save(scene, "%s/%s.tscn" % [output_folder, room.name.to_lower()])
			if error != OK:
				push_error("RoomCreator ❌: An error %d occurred while saving the scene %s to %s" % [error, room.name, output_folder])
		
		index += 1


func create_csg_rooms() -> void:
	if room_parameters == null:
		push_warning("RoomCreator ⚠️: The room creator needs a RoomParameters resource to generate the CSGRooms")
		return
		
	if _tool_can_be_used():
		var root_node = _prepare_csg_rooms_output_node()
		
		if generate_mesh_mode == MeshGenerationMode.OneCombinedMesh:
			root_node = _prepare_csg_combiner_root()
		
		var number_of_rooms: int = calculate_number_of_rooms(use_bridge_connector_between_rooms)

		for room_number in number_of_rooms:
			var csg_room = create_csg_room()
			csg_room.position = csg_rooms_created.back().position if csg_rooms_created.size() > 0 else Vector3.ZERO
			
			root_node.add_child(csg_room)
			
			if csg_rooms_created.size() > 0 and csg_room:
				var previous_room: CSGRoom = csg_rooms_created.back() as CSGRoom
				
				if display_mode == DisplayMode.Connected:
					connect_rooms(previous_room, csg_room)
				elif display_mode == DisplayMode.Grid:
					var new_grid_row = csg_rooms_created.size() % grid_columns == 0
					csg_room.position = Vector3(
						0 if new_grid_row else previous_room.position.x + room_parameters.max_room_size.x, 
						0, 
						previous_room.position.z - (room_parameters.max_room_size.z + room_parameters.max_room_size.z / 2.0) if new_grid_row else previous_room.position.z
					)
					

			csg_rooms_created.append(csg_room)
		
		created_csg_rooms.emit(csg_rooms_created)


func create_csg_room() -> CSGRoom:
	var is_bridge_connector: bool = use_bridge_connector_between_rooms and csg_rooms_created.size() > 0 and not csg_rooms_created.back().is_bridge_room_connector
	var room: CSGRoom = CSGRoom.new()
	room.configuration = RoomConfiguration.new()
	
	room.name = "Room%d" % csg_rooms_created.size()
	room.position = csg_rooms_created.back().position if csg_rooms_created.size() > 0 else Vector3.ZERO
	room.use_collision = false
	room.is_bridge_room_connector = is_bridge_connector
	room.configuration.room_size = generate_room_size_based_on_range(min_bridge_connector_size, max_bridge_connector_size) if is_bridge_connector else generate_room_size_based_on_range()
	room.configuration.door_size = room_parameters.door_size
	room.configuration.number_of_doors = clampi(doors_per_room, 1, 4)
	room.configuration.randomize_door_position_in_wall = room_parameters.randomize_door_position_in_wall
	room.configuration.include_floor = include_floor
	room.configuration.include_ceil = include_ceil
	room.configuration.include_ceil_columns = include_ceil_columns
	room.configuration.include_corner_columns = include_corner_columns
	room.configuration.include_front_wall = include_front_wall
	room.configuration.include_back_wall = include_back_wall
	room.configuration.include_left_wall = include_left_wall
	room.configuration.include_right_wall = include_right_wall
	room.configuration.generate_materials = generate_materials
	room.configuration.ceil_thickness = room_parameters.ceil_thickness
	room.configuration.floor_thickness = room_parameters.floor_thickness
	room.configuration.wall_thickness = room_parameters.wall_thickness
	room.configuration.ceil_column_thickness = room_parameters.ceil_column_thickness
	room.configuration.ceil_column_height = room_parameters.ceil_column_height
	room.configuration.corner_column_thickness = room_parameters.corner_column_thickness
	
	return room


func connect_rooms(room_a: CSGRoom, room_b: CSGRoom) -> void:
	var available_sockets_room_a: Array[Marker3D]= room_a.available_sockets()
	var available_sockets_room_b: Array[Marker3D]= room_b.available_sockets()
	
	if available_sockets_room_a.size() > 0 and available_sockets_room_b.size() > 0:
		var room_a_socket: Marker3D = available_sockets_room_a.front() as Marker3D
		var room_b_socket: Marker3D = available_sockets_room_b.front() as Marker3D
		var wall_room_a: CSGBox3D = room_a_socket.get_parent() as CSGBox3D
		var wall_room_b: CSGBox3D = room_b_socket.get_parent() as CSGBox3D
		
		var rotation_to_align_rooms: float = wall_rotations[wall_room_b.name][wall_room_a.name]
		
		# This -room calculation adapts the rotation relatively to last room
		room_b.rotate_y(rotation_to_align_rooms - (-room_a.rotation.y))
		room_b.global_translate(room_a_socket.global_position - room_b_socket.global_position)
		
		room_a_socket.set_meta("connected", room_b_socket)
		room_b_socket.set_meta("connected", room_a_socket)
	
	
func generate_room_size_based_on_range(min_room_size: Vector3 = room_parameters.min_room_size, max_room_size: Vector3 = room_parameters.max_room_size) -> Vector3:
	if min_room_size.is_equal_approx(max_room_size):
		return min_room_size
	else:
		var room_size: Vector3 = Vector3(
				randf_range(min_room_size.x, max_room_size.x),
				randf_range(min_room_size.y, max_room_size.y),
				randf_range(min_room_size.z, max_room_size.z),
			) 
		
		if room_parameters.use_integer_values_size:
			room_size = round(room_size)
			
		return room_size


func calculate_number_of_rooms(use_bridge_connectors: bool = use_bridge_connector_between_rooms) -> int:
	var number_of_rooms = number_of_rooms_per_generation
	
	if use_bridge_connectors:
		number_of_rooms += ceili(number_of_rooms / 2.0)
		
		if number_of_rooms % 2 == 0:
			number_of_rooms += 1
	
	return number_of_rooms


func generate_collision_on_room_mesh(room_mesh_instance: RoomMesh) -> void:
	if generate_collisions:
		match type_of_collision:
			AvailableCollisions.Convex:
				var convex_collision = CollisionShape3D.new()
				convex_collision.name = "%sConvexCollision" % room_mesh_instance.name
				convex_collision.shape = room_mesh_instance.mesh.create_convex_shape(clean_collision, simplified_collision)
			
				if create_static_body:
					var body = StaticBody3D.new()
					body.name = "%sStaticBody3D" % room_mesh_instance.name
					room_mesh_instance.add_child(body)
					RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(body)
					body.add_child(convex_collision)
				else:
					room_mesh_instance.add_child(convex_collision)
					
				RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(convex_collision)
				
			AvailableCollisions.Trimesh:
				var trimesh_collision = CollisionShape3D.new()
				trimesh_collision.name = "%sTrimeshCollision" % room_mesh_instance.name
				trimesh_collision.shape = room_mesh_instance.mesh.create_trimesh_shape()
				
				if create_static_body:
					var body = StaticBody3D.new()
					body.name = "%sStaticBody3D" % room_mesh_instance.name
					room_mesh_instance.add_child(body)
					RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(body)
					body.add_child(trimesh_collision)
				else:
					room_mesh_instance.add_child(trimesh_collision)
			
				RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(trimesh_collision)
	

func generate_room_meshes() -> void:
	if csg_rooms_created.is_empty():
		push_warning("RoomCreator ⚠️: No CSGRooms detected to generate the final meshes")
		return
		
	if _tool_can_be_used():
		
		if generate_mesh_mode == MeshGenerationMode.MeshPerRoom:
			if room_meshes_output_node == null:
				room_meshes_output_node = Node3D.new()
				room_meshes_output_node.name = "RoomMeshesOutputNode"
				add_child(room_meshes_output_node)
				RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_meshes_output_node)
				
			var room_created_names: Array = rooms_created.map(func(room: RoomMesh): return room.name)
			var new_rooms = csg_rooms_created.filter(func(csg_room): return not csg_room.name in room_created_names)
			
			for room: CSGRoom in new_rooms:
				var room_mesh_instance: RoomMesh = room.generate_mesh_instance() as RoomMesh
				
				if room_mesh_instance:
					room_meshes_output_node.add_child(room_mesh_instance)
					
					RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_mesh_instance)
					
					add_door_sockets_to_generated_room_mesh(room_mesh_instance)
					name_surfaces_on_room_mesh(room, room_mesh_instance)
					generate_collision_on_room_mesh(room_mesh_instance)
					rooms_created.append(room_mesh_instance)
					
					room_mesh_instance.set_script(null)
					
			created_rooms.emit(rooms_created)
			
		elif generate_mesh_mode == MeshGenerationMode.OneCombinedMesh:
			var csg_combiner_root: CSGCombiner3D = csg_rooms_output_node.get_node("CSGCombinerRoot") as CSGCombiner3D
			
			if room_meshes_output_node:
				room_meshes_output_node.free()
				
			room_meshes_output_node = Node3D.new()
			room_meshes_output_node.name = "RoomMeshesOutputNode"
			add_child(room_meshes_output_node)
			RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_meshes_output_node)
			
			var meshes = csg_combiner_root.get_meshes()
			
			if meshes.size() > 1:
				var room_mesh_instance = RoomMesh.new()
				room_mesh_instance.name = "GeneratedRoomMesh"
				room_mesh_instance.mesh = meshes[1] as ArrayMesh
				
				for socket: Marker3D in RoomCreatorPluginUtilities.find_nodes_of_type(csg_combiner_root, Marker3D.new()):
					room_mesh_instance.sockets.append(socket)

				room_meshes_output_node.add_child(room_mesh_instance)
				
				RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_mesh_instance)
				
				add_door_sockets_to_generated_room_mesh(room_mesh_instance)
				name_surfaces_on_combined_mesh(csg_combiner_root, room_mesh_instance)
				generate_collision_on_room_mesh(room_mesh_instance)
				
				room_mesh_instance.set_script(null)


func add_door_sockets_to_generated_room_mesh(room_mesh_instance: RoomMesh) -> void:
	for socket: Marker3D in room_mesh_instance.sockets:
		## Duplicate does not work as expected so a new Marker3d needs to be created and assign the properties manually
		var door_socket = Marker3D.new()
		door_socket.name = socket.name
		door_socket.set_meta("wall", socket.get_meta("wall"))
		
		room_mesh_instance.add_child(door_socket)
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(door_socket)
		
		door_socket.global_position = socket.global_position
		door_socket.global_rotation = socket.global_rotation

	
func name_surfaces_on_combined_mesh(root_node_for_rooms: CSGCombiner3D, room_mesh_instance: MeshInstance3D) -> void:
	var index: int = 0
	
	for room: CSGRoom in root_node_for_rooms.get_children().filter(func(child): return child is CSGRoom):
		for shape: CSGShape3D in room.materials_by_room_part:
			room_mesh_instance.mesh.surface_set_name(index, shape.name)
			index += 1
	
	
func name_surfaces_on_room_mesh(room: CSGRoom, room_mesh_instance: MeshInstance3D) -> void:
	print(room_mesh_instance.mesh)
	for shape: CSGShape3D in room.materials_by_room_part:
		room_mesh_instance.mesh.surface_set_name(room.materials_by_room_part[shape], shape.name)


func clear_rooms_in_scene_tree() -> void:
	if _tool_can_be_used():
		# Never delete arbitrary user-authored children.
		if is_instance_valid(csg_rooms_output_node):
			csg_rooms_output_node.free()
		if is_instance_valid(room_meshes_output_node):
			room_meshes_output_node.free()
		csg_rooms_output_node = null
		room_meshes_output_node = null
		
		csg_rooms_created.clear()
		rooms_created.clear()


func clear_last_generated_rooms_in_scene_tree() -> void:
	if _tool_can_be_used() and not csg_rooms_created.is_empty():
		var rooms_to_remove_count = number_of_rooms_per_generation + (ceili(number_of_rooms_per_generation / 2) if use_bridge_connector_between_rooms else 0)

		var last_rooms_created = csg_rooms_created.slice(max(0, csg_rooms_created.size() - rooms_to_remove_count))
		csg_rooms_created = csg_rooms_created.slice(0, csg_rooms_created.size() - last_rooms_created.size())
		
		for room in last_rooms_created:
			room.free()
		
		if csg_rooms_created.is_empty() and csg_rooms_output_node:
				csg_rooms_output_node.free()
				csg_rooms_output_node = null
			

func _prepare_csg_rooms_output_node() -> Node3D:
	if csg_rooms_output_node == null:
		csg_rooms_output_node = Node3D.new()
		csg_rooms_output_node.name = "CSGRoomsOutputNode"
		add_child(csg_rooms_output_node)
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(csg_rooms_output_node)
		
	return csg_rooms_output_node
	
	
func _prepare_csg_combiner_root() -> CSGCombiner3D:
	var csg_combiner_root: CSGCombiner3D = csg_rooms_output_node.get_node_or_null("CSGCombinerRoot")
			
	if csg_combiner_root == null:
		csg_combiner_root = CSGCombiner3D.new()
		csg_combiner_root.name = "CSGCombinerRoot"
		csg_combiner_root.use_collision = false
		
	if not csg_combiner_root.is_inside_tree():
		csg_rooms_output_node.add_child(csg_combiner_root)
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(csg_combiner_root)
	
	return csg_combiner_root


func _tool_can_be_used() -> bool:
	return room_parameters and (Engine.is_editor_hint() and is_inside_tree()) or (not Engine.is_editor_hint() and is_node_ready())
