@tool
class_name RoomOpening
extends Resource
## One persistent, designer-authored wall opening (meters, room-local coordinates).

enum Wall { FRONT, BACK, LEFT, RIGHT }
enum Kind { DOOR, WINDOW, ARCH }

@export var stable_id: String = "opening_01"
@export var wall: Wall = Wall.FRONT
@export var kind: Kind = Kind.DOOR
## Signed horizontal displacement from the wall center.
@export var offset: float = 0.0
@export_range(0.1, 20.0, 0.05, "or_greater") var width: float = 1.5
@export_range(0.1, 20.0, 0.05, "or_greater") var height: float = 2.2
## Door/arch openings should have a zero sill for continuous walkable floors.
@export_range(0.0, 20.0, 0.05, "or_greater") var sill_height: float = 0.0
@export var enabled: bool = true
