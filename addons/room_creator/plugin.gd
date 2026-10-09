@tool
extends EditorPlugin

## F3.3: context-aware spatial editing surface. The existing Inspector stays
## the advanced source-of-truth; this dock calls the same safe transactions.
const DockScript = preload("res://addons/room_creator/src/editor/dungeon_editor_dock.gd")
const Picker = preload("res://addons/room_creator/src/editor/dungeon_viewport_picker.gd")

var inspector_plugin
var _dungeon_dock: Control
var _editor_dock: EditorDock
var _tool_button: Button
var _active_author: DungeonAuthoring3D
var _viewport_camera: Camera3D
var _poll_timer: float = 0.0


func _enter_tree() -> void:
	add_custom_type(
		"RoomCreator", "Node3D",
		preload("res://addons/room_creator/src/room_creator.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	add_custom_type(
		"RoomAuthoring3D", "Node3D",
		preload("res://addons/room_creator/src/next/room_authoring_3d.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	add_custom_type(
		"DungeonAuthoring3D", "Node3D",
		preload("res://addons/room_creator/src/next/dungeon/dungeon_authoring_3d.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	add_custom_type(
		"DungeonGenerator", "Node3D",
		preload("res://addons/room_creator/src/dungeon/dungeon_generator.gd"),
		preload("res://addons/room_creator/assets/icon.svg")
	)
	inspector_plugin = preload("res://addons/room_creator/src/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	# Godot 4.7's EditorDock is draggable between bottom, side and
	# floating layouts. The old add_control_to_dock() API restricts the
	# original Room Creator panel to vertical positions.
	_editor_dock = EditorDock.new()
	_editor_dock.name = "RoomCreatorWorkspace"
	_editor_dock.title = "Room Creator"
	_editor_dock.layout_key = "room_creator_spatial_workspace_v2"
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_editor_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_editor_dock.dock_icon = preload("res://addons/room_creator/assets/icon.svg")
	_dungeon_dock = DockScript.new()
	_dungeon_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dungeon_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_dock.add_child(_dungeon_dock)
	add_dock(_editor_dock)
	_dungeon_dock.mode_changed.connect(_on_mode_changed)
	_dungeon_dock.selection_changed.connect(_on_selection_changed)
	_tool_button = Button.new()
	_tool_button.name = "RoomCreatorViewportTool"
	_tool_button.toggle_mode = true
	_tool_button.text = "Room Tool"
	_tool_button.tooltip_text = "Edit rooms in the 3D viewport: select, paint locks, or erase locks. Esc exits. Advanced properties remain in the Inspector."
	_tool_button.toggled.connect(_on_tool_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _tool_button)
	set_input_event_forwarding_always_enabled()
	call_deferred("_sync_editor_scene")


func _exit_tree() -> void:
	_active_author = null
	_viewport_camera = null
	if is_instance_valid(_tool_button):
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _tool_button)
		_tool_button.queue_free()
	if is_instance_valid(_editor_dock):
		remove_dock(_editor_dock)
		_editor_dock.queue_free()
		_editor_dock = null
	_dungeon_dock = null
	remove_custom_type("RoomAuthoring3D")
	remove_custom_type("DungeonAuthoring3D")
	remove_custom_type("DungeonGenerator")
	remove_custom_type("RoomCreator")
	remove_inspector_plugin(inspector_plugin)


func _handles(object: Object) -> bool:
	return object is DungeonAuthoring3D


func _edit(object: Object) -> void:
	if object is DungeonAuthoring3D:
		_bind_author(object as DungeonAuthoring3D)


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_tool_button):
		_tool_button.visible = visible and is_instance_valid(_active_author)


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= 0.30:
		_poll_timer = 0.0
		_sync_editor_scene()


func _sync_editor_scene() -> void:
	if not is_instance_valid(_dungeon_dock):
		return
	var root := EditorInterface.get_edited_scene_root()
	var next: DungeonAuthoring3D = root as DungeonAuthoring3D
	if next != _active_author:
		_bind_author(next)


func _bind_author(author: DungeonAuthoring3D) -> void:
	_active_author = author if is_instance_valid(author) else null
	if not is_instance_valid(_dungeon_dock):
		return
	_dungeon_dock.set_author(_active_author)
	if is_instance_valid(_tool_button):
		_tool_button.visible = _active_author != null
		if _active_author == null:
			_tool_button.set_pressed_no_signal(false)
	update_overlays()


func _on_tool_toggled(_pressed: bool) -> void:
	update_overlays()


func _on_mode_changed(_mode: int) -> void:
	update_overlays()


func _on_selection_changed(_room_id: String) -> void:
	update_overlays()


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_active_author) or not is_instance_valid(_tool_button) or not _tool_button.button_pressed:
		return AFTER_GUI_INPUT_PASS
	if _active_author.layout == null:
		return AFTER_GUI_INPUT_PASS
	_viewport_camera = viewport_camera
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_tool_button.set_pressed_no_signal(false)
		update_overlays()
		return AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseButton:
		return AFTER_GUI_INPUT_PASS
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or click.ctrl_pressed or click.alt_pressed or click.shift_pressed:
		return AFTER_GUI_INPUT_PASS
	var ray_origin: Vector3 = viewport_camera.project_ray_origin(click.position)
	var ray_direction: Vector3 = viewport_camera.project_ray_normal(click.position)
	var selected: String = Picker.pick_room(_active_author.layout, ray_origin, ray_direction)
	if selected.is_empty():
		return AFTER_GUI_INPUT_PASS
	_dungeon_dock.apply_viewport_action(selected)
	update_overlays()
	return AFTER_GUI_INPUT_STOP


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_active_author) or not is_instance_valid(_viewport_camera) or not is_instance_valid(_tool_button) or not _tool_button.button_pressed:
		return
	if _active_author.layout == null:
		return
	var room: RoomPlacementData
	for item in _active_author.layout.rooms:
		if item.stable_id == _active_author.selected_room_id:
			room = item
			break
	if room == null:
		return
	var corners: PackedVector3Array = Picker.room_corners(_active_author.layout, room)
	if corners.size() != 4:
		return
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		if _viewport_camera.is_position_behind(a) or _viewport_camera.is_position_behind(b):
			continue
		overlay.draw_line(_viewport_camera.unproject_position(a), _viewport_camera.unproject_position(b), Color(0.3, 0.85, 1.0), 3.0, true)
