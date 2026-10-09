@tool
class_name RoomValidationReport
extends Resource
## Stable diagnostics for headless tests and the editor. Never silently bake invalid input.

@export var errors: PackedStringArray = PackedStringArray()
@export var warnings: PackedStringArray = PackedStringArray()

func add_error(code: String, detail: String) -> void:
	errors.append("%s: %s" % [code, detail])

func add_warning(code: String, detail: String) -> void:
	warnings.append("%s: %s" % [code, detail])

func is_valid() -> bool:
	return errors.is_empty()

func summary() -> String:
	if is_valid():
		return "Valid (%d warnings)" % warnings.size()
	return "Invalid (%d errors, %d warnings): %s" % [errors.size(), warnings.size(), errors[0]]
