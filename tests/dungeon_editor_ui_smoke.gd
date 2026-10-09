extends SceneTree
## Headless F3.3 UI: oriented ray picking, editor dock selection/search,
## paint lock/erase, canonical source-only operations and no physics reliance.

const Picker = preload("res://addons/room_creator/src/editor/dungeon_viewport_picker.gd")
const Dock = preload("res://addons/room_creator/src/editor/dungeon_editor_dock.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.seed = 53120
	config.grid_size = Vector2i(12, 12)
	config.critical_path_min = 7
	config.critical_path_max = 9
	config.branch_count = 3
	var res := DungeonPlanner.generate_layout(config)
	if not _check(res.success, "A canonical deterministic layout is required."):
		return
	var author := DungeonAuthoring3D.new()
	author.name = "UIFixture"
	author.config = config
	author.layout = res.layout
	root.add_child(author)
	var dock := Dock.new()
	root.add_child(dock)
	dock.set_author(author)
	var one: RoomPlacementData = author.layout.rooms[0]
	var two: RoomPlacementData = author.layout.rooms[1]
	var ray_at: Vector3 = one.world_transform.origin + Vector3.UP * 70.0
	if not _check(Picker.pick_room(author.layout, ray_at, Vector3.DOWN) == one.stable_id, "Top-down room pick must find real layout room even with zero preview physics."):
		return
	if not _check(Picker.pick_room(author.layout, ray_at, Vector3.UP).is_empty() and Picker.pick_room(author.layout, ray_at + Vector3(500, 0, 500), Vector3.DOWN).is_empty(), "Ray picking must not select behind camera or outside world geometry."):
		return
	var rotated := author.layout.duplicate(true) as LevelLayout
	rotated.rooms[0].world_transform.basis = Basis(Vector3.UP, deg_to_rad(31.0))
	if not _check(Picker.pick_room(rotated, ray_at, Vector3.DOWN) == one.stable_id, "31 degree rotated OBB should remain ray-selectable."):
		return
	if not _check(Picker.room_corners(rotated, rotated.rooms[0]).size() == 4, "3D highlight must have oriented room corners."):
		return
	if not _check(dock.select_room(two.stable_id) and author.selected_room_id == two.stable_id, "Dock list and 3D selection must update the same stable selected_room_id."):
		return
	var old := author.layout.fingerprint()
	dock.set_mode(1)
	if not _check(dock.apply_viewport_action(one.stable_id) and author.layout.rooms[0].edit_locked and author.layout.fingerprint() == old, "Lock brush must seal the exact selected graph room without changing the baked geometry fingerprint."):
		return
	dock.set_mode(2)
	if not _check(dock.apply_viewport_action(one.stable_id) and not author.layout.rooms[0].edit_locked, "Erase lock brush must recover the selected room."):
		return
	dock.set_mode(0)
	if not _check(dock.apply_viewport_action(two.stable_id) and author.selected_room_id == two.stable_id and not author.layout.rooms[1].edit_locked, "Select mode cannot mutate protected state or room geometry."):
		return
	dock._search.text = one.stable_id
	dock._fill_rooms()
	if not _check(dock._room_ids.size() == 1 and dock._room_ids[0] == one.stable_id, "Search must be filtered against the canonical stable room IDs."):
		return
	dock._search.text = ""
	dock._filter.select(1)
	dock._fill_rooms()
	if not _check(dock._room_ids.is_empty(), "Locked-only filter should be empty after erase."):
		return
	dock._filter.select(0)
	dock._fill_rooms()
	if not _check(dock._room_ids.size() == author.layout.rooms.size(), "All-room browser must list every generated room once."):
		return
	# Dock's property fields delegate to the same audited, rollback-safe
	# Inspector action rather than reimplementing geometry in UI code.
	dock._delta_x.value = 0.25
	dock._delta_z.value = 0.25
	dock._size_x.value = 7.2
	dock._size_z.value = 7.6
	dock._shape.select(2) # Cross
	dock._rotation.select(1) # 0 turns
	# Coordinates of this fixture are separated by 8 m: a cardinal
	# dogleg cannot make the turn until variable grid spacing is enabled.
	# Unsafe edits must leave current authoring untouched.
	var snapshot: LevelLayout = author.layout
	dock._apply_override()
	if not _check(author.layout == snapshot, "Failed dock override must preserve source resource and generated nodes."):
		return
	dock.queue_free()
	author.queue_free()
	await process_frame
	print("DUNGEON_EDITOR_UI_SMOKE: PASS (oriented viewport picks, stable room list, mode-based lock painting, filtering and safe edit delegation)")
	quit(0)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_EDITOR_UI_SMOKE: FAIL: " + message)
		quit(1)
	return ok
