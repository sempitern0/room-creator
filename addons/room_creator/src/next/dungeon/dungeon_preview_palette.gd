@tool
class_name DungeonPreviewPalette
extends Resource
## Editor-only semantic colors. These never modify baked meshes or gameplay materials.

@export var entrance: Color = Color("#29b86d")
@export var exit: Color = Color("#e45050")
@export var critical_path: Color = Color("#38b8df")
@export var branches: Color = Color("#e9ab42")
@export var alternate_loops: Color = Color("#a97cff")
@export var route_width: float = 0.30
