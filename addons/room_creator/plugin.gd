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
var _stamp_source: String = ""
var _stamp_wall: int = -1
var _stamp_layout: LevelLayout
var _stamp_proposal: DungeonBuildResult


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
	_dungeon_dock.stamp_wall_changed.connect(_on_stamp_wall_changed)
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
	_clear_stamp_preview()
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
	_clear_stamp_preview()
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
	_clear_stamp_preview()
	update_overlays()


func _on_selection_changed(room_id: String) -> void:
	if is_instance_valid(_dungeon_dock) and _dungeon_dock.active_mode == _dungeon_dock.MODE_STAMP:
		_preview_stamp(room_id)
	update_overlays()


func _on_stamp_wall_changed(_wall: int) -> void:
	if not _stamp_source.is_empty():
		_preview_stamp(_stamp_source, true)
	update_overlays()


func _clear_stamp_preview() -> void:
	_stamp_source = ""
	_stamp_wall = -1
	_stamp_layout = null
	_stamp_proposal = null


func _preview_stamp(room_id: String, force: bool = false) -> void:
	if not is_instance_valid(_active_author) or _active_author.layout == null:
		_clear_stamp_preview()
		return
	var wall: int = _dungeon_dock.get_stamp_wall()
	if not force and _stamp_source == room_id and _stamp_wall == wall and _stamp_layout == _active_author.layout:
		return
	_stamp_source = room_id
	_stamp_wall = wall
	_stamp_layout = _active_author.layout
	_stamp_proposal = _active_author.stamp_room_candidate(room_id, wall) if not room_id.is_empty() else null
	if _stamp_proposal != null:
		_dungeon_dock.show_stamp_feedback("Valid branch position. Click to add." if _stamp_proposal.success else "Blocked: " + _stamp_proposal.report.summary())


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
	if _dungeon_dock.active_mode == _dungeon_dock.MODE_STAMP and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var cursor_room := Picker.pick_room(_active_author.layout, viewport_camera.project_ray_origin(motion.position), viewport_camera.project_ray_normal(motion.position))
		if cursor_room != _stamp_source or _stamp_layout != _active_author.layout or _stamp_wall != _dungeon_dock.get_stamp_wall():
			_preview_stamp(cursor_room)
			update_overlays()
		return AFTER_GUI_INPUT_PASS
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
	if _dungeon_dock.active_mode == _dungeon_dock.MODE_STAMP:
		_preview_stamp(selected)
	_dungeon_dock.apply_viewport_action(selected)
	update_overlays()
	return AFTER_GUI_INPUT_STOP


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_active_author) or not is_instance_valid(_viewport_camera) or not is_instance_valid(_tool_button) or not _tool_button.button_pressed:
		return
	if _active_author.layout == null:
		return
	if _dungeon_dock.active_mode == _dungeon_dock.MODE_STAMP and not _stamp_source.is_empty():
		if _stamp_layout != _active_author.layout or _stamp_wall != _dungeon_dock.get_stamp_wall():
			_preview_stamp(_stamp_source, true)
		var ghost := DungeonSocketRoomStamp.preview_pose(_active_author.layout, _stamp_source, _dungeon_dock.get_stamp_wall())
		if ghost != null:
			var points: PackedVector3Array = Picker.room_corners(_active_author.layout, ghost)
			var screen := PackedVector2Array()
			for vertex in points:
				if _viewport_camera.is_position_behind(vertex):
					screen.clear()
					break
				screen.append(_viewport_camera.unproject_position(vertex))
			if screen.size() == 4:
				var valid: bool = _stamp_proposal != null and _stamp_proposal.success
				var tint := Color(0.22, 0.85, 0.45) if valid else Color(0.95, 0.27, 0.3)
				overlay.draw_colored_polygon(screen, Color(tint.r, tint.g, tint.b, 0.16))
				for j in 4:
					overlay.draw_line(screen[j], screen[(j + 1) % 4], tint, 3.0, true)
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
