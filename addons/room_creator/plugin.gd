@tool
extends EditorPlugin

var inspector_plugin

func _enter_tree() -> void:
	add_custom_type(
		"RoomCreator",
		"Node3D",
		preload("res://addons/room_creator/src/room_creator.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	add_custom_type(
		"RoomAuthoring3D",
		"Node3D",
		preload("res://addons/room_creator/src/next/room_authoring_3d.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	add_custom_type(
		"DungeonGenerator",
		"Node3D",
		preload("res://addons/room_creator/src/dungeon/dungeon_generator.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	
	inspector_plugin = preload("res://addons/room_creator/src/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)


func _exit_tree() -> void:
	remove_custom_type("RoomAuthoring3D")
	remove_custom_type("DungeonGenerator")
	remove_custom_type("RoomCreator")
	remove_inspector_plugin(inspector_plugin)
