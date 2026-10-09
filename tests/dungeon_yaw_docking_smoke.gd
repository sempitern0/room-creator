extends SceneTree
## F2.8.2: SAT-OBB regression + deterministic rigid socket docking with yaw,
## real BoxShape3D bridge physics, rejected blocker and standalone export.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a: Dictionary = DungeonOrientedBounds.rectangle(Vector3.ZERO, Vector2(8, 2), Basis(Vector3.UP, deg_to_rad(37.0)))
	var b: Dictionary = DungeonOrientedBounds.rectangle(Vector3(7, 0, 0), Vector2(8, 2))
	if not _check(not DungeonOrientedBounds.overlaps(a, b), "Separated thin rotated rectangles must pass SAT even when some broad AABBs intersect."):
		return
	var c: Dictionary = DungeonOrientedBounds.rectangle(Vector3(0.5, 0, 0.4), Vector2(3, 3), Basis(Vector3.UP, deg_to_rad(19.0)))
	if not _check(DungeonOrientedBounds.overlaps(a, c) and DungeonOrientedBounds.contains_point(a, Vector3.ZERO), "Intersecting OBBs must collide; rotated center must remain within its box."):
		return
	var anchor_socket := Transform3D(Basis.IDENTITY, Vector3(0, 0, -4))
	var second_socket := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 4))
	var size := Vector3(8, 3.5, 8)
	var obstacle_list: Array[Dictionary] = []
	var random_poses: int = 0
	for i in 80:
		var yaw: float = deg_to_rad(17.0 + float(i) * 2.5)
		var anchor := Transform3D(Basis(Vector3.UP, yaw), Vector3(float(i) * 2.0, 0, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 44000 + i
		var attempt := DungeonYawDockingSolver.solve(anchor, size, anchor_socket, size, second_socket, obstacle_list, 3.5, 7.0, 12, rng)
		if not _check(attempt.get("success", false), "Every unblocked yaw-docking case must find a valid pose."):
			return
		var replay_rng := RandomNumberGenerator.new()
		replay_rng.seed = 44000 + i
		var replay := DungeonYawDockingSolver.solve(anchor, size, anchor_socket, size, second_socket, obstacle_list, 3.5, 7.0, 12, replay_rng)
		if not _check(replay.get("success", false) and (attempt["transform"] as Transform3D).is_equal_approx(replay["transform"]) and attempt["gap"] == replay["gap"], "Docking must replay byte-equivalent positions from the same seed."):
			return
		var dst: Transform3D = attempt["transform"]
		var start: Transform3D = anchor * anchor_socket
		var end: Transform3D = dst * second_socket
		if not _check(start.origin.distance_to(end.origin) >= 3.5 - 0.002 and (start.basis * Vector3.FORWARD).dot(end.basis * Vector3.FORWARD) < -0.9999, "Sockets must face one another across a real positive gap."):
			return
		if not _check(not DungeonOrientedBounds.overlaps(DungeonOrientedBounds.rectangle(anchor.origin, Vector2(8, 8), anchor.basis), DungeonOrientedBounds.rectangle(dst.origin, Vector2(8, 8), dst.basis)), "Docking must reject overlapping room OBBs."):
			return
		random_poses += 1
	if not _check(random_poses == 80, "Bounded solver must exercise all yaw fixtures."):
		return
	var yaw_root := Transform3D(Basis(Vector3.UP, deg_to_rad(27)), Vector3(12, 0, 13))
	# Non-cardinal local socket normals produce different, arbitrary yaw poses
	# without relying on 90-degree room rotations.
	var candidate_angled := Transform3D(Basis(Vector3.UP, deg_to_rad(31)) * Basis(Vector3.UP, PI), Vector3(0, 0, 4))
	var arbitrary_pose := DungeonYawDockingSolver.dock(yaw_root, anchor_socket, candidate_angled, 6.0)
	if not _check(absf(rad_to_deg(arbitrary_pose.basis.get_euler().y) - 27.0) > 5.0, "Tilted prefab socket basis must result in a genuinely different room yaw."):
		return
	var fixed_rng := RandomNumberGenerator.new()
	fixed_rng.seed = 1
	var blocked_at := DungeonYawDockingSolver.dock(yaw_root, anchor_socket, second_socket, 5.0)
	var blockers: Array[Dictionary] = [DungeonOrientedBounds.rectangle(blocked_at.origin, Vector2(24, 24), blocked_at.basis)]
	var rejected := DungeonYawDockingSolver.solve(yaw_root, size, anchor_socket, size, second_socket, blockers, 4.5, 5.5, 8, fixed_rng)
	if not _check(not rejected.get("success", true) and rejected.get("attempts", 0) == 8, "Bounded OBB placement must reject an obstructed socket candidate without hanging."):
		return
	var impossible := DungeonYawDockingSolver.solve(yaw_root, size, anchor_socket, size, second_socket, obstacle_list, -2.0, 1.0, 999, fixed_rng)
	if not _check(not impossible.get("success", true), "Invalid search limits must be refused."):
		return
	# Build a physical 27-degree, non-cardinal two-room bridge with proper
	# opposed real room doorways using existing F1 static box primitives.
	var room_front := _room(RoomOpening.Wall.FRONT)
	var room_back := _room(RoomOpening.Wall.BACK)
	var first: Node3D = RoomGeometryBuilder.build(room_front, true)
	var second: Node3D = RoomGeometryBuilder.build(room_back, true)
	if not _check(first != null and second != null, "F1 rooms must support socket-pair authoring."):
		return
	var first_socket := first.get_node_or_null("Socket_test_portal") as Marker3D
	var second_socket_node := second.get_node_or_null("Socket_test_portal") as Marker3D
	var pose_a := Transform3D(Basis(Vector3.UP, deg_to_rad(27.0)), Vector3(12, 0, 13))
	var phys_rng := RandomNumberGenerator.new()
	phys_rng.seed = 42
	var physical := DungeonYawDockingSolver.solve(pose_a, size, first_socket.transform, size, second_socket_node.transform, obstacle_list, 4.0, 6.0, 8, phys_rng)
	if not _check(physical.get("success", false), "Physical yaw room pair must dock."):
		return
	var pose_b: Transform3D = physical["transform"]
	var start_pose: Transform3D = pose_a * first_socket.transform
	var finish_pose: Transform3D = pose_b * second_socket_node.transform
	var bridge := DungeonYawSocketBridge.build(start_pose, finish_pose, 1.6, 3.5, 0.2, 0.2)
	if not _check(bridge != null, "An arbitrary-yaw corridor should compile native static geometry and collision."):
		return
	var stage := Node3D.new()
	stage.name = "RotatedSocketPair"
	root.add_child(stage)
	first.name = "FirstRoom"
	first.transform = pose_a
	stage.add_child(first)
	second.name = "SecondRoom"
	second.transform = pose_b
	stage.add_child(second)
	stage.add_child(bridge)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.safe_margin = 0.001
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	actor.add_child(shape)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var y: float = 1.8 * 0.5 + 0.08
	var steps := PackedVector3Array([pose_a.origin, start_pose.origin, finish_pose.origin, pose_b.origin])
	actor.global_position = steps[0] + Vector3.UP * y
	for i in range(1, steps.size()):
		var target: Vector3 = steps[i] + Vector3.UP * y
		if not _check(not actor.test_move(actor.global_transform, target - actor.global_position), "27-degree bridge physical capsule crossing failed on segment %d" % i):
			return
		actor.global_position = target
	stage.remove_child(actor)
	actor.free()
	stage.get_parent().remove_child(stage)
	# Native scene must roundtrip without addon runtime nodes.
	var exported := PackedScene.new()
	_owners(stage, stage)
	if not _check(exported.pack(stage) == OK, "Arbitrary-yaw physical pair must pack."):
		return
	var path := "user://yaw_pair_smoke.tscn"
	if not _check(ResourceSaver.save(exported, path) == OK, "Yaw pair must save."):
		return
	var opened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(opened != null, "Yaw pair must reload."):
		return
	var reload := opened.instantiate()
	if not _check(reload.find_children("*", "CollisionShape3D", true, false).size() > 5, "Export must retain actual rotated collider geometry."):
		return
	reload.free()
	stage.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("DUNGEON_YAW_DOCKING_SMOKE: PASS (80 deterministic yaw probes, SAT OBB, blocked-search rejection, real rotated capsule bridge and export)")
	quit(0)


func _room(wall: int) -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.room_size = Vector3(8, 3.5, 8)
	var opening := RoomOpening.new()
	opening.stable_id = "test_portal"
	opening.wall = wall
	opening.kind = RoomOpening.Kind.DOOR
	opening.width = 1.6
	opening.height = 2.3
	bp.openings = [opening]
	return bp


func _owners(n: Node, root_owner: Node) -> void:
	for child in n.get_children():
		child.owner = root_owner
		_owners(child, root_owner)


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DUNGEON_YAW_DOCKING_SMOKE: FAIL: " + message)
		quit(1)
	return ok
