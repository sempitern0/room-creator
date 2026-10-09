@tool
class_name DungeonRoomEditing
extends RefCounted
## F3.1: persistent room-scoped authoring locks and local appearance rerolls.
## Topology, socket geometry, route points and world poses remain unchanged.
## A stale locked room is an EXPLICIT conflict; it is never silently discarded.

static func topology_signature(layout: LevelLayout, room: RoomPlacementData) -> String:
	var parts := PackedStringArray()
	parts.append("%s:%d:%d:%d:%d" % [room.stable_id, room.cell.x, room.cell.y, room.exterior_wall, int(room.role)])
	for edge in layout.connections:
		if edge.from_room_id == room.stable_id or edge.to_room_id == room.stable_id:
			parts.append("%s:%s:%s:%d:%d:%.4f:%.4f" % [
				edge.stable_id, edge.from_room_id, edge.to_room_id,
				edge.from_wall, edge.to_wall, edge.clear_width, edge.clear_height
			])
	parts.sort()
	return "|".join(parts).md5_text()


static func validate_locks(layout: LevelLayout) -> RoomValidationReport:
	var report := RoomValidationReport.new()
	if layout == null:
		return report
	var existing: Dictionary = {}
	for room in layout.rooms:
		if room == null:
			continue
		if existing.has(room.stable_id):
			continue # Duplicate room IDs are diagnosed by DungeonPlanner.
		existing[room.stable_id] = true
		if not room.edit_locked:
			continue
		if room.lock_topology_signature.is_empty():
			report.add_error("ROOM_LOCK_UNSEALED", "Room %s is locked without a captured topology. Use Lock Room in the Inspector." % room.stable_id)
		elif room.lock_topology_signature != topology_signature(layout, room):
			report.add_error("ROOM_LOCK_CONFLICT", "Room %s no longer matches its captured cell, role or doorway graph. Unlock/relock only after resolving the change." % room.stable_id)
	return report


static func any_locked(layout: LevelLayout) -> bool:
	if layout == null:
		return false
	for room in layout.rooms:
		if room != null and room.edit_locked:
			return true
	return false


static func toggle_lock(source: LevelLayout, room_id: String, locked: bool) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	if source == null:
		result.report.add_error("LAYOUT_MISSING", "Generate a dungeon before locking rooms.")
		return result
	var target_id := room_id.strip_edges()
	if target_id.is_empty():
		result.report.add_error("ROOM_ID_REQUIRED", "Enter the stable room ID shown in LevelLayout (e.g. room_0000).")
		return result
	var copy := source.duplicate(true) as LevelLayout
	for room in copy.rooms:
		if room.stable_id != target_id:
			continue
		# Validate the edited layout, not the previous lock state: this
		# permits Unlock Room to RESOLVE a stale topology-signature conflict.
		room.edit_locked = locked
		room.lock_topology_signature = topology_signature(copy, room) if locked else ""
		result.report = DungeonPlanner.validate_layout(copy)
		if not result.report.is_valid():
			return result
		result.success = true
		result.layout = copy
		result.seed = source.seed
		return result
	result.report.add_error("ROOM_ID_UNKNOWN", "Cannot find room %s in the existing layout. No changes were applied." % target_id)
	return result


