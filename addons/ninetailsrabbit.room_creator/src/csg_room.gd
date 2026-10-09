@tool
class_name CSGRoom extends CSGCombiner3D

@export var configuration: RoomConfiguration
@export var is_bridge_room_connector : bool = false

var floor_side: CSGShape3D
var ceil_side: CSGShape3D
var front_wall: CSGShape3D
var back_wall: CSGShape3D
var left_wall: CSGShape3D
var right_wall: CSGShape3D

var materials_by_room_part: Dictionary ##  CSGShape and the surface related index
var doors: Array[CSGShape3D] = []
var corner_columns: Array[CSGShape3D] = []
var ceil_columns: Array[CSGShape3D] = []


func _enter_tree() -> void:
	if configuration == null:
		push_warning("CSGRoom: Assign a RoomConfiguration before adding the node.")
		return
	if get_child_count() == 0 and not configuration.room_size.is_zero_approx():
		build()


func build() -> void:
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(self)
	
	if is_bridge_room_connector:
		name = "BridgeConnector%s" % name
		
	if configuration.include_floor:
		create_floor(configuration.room_size)
		
	if configuration.include_ceil:
		create_ceil(configuration.room_size)
		
		if configuration.include_ceil_columns:
			create_ceil_columns(configuration.room_size)
		
	if configuration.include_front_wall:
		create_front_wall(configuration.room_size)
	
	if configuration.include_back_wall:
		create_back_wall(configuration.room_size)
		
	if configuration.include_right_wall:
		create_right_wall(configuration.room_size)
		
	if configuration.include_left_wall:
		create_left_wall(configuration.room_size)
		
	if configuration.include_corner_columns:
		create_corner_columns()
	
	if is_bridge_room_connector:
		if configuration.include_front_wall and configuration.include_back_wall:
			create_door_slot_in_wall(front_wall, 1)
			create_door_slot_in_wall(back_wall, 2)
		elif configuration.include_right_wall and configuration.include_left_wall:
			create_door_slot_in_wall(right_wall, 1)
			create_door_slot_in_wall(left_wall, 2)
	else:
		if not configuration.use_manual_door_mode:
			for socket_number in configuration.number_of_doors:
				create_door_slot_in_random_wall(socket_number)
			
	create_materials_on_room()
		

func create_manual_doors() -> void:
	var socket_number: int = 1
			
	if configuration.door_in_back_wall:
		create_door_slot_in_wall(back_wall, socket_number)
		socket_number += 1
		
	if configuration.door_in_front_wall:
		create_door_slot_in_wall(front_wall, socket_number)
		socket_number += 1
		
	if configuration.door_in_left_wall:
		create_door_slot_in_wall(left_wall, socket_number)
		socket_number += 1
		
	if configuration.door_in_right_wall:
		create_door_slot_in_wall(right_wall, socket_number)


func create_materials_on_room() -> void:
	if configuration.generate_materials:
		var shapes =  RoomCreatorPluginUtilities.get_all_children(self).filter(func(child): return child is CSGShape3D)
		var index: int = 0
		
		for shape: CSGShape3D in shapes:
			shape.material = StandardMaterial3D.new()
				
			materials_by_room_part[shape] = index
			index += 1


func generate_mesh_instance():
	var meshes = get_meshes()
	
	if meshes.size() > 1:
		var room_mesh: RoomMesh = RoomMesh.new()
		room_mesh.name = name
		room_mesh.mesh = meshes[1]
		room_mesh.position = position
		room_mesh.rotation = rotation
		room_mesh.sockets = door_sockets()
		
		return room_mesh
	
	return null

#region Getters
func walls() -> Array[CSGShape3D]:
	var result: Array[CSGShape3D] = []

	for wall: CSGShape3D in RoomCreatorPluginUtilities.remove_falsy_values([front_wall, back_wall, right_wall, left_wall]):
		result.append(wall)
	
	return result


func door_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	positions.assign(doors.map(func(door: CSGShape3D): return door.global_position))
	
	return positions


func available_sockets() -> Array[Marker3D]:
	var markers = door_sockets().filter(func(socket: Node): return socket is Marker3D and not socket.get_meta("connected"))
	var sockets: Array[Marker3D] = []
	
	for socket: Marker3D in markers:
		sockets.append(socket)
	
	return sockets


func door_sockets() ->  Array[Marker3D]:
	var markers = RoomCreatorPluginUtilities.find_nodes_of_type(self, Marker3D.new())
	var sockets: Array[Marker3D] = []
	
	for socket: Marker3D in markers:
		sockets.append(socket)
	
	return sockets


func get_door_sloot_from_wall(wall: CSGShape3D):
	if wall:
		return wall.get_node_or_null("%sDoorSlot" % wall.name)
		
	return null
