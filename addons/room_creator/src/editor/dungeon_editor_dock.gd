@tool
extends VBoxContainer
## Compact, first-class F3 spatial authoring dock. Intentional separation:
## build/config is one task; room browsing and manipulation another.
## UI commands always delegate to the canonical DungeonAuthoring3D actions
## so all validation, scene source persistence and Undo/Redo stay centralized.

signal mode_changed(mode: int)
signal selection_changed(room_id: String)

const MODE_SELECT: int = 0
const MODE_LOCK: int = 1
const MODE_UNLOCK: int = 2
const MODE_PAINT_ART: int = 3

var author: DungeonAuthoring3D
var active_mode: int = MODE_SELECT
var _tracked_layout: LevelLayout
var _tracked_id: String = ""
var _refresh_timer: float = 0.0
var _room_ids: Array[String] = []

var _search: LineEdit
var _room_list: ItemList
var _details: Label
var _status: Label
var _mode_picker: OptionButton
var _delta_x: SpinBox
var _delta_z: SpinBox
var _size_x: SpinBox
var _size_z: SpinBox
var _shape: OptionButton
var _rotation: OptionButton
var _room_tabs: TabContainer
var _filter: OptionButton
var _module_picker: OptionButton
var _module_profiles: Array[DungeonRoomModule] = []
var _palette_source: DungeonConfig