static func regenerate_unlocked(source: LevelLayout, config: DungeonConfig, variation_seed: int) -> DungeonBuildResult:
	var result := DungeonBuildResult.new()
	result.seed = variation_seed
	result.report = DungeonPlanner.validate_layout(source)
	if not result.report.is_valid():
		return result
	if config == null:
		result.report.add_error("ROOM_EDIT_CONFIG", "Assign a DungeonConfig to select room silhouette weights.")
		return result
	var config_check := DungeonPlanner.validate_config(config)
	if not config_check.is_valid():
		for problem in config_check.errors:
			result.report.add_error("ROOM_EDIT_CONFIG", problem)
		return result
	if [config.rectangle_weight, config.cross_weight, config.l_shape_weight, config.t_shape_weight].max() <= 0:
		result.report.add_error("ROOM_EDIT_SHAPES", "At least one silhouette weight must be positive.")
		return result
	var fresh := source.duplicate(true) as LevelLayout
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	var changed: int = 0
	var available: int = 0
	for room in fresh.rooms:
		if room.edit_locked or room.authored_override_active or room.structural_prefab != null:
			# Explicit authored geometry and structural shells are retained;
			# choosing another prefab or shape here
			# would also require updating authored socket offsets and rerouting.
			continue
		available += 1
		var before_shape: int = int(room.shape)
		var before_turns: int = room.shape_rotation
		var before_module: DungeonRoomModule = room.module_profile
		var needed: Array[int] = []
		for opening in DungeonPlanner.make_blueprint(fresh, room).openings:
			needed.append(int(opening.wall))
		var candidates: Array[Dictionary] = []
		var total: int = 0
		var weights := [config.rectangle_weight, config.cross_weight, config.l_shape_weight, config.t_shape_weight]
		for index in weights.size():
			var weight: int = weights[index]
			if weight <= 0:
				continue
			for turns in 4:
				var all_walls := true
				for wall in needed:
					if not RoomFootprint.supports_wall(index as RoomFootprint.Shape, turns, wall):
						all_walls = false
						break
				if not all_walls:
					continue
				room.shape = index as RoomFootprint.Shape
				room.shape_rotation = turns
				var geometry_check := RoomGeometryBuilder.validate(DungeonPlanner.make_blueprint(fresh, room))
				if not geometry_check.is_valid():
					continue
				# Profiles are picked independently of the shape if possible;
				# a required visual module cannot just be dropped.
				var module_found := false
				for module_profile in config.room_modules:
					if module_profile != null and module_profile.shape == room.shape and module_profile.supports(needed, turns):
						module_found = true
						break
				if config.require_room_modules and not module_found:
					continue
				candidates.append({"shape": index, "turns": turns, "weight": weight})
				total += weight
		room.shape = before_shape as RoomFootprint.Shape
		room.shape_rotation = before_turns
		room.module_profile = before_module
		if total == 0:
			result.report.add_error("ROOM_EDIT_NO_CANDIDATE", "No valid silhouette/socket combination for unlocked room %s. Existing layout remains unchanged." % room.stable_id)
			return result
		var options: Array[Dictionary] = []
		# Prefer a different geometry when more than one valid alternative.
		for entry in candidates:
			if candidates.size() == 1 or int(entry["shape"]) != before_shape or int(entry["turns"]) != before_turns:
				options.append(entry)
		if options.is_empty():
			options = candidates
		var weight_total: int = 0
		for entry in options:
			weight_total += int(entry["weight"])
		var ticket := rng.randi_range(0, weight_total - 1)
		for entry in options:
			ticket -= int(entry["weight"])
			if ticket < 0:
				room.shape = int(entry["shape"]) as RoomFootprint.Shape
				room.shape_rotation = int(entry["turns"])
				break
		room.module_profile = null
		var compatible: Array[DungeonRoomModule] = []
		var pool: int = 0
		for module_profile in config.room_modules:
			if module_profile != null and module_profile.shape == room.shape and module_profile.supports(needed, room.shape_rotation):
				compatible.append(module_profile)
				pool += module_profile.weight
		if pool > 0 and (config.require_room_modules or rng.randf() < config.module_chance):
			var picked: int = rng.randi_range(0, pool - 1)
			for option in compatible:
				picked -= option.weight
				if picked < 0:
					room.module_profile = option
					break
		if room.shape != before_shape or room.shape_rotation != before_turns or room.module_profile != before_module:
			changed += 1
	if available == 0:
		result.report.add_error("ROOM_EDIT_NO_UNLOCKED", "No unlocked procedural rooms to reroll. Unlock a procedural room or edit it directly.")
		return result
	result.report = DungeonPlanner.validate_layout(fresh)
	if not result.report.is_valid():
		result.report.add_error("ROOM_EDIT_ABORTED", "A candidate failed physical graph validation. Original layout is intact.")
		return result
	if changed == 0:
		result.report.add_error("ROOM_EDIT_NO_CHANGE", "No unlocked room appearance changed with the selected config and variation seed.")
		return result
	result.layout = fresh
	result.success = true
	result.attempts = 1
	result.expansions = changed
	return result


static func decorate_preview(preview: Node3D, layout: LevelLayout) -> void:
	if preview == null or layout == null:
		return
	var parent := Node3D.new()
	parent.name = "PreviewLockedRooms"
	for room in layout.rooms:
		if not room.edit_locked:
			continue
		var label := Label3D.new()
		label.name = "Locked_" + room.stable_id.validate_node_name()
		label.text = "LOCKED"
		label.font_size = 28
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.89, 0.38)
		label.position = room.world_transform.origin + Vector3.UP * (DungeonPlanner.actual_size(layout, room).y + 1.0)
		parent.add_child(label)
		label.set_meta("room_id", room.stable_id)
	for room in layout.rooms:
		if not room.authored_override_active:
			continue
		var edited_label := Label3D.new()
		edited_label.name = "Edited_" + room.stable_id.validate_node_name()
		edited_label.text = "EDITED"
		edited_label.font_size = 24
		edited_label.pixel_size = 0.008
		edited_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		edited_label.no_depth_test = true
		edited_label.modulate = Color(0.25, 0.84, 0.95)
		edited_label.position = room.world_transform.origin + Vector3.UP * (DungeonPlanner.actual_size(layout, room).y + 1.6)
		parent.add_child(edited_label)
		edited_label.set_meta("room_id", room.stable_id)
	if parent.get_child_count() > 0:
		preview.add_child(parent)
	else:
		parent.free()
