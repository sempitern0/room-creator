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

## F2.6 optional orthogonal 3-leg route from one physical door socket to
## the other. Empty means the legacy straight corridor.
@export var route_points: PackedVector3Array = PackedVector3Array()

## F2.8: signed position along each endpoint wall in room-local meters.
## FRONT/BACK offsets use X; LEFT/RIGHT offsets use Z.
@export var from_offset: float = 0.0
@export var to_offset: float = 0.0
