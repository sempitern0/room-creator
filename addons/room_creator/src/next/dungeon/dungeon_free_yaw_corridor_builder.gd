@tool
class_name DungeonFreeYawCorridorBuilder
extends RefCounted
## Native static angled corridor union. A polygon boolean of three swept
## rectangles + two elbow clearances yields one continuous concave floor/roof.
## ONLY true exterior perimeter edges become side-wall BoxShape3D colliders:
## no internal wall blocks a turn and no open flank leaks into empty space.

static func build(layout: LevelLayout, edge: RoomConnectionData, collisions: bool = true) -> Node3D:
	if edge.route_points.size() != 4:
		return null
	var route: PackedVector3Array = edge.route_points
	var half: float = edge.clear_width * 0.5 + layout.wall_thickness
	var polys: Array[PackedVector2Array] = []
	for i in 3:
		var delta: Vector3 = route[i + 1] - route[i]
		if delta.length() <= 0.01:
			return null
		var along := Vector2(delta.x, delta.z).normalized()
		var across := Vector2(-along.y, along.x) * half
		var start := Vector2(route[i].x, route[i].z)
		var finish := Vector2(route[i + 1].x, route[i + 1].z)
		polys.append(PackedVector2Array([start + across, finish + across, finish - across, start - across]))
	for joint in [1, 2]:
		# Corners have enough clearance for a full capsule when walking turns.
		var point := Vector2(route[joint].x, route[joint].z)
		var spread: float = half * 0.9
		polys.append(PackedVector2Array([point + Vector2(-spread, -spread), point + Vector2(spread, -spread), point + Vector2(spread, spread), point + Vector2(-spread, spread)]))
	var merged: Array[PackedVector2Array] = [polys[0]]
	for i in range(1, polys.size()):
		var next: Array[PackedVector2Array] = []
		for region in merged:
			var union := Geometry2D.merge_polygons(region, polys[i])
			if union.is_empty():
				return null
			for polygon in union:
				next.append(polygon)
		merged = next
	if merged.size() != 1:
		return null
	var outline: PackedVector2Array = merged[0]
	if outline.size() < 4:
		return null
	var container := Node3D.new()
	container.name = "Connector_" + edge.stable_id.validate_node_name()
	container.set_meta("connection_id", edge.stable_id)
	container.set_meta("route_points", edge.route_points)
	# A merged triangulated surface avoids coplanar overlaps and z-fighting.
	_add_polygon(container, "Floor", outline, 0.0, Vector3.UP, layout, collisions)
	if layout.include_ceiling:
		_add_polygon(container, "Ceiling", outline, layout.room_size.y, Vector3.DOWN, layout, collisions)
	var start := Vector2(route[0].x, route[0].z)
	var end := Vector2(route[3].x, route[3].z)
	var a_normal := Vector2(route[1].x - route[0].x, route[1].z - route[0].z).normalized()
	var b_normal := Vector2(route[2].x - route[3].x, route[2].z - route[3].z).normalized()
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var direction: Vector2 = b - a
		if direction.length() < 0.01:
			continue
		var midpoint: Vector2 = (a + b) * 0.5
		# A doorway cutout is a deliberate boundary hole at the matching
		# authored wall face. The physical room supplies either side jamb.
		var a_cap: bool = absf((midpoint - start).dot(a_normal)) < 0.015 and absf(direction.normalized().dot(a_normal)) < 0.015
		var b_cap: bool = absf((midpoint - end).dot(b_normal)) < 0.015 and absf(direction.normalized().dot(b_normal)) < 0.015
		if a_cap or b_cap:
			continue
		var yaw := atan2(-direction.x, -direction.y)
		var wall := Node3D.new()
		wall.name = "Wall_%03d" % i
		wall.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(midpoint.x, layout.room_size.y * 0.5, midpoint.y))
		container.add_child(wall)
		_add_box(wall, "WallMesh", Vector3.ZERO, Vector3(layout.wall_thickness, layout.room_size.y, direction.length()), layout.wall_material, layout.collision_layer, collisions)
	return container


static func _add_polygon(parent: Node3D, label: String, outline: PackedVector2Array, elevation: float, normal: Vector3, layout: LevelLayout, collisions: bool) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in indices:
		var p: Vector2 = outline[index]
		vertices.append(Vector3(p.x, elevation, p.y))
		normals.append(normal)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: Material = layout.floor_material if label == "Floor" else layout.ceiling_material
	if material == null:
		var default_mat := StandardMaterial3D.new()
		default_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material = default_mat
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	parent.add_child(visual)
	if collisions:
		var body := StaticBody3D.new()
		body.name = "StaticBody"
		body.collision_layer = layout.collision_layer
		body.collision_mask = layout.collision_mask
		visual.add_child(body)
		var hit := CollisionShape3D.new()
		hit.name = "Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.data = vertices
		shape.backface_collision = true
		hit.shape = shape
		body.add_child(hit)


static func _add_box(root: Node3D, label: String, point: Vector3, dimensions: Vector3, material: Material, layer: int, collisions: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.position = point
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = material
	root.add_child(mesh)
	if collisions:
		var body := StaticBody3D.new()
		body.name = "StaticBody"
		body.collision_layer = layer
		body.collision_mask = layer
		mesh.add_child(body)
		var hit := CollisionShape3D.new()
		hit.name = "Collision"
		var shape := BoxShape3D.new()
		shape.size = dimensions
		hit.shape = shape
		body.add_child(hit)
