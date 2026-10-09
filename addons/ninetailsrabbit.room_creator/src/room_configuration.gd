class_name RoomConfiguration extends Resource

## The dimensions of the room where Vector3(width, height, depth)
@export var room_size: Vector3 = Vector3(5.0, 4.0, 7.0)
## Generate a standard material named with the room part that belongs
@export var generate_materials: bool = true
@export_group("Thickness")
@export var wall_thickness: float = 0.15
@export var ceil_thickness: float = 0.1
@export var floor_thickness: float = 0.1
@export_group("Ceil columns")
@export var ceil_column_height: float = 0.6
@export var ceil_column_thickness: float = 0.5
@export_group("Corner columns")
@export var corner_column_thickness: float = 0.5
@export_group("Includes")
@export var include_ceil: bool = true
@export var include_ceil_columns: bool = false
@export var include_floor: bool = true
@export var include_right_wall: bool = true
@export var include_left_wall: bool = true
@export var include_front_wall: bool = true
@export var include_back_wall: bool = true
@export var include_corner_columns: bool = false
@export_group("Doors")
## When enabled the doors are created based on the dungeon critical path and branches
@export var use_manual_door_mode: bool = false:
	set(value):
		use_manual_door_mode = value
		notify_property_list_changed()
@export var door_size: Vector3 = Vector3(1.5, 2.0, 0.25)
@export_range(1, 4, 1) var number_of_doors = 1
@export var randomize_door_position_in_wall: bool = false
@export var door_in_left_wall: bool = false
@export var door_in_right_wall: bool = false
@export var door_in_front_wall: bool = false
@export var door_in_back_wall: bool = false


func _validate_property(property: Dictionary) -> void:
	if property.name in [
		"door_size",
		"number_of_doors",
		"randomize_door_position_in_wall",
		"door_in_left_wall",
		"door_in_right_wall",
		"door_in_front_wall",
		"door_in_back_wall",
	]:
		property.usage = PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR if use_manual_door_mode else PROPERTY_USAGE_EDITOR