#endregion

#region Part creators
func create_door_slot_in_random_wall(socket_number: int = 1, size: Vector3 = configuration.room_size, _door_size: Vector3 = configuration.door_size) -> void:
	var available_walls = walls().filter(func(wall: CSGShape3D): return wall.name.containsn("wall") and wall.get_child_count() == 0)

	if available_walls.size() > 0:
		create_door_slot_in_wall(available_walls.pick_random(), socket_number, size, _door_size)


func create_door_slot_in_wall(wall: CSGShape3D, socket_number: int = 1, size: Vector3 = configuration.room_size, _door_size: Vector3 = configuration.door_size) -> void:
	if wall.get_child_count() == 0:
		var regex: RegEx = RegEx.new()
		regex.compile("(front|back)")
		
		var regex_result = regex.search(wall.name.to_lower()) # Front and back walls does not apply door rotation to fit in
		
		var door_position: Vector3 = Vector3(0, Vector3.DOWN.y * ( (configuration.room_size.y / 2) - (_door_size.y / 2) ), 0)
		var door_rotation: Vector3 = Vector3(0, 0 if regex_result else PI / 2, 0)
		
		if configuration.randomize_door_position_in_wall:
			if door_rotation.y != 0 and (wall.size.z - _door_size.x) > _door_size.x:
				door_position.z = (-1 if RoomCreatorPluginUtilities.chance(0.5) else 1) * randf_range(_door_size.x, (wall.size.z - _door_size.x) / 2)
			
			if door_rotation.y == 0 and (wall.size.x - _door_size.x) > _door_size.x:
				door_position.x = (-1 if RoomCreatorPluginUtilities.chance(0.5) else 1) * randf_range(_door_size.x, (wall.size.x - _door_size.x) / 2)
				
		var door_slot: CSGBox3D = CSGBox3D.new()
		door_slot.name = "%sDoorSlot" % wall.name
		door_slot.operation = CSGBox3D.OPERATION_SUBTRACTION
		door_slot.size = _door_size
		door_slot.position = door_position
		door_slot.rotation = door_rotation
		
		wall.add_child(door_slot)
		
		if not doors.has(door_slot):
			doors.append(door_slot)
		
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(door_slot)
		
		var room_socket: Marker3D = Marker3D.new()
		room_socket.name = "RoomSocket %d" % socket_number
		room_socket.position = Vector3(door_slot.position.x, min( (door_slot.position.y + _door_size.y / 2) + 0.1, size.y), door_slot.position.z)
		room_socket.set_meta("connected", false)
		
		match wall.name.to_lower().strip_edges():
			"frontwall":
				room_socket.position += Vector3.FORWARD * (configuration.wall_thickness / 2)
			"backwall":
				room_socket.position += Vector3.BACK * (configuration.wall_thickness / 2)
			"rightwall":
				room_socket.position += Vector3.RIGHT * (configuration.wall_thickness / 2)
			"leftwall":
				room_socket.position += Vector3.LEFT * (configuration.wall_thickness / 2)
			
		room_socket.set_meta("wall", wall.name)
				
		wall.add_child(room_socket)
		RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(room_socket)
	

func create_ceil_columns(size: Vector3 = configuration.room_size) -> void:
	var ceil_column_base: CSGShape3D = ceil_side.duplicate()
	ceil_column_base.name = "CeilColumnsInterior"
	ceil_column_base.size = Vector3(ceil_column_base.size.x - configuration.ceil_thickness,  configuration.ceil_column_height, ceil_column_base.size.z - configuration.ceil_thickness)
	
	var ceil_column_substraction: CSGShape3D = ceil_column_base.duplicate()
	ceil_column_substraction.name = "CeilColumnsExterior"
	ceil_column_substraction.operation = CSGShape3D.OPERATION_SUBTRACTION
	ceil_column_substraction.size = Vector3(size.x - configuration.ceil_column_thickness * 2, ceil_column_base.size.y + configuration.ceil_column_thickness * 2, size.z - configuration.ceil_column_thickness * 2)
	
	add_child(ceil_column_base)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(ceil_column_base)
	ceil_column_base.add_child(ceil_column_substraction)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(ceil_column_substraction)
	
	ceil_column_substraction.position = Vector3.ZERO
	ceil_column_base.position.y -= min(configuration.ceil_column_height, configuration.ceil_column_thickness) - configuration.ceil_thickness * 2
	
	ceil_columns.append_array([ceil_column_base, ceil_column_substraction])


