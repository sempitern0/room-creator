@tool
class_name DungeonYawSocketBridge
extends RefCounted
## A portable, fully static straight bridge connecting two opposed sockets
## at arbitrary yaw. Source sockets, not grid axes, define its orientation.

static func build(start: Transform3D, finish: Transform3D, clear_width: float, height: float, wall_thickness: float, floor_thickness: float, collision_layer: int = 1, with_collisions: bool = true) -> Node3D:
	var length: float = start.origin.distance_to(finish.origin)
	var front: Vector3 = start.basis * Vector3.FORWARD
	var back: Vector3 = finish.basis * Vector3.FORWARD
	if length < 0.5 or clear_width < 0.5 or height < 1.0 or wall_thickness <= 0.0 or absf(front.dot(back) + 1.0) > 0.001 or front.dot((finish.origin - start.origin).normalized()) < 0.999:
		return null
	var node := Node3D.new()
	node.name = "YawSocketBridge"
	node.transform = Transform3D(start.basis, (start.origin + finish.origin) * 0.5)
	node.set_meta("socket_gap", length)
	_add_box(node, "Floor", Vector3(0.0, -floor_thickness * 0.5, 0.0), Vector3(clear_width + 2.0 * wall_thickness, floor_thickness, length), with_collisions, collision_layer)
	_add_box(node, "Ceiling", Vector3(0.0, height + floor_thickness * 0.5, 0.0), Vector3(clear_width + 2.0 * wall_thickness, floor_thickness, length), with_collisions, collision_layer)
	for direction in [-1, 1]:
		_add_box(node, "Wall_%d" % direction, Vector3(float(direction) * (clear_width + wall_thickness) * 0.5, height * 0.5, 0.0), Vector3(wall_thickness, height, length), with_collisions, collision_layer)
	return node


static func _add_box(parent: Node3D, label: String, center: Vector3, size: Vector3, collisions: bool, layer: int) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = label
	mesh_node.position = center
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	parent.add_child(mesh_node)
	if collisions:
		var static_body := StaticBody3D.new()
		static_body.name = "StaticBody"
		static_body.collision_layer = layer
		static_body.collision_mask = layer
		mesh_node.add_child(static_body)
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		var box := BoxShape3D.new()
		box.size = size
		collider.shape = box
		static_body.add_child(collider)
