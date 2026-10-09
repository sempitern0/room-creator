@tool
extends EditorPlugin
## Loaded ONLY by CI in a temporary project.godot edit. Exercises actual
## EditorInterface + EditorUndoRedoManager, unlike standalone SceneTree tests.

func _enter_tree() -> void:
	call_deferred("_exercise")


func _exercise() -> void:
	EditorInterface.open_scene_from_path("res://examples/dungeon_authoring.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var author := EditorInterface.get_edited_scene_root() as DungeonAuthoring3D
	if not _check(author != null, "Failed to open modular authoring as an edited scene."):
		return
	if not _check(author.get_node_or_null("DungeonPreview") == null, "Example should open without a stale persisted preview."):
		return
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	var preview := author.get_node_or_null("DungeonPreview")
	if not _check(author.layout != null and preview != null, "Deferred inspector Generate Layout should display a preview."):
		return
	if not _check(_count_nodes(preview, "ModuleDecor") == _expected_modules(author.layout), "Preview must hold exactly one visual module per room."):
		return
	author._request_preview()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and _count_nodes(preview, "ModuleDecor") == _expected_modules(author.layout), "Refresh must not duplicate nested visual modules."):
		return
	# F3.3: real main-addon UI dock, not an isolated Control fixture.
	# The project editor loads the production Room Creator plugin alongside
	# this integration harness; the dock must be present and attached to
	# the currently edited source root.
	var room_dock := EditorInterface.get_base_control().find_child("RoomCreatorDungeonDock", true, false) as Control
	if not _check(room_dock != null, "Room Creator must expose its own context-aware dungeon dock in Godot."):
		return
	for frame in 25:
		if room_dock.get("author") == author:
			break
		await get_tree().process_frame
	if not _check(room_dock.get("author") == author and room_dock.visible, "Dock must automatically attach to the canonical edited DungeonAuthoring3D."):
		return
	var dock_id: String = author.layout.rooms[1].stable_id
	if not _check(room_dock.call("select_room", dock_id) and author.selected_room_id == dock_id, "Selecting the dock's room list must target the authoring source stable ID."):
		return
	room_dock.call("set_mode", 1)
	if not _check(room_dock.call("apply_viewport_action", dock_id), "Viewport lock-paint action should accept a visible room."):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout.rooms[1].edit_locked, "Production dock must paint a room lock using existing transactional Undo/Redo."):
		return
	room_dock.call("set_mode", 2)
	room_dock.call("apply_viewport_action", dock_id)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(not author.layout.rooms[1].edit_locked, "Production dock must erase room lock without destroying the graph."):
		return
	room_dock.call("set_mode", 0)
	# F3.1 exercises the exact deferred Inspector actions and a real
	# EditorUndoRedoManager roundtrip, not just a headless logic helper.
	var protected_id := author.layout.rooms[0].stable_id
	author.selected_room_id = protected_id
	author._request_lock_room()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout.rooms[0].edit_locked and author.get_node_or_null("DungeonPreview").find_children("Locked_*", "Label3D", true, false).size() == 1, "Lock Selected Room must persist a room lock and show it from above."):
		return
	var history := EditorInterface.get_editor_undo_redo()
	# EditorUndoRedoManager has no undo()/redo() itself; for graphical CI
	# inspect its scene-specific UndoRedo resource.
	var scene_history := history.get_history_undo_redo(history.get_object_history_id(author))
	if not _check(scene_history != null, "Current authoring scene should have a persistent UndoRedo history."):
		return
	scene_history.undo()
	await get_tree().process_frame
	if not _check(not author.layout.rooms[0].edit_locked, "Editor Undo must revert the room lock."):
		return
	scene_history.redo()
	await get_tree().process_frame
	if not _check(author.layout.rooms[0].edit_locked, "Editor Redo must restore the protected room without changing the other rooms."):
		return
	var fixed_room := author.layout.rooms[0].duplicate(true) as RoomPlacementData
	var before_reroll := author.layout.fingerprint()
	author.appearance_variation_seed = 8337
	author._request_regenerate_unlocked()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout.fingerprint() != before_reroll and author.layout.rooms[0].edit_locked and author.layout.rooms[0].shape == fixed_room.shape and author.layout.rooms[0].world_transform == fixed_room.world_transform, "Local reroll must change only unlocked appearances, preserving locked-room geometry and pose."):
		return
	author._request_unlock_room()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(not author.layout.rooms[0].edit_locked and DungeonPlanner.validate_layout(author.layout).is_valid(), "Unlock Selected Room should recover a valid fully editable layout."):
		return
	var snapshot := PackedScene.new()
	if not _check(snapshot.pack(author) == OK, "Editor-generated scene tree must remain packable."):
		return
	var path := "user://room_creator_editor_integration.tscn"
	if not _check(ResourceSaver.save(snapshot, path) == OK, "Editor-generated authoring scene must save."):
		return
	var reload_scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reload_scene != null, "Editor-generated authoring scene must reopen."):
		return
	var reopened := reload_scene.instantiate()
	if not _check(reopened is DungeonAuthoring3D and reopened.layout != null and reopened.config != null, "Saved authoring scene must preserve config and layout."):
		return
	if not _check(reopened.get_node_or_null("DungeonPreview") == null and reopened.get_node_or_null("DungeonBake") == null, "Generated nodes must never be saved into an authoring scene."):
		return
	reopened.preview_layout()
	if not _check(_count_nodes(reopened.get_node_or_null("DungeonPreview"), "ModuleDecor") == _expected_modules(reopened.layout), "A reopened authoring scene must regenerate the same modules from its saved layout."):
		return
	reopened.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	author._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.get_node_or_null("DungeonPreview") == null and author.get_node_or_null("DungeonBake") != null, "Bake must hide preview and preserve valid static geometry."):
		return
	author.config.seed += 1
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.get_node_or_null("DungeonBake") == null and author.get_node_or_null("DungeonPreview") != null, "Regeneration should replace bake with a fresh modular preview."):
		return
	# F3.2: the real Inspector runs the same transactional manual override as
	# headless tests, including scene-owned UndoRedo and exact source-only save.
	var edit_config := DungeonConfig.new()
	edit_config.seed = 19850
	edit_config.grid_size = Vector2i(12, 12)
	edit_config.critical_path_min = 7
	edit_config.critical_path_max = 9
	edit_config.branch_count = 5
	edit_config.max_attempts = 24
	edit_config.use_variable_grid_spacing = true
	edit_config.min_corridor_gap = 10.0
	edit_config.max_corridor_gap = 13.0
	author.config = edit_config
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout != null and author.layout.rooms.size() >= 10, "Room Override editor fixture must generate a stable canonical dungeon."):
		return
	author.selected_room_id = author.layout.rooms[-1].stable_id
	author.manual_translation = Vector3(0.25, 0, 0.25)
	author.manual_room_size = Vector2(7.2, 7.6)
	author.manual_shape_choice = 2
	author.manual_shape_rotation = 0
	var before_override := author.layout.fingerprint()
	author._request_apply_room_override()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout.fingerprint() != before_override and author.layout.rooms[-1].authored_override_active and author.get_node_or_null("DungeonPreview").find_children("Edited_*", "Label3D", true, false).size() == 1, "Deferred Inspector room overrides should produce validated, visibly edited geometry."):
		return
	scene_history = history.get_history_undo_redo(history.get_object_history_id(author))
	scene_history.undo()
	await get_tree().process_frame
	if not _check(author.layout.fingerprint() == before_override, "Undo must recover original physical rooms and corridors."):
		return
	scene_history.redo()
	await get_tree().process_frame
	if not _check(author.layout.rooms[-1].authored_override_active and author.layout.fingerprint() != before_override, "Redo must recover the persisted designer edit and local reroute."):
		return
	var authored_snapshot := PackedScene.new()
	if not _check(authored_snapshot.pack(author) == OK and authored_snapshot.get_state().get_node_count() == 1, "Ctrl+S after manual edits must keep only the single source authoring node."):
		return
	# Exercise actual Inspector/UndoRedo transactions with collision-bearing
	# room prefabs in a real graphical editor, not just a SceneTree test.
	var profile_preset := load("res://examples/dungeon_structural_preset.tres") as DungeonConfig
	if not _check(profile_preset != null, "Structural room preset must be importable from Inspector."):
		return
	author.config = profile_preset
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	var structural_count := _count_nodes(preview, "StructuralShell")
	if not _check(preview != null and structural_count > 0, "Inspector must compile full collision-bearing room prefabs inside the existing authoring scene."):
		return
	author._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	var structural_bake := author.get_node_or_null("DungeonBake")
	if not _check(structural_bake != null and _count_nodes(structural_bake, "StructuralShell") == structural_count, "Baking must preserve exact authored prefab identities without duplicate scene instances."):
		return
	var source := PackedScene.new()
	if not _check(source.pack(author) == OK and source.get_state().get_node_count() == 1, "Ctrl+S must never serialize prefab meshes inside the authoring scene."):
		return
	# F2.8: an asymmetric full collision prefab uses the same deferred
	# Inspector generation, bake, and source-only Ctrl+S path as F2.7.
	var offset_preset := load("res://examples/dungeon_offset_socket_preset.tres") as DungeonConfig
	if not _check(offset_preset != null, "Offset-socket preset must be importable."):
		return
	var found_offset_seed := false
	for candidate in 35:
		offset_preset.seed = 27000 + candidate
		var candidate_layout := DungeonPlanner.generate_layout(offset_preset)
		if not candidate_layout.success:
			continue
		for room in candidate_layout.layout.rooms:
			if room.structural_prefab != null:
				found_offset_seed = true
				break
		if found_offset_seed:
			break
	if not _check(found_offset_seed, "The asymmetric prefab preset must have at least one accepted structural room."):
		return
	author.config = offset_preset
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and _count_nodes(preview, "StructuralShell") > 0, "Inspector must preview room shells with offset door sockets."):
		return
	author._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	structural_bake = author.get_node_or_null("DungeonBake")
	if not _check(structural_bake != null and _count_nodes(structural_bake, "StructuralShell") > 0, "Inspector must bake asymmetric authored room colliders."):
		return
	source = PackedScene.new()
	if not _check(source.pack(author) == OK and source.get_state().get_node_count() == 1, "Generated off-center prefab geometry must remain transient in authoring scenes."):
		return
	# F2 full multiroom yaw: same canonical DungeonAuthoring3D, not another
	# specialized copy. Test real Inspector actions, preview, bake and save.
	var free_preset := load("res://examples/dungeon_free_yaw_preset.tres") as DungeonConfig
	if not _check(free_preset != null and DungeonPlanner.validate_config(free_preset).is_valid(), "Full free-yaw preset must be importable in the Inspector."):
		return
	author.config = free_preset
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	if not _check(author.layout != null and author.layout.free_yaw_enabled and preview != null, "Canonical author must preview a multiroom free-yaw layout."):
		return
	var yaw_rooms: int = 0
	for room in author.layout.rooms:
		if absf(rad_to_deg(room.world_transform.basis.get_euler().y)) > 4.0:
			yaw_rooms += 1
	if not _check(yaw_rooms >= 1 and preview.find_children("Connector_*", "Node3D", true, false).size() == author.layout.connections.size(), "Free-yaw preview must visibly contain rotated rooms and all physical connectors."):
		return
	author._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	var full_bake := author.get_node_or_null("DungeonBake")
	if not _check(full_bake != null and full_bake.find_children("*", "CollisionShape3D", true, false).size() > 10, "Canonical author must bake complete collision for a multiroom rotated dungeon."):
		return
	var free_snapshot := PackedScene.new()
	if not _check(free_snapshot.pack(author) == OK and free_snapshot.get_state().get_node_count() == 1, "Ctrl+S must keep the full yaw generated scene transient too."):
		return
	# F2 full off-grid socket packing must also work through this ONE
	# canonical dungeon author scene and serialize no derived mesh nodes.
	var socket_preset := load("res://examples/dungeon_offgrid_socket_preset.tres") as DungeonConfig
	if not _check(socket_preset != null and DungeonPlanner.validate_config(socket_preset).is_valid(), "The off-grid Inspector preset must load as valid DungeonConfig."):
		return
	var found_socket_seed := false
	for n in 10:
		socket_preset.seed = 47000 + n
		if DungeonPlanner.generate_layout(socket_preset).success:
			found_socket_seed = true
			break
	if not _check(found_socket_seed, "The editor preset must produce a valid socket-packed multiroom dungeon."):
		return
	author.config = socket_preset
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and author.layout != null and author.layout.offgrid_socket_packing_enabled, "The canonical Inspector must preview a truly off-grid socket dungeon."):
		return
	author._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	var socket_bake := author.get_node_or_null("DungeonBake")
	if not _check(socket_bake != null and socket_bake.find_children("Connector_*", "Node3D", true, false).size() == author.layout.connections.size(), "The actual editor Bake action must include every off-grid connector."):
		return
	var socket_saved := PackedScene.new()
	if not _check(socket_saved.pack(author) == OK and socket_saved.get_state().get_node_count() == 1, "Off-grid generated geometry must never pollute the saved authoring scene."):
		return
	# Failed new configurations preserve the last successful F2 bake/layout.
	var prior_layout: LevelLayout = author.layout
	var broken_config := DungeonConfig.new()
	broken_config.enable_offgrid_socket_packing = true
	author.config = broken_config
	author._request_generate_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(author.layout == prior_layout and author.get_node_or_null("DungeonBake") != null, "An unsatisfiable off-grid edit must preserve the previous baked dungeon."):
		return
	# The experimental free-yaw pair is a DIFFERENT authoring lab, not a
	# duplicate general dungeon scene. Exercise its actual Inspector buttons.
	EditorInterface.open_scene_from_path("res://examples/yaw_socket_pair_lab.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var yaw_lab := EditorInterface.get_edited_scene_root() as DungeonYawPairLab3D
	if not _check(yaw_lab != null, "Experimental yaw lab must load in the real Godot editor."):
		return
	yaw_lab._request_preview()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(yaw_lab.get_node_or_null("YawPairGenerated") != null, "Yaw lab inspector must generate a docked non-cardinal pair."):
		return
	var lab_source := PackedScene.new()
	if not _check(lab_source.pack(yaw_lab) == OK and lab_source.get_state().get_node_count() == 1, "The yaw authoring lab must also save only its source node, not generated mesh geometry."):
		return
	yaw_lab._request_bake()
	await get_tree().process_frame
	await get_tree().process_frame
	var physical_pair := yaw_lab.get_node_or_null("YawPairGenerated")
	if not _check(physical_pair != null and physical_pair.find_children("*", "CollisionShape3D", true, false).size() > 5, "Yaw lab must bake real physical room and corridor collision."):
		return
	yaw_lab.export_path = "user://yaw_editor_smoke.tscn"
	if not _check(yaw_lab.save_pair() == OK, "Yaw lab must export a native PackedScene using the editor action."):
		return
	var reopen_pair := ResourceLoader.load(yaw_lab.export_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(reopen_pair != null, "Exported yaw editor scene must reload."):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(yaw_lab.export_path))
	print("DUNGEON_EDITOR_INTEGRATION: PASS")
	get_tree().quit(0)


func _expected_modules(layout: LevelLayout) -> int:
	var amount: int = 0
	for room in layout.rooms:
		if room.module_profile != null:
			amount += 1
	return amount


func _count_nodes(root: Node, name: String) -> int:
	return root.find_children(name, "Node3D", true, false).size() if root != null else 0


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_EDITOR_INTEGRATION: FAIL: " + message)
		get_tree().quit(1)
	return ok