func create_corner_columns(size: Vector3 = configuration.room_size) -> void:
	var adjustment_thickness = configuration.corner_column_thickness / 2.0 + configuration.wall_thickness / 2.0
	var column_size: Vector3 =  Vector3(configuration.corner_column_thickness, size.y, configuration.corner_column_thickness)
	
	var top_right_column: CSGBox3D = CSGBox3D.new()
	var top_left_column: CSGBox3D = CSGBox3D.new()
	var bottom_right_column: CSGBox3D = CSGBox3D.new()
	var bottom_left_column: CSGBox3D = CSGBox3D.new()
	
	corner_columns.append_array([top_right_column, top_left_column, bottom_right_column, bottom_left_column])
	
	top_right_column.name = "TopRightCornerColumn"
	top_right_column.size = column_size
	
	add_child(top_right_column)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(top_right_column)
	top_right_column.position = Vector3( (size.x / 2.0) - adjustment_thickness, size.y / 2.0, -((size.z / 2.0) - adjustment_thickness))

	top_left_column.name = "TopLeftCornerColumn"
	top_left_column.size = column_size
	top_left_column.position = Vector3(-((size.x / 2.0) - adjustment_thickness), size.y / 2.0, -((size.z / 2.0) - adjustment_thickness))
	add_child(top_left_column)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(top_left_column)

	bottom_right_column.name = "BottomRightCornerColumn"
	bottom_right_column.size = column_size
	add_child(bottom_right_column)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(bottom_right_column)
	bottom_right_column.position = Vector3( (size.x / 2.0) - adjustment_thickness, size.y / 2.0, ((size.z / 2.0) - adjustment_thickness))

	bottom_left_column.name = "BottomLeftCornerColumn"
	bottom_left_column.size = column_size
	add_child(bottom_left_column)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(bottom_left_column)
	bottom_left_column.position = Vector3(-((size.x / 2.0) - adjustment_thickness), size.y / 2.0, ((size.z / 2.0) - adjustment_thickness))
	
	
func create_floor(size: Vector3 = configuration.room_size) -> void:
	if configuration.floor_thickness == 0:
		floor_side = CSGMesh3D.new()
		floor_side.mesh = PlaneMesh.new()
		floor_side.mesh.size = Vector2(size.x, size.z)
		floor_side.flip_faces = false
	else:
		floor_side = CSGBox3D.new()
		floor_side.size = Vector3(size.x + configuration.floor_thickness * 2, configuration.floor_thickness, size.z + configuration.floor_thickness * 2)
		
	floor_side.name = "Floor"
	floor_side.position = Vector3.ZERO
	
	add_child(floor_side)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(floor_side)


func create_ceil(size: Vector3 = configuration.room_size) -> void:
	if configuration.ceil_thickness == 0:
		ceil_side = CSGMesh3D.new()
		ceil_side.mesh = PlaneMesh.new()
		ceil_side.mesh.size = Vector2(size.x, size.z)
		ceil_side.position = Vector3(0, max(size.y, size.y - size.y / 2.5), 0)
		ceil_side.flip_faces = true
	else:
		ceil_side = CSGBox3D.new()
		ceil_side.size = Vector3(size.x + configuration.ceil_thickness * 2, configuration.ceil_thickness, size.z + configuration.ceil_thickness * 2)
		ceil_side.position = Vector3(0, max(size.y, (size.y + configuration.ceil_thickness) - size.y / 2.5), 0)
		
	ceil_side.name = "Ceil"
	
	add_child(ceil_side)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(ceil_side)


func create_front_wall(size: Vector3 = configuration.room_size) -> void:
	if configuration.wall_thickness == 0:
		front_wall = CSGMesh3D.new()
		front_wall.mesh = PlaneMesh.new()
		front_wall.mesh.size = Vector2(size.x, size.y)
		front_wall.position = Vector3(0, size.y / 2, min(-size.z / 2, -size.z / 2.5))
		front_wall.flip_faces = false
		front_wall.mesh.orientation = PlaneMesh.FACE_Z
	else:
		front_wall = CSGBox3D.new()
		front_wall.size = Vector3(size.x, size.y, configuration.wall_thickness)
		front_wall.position = Vector3(0, size.y / 2, min(-size.z / 2, -(size.z + configuration.wall_thickness) / 2.5) )
		
	front_wall.name = "FrontWall"
	
	add_child(front_wall)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(front_wall)


func create_back_wall(size: Vector3 = configuration.room_size) -> void:
	if configuration.wall_thickness == 0:
		back_wall = CSGMesh3D.new()
		back_wall.mesh = PlaneMesh.new()
		back_wall.mesh.size = Vector2(size.x, size.y)
		back_wall.position = Vector3(0, size.y / 2, max(size.z / 2, size.z / 2.5))
		back_wall.flip_faces = true
		back_wall.mesh.orientation = PlaneMesh.FACE_Z
	else:
		back_wall = CSGBox3D.new()
		back_wall.size = Vector3(size.x, size.y, configuration.wall_thickness)
		back_wall.position = Vector3(0, size.y / 2, max(size.z / 2, (size.z + configuration.wall_thickness) / 2.5) )
		
	back_wall.name = "BackWall"
	
	add_child(back_wall)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(back_wall)


