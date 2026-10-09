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
## Enable to inspect every new layout immediately. Disable for very large drafts.
@export var auto_preview_on_generate: bool = true
@export var layout: LevelLayout
@export_group("Preview Diagnostics")
@export var preview_palette: DungeonPreviewPalette = DungeonPreviewPalette.new()
@export var show_room_role_colors: bool = true
@export var show_connection_routes: bool = true
@export var show_entrance_exit_labels: bool = true
@export_file("*.tscn") var output_scene_path: String = "res://room_creator/dungeons/dungeon.tscn"
@export_group("F3 Room Editing")
## Stable ID from LevelLayout.rooms, e.g. room_0003. Locks are stored on the
## LevelLayout's RoomPlacementData and survive Ctrl+S and editor reopen.
@export var selected_room_id: String = "room_0000"
@export var appearance_variation_seed: int = 20001
@export var show_locked_room_labels: bool = true
@export_tool_button("Lock Selected Room") var lock_room_action: Callable = _request_lock_room
@export_tool_button("Unlock Selected Room") var unlock_room_action: Callable = _request_unlock_room
@export_tool_button("Regenerate Unlocked Rooms") var regenerate_unlocked_action: Callable = _request_regenerate_unlocked
@export_subgroup("F3.2 Explicit Overrides")
## Translation is relative to current pose, horizontally only. Total bounded
## movement is 3 m from the pose at the first edit. 0 width/depth means keep.
@export var manual_translation: Vector3 = Vector3.ZERO
@export var manual_room_size: Vector2 = Vector2.ZERO
## Keep current, Rect, Cross, L, T; incompatible existing modules are rejected.
@export_enum("Keep", "Rectangle", "Cross", "L Shape", "T Shape") var manual_shape_choice: int = 0
@export_range(-1, 3, 1) var manual_shape_rotation: int = -1
@export_tool_button("Apply Selected Room Override") var apply_room_override_action: Callable = _request_apply_room_override
@export_subgroup("F3.3 Room Palette")
## Visual-only socket-matched art; selected in the dock or advanced Inspector.
@export var selected_visual_module: DungeonRoomModule
@export_tool_button("Paint Selected Room Module") var paint_room_module_action: Callable = _request_paint_room_module
@export_tool_button("Generate Layout") var generate_action: Callable = _request_generate_layout
@export_tool_button("Validate Layout") var validate_action: Callable = _request_validate
@export_tool_button("Preview Layout") var preview_action: Callable = _request_preview
@export_tool_button("Bake Static Dungeon") var bake_action: Callable = _request_bake
@export_tool_button("Save Baked Scene") var save_action: Callable = _request_save
@export_tool_button("Clear Preview") var clear_preview_action: Callable = _request_clear_preview
@export_tool_button("Clear Bake") var clear_bake_action: Callable = _request_clear_bake

var last_result: DungeonBuildResult
var last_report: RoomValidationReport

# Inspector tool buttons run from the editor's GUI/Inspector stack. Defer
# scene replacement until its input/notification transaction is complete to
# avoid nested editor dialogs and reentrant SceneTree mutations.
var _queued_editor_operation: StringName = &""

func _request_generate_layout() -> void:
	_queue_editor_action(&"generate_new_layout")


func _request_lock_room() -> void:
	_queue_editor_action(&"lock_selected_room")


func _request_unlock_room() -> void:
	_queue_editor_action(&"unlock_selected_room")


func _request_regenerate_unlocked() -> void:
	_queue_editor_action(&"regenerate_unlocked_rooms")


func _request_apply_room_override() -> void:
	_queue_editor_action(&"apply_selected_room_override")


func _request_paint_room_module() -> void:
	_queue_editor_action(&"paint_selected_room_module")


func _request_validate() -> void:
	_queue_editor_action(&"validate_current_layout")


func _request_preview() -> void:
	_queue_editor_action(&"preview_layout")


func _request_bake() -> void:
	_queue_editor_action(&"bake")


func _request_save() -> void:
	_queue_editor_action(&"save_scene")


func _request_clear_preview() -> void:
	_queue_editor_action(&"clear_preview")


func _request_clear_bake() -> void:
	_queue_editor_action(&"clear_bake")


func _queue_editor_action(method: StringName) -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		# Coalesce overlapping inspector actions while a build is queued.
		if _queued_editor_operation != &"":
			return
		_queued_editor_operation = method
		call_deferred("_run_queued_editor_action")
	else:
		call(method)


func _run_queued_editor_action() -> void:
	var method: StringName = _queued_editor_operation
	_queued_editor_operation = &""
	if not is_inside_tree() or method == &"":
		return
	call(method)