func _ready() -> void:
	name = "RoomCreatorDungeonDock"
	custom_minimum_size = Vector2(292, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	set_author(null)


func set_author(next: DungeonAuthoring3D) -> void:
	if author == next:
		_refresh()
		return
	if is_instance_valid(author):
		if author.layout_generated.is_connected(_on_layout_changed):
			author.layout_generated.disconnect(_on_layout_changed)
		if author.generation_failed.is_connected(_on_failed):
			author.generation_failed.disconnect(_on_failed)
		if author.validation_finished.is_connected(_on_validated):
			author.validation_finished.disconnect(_on_validated)
	author = next if is_instance_valid(next) else null
	_tracked_layout = null
	_tracked_id = ""
	_palette_source = null
	if author != null:
		author.layout_generated.connect(_on_layout_changed)
		author.generation_failed.connect(_on_failed)
		author.validation_finished.connect(_on_validated)
	_refresh()


func set_mode(value: int) -> void:
	active_mode = clampi(value, MODE_SELECT, MODE_PAINT_ART)
	if _mode_picker != null and _mode_picker.selected != active_mode:
		_mode_picker.select(active_mode)
	mode_changed.emit(active_mode)


func select_room(room_id: String) -> bool:
	if author == null or author.layout == null:
		return false
	for room in author.layout.rooms:
		if room.stable_id == room_id:
			author.selected_room_id = room_id
			_refresh()
			selection_changed.emit(room_id)
			return true
	return false


func apply_viewport_action(room_id: String) -> bool:
	if not select_room(room_id):
		return false
	match active_mode:
		MODE_LOCK:
			author._request_lock_room()
		MODE_UNLOCK:
			author._request_unlock_room()
		MODE_PAINT_ART:
			_paint_module()
	return true


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < 0.22:
		return
	_refresh_timer = 0.0
	if not is_instance_valid(author):
		if author != null:
			set_author(null)
		return
	if author.layout != _tracked_layout or author.selected_room_id != _tracked_id or author.config != _palette_source:
		_refresh()


func _build() -> void:
	var title := Label.new()
	title.text = "ROOM CREATOR"
	title.add_theme_font_size_override("font_size", 19)
	add_child(title)
	_note(self, "Dungeon workspace · F3 room tools")
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	_room_tabs = tabs

	var build := VBoxContainer.new()
	build.name = "Build"
	tabs.add_child(build)
	_heading(build, "Generation")
	_note(build, "Use the DungeonAuthoring3D Config in the Inspector to choose the generation preset.")
	_action(build, "Generate dungeon", "_request_generate_layout")
	_action(build, "Preview layout", "_request_preview")
	_action(build, "Validate layout", "_request_validate")
	_heading(build, "Output")
	_action(build, "Bake static geometry", "_request_bake")
	_action(build, "Export baked scene", "_request_save")
	_note(build, "Preview and bake remain transient; exported scenes contain native collision.")

	# Rooms contains browsing, palette and precision fields. A real dock can
	# be only ~300 px wide and ~450 px high, so scroll instead of clipping UI.
	var room_scroll := ScrollContainer.new()
	room_scroll.name = "Rooms"
	room_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(room_scroll)
	var rooms := VBoxContainer.new()
	rooms.custom_minimum_size.x = 268
	rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_scroll.add_child(rooms)
	_heading(rooms, "Viewport tool")
	_mode_picker = OptionButton.new()
	_mode_picker.add_item("Select room", MODE_SELECT)
	_mode_picker.add_item("Paint locks", MODE_LOCK)
	_mode_picker.add_item("Erase locks", MODE_UNLOCK)
	_mode_picker.add_item("Paint visual modules", MODE_PAINT_ART)
	_mode_picker.item_selected.connect(func(index: int) -> void: set_mode(index))
	rooms.add_child(_mode_picker)
	_note(rooms, "Enable Room Tool in the 3D toolbar. Click a room to select or paint a lock/module. Esc exits.")
	_heading(rooms, "Visual module palette")
	_module_picker = OptionButton.new()
	rooms.add_child(_module_picker)
	var paint_bar := HBoxContainer.new()
	rooms.add_child(paint_bar)
	var paint_btn := Button.new()
	paint_btn.text = "Apply to selected"
	paint_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_btn.pressed.connect(_paint_module)
	paint_bar.add_child(paint_btn)
	_note(rooms, "Palette reads Config.room_modules. None clears current room art. Only compatible visual-only modules can be painted.")
	_heading(rooms, "Find a room")
	_search = LineEdit.new()
	_search.placeholder_text = "Filter by room ID or role..."
	_search.text_changed.connect(func(_value: String) -> void: _fill_rooms())
	rooms.add_child(_search)
	_filter = OptionButton.new()
	_filter.add_item("All rooms")
	_filter.add_item("Locked only")
	_filter.add_item("Edited only")
	_filter.item_selected.connect(func(_index: int) -> void: _fill_rooms())
	rooms.add_child(_filter)
	_room_list = ItemList.new()
	_room_list.custom_minimum_size.y = 142
	_room_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_list.item_selected.connect(_on_list_select)
	rooms.add_child(_room_list)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rooms.add_child(_details)
	var lock_bar := HBoxContainer.new()
	rooms.add_child(lock_bar)
	_action(lock_bar, "Lock", "_request_lock_room", true)
	_action(lock_bar, "Unlock", "_request_unlock_room", true)
	_action(rooms, "Reroll unlocked room appearances", "_request_regenerate_unlocked")

	_heading(rooms, "Move selected room (metres)")
	var moves := HBoxContainer.new()
	rooms.add_child(moves)
	_delta_x = _spin(moves, "X", -3.0, 3.0, 0.25, 0.0)
	_delta_z = _spin(moves, "Z", -3.0, 3.0, 0.25, 0.0)
	_heading(rooms, "Footprint (0 keeps current)")
	var sizes := HBoxContainer.new()
	rooms.add_child(sizes)
	_size_x = _spin(sizes, "Width", 0.0, 128.0, 0.1, 0.0)
	_size_z = _spin(sizes, "Depth", 0.0, 128.0, 0.1, 0.0)
	var shapes := HBoxContainer.new()
	rooms.add_child(shapes)
	_shape = OptionButton.new()
	_shape.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in ["Keep shape", "Rectangle", "Cross", "L Shape", "T Shape"]:
		_shape.add_item(label)
	shapes.add_child(_shape)
	_rotation = OptionButton.new()
	_rotation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in ["Keep turn", "0°", "90°", "180°", "270°"]:
		_rotation.add_item(label)
	shapes.add_child(_rotation)
	var apply := Button.new()
	apply.text = "Apply safe override"
	apply.tooltip_text = "Rebuild only incident corridors. Reject changes with invalid collisions/sockets. Fully Undo/Redo-enabled."
	apply.pressed.connect(_apply_override)
	rooms.add_child(apply)
	_note(rooms, "If the edit cannot fit, nothing is modified. The Inspector retains advanced fields and settings.")

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a DungeonAuthoring3D scene."
	add_child(_status)


func _heading(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _note(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.64, 0.70, 0.77))
	parent.add_child(label)


func _action(parent: Node, label: String, method: StringName, compact: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		button.custom_minimum_size.x = 90
	button.pressed.connect(func() -> void:
		if is_instance_valid(author):
			author.call(method)
	)
	parent.add_child(button)
	return button


func _spin(parent: Node, label: String, minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.value = initial
	field.prefix = label + " "
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _fill_palette() -> void:
	if _module_picker == null:
		return
	_module_profiles.clear()
	_module_picker.clear()
	_module_picker.add_item("None / erase art")
	_module_profiles.append(null)
	_palette_source = author.config if author != null else null
	if author == null or author.config == null:
		return
	for module in author.config.room_modules:
		if module == null:
			continue
		if _module_profiles.has(module):
			continue
		_module_profiles.append(module)
		_module_picker.add_item(module.stable_id)
	if author.selected_visual_module != null:
		var selection_index: int = _module_profiles.find(author.selected_visual_module)
		if selection_index >= 0:
			_module_picker.select(selection_index)


func _paint_module() -> void:
	if not is_instance_valid(author):
		return
	var index: int = _module_picker.selected
	if index < 0 or index >= _module_profiles.size():
		return
	author.selected_visual_module = _module_profiles[index]
	author._request_paint_room_module()


func _fill_rooms() -> void:
	if _room_list == null:
		return
	_room_list.clear()
	_room_ids.clear()
	if author == null or author.layout == null:
		return
	var query: String = _search.text.strip_edges().to_lower()
	for room in author.layout.rooms:
		if room == null:
			continue
		if _filter.selected == 1 and not room.edit_locked:
			continue
		if _filter.selected == 2 and not room.authored_override_active:
			continue
		var role: String = RoomPlacementData.Role.keys()[int(room.role)].capitalize()
		if not query.is_empty() and not room.stable_id.to_lower().contains(query) and not role.to_lower().contains(query):
			continue
		var markers := (" [L]" if room.edit_locked else "") + (" [E]" if room.authored_override_active else "")
		_room_ids.append(room.stable_id)
		_room_list.add_item(room.stable_id + "  ·  " + role + markers)
		if room.stable_id == author.selected_room_id:
			_room_list.select(_room_ids.size() - 1)


func _refresh() -> void:
	var valid: bool = is_instance_valid(author)
	if _room_tabs == null:
		return
	_room_tabs.visible = valid
	if not valid:
		_details.text = ""
		_status.text = "Open a scene with a DungeonAuthoring3D root."
		_fill_palette()
		_tracked_layout = null
		_tracked_id = ""
		return
	_tracked_layout = author.layout
	_tracked_id = author.selected_room_id
	if author.config != _palette_source or _module_profiles.is_empty():
		_fill_palette()
	_fill_rooms()
	if author.layout == null:
		_details.text = "Generate a layout to begin."
		_status.text = "No layout yet."
		return
	var found: RoomPlacementData
	for room in author.layout.rooms:
		if room.stable_id == author.selected_room_id:
			found = room
			break
	_status.text = "%d rooms  ·  %d connections" % [author.layout.rooms.size(), author.layout.connections.size()]
	if found != null:
		var size: Vector3 = DungeonPlanner.actual_size(author.layout, found)
		_details.text = "%s · %s\n%.1f × %.1f m | %d links | %s" % [
			found.stable_id, RoomPlacementData.Role.keys()[int(found.role)],
			size.x, size.z, _count_links(found.stable_id),
			"LOCKED" if found.edit_locked else "Editable"
		]
	else:
		_details.text = "Select a room in the list or click it in the viewport."


func _count_links(room_id: String) -> int:
	var count: int = 0
	for edge in author.layout.connections:
		if edge.from_room_id == room_id or edge.to_room_id == room_id:
			count += 1
	return count


func _on_list_select(index: int) -> void:
	if index >= 0 and index < _room_ids.size():
		select_room(_room_ids[index])


func _apply_override() -> void:
	if not is_instance_valid(author):
		return
	author.manual_translation = Vector3(_delta_x.value, 0.0, _delta_z.value)
	author.manual_room_size = Vector2(_size_x.value, _size_z.value)
	author.manual_shape_choice = _shape.selected
	author.manual_shape_rotation = _rotation.selected - 1
	author._request_apply_room_override()


func _on_layout_changed(_result: DungeonBuildResult) -> void:
	_refresh()


func _on_failed(report: RoomValidationReport) -> void:
	_refresh()
	_status.text = "Edit rejected: " + report.summary()


func _on_validated(report: RoomValidationReport) -> void:
	_status.text = "Layout valid" if report.is_valid() else "Validation: " + report.summary()
