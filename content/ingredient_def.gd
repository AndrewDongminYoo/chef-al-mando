extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var unit_cost: int = 0
@export var purchasable: bool = true
## 미장 항목 하나를 만들 때 소비하는 원재료와 수량. 원재료는 비어 있습니다.
@export var inputs: Dictionary[String, int] = {}
## 미장 항목 하나를 만드는 준비 노동량. 원재료는 0입니다.
@export var labor_units: int = 0


func is_mise() -> bool:
	return not purchasable and not inputs.is_empty()