func create_right_wall(size: Vector3 = configuration.room_size) -> void:
	if configuration.wall_thickness == 0:
		right_wall = CSGMesh3D.new()
		right_wall.mesh = PlaneMesh.new()
		right_wall.mesh.size = Vector2(size.z, size.y)
		right_wall.position = Vector3(max(size.x / 2, size.x / 2.5), size.y / 2, 0)
		right_wall.flip_faces = true
		right_wall.mesh.orientation = PlaneMesh.FACE_X
	else:
		right_wall = CSGBox3D.new()
		right_wall.size = Vector3(configuration.wall_thickness, size.y, size.z)
		right_wall.position = Vector3(max(size.x / 2, (size.x + configuration.wall_thickness) / 2.5) , size.y / 2, 0)
		
	right_wall.name = "RightWall"
		
	add_child(right_wall)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(right_wall)


func create_left_wall(size: Vector3 = configuration.room_size) -> void:
	if configuration.wall_thickness == 0:
		left_wall = CSGMesh3D.new()
		left_wall.mesh = PlaneMesh.new()
		left_wall.mesh.size = Vector2(size.z, size.y)
		left_wall.position = Vector3(min(-size.x / 2, -size.x / 2.5), size.y / 2, 0)
		left_wall.flip_faces = false
		left_wall.mesh.orientation = PlaneMesh.FACE_X
	else:
		left_wall = CSGBox3D.new()
		left_wall.size = Vector3(configuration.wall_thickness, size.y, size.z)
		left_wall.position = Vector3(min(-size.x / 2, (-size.x + configuration.wall_thickness) / 2.5) , size.y / 2, 0)
	
	left_wall.name = "LeftWall"
	
	add_child(left_wall)
	RoomCreatorPluginUtilities.set_owner_to_edited_scene_root(left_wall)

#endregion

#region Materials
func change_ceil_material(new_material: StandardMaterial3D) -> CSGRoom:
	if ceil_side:
		ceil_side.material = new_material
	
	return self
	

func change_floor_material(new_material: StandardMaterial3D) -> CSGRoom:
	if floor_side:
		floor_side.material = new_material
	
	return self


func change_left_wall_material(new_material: StandardMaterial3D) -> CSGRoom:
	if left_wall:
		left_wall.material = new_material
	
	return self


func change_right_wall_material(new_material: StandardMaterial3D) -> CSGRoom:
	if right_wall:
		right_wall.material = new_material
	
	return self


func change_front_wall_material(new_material: StandardMaterial3D) -> CSGRoom:
	if front_wall:
		front_wall.material = new_material
	
	return self


func change_back_wall_material(new_material: StandardMaterial3D) -> CSGRoom:
	if back_wall:
		back_wall.material = new_material
	
	return self
	
	
func change_doors_material(new_material: StandardMaterial3D) -> CSGRoom:
	if doors.size():
		for door in doors:
			door.material = new_material
	
	return self

func change_corner_columns_material(new_material: StandardMaterial3D) -> CSGRoom:
	if corner_columns.size():
		for column in corner_columns:
			column.material = new_material
	
	return self


func change_ceil_columns_material(new_material: StandardMaterial3D) -> CSGRoom:
	if ceil_columns.size():
		for column in ceil_columns:
			column.material = new_material
	
	return self

#endregion

#region Visibility
func show_ceil() -> CSGRoom:
	if ceil_side:
		ceil_side.show()
	
	return self


func toggle_ceil_visibility() -> CSGRoom:
	if ceil_side:
		ceil_side.visible = !ceil_side.visible
	
	return self


func toggle_floor_visibility() -> CSGRoom:
	if floor_side:
		floor_side.visible = !floor_side.visible
	
	return self


func toggle_left_wall_visibility() -> CSGRoom:
	if left_wall:
		left_wall.visible = !left_wall.visible
	
	return self


func toggle_right_wall_visibility() -> CSGRoom:
	if right_wall:
		right_wall.visible = !right_wall.visible
	
	return self


func toggle_front_wall_visibility() -> CSGRoom:
	if front_wall:
		front_wall.visible = !front_wall.visible
	
	return self

func toggle_back_wall_visibility() -> CSGRoom:
	if back_wall:
		back_wall.visible = !back_wall.visible
	
	return self

#endregion
