extends Resource

const ProcessDef := preload("res://content/process_def.gd")

@export var id: String = ""
@export var display_name: String = ""
@export var ingredients: Dictionary[String, int] = {}
@export var cook_role: String = ""
@export var revenue: int = 0
@export var patience_ticks: int = 0
@export var first_process_id: String = ""
@export var processes: Array[ProcessDef] = []


func ordered_processes() -> Array[ProcessDef]:
	var by_id: Dictionary[String, ProcessDef] = {}
	for process: ProcessDef in processes:
		if process == null or by_id.has(process.id):
			return []
		by_id[process.id] = process
	var result: Array[ProcessDef] = []
	var next: String = first_process_id
	var visited: Dictionary[String, bool] = {}
	while not next.is_empty():
		if visited.has(next) or not by_id.has(next):
			return []
		visited[next] = true
		var process: ProcessDef = by_id[next]
		result.append(process)
		next = process.next_id
	return result if result.size() == processes.size() else []