func generate_layout(source: DungeonConfig) -> DungeonBuildResult:
	return DungeonPlanner.generate_layout(source)


func generate_new_layout() -> void:
	if DungeonRoomEditing.any_locked(layout):
		var blocked := DungeonBuildResult.new()
		blocked.report.add_error("ROOM_LOCK_CONFLICT", "Full topology regeneration would discard locked designer rooms. Unlock them or use Regenerate Unlocked Rooms, which preserves all room/socket identities.")
		last_result = blocked
		last_report = blocked.report
		generation_failed.emit(blocked.report)
		push_warning("DungeonAuthoring3D: " + blocked.report.summary())
		return
	var result := generate_layout(config)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return
	# Compile before touching the currently valid layout, preview or bake.
	# An unsuccessful generation never deletes the designer's previous work.
	if not _can_replace_generated(PREVIEW_NAME) or not _can_replace_generated(BAKE_NAME):
		result.success = false
		result.report.add_error("GENERATED_NAME_OCCUPIED", "A user-owned node occupies DungeonPreview or DungeonBake.")
		generation_failed.emit(result.report)
		return
	var preview_snapshot: PackedScene = null
	if auto_preview_on_generate:
		var geometry := _build_diagnostic_preview(result.layout)
		if geometry == null:
			result.success = false
			result.report.add_error("PREVIEW_COMPILE", "Unable to compile the generated layout.")
			generation_failed.emit(result.report)
			return
		preview_snapshot = _snapshot_node(geometry)
		geometry.free()
		if preview_snapshot == null:
			result.success = false
			result.report.add_error("PREVIEW_PACK", "Unable to serialize the new preview.")
			generation_failed.emit(result.report)
			return
	var old_preview := _snapshot_node(_get_generated(PREVIEW_NAME))
	var old_bake := _snapshot_node(_get_generated(BAKE_NAME))
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		var history := EditorInterface.get_editor_undo_redo()
		history.create_action("Generate Dungeon Layout and Preview", UndoRedo.MERGE_DISABLE, self)
		history.add_do_method(self, "_apply_generation", result.layout, preview_snapshot, null)
		history.add_undo_method(self, "_apply_generation", layout, old_preview, old_bake)
		history.commit_action()
	else:
		_apply_generation(result.layout, preview_snapshot, null)
	layout_generated.emit(result)


## F3 authoring: lock state is a resource-level edit, not a change to
## physical geometry. The existing bake remains valid and no scene children
## are serialized into the user-authored source.
func lock_selected_room() -> bool:
	return _edit_lock(true)


func unlock_selected_room() -> bool:
	return _edit_lock(false)


func _edit_lock(locked: bool) -> bool:
	var result := DungeonRoomEditing.toggle_lock(layout, selected_room_id, locked)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return false
	return _commit_room_edit(result, "Lock Dungeon Room" if locked else "Unlock Dungeon Room", true)


func regenerate_unlocked_rooms() -> bool:
	var result := DungeonRoomEditing.regenerate_unlocked(layout, config, appearance_variation_seed)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return false
	return _commit_room_edit(result, "Regenerate Unlocked Dungeon Rooms", false)


func apply_selected_room_override() -> bool:
	var chosen_shape: int = manual_shape_choice - 1 if manual_shape_choice > 0 else -1
	var result := DungeonRoomOverrides.apply(layout, selected_room_id, manual_translation, manual_room_size, chosen_shape, manual_shape_rotation)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return false
	# The override can move a doorway: always clear stale baked connectors.
	return _commit_room_edit(result, "Apply Selected Dungeon Room Override", false)


func paint_selected_room_module() -> bool:
	var result := DungeonRoomModulePainter.paint(layout, selected_room_id, selected_visual_module)
	last_result = result
	last_report = result.report
	if not result.success:
		generation_failed.emit(result.report)
		push_warning("DungeonAuthoring3D: " + result.report.summary())
		return false
	return _commit_room_edit(result, "Paint Dungeon Room Visual Module", false)


