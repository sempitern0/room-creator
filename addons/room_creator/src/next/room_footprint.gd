@tool
class_name RoomFootprint
extends RefCounted
## Orthogonal silhouette library: occupied thirds of a room's 3x3 footprint.
## A shape's footprint remains inside its grid cell, with explicit boundary sockets.

enum Shape { RECTANGLE, CROSS, L_SHAPE, T_SHAPE }

static func cells(shape: Shape, turns: int = 0) -> Array[Vector2i]:
	var occupied: Array[Vector2i] = []
	match shape:
		Shape.RECTANGLE:
			for z in 3:
				for x in 3:
					occupied.append(Vector2i(x, z))
		Shape.CROSS:
			occupied = [Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 2)]
		Shape.L_SHAPE:
			occupied = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
		Shape.T_SHAPE:
			occupied = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
		_:
			return []
	for i in occupied.size():
		for j in posmod(turns, 4):
			var pos: Vector2i = occupied[i]
			occupied[i] = Vector2i(2 - pos.y, pos.x)
	return occupied


static func supports_wall(shape: Shape, turns: int, wall: RoomOpening.Wall) -> bool:
	var cell := Vector2i(1, 0)
	match wall:
		RoomOpening.Wall.BACK:
			cell = Vector2i(1, 2)
		RoomOpening.Wall.LEFT:
			cell = Vector2i(0, 1)
		RoomOpening.Wall.RIGHT:
			cell = Vector2i(2, 1)
	return cells(shape, turns).has(cell)


static func is_valid_shape(shape: int) -> bool:
	return shape >= Shape.RECTANGLE and shape <= Shape.T_SHAPE
