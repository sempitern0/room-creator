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
	if not _check(_count_nodes(preview, "ModuleDecor") == author.layout.rooms.size(), "Preview must hold exactly one visual module per room."):
		return
	author._request_preview()
	await get_tree().process_frame
	await get_tree().process_frame
	preview = author.get_node_or_null("DungeonPreview")
	if not _check(preview != null and _count_nodes(preview, "ModuleDecor") == author.layout.rooms.size(), "Refresh must not duplicate nested visual modules."):
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
	if not _check(_count_nodes(reopened.get_node_or_null("DungeonPreview"), "ModuleDecor") == author.layout.rooms.size(), "Reload should not create duplicate prefab children."):
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
	print("DUNGEON_EDITOR_INTEGRATION: PASS")
	get_tree().quit(0)


func _count_nodes(root: Node, name: String) -> int:
	return root.find_children(name, "Node3D", true, false).size() if root != null else 0


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_EDITOR_INTEGRATION: FAIL: " + message)
		get_tree().quit(1)
	return ok
