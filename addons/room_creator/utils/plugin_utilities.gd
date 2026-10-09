class_name RoomCreatorPluginUtilities


static func set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint():
		node.owner = node.get_tree().edited_scene_root
	

static func remove_falsy_values(array: Array) -> Array:
	var cleaned_array := []
	
	for element in array:
		if element:
			cleaned_array.append(element)
		
	return cleaned_array
	
	
static func get_all_children(from_node: Node) -> Array: 
	var nodes := []
	
	for child in from_node.get_children():
		if child.get_child_count() > 0:
			nodes.append(child)
			nodes.append_array(get_all_children(child))
		else:
			nodes.append(child)
			
	return nodes


## Only works for native nodes like Area2D, Camera2D, etc.
## Example NodePositioner.find_nodes_of_type(self, Control.new())
static func find_nodes_of_type(node: Node, type_to_find: Node) -> Array:
	var  result := []
	
	var childrens = node.get_children(true)

	for child in childrens:
		if child.is_class(type_to_find.get_class()):
			result.append(child)
		else:
			result.append_array(find_nodes_of_type(child, type_to_find))
	
	return result


static func chance(probability_chance: float = 0.5) -> bool:
	probability_chance = clamp(probability_chance, 0.0, 1.0)
	
	return randf() < probability_chance


static func flatten(array: Array[Variant]):
	var result := []
	
	for i in array.size():
		if typeof(array[i]) >= TYPE_ARRAY:
			result.append_array(flatten(array[i]))
		else:
			result.append(array[i])

	return result
