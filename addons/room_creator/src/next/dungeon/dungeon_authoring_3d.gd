@tool
class_name DungeonAuthoring3D
extends Node3D
## F2 editor facade. Planning is pure; preview and bake are separate undoable actions.

signal layout_generated(result: DungeonBuildResult)
signal validation_finished(report: RoomValidationReport)
signal generation_failed(report: RoomValidationReport)
signal bake_finished(root: Node3D)
signal export_finished(path: String, error: Error)

const PREVIEW_NAME := "DungeonPreview"
const BAKE_NAME := "DungeonBake"
const GENERATED_META := "room_creator_generated"

@export var config: DungeonConfig
@export var layout: LevelLayout
@export_file("*.tscn") var output_scene_path: String = "res://room_creator/dungeons/dungeon.tscn"
@export_tool_button("Generate Layout") var generate_action: Callable = generate_new_layout
@export_tool_button("Validate Layout") var validate_action: Callable = validate_current_layout
@export_tool_button("Preview Layout") var preview_action: Callable = preview_layout
@export_tool_button("Bake Static Dungeon") var bake_action: Callable = bake
@export_tool_button("Save Baked Scene") var save_action: Callable = save_scene
@export_tool_button("Clear Preview") var clear_preview_action: Callable = clear_preview
@export_tool_button("Clear Bake") var clear_bake_action: Callable = clear_bake

var last_result: DungeonBuildResult
var last_report: RoomValidationReport

func generate_layout(source: DungeonConfig) -> DungeonBuildResult:
	return DungeonPlanner.generate_layout(source)


func generate_new_layout() -> void:
	var result := generate_layout(config)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return
	# Old valid preview/bake remain untouched. Save will reject stale bake versions.
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		var history := EditorInterface.get_editor_undo_redo()
		history.create_action("Generate Dungeon Layout", UndoRedo.MERGE_DISABLE, self)
		history.add_do_property(self, "layout", result.layout)
		history.add_undo_property(self, "layout", layout)
		history.commit_action()
	else:
		layout = result.layout
	layout_generated.emit(result)


func validate_current_layout() -> RoomValidationReport:
	last_report = DungeonPlanner.validate_layout(layout)
	validation_finished.emit(last_report)
	if not last_report.is_valid():
		push_warning("DungeonAuthoring3D: " + last_report.summary())
	return last_report


func get_layout() -> LevelLayout:
	return layout


func get_last_seed() -> int:
	return layout.seed if layout != null else 0


func get_last_report() -> RoomValidationReport:
	return last_report


func preview_layout() -> void:
	if not validate_current_layout().is_valid():
		return
	_commit_generated_action(PREVIEW_NAME, DungeonSceneCompiler.build(layout, false), "Preview Dungeon")


func bake() -> void:
	if not validate_current_layout().is_valid():
		return
	_commit_generated_action(BAKE_NAME, DungeonSceneCompiler.build(layout, true), "Bake Static Dungeon")
	bake_finished.emit(_get_generated(BAKE_NAME))


func clear_preview() -> void:
	_commit_generated_action(PREVIEW_NAME, null, "Clear Dungeon Preview")


func clear_bake() -> void:
	_commit_generated_action(BAKE_NAME, null, "Clear Dungeon Bake")


func save_scene() -> Error:
	if not validate_current_layout().is_valid():
		return ERR_INVALID_DATA
	var baked := _get_generated(BAKE_NAME)
	if baked == null:
		push_warning("DungeonAuthoring3D: Bake the dungeon before saving.")
		return ERR_DOES_NOT_EXIST
	if baked.get_meta("layout_fingerprint", "") != layout.fingerprint():
		push_error("DungeonAuthoring3D: Layout changed since bake. Re-bake before exporting.")
		return ERR_INVALID_DATA
	if not output_scene_path.begins_with("res://") or not output_scene_path.ends_with(".tscn"):
		push_error("DungeonAuthoring3D: Scene path must be res://... .tscn.")
		return ERR_INVALID_PARAMETER
	var copy := baked.duplicate()
	copy.name = "Dungeon"
	_set_descendant_owners(copy, copy)
	var packed := PackedScene.new()
	var error := packed.pack(copy)
	if error == OK:
		error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_scene_path.get_base_dir()))
		if error == OK:
			error = ResourceSaver.save(packed, output_scene_path)
	copy.free()
	if error != OK:
		push_error("DungeonAuthoring3D: Export failed with error %d." % error)
	elif Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	export_finished.emit(output_scene_path, error)
	return error


func _get_generated(node_name: String) -> Node3D:
	var candidate := get_node_or_null(NodePath(node_name))
	if candidate is Node3D and candidate.get_meta(GENERATED_META, false):
		return candidate as Node3D
	return null


func _remove_generated(node_name: String) -> void:
	var candidate := _get_generated(node_name)
	if candidate != null:
		remove_child(candidate)
		candidate.free()


func _commit_generated_action(node_name: String, geometry: Node3D, action_label: String) -> void:
	var occupant := get_node_or_null(NodePath(node_name))
	if occupant != null and not occupant.get_meta(GENERATED_META, false):
		push_error("DungeonAuthoring3D: User-owned node %s will not be modified." % node_name)
		if geometry != null:
			geometry.free()
		return
	if geometry == null and _get_generated(node_name) == null:
		return
	var before := _snapshot_node(_get_generated(node_name))
	var after := _snapshot_node(geometry)
	if geometry != null:
		geometry.free()
		if after == null:
			push_error("DungeonAuthoring3D: Failed to serialize generated geometry.")
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
		push_error("DungeonAuthoring3D: Refusing to overwrite user node %s." % node_name)
		return
	_remove_generated(node_name)
	if snapshot == null:
		return
	var generated := snapshot.instantiate() as Node3D
	if generated == null:
		push_error("DungeonAuthoring3D: Failed to instantiate geometry snapshot.")
		return
	generated.name = node_name
	add_child(generated)
	var scene_root: Node = self
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		scene_root = get_tree().edited_scene_root
	generated.owner = scene_root
	_set_descendant_owners(generated, scene_root)


static func _snapshot_node(node: Node3D) -> PackedScene:
	if node == null:
		return null
	var copy := node.duplicate() as Node3D
	_set_descendant_owners(copy, copy)
	var snapshot := PackedScene.new()
	var error := snapshot.pack(copy)
	copy.free()
	return snapshot if error == OK else null


static func _set_descendant_owners(parent: Node, target_owner: Node) -> void:
	for child in parent.get_children():
		child.owner = target_owner
		_set_descendant_owners(child, target_owner)
