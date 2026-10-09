@tool
class_name RoomParameters extends Resource

@export_range(1, 4, 1) var doors: int = 2
@export var randomize_door_position_in_wall: bool = false
@export var is_bridge_connector: bool = false
## Decimal values are rounded when generate betwen a min-max size range
@export var use_integer_values_size: bool = true
@export_group("Door")
@export var door_size: Vector3 = Vector3(1.5, 2.0, 0.25)
@export_group("Size")
@export var min_room_size: Vector3 = Vector3(6.0, 3.5, 5.0)
@export var max_room_size: Vector3 = Vector3(10.0, 5.0, 6.0)
@export_group("Thickness")
@export var plane: bool = false:
	set(value):
		plane = value
		
		if plane:
			wall_thickness = 0
			ceil_thickness = 0
			floor_thickness = 0
			notify_property_list_changed()
		else:
			wall_thickness = 0.15
			ceil_thickness = 0.1
			floor_thickness = 0.1
			notify_property_list_changed()
			
@export var wall_thickness: float = 0.15
@export var ceil_thickness: float = 0.1
@export var floor_thickness: float = 0.1
@export_group("Ceil columns")
@export var ceil_column_height: float = 0.30
@export var ceil_column_thickness: float = 0.30
@export_group("Corner columns")
@export var corner_column_thickness: float = 0.5
