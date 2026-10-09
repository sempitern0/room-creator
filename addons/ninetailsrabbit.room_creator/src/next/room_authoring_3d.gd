@tool
class_name RoomAuthoring3D
extends Node3D
## New non-destructive authoring node. Legacy RoomCreator remains available.

signal validation_finished(report: RoomValidationReport)
signal bake_finished(root: Node3D)
signal export_finished(path: String, result: Error)

const PREVIEW_NAME := "RoomCreatorPreview"
const BAKE_NAME := "RoomCreatorBake"
const GENERATED_META := "room_creator_generated"

@export var blueprint: RoomBlueprint
@export_file("*.tscn") var output_scene_path: String = "res://room_creator/rooms/room.tscn"
@export_tool_button("Generate Preview") var preview_action: Callable = generate_preview
@export_tool_button("Validate Blueprint") var validate_action: Callable = validate_blueprint
@export_tool_button("Bake Static Room") var bake_action: Callable = bake
@export_tool_button("Save Baked Scene") var save_action: Callable = save_scene
@export_tool_button("Clear Preview") var clear_preview_action: Callable = clear_preview
@export_tool_button("Clear Bake") var clear_bake_action: Callable = clear_bake

var last_report: RoomValidationReport

func validate_blueprint() -> RoomValidationReport:
	last_report = RoomGeometryBuilder.validate(blueprint)
	validation_finished.emit(last_report)
	if not last_report.is_valid():
		push_warning("RoomAuthoring3D: " + last_report.summary())
	return last_report


func generate_preview() -> void:
	if not validate_blueprint().is_valid():
		return
	var geometry := RoomGeometryBuilder.build(blueprint, false)
	_replace_generated(PREVIEW_NAME, geometry)


func bake() -> void:
	if not validate_blueprint().is_valid():
		return
	var geometry := RoomGeometryBuilder.build(blueprint, true)
	_replace_generated(BAKE_NAME, geometry)
	bake_finished.emit(geometry)


func clear_preview() -> void:
	_remove_generated(PREVIEW_NAME)


func clear_bake() -> void:
	_remove_generated(BAKE_NAME)


func save_scene() -> Error:
	var baked := _get_generated(BAKE_NAME)
	if baked == null:
		push_warning("RoomAuthoring3D: Bake a valid room before saving.")
		return ERR_DOES_NOT_EXIST
	if not output_scene_path.begins_with("res://") or not output_scene_path.ends_with(".tscn"):
		push_error("RoomAuthoring3D: Output must be a res:// .tscn path.")
		return ERR_INVALID_PARAMETER
	var copy := baked.duplicate()
	copy.name = "Room"
	_set_descendant_owners(copy, copy)
	var scene := PackedScene.new()
	var error := scene.pack(copy)
	if error == OK:
		var directory := output_scene_path.get_base_dir()
		error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if error == OK:
			error = ResourceSaver.save(scene, output_scene_path)
	copy.free()
	if error != OK:
		push_error("RoomAuthoring3D: Scene export failed (error %d)." % error)
	elif Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	export_finished.emit(output_scene_path, error)
	return error


func _get_generated(node_name: String) -> Node3D:
	var child := get_node_or_null(NodePath(node_name))
	if child is Node3D and child.get_meta(GENERATED_META, false):
		return child as Node3D
	return null


func _remove_generated(node_name: String) -> void:
	var generated := _get_generated(node_name)
	if generated != null:
		remove_child(generated)
		generated.free()


func _replace_generated(node_name: String, geometry: Node3D) -> void:
	if geometry == null:
		return
	var occupant := get_node_or_null(NodePath(node_name))
	if occupant != null and not occupant.get_meta(GENERATED_META, false):
		push_error("RoomAuthoring3D: A user-owned node occupies %s; no changes made." % node_name)
		geometry.free()
		return
	_remove_generated(node_name)
	geometry.name = node_name
	add_child(geometry)
	var scene_root: Node = null
	if is_inside_tree():
		scene_root = get_tree().edited_scene_root if Engine.is_editor_hint() else self
	if scene_root == null:
		scene_root = self
	geometry.owner = scene_root
	_set_descendant_owners(geometry, scene_root)


static func _set_descendant_owners(parent: Node, target_owner: Node) -> void:
	for child in parent.get_children():
		child.owner = target_owner
		_set_descendant_owners(child, target_owner)
