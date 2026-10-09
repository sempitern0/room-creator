@tool
class_name RoomConnectionData
extends Resource
## One logical edge is the sole source for both reciprocal door openings.

@export var stable_id: String = ""
@export var from_room_id: String = ""
@export var to_room_id: String = ""
@export var from_wall: RoomOpening.Wall = RoomOpening.Wall.FRONT
@export var to_wall: RoomOpening.Wall = RoomOpening.Wall.BACK
@export var clear_width: float = 1.6
@export var clear_height: float = 2.3
