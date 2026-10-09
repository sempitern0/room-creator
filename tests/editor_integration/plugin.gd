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
