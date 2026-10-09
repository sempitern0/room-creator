extends SceneTree
## Semantic editor preview regression: roles, alternative graph cycles,
## configurable palette, preview-only geometry, bake isolation and determinism.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DungeonConfig.new()
	config.seed = 822
	config.grid_size = Vector2i(12, 12)
	config.critical_path_min = 8
	config.critical_path_max = 8
	config.branch_count = 8
	config.loop_count = 1
	config.max_attempts = 32
	config.rectangle_weight = 3
	config.cross_weight = 8
	config.l_shape_weight = 7
	config.t_shape_weight = 7
	var author := DungeonAuthoring3D.new()
	author.config = config
	author.generate_new_layout()
	var layout := author.layout
	if not _check(layout != null, "The deterministic sample must generate."):
		return
	var preview := author.get_node_or_null("DungeonPreview") as Node3D
	if not _check(preview != null, "Generating a layout must build a diagnostic preview."):
		return
	var layer := preview.get_node_or_null("PreviewRoutes")
	if not _check(layer != null, "Preview must include a diagnostic overlay."):
		return
	var routes := layer.find_children("Route_*", "MeshInstance3D", true, false)
	var kinds: Dictionary = {}
	for route in routes:
		var kind: String = route.get_meta("path_kind", "")
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	if not _check(routes.size() == layout.connections.size(), "Every connection needs a visible route segment."):
		return
	if not _check(int(kinds.get("critical", 0)) == layout.critical_path_ids.size() - 1, "Critical route edges must be cyan."):
		return
	if not _check(int(kinds.get("branch", 0)) == layout.rooms.size() - layout.critical_path_ids.size(), "Branch edges must be amber."):
		return
	if not _check(int(kinds.get("loop", 0)) == layout.expected_loops, "Alternative loop edges must be purple."):
		return
	if not _check(layer.get_node_or_null("RoleLabel_Entrance") != null and layer.get_node_or_null("RoleLabel_Exit") != null, "Entrance/exit labels must both be visible."):
		return
	var entrance := preview.get_node_or_null(NodePath(layout.entrance_id))
	var exit_room := preview.get_node_or_null(NodePath(layout.exit_id))
	var entrance_floor := _floor(entrance)
	var exit_floor := _floor(exit_room)
	if not _check(entrance_floor != null and exit_floor != null, "Floor meshes must be available for role styling."):
		return
	if not _check(entrance_floor.material_override is StandardMaterial3D and exit_floor.material_override is StandardMaterial3D, "Role tint must use preview-only material overrides."):
		return
	if not _check((entrance_floor.material_override as StandardMaterial3D).albedo_color == author.preview_palette.entrance, "Entrance floor must use the configured green."):
		return
	if not _check((exit_floor.material_override as StandardMaterial3D).albedo_color == author.preview_palette.exit, "Exit floor must use the configured red."):
		return
	# Palette changes are reflected by explicit Preview Layout refresh.
	author.preview_palette.entrance = Color(0.1, 0.75, 0.3)
	author.show_entrance_exit_labels = false
	author.preview_layout()
	preview = author.get_node_or_null("DungeonPreview") as Node3D
	layer = preview.get_node_or_null("PreviewRoutes")
	if not _check(layer.get_node_or_null("RoleLabel_Entrance") == null, "Labels may be disabled independently."):
		return
	entrance_floor = _floor(preview.get_node_or_null(NodePath(layout.entrance_id)))
	if not _check((entrance_floor.material_override as StandardMaterial3D).albedo_color == author.preview_palette.entrance, "Refreshed preview must use the edited palette."):
		return
	author.show_connection_routes = false
	author.show_room_role_colors = false
	author.preview_layout()
	preview = author.get_node_or_null("DungeonPreview") as Node3D
	layer = preview.get_node_or_null("PreviewRoutes")
	if not _check(layer == null or layer.find_children("Route_*", "MeshInstance3D", true, false).is_empty(), "Routes can be independently hidden."):
		return
	entrance_floor = _floor(preview.get_node_or_null(NodePath(layout.entrance_id)))
	if not _check(entrance_floor.material_override == null, "Disabling tint must keep natural source materials."):
		return
	author.show_room_role_colors = true
	author.show_connection_routes = true
	author.show_entrance_exit_labels = true
	author.bake()
	if not _check(author.get_node_or_null("DungeonPreview") == null, "Baking hides the preview."):
		return
	var baked := author.get_node_or_null("DungeonBake") as Node3D
	if not _check(baked != null and baked.get_node_or_null("PreviewRoutes") == null, "Baked output may not contain diagnostic graphics."):
		return
	entrance_floor = _floor(baked.get_node_or_null(NodePath(layout.entrance_id)))
	if not _check(entrance_floor != null and entrance_floor.material_override == null, "Baked room materials must not be tinted."):
		return
	var previous_bake := baked
	author.preview_layout()
	if not _check(author.get_node_or_null("DungeonBake") == previous_bake, "Preview refresh must not touch an existing bake."):
		return
	config.seed = 824
	author.generate_new_layout()
	if not _check(author.get_node_or_null("DungeonBake") == null and author.get_node_or_null("DungeonPreview") != null, "New generation removes stale bake and immediately creates the new diagnostic preview."):
		return
	author.free()
	print("DUNGEON_DIAGNOSTICS_SMOKE: PASS (role colors, branch/loop edges, toggle behavior, bake isolation)")
	quit(0)


func _floor(room: Node) -> MeshInstance3D:
	if room == null:
		return null
	for child in room.get_children():
		if child is MeshInstance3D and (child.name == "Floor" or child.name.begins_with("Floor_")):
			return child as MeshInstance3D
	return null


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_DIAGNOSTICS_SMOKE: FAIL: " + message)
		quit(1)
	return ok
