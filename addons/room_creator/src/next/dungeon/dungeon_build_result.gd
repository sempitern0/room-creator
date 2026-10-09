@tool
class_name DungeonBuildResult
extends RefCounted
## Failed generations never publish an invalid or partial layout.

var success: bool = false
var layout: LevelLayout
var report: RoomValidationReport = RoomValidationReport.new()
var seed: int = 0
var attempts: int = 0
var expansions: int = 0