func _commit_room_edit(result: DungeonBuildResult, label: String, keep_bake: bool) -> bool:
	if not _can_replace_generated(PREVIEW_NAME) or not _can_replace_generated(BAKE_NAME):
		result.report.add_error("GENERATED_NAME_OCCUPIED", "Cannot modify user-owned preview or bake nodes.")
		generation_failed.emit(result.report)
		return false
	var old_preview := _snapshot_node(_get_generated(PREVIEW_NAME))
	var old_bake := _snapshot_node(_get_generated(BAKE_NAME))
	var next_preview: PackedScene = null
	if not keep_bake or old_bake == null and (auto_preview_on_generate or old_preview != null):
		var preview := _build_diagnostic_preview(result.layout)
		if preview == null:
			result.report.add_error("F3_PREVIEW", "Cannot compile local room edit. Original layout retained.")
			generation_failed.emit(result.report)
			return false
		next_preview = _snapshot_node(preview)
		preview.free()
		if next_preview == null:
			result.report.add_error("F3_PREVIEW_PACK", "Cannot snapshot room edit preview.")
			generation_failed.emit(result.report)
			return false
	# Lock/unlock never changes layout.fingerprint(); it only changes source
	# room metadata. Rerolls must clear an old baked mesh fingerprint.
	var retained_bake: PackedScene = old_bake if keep_bake else null
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		var history := EditorInterface.get_editor_undo_redo()
		history.create_action(label, UndoRedo.MERGE_DISABLE, self)
		history.add_do_method(self, "_apply_generation", result.layout, next_preview, retained_bake)
		history.add_undo_method(self, "_apply_generation", layout, old_preview, old_bake)
		history.commit_action()
	else:
		_apply_generation(result.layout, next_preview, retained_bake)
	layout_generated.emit(result)
	return true


func _can_replace_generated(node_name: String) -> bool:
	var existing := get_node_or_null(NodePath(node_name))
	return existing == null or existing.get_meta(GENERATED_META, false)


func _apply_generation(new_layout: LevelLayout, preview_snapshot: PackedScene, baked_snapshot: PackedScene) -> void:
	layout = new_layout
	_apply_snapshot(PREVIEW_NAME, preview_snapshot)
	_apply_snapshot(BAKE_NAME, baked_snapshot)


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


func _build_diagnostic_preview(source: LevelLayout) -> Node3D:
	var geometry := DungeonSceneCompiler.build(source, false)
	if geometry != null and (show_room_role_colors or show_connection_routes or show_entrance_exit_labels):
		DungeonPreviewOverlay.apply(
			geometry, source, preview_palette,
			show_room_role_colors, show_connection_routes, show_entrance_exit_labels
		)
	if geometry != null and show_locked_room_labels:
		DungeonRoomEditing.decorate_preview(geometry, source)
	return geometry


func preview_layout() -> void:
	if not validate_current_layout().is_valid():
		return
	_commit_generated_action(PREVIEW_NAME, _build_diagnostic_preview(layout), "Preview Dungeon")


func bake() -> void:
	if not validate_current_layout().is_valid():
		return
	if not _can_replace_generated(PREVIEW_NAME) or not _can_replace_generated(BAKE_NAME):
		push_error("DungeonAuthoring3D: Cannot overwrite user-owned preview/bake nodes.")
		return
	var geometry := DungeonSceneCompiler.build(layout, true)
	if geometry == null:
		push_error("DungeonAuthoring3D: Failed to compile the static dungeon.")
		return
	var baked_snapshot := _snapshot_node(geometry)
	geometry.free()
	if baked_snapshot == null:
		push_error("DungeonAuthoring3D: Failed to serialize baked geometry.")
		return
	var old_preview := _snapshot_node(_get_generated(PREVIEW_NAME))
	var old_bake := _snapshot_node(_get_generated(BAKE_NAME))
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		var history := EditorInterface.get_editor_undo_redo()
		history.create_action("Bake Dungeon and Hide Preview", UndoRedo.MERGE_DISABLE, self)
		history.add_do_method(self, "_apply_bake_state", baked_snapshot, null)
		history.add_undo_method(self, "_apply_bake_state", old_bake, old_preview)
		history.commit_action()
	else:
		_apply_bake_state(baked_snapshot, null)
	bake_finished.emit(_get_generated(BAKE_NAME))


func _apply_bake_state(baked_snapshot: PackedScene, preview_snapshot: PackedScene) -> void:
	_apply_snapshot(BAKE_NAME, baked_snapshot)
	_apply_snapshot(PREVIEW_NAME, preview_snapshot)


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
	# The authoring node is the only saved source of truth. Generated preview
	# and baked geometry are transient editor/runtime children, never owned
	# by the edited scene root. This prevents saving thousands of derived nodes
	# into the authoring .tscn after an ordinary Ctrl+S.
	# Save Baked Scene explicitly packs an independent native-engine scene.
	generated.owner = null


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
		# Generated snapshots own fully independent, script-free native nodes.
		# Never both reference a foreign PackedScene and override ownership
		# of all of its internal nodes: the editor may restore them twice.
		if not child.scene_file_path.is_empty():
			child.scene_file_path = ""
		child.owner = target_owner
		_set_descendant_owners(child, target_owner)
