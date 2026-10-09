@tool
class_name DungeonYawPairLab3D
extends Node3D
## Experimental F2.8.2 authoring laboratory: exactly TWO static rooms with
## mutually facing sockets. Not a replacement for DungeonAuthoring3D.
## Allows arbitrary scene-authored socket normals and SAT-bounded rigid docking.
## Generated children are transient; Save Pair Scene exports an independent
## native PackedScene with physics. This deliberately does not add the test pair
## to the current cardinal-connected dungeon graph.

@export var first_room_scene: PackedScene
@export var second_room_scene: PackedScene
@export var first_socket: StringName = &"SocketFront"
@export var second_socket: StringName = &"SocketBack"
@export var first_size: Vector3 = Vector3(8, 3.5, 8)
@export var second_size: Vector3 = Vector3(8, 3.5, 8)
@export_range(-180.0, 180.0, 0.5) var first_yaw_degrees: float = 27.0
@export var seed: int = 42
@export_range(0.5, 30.0, 0.25) var min_gap: float = 4.0
@export_range(0.5, 30.0, 0.25) var max_gap: float = 6.0
@export_range(1, 64, 1) var attempts: int = 12
@export_range(0.8, 5.0, 0.1) var bridge_width: float = 1.6
@export_file("*.tscn") var export_path: String = "res://room_creator/dungeons/yaw_pair.tscn"

@export_tool_button("Preview Socket Pair") var preview_button: Callable = _request_preview
@export_tool_button("Bake Physical Pair") var bake_button: Callable = _request_bake
@export_tool_button("Save Physical Pair") var save_button: Callable = _request_save
@export_tool_button("Clear Pair") var clear_button: Callable = _request_clear

const GENERATED_NAME: String = "YawPairGenerated"
var last_error: String = ""
var _queued: StringName = &""

func _request_preview() -> void:
	_schedule(&"preview_pair")


func _request_bake() -> void:
	_schedule(&"bake_pair")


func _request_save() -> void:
	_schedule(&"save_pair")


func _request_clear() -> void:
	_schedule(&"clear_pair")


func _schedule(method: StringName) -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		if _queued != &"":
			return
		_queued = method
		call_deferred("_deferred_action")
	else:
		call(method)


func _deferred_action() -> void:
	var method := _queued
	_queued = &""
	if is_inside_tree() and method != &"":
		call(method)


func preview_pair() -> bool:
	return _generate(false)


func bake_pair() -> bool:
	return _generate(true)


func _generate(with_collisions: bool) -> bool:
	last_error = ""
	var old := get_node_or_null(NodePath(GENERATED_NAME))
	if old != null and not old.get_meta("room_creator_generated", false):
		last_error = "A user-owned node occupies the YawPairGenerated name."
		return false
	var first: Node3D = _make_room(first_room_scene, first_socket, RoomOpening.Wall.FRONT, first_size, with_collisions)
	var second: Node3D = _make_room(second_room_scene, second_socket, RoomOpening.Wall.BACK, second_size, with_collisions)
	if first == null or second == null:
		if first != null:
			first.free()
		if second != null:
			second.free()
		last_error = "Both rooms need a Node3D scene with direct Marker3D sockets or the built-in default room."
		return false
	var a_socket := first.get_node_or_null(NodePath(first_socket)) as Marker3D
	var b_socket := second.get_node_or_null(NodePath(second_socket)) as Marker3D
	if a_socket == null or b_socket == null:
		first.free()
		second.free()
		last_error = "Missing direct socket marker."
		return false
	var pose := Transform3D(Basis(Vector3.UP, deg_to_rad(first_yaw_degrees)), Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var obstacles: Array[Dictionary] = []
	var solution := DungeonYawDockingSolver.solve(pose, first_size, a_socket.transform, second_size, b_socket.transform, obstacles, min_gap, max_gap, attempts, rng, bridge_width)
	if not solution.get("success", false):
		first.free()
		second.free()
		last_error = "No collision-free rigid socket placement: %s" % solution.get("reason", "UNKNOWN")
		return false
	var start: Transform3D = solution["start"]
	var finish: Transform3D = solution["finish"]
	var bridge := DungeonYawSocketBridge.build(start, finish, bridge_width, minf(first_size.y, second_size.y), 0.2, 0.2, 1, with_collisions)
	if bridge == null:
		first.free()
		second.free()
		last_error = "Socket normals are not coaxial or a bridge could not be compiled."
		return false
	var container := Node3D.new()
	container.name = GENERATED_NAME
	container.set_meta("room_creator_generated", true)
	container.set_meta("seed", seed)
	container.set_meta("first_yaw", first_yaw_degrees)
	first.name = "DockedFirst"
	first.transform = pose
	container.add_child(first)
	second.name = "DockedSecond"
	second.transform = solution["transform"]
	container.add_child(second)
	container.add_child(bridge)
	if old != null:
		remove_child(old)
		old.free()
	add_child(container)
	return true


func _make_room(scene: PackedScene, socket_name: StringName, default_wall: int, size: Vector3, collisions: bool) -> Node3D:
	if scene != null:
		var inst := scene.instantiate() as Node3D
		if inst == null:
			return null
		inst.scene_file_path = ""
		if not collisions:
			_remove_collisions(inst)
		return inst
	var bp := RoomBlueprint.new()
	bp.room_size = size
	var opening := RoomOpening.new()
	opening.stable_id = str(socket_name).trim_prefix("Socket")
	opening.wall = default_wall
	opening.width = bridge_width
	opening.height = minf(size.y - 0.2, 2.3)
	bp.openings.append(opening)
	var built := RoomGeometryBuilder.build(bp, collisions)
	if built != null:
		var marker := built.get_node_or_null(NodePath("Socket_" + opening.stable_id)) as Marker3D
		if marker != null:
			marker.name = socket_name
	return built


func _remove_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			node.remove_child(child)
			child.free()
		else:
			_remove_collisions(child)


func clear_pair() -> void:
	var node := get_node_or_null(NodePath(GENERATED_NAME))
	if node != null and node.get_meta("room_creator_generated", false):
		remove_child(node)
		node.free()


func save_pair() -> Error:
	var pair := get_node_or_null(NodePath(GENERATED_NAME)) as Node3D
	if pair == null or not pair.get_meta("room_creator_generated", false):
		last_error = "Bake Physical Pair before saving."
		return ERR_INVALID_DATA
	if pair.find_children("*", "CollisionShape3D", true, false).is_empty():
		last_error = "The preview is collision-free. Bake Physical Pair first."
		return ERR_INVALID_DATA
	var target := pair.duplicate()
	target.name = "BakedYawSocketPair"
	_assign_owner(target, target)
	var packed := PackedScene.new()
	var err := packed.pack(target)
	if err == OK:
		err = ResourceSaver.save(packed, export_path)
	target.free()
	if err != OK:
		last_error = "Unable to export physical socket pair (error %d)." % err
	return err


static func _assign_owner(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owner(child, owner)
