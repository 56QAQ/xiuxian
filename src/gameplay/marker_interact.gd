class_name MarkerInteract
extends Node3D
## 通用交互点：挂在标记点上，[F] 触发回调 action(actor)。

var prompt: String = ""
var action: Callable
var interact_radius: float = 3.0


static func create(parent: Node3D, prompt_text: String, cb: Callable, radius: float = 3.0) -> MarkerInteract:
	var m := MarkerInteract.new()
	m.prompt = prompt_text
	m.action = cb
	m.interact_radius = radius
	parent.add_child(m)
	return m


func _ready() -> void:
	add_to_group("interactable")


func interact_prompt() -> String:
	return prompt


func interact(actor: Node3D) -> void:
	if action.is_valid():
		action.call(actor)
