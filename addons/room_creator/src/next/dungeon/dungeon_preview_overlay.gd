@tool
class_name DungeonPreviewOverlay
extends RefCounted
## Add semantic editor visualization to an already compiled preview only.
## A room's role and the actual graph edges decide the colors.
## The classifier uses a main-path spanning forest to identify extra loop edges.

const META_KEY := "room_creator_preview_overlay"
const ROUTES_NAME := "PreviewRoutes"
const K_MAIN := "critical"
const K_BRANCH := "branch"
const K_LOOP := "loop"

static func apply(preview: Node3D, layout: LevelLayout, palette: DungeonPreviewPalette, color_floors: bool = true, draw_routes: bool = true, draw_labels: bool = true) -> void:
	if preview == null or layout == null:
		return
	var colors: DungeonPreviewPalette = palette if palette != null else DungeonPreviewPalette.new()
	var old := preview.get_node_or_null(ROUTES_NAME)
	if old != null and old.get_meta(META_KEY, false):
		preview.remove_child(old)
		old.free()
	var room_by_id: Dictionary = {}
	for room in layout.rooms:
		room_by_id[room.stable_id] = room
		if color_floors:
			var node := preview.get_node_or_null(NodePath(room.stable_id))
			if node != null:
				_color_surface_meshes(node, _role_color(room.role, colors))
	var group := Node3D.new()
	group.name = ROUTES_NAME
	group.set_meta(META_KEY, true)
	preview.add_child(group)
	if draw_routes:
		var types: Dictionary = classify_edges(layout)
		for edge in layout.connections:
			if not room_by_id.has(edge.from_room_id) or not room_by_id.has(edge.to_room_id):
				continue
			var kind: String = types.get(edge.stable_id, K_BRANCH)
			var color: Color = colors.critical_path
			if kind == K_BRANCH:
				color = colors.branches
			elif kind == K_LOOP:
				color = colors.alternate_loops
			var from_room: RoomPlacementData = room_by_id[edge.from_room_id]
			var to_room: RoomPlacementData = room_by_id[edge.to_room_id]
			var top: float = layout.room_size.y + (layout.ceiling_thickness if layout.include_ceiling else 0.0)
			if edge.route_points.size() == 4:
				var track := PackedVector3Array([from_room.world_transform.origin])
				track.append_array(edge.route_points)
				track.append(to_room.world_transform.origin)
				var drawn: int = 0
				for i in range(track.size() - 1):
					if track[i].distance_to(track[i + 1]) <= 0.01:
						continue
					_add_route(group, edge.stable_id if drawn == 0 else "Part_%s_%d" % [edge.stable_id, drawn],
						track[i], track[i + 1], top, colors.route_width, color, kind)
					drawn += 1
			else:
				_add_route(group, edge.stable_id, from_room.world_transform.origin, to_room.world_transform.origin, top, colors.route_width, color, kind)
	if draw_labels:
		for room in layout.rooms:
			if room.role == RoomPlacementData.Role.ENTRANCE or room.role == RoomPlacementData.Role.EXIT:
				_add_label(group, room, layout, colors)


static func classify_edges(layout: LevelLayout) -> Dictionary:
	var kinds: Dictionary = {}
	if layout == null:
		return kinds
	var parent: Dictionary = {}
	for room in layout.rooms:
		parent[room.stable_id] = room.stable_id
	var main_pairs: Dictionary = {}
	for i in range(layout.critical_path_ids.size() - 1):
		main_pairs[_pair(layout.critical_path_ids[i], layout.critical_path_ids[i + 1])] = true
	# Prioritize the main route. An added edge that closes a cycle is
	# an alternative route even when its endpoints are branch rooms.
	for edge in layout.connections:
		if main_pairs.has(_pair(edge.from_room_id, edge.to_room_id)):
			kinds[edge.stable_id] = K_MAIN
			_union(parent, edge.from_room_id, edge.to_room_id)
	for edge in layout.connections:
		if kinds.has(edge.stable_id):
			continue
		if _find(parent, edge.from_room_id) == _find(parent, edge.to_room_id):
			kinds[edge.stable_id] = K_LOOP
		else:
			kinds[edge.stable_id] = K_BRANCH
			_union(parent, edge.from_room_id, edge.to_room_id)
	return kinds


static func _pair(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _find(parent: Dictionary, room_id: String) -> String:
	if not parent.has(room_id):
		return room_id
	var candidate: String = parent[room_id]
	while parent.has(candidate) and candidate != parent[candidate]:
		candidate = parent[candidate]
	return candidate


static func _union(parent: Dictionary, a: String, b: String) -> void:
	var pa: String = _find(parent, a)
	var pb: String = _find(parent, b)
	if pa != pb:
		parent[pb] = pa


static func _role_color(role: RoomPlacementData.Role, colors: DungeonPreviewPalette) -> Color:
	match role:
		RoomPlacementData.Role.ENTRANCE:
			return colors.entrance
		RoomPlacementData.Role.EXIT:
			return colors.exit
		RoomPlacementData.Role.BRANCH:
			return colors.branches
	return colors.critical_path


static func _color_surface_meshes(room_node: Node, color: Color) -> void:
	var material := _unshaded(color)
	for child in room_node.get_children():
		if child is MeshInstance3D and (child.name == "Floor" or child.name.begins_with("Floor_") or child.name == "Ceiling" or child.name.begins_with("Ceiling_")):
			(child as MeshInstance3D).material_override = material


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


static func _add_route(parent_node: Node3D, edge_id: String, a: Vector3, b: Vector3, ceiling_top: float, width: float, color: Color, kind: String) -> void:
	var distance: float = a.distance_to(b)
	if distance <= 0.01:
		return
	var delta: Vector3 = (b - a).normalized()
	var visual := MeshInstance3D.new()
	visual.name = "Route_" + edge_id.validate_node_name()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(width, 0.05), 0.025, distance)
	visual.mesh = box
	visual.material_override = _unshaded(color)
	visual.transform = Transform3D(Basis.looking_at(delta, Vector3.UP), (a + b) * 0.5 + Vector3.UP * (ceiling_top + 0.15))
	visual.set_meta("connection_id", edge_id)
	visual.set_meta("path_kind", kind)
	parent_node.add_child(visual)


static func _add_label(parent_node: Node3D, room: RoomPlacementData, layout: LevelLayout, palette: DungeonPreviewPalette) -> void:
	var marker := Label3D.new()
	var is_entry: bool = room.role == RoomPlacementData.Role.ENTRANCE
	marker.name = "RoleLabel_Entrance" if is_entry else "RoleLabel_Exit"
	marker.text = "ENTRANCE" if is_entry else "EXIT"
	marker.font_size = 56
	marker.pixel_size = 0.008
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.modulate = palette.entrance if is_entry else palette.exit
	var anchor: Vector3 = room.world_transform.origin
	if room.exterior_wall >= 0:
		var half_size: Vector3 = DungeonPlanner.actual_size(layout, room) * 0.5
		match room.exterior_wall:
			RoomOpening.Wall.FRONT:
				anchor.z -= half_size.z
			RoomOpening.Wall.BACK:
				anchor.z += half_size.z
			RoomOpening.Wall.LEFT:
				anchor.x -= half_size.x
			RoomOpening.Wall.RIGHT:
				anchor.x += half_size.x
	var top: float = layout.room_size.y + (layout.ceiling_thickness if layout.include_ceiling else 0.0)
	marker.position = anchor + Vector3.UP * (top + 0.7)
	marker.set_meta("room_id", room.stable_id)
	parent_node.add_child(marker)
