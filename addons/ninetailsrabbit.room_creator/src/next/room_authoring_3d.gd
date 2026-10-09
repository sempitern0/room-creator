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
	_commit_generated_action(PREVIEW_NAME, RoomGeometryBuilder.build(blueprint, false), "Generate Room Preview")


func bake() -> void:
	if not validate_blueprint().is_valid():
		return
	_commit_generated_action(BAKE_NAME, RoomGeometryBuilder.build(blueprint, true), "Bake Static Room")
	bake_finished.emit(_get_generated(BAKE_NAME))


func clear_preview() -> void:
	_commit_generated_action(PREVIEW_NAME, null, "Clear Room Preview")


func clear_bake() -> void:
	_commit_generated_action(BAKE_NAME, null, "Clear Static Room")


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


func _commit_generated_action(node_name: String, geometry: Node3D, action_label: String) -> void:
	var occupant := get_node_or_null(NodePath(node_name))
	if occupant != null and not occupant.get_meta(GENERATED_META, false):
		push_error("RoomAuthoring3D: A user-owned node occupies %s; no changes made." % node_name)
		if geometry != null:
			geometry.free()
		return
	# PackedScene snapshots keep the exact before/after geometry. Undo does not
	# read a blueprint that the designer may have subsequently edited.
	var before := _snapshot_node(_get_generated(node_name))
	var after := _snapshot_node(geometry)
	if geometry != null:
		geometry.free()
		if after == null:
			push_error("RoomAuthoring3D: Unable to snapshot generated geometry.")
			return
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		var history := EditorInterface.get_editor_undo_redo()
		history.create_action(action_label, UndoRedo.MERGE_DISABLE, self)
		history.add_do_method(self, "_apply_snapshot", node_name, after)
		history.add_undo_method(self, "_apply_snapshot", node_name, before)
		history.commit_action()
	else:
		_apply_snapshot(node_name, after)


func _apply_snapshot(node_name: String, snapshot: PackedScene) -> void:
	var occupant := get_node_or_null(NodePath(node_name))
	if occupant != null and not occupant.get_meta(GENERATED_META, false):
		push_error("RoomAuthoring3D: Refusing to overwrite user-owned node %s." % node_name)
		return
	_remove_generated(node_name)
	if snapshot == null:
		return
	var geometry := snapshot.instantiate() as Node3D
	if geometry == null:
		push_error("RoomAuthoring3D: Unable to instantiate snapshot.")
		return
	geometry.name = node_name
	add_child(geometry)
	var scene_root: Node = null
	if is_inside_tree():
		scene_root = get_tree().edited_scene_root if Engine.is_editor_hint() else self
	if scene_root == null:
		scene_root = self
	geometry.owner = scene_root
	_set_descendant_owners(geometry, scene_root)


static func _snapshot_node(node: Node3D) -> PackedScene:
	if node == null:
		return null
	var copy := node.duplicate() as Node3D
	_set_descendant_owners(copy, copy)
	var snapshot := PackedScene.new()
	var result := snapshot.pack(copy)
	copy.free()
	if result != OK:
		return null
	return snapshot


static func _set_descendant_owners(parent: Node, target_owner: Node) -> void:
	for child in parent.get_children():
		child.owner = target_owner
		_set_descendant_owners(child, target_owner)
