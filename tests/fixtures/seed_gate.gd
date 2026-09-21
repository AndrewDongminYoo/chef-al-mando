extends RefCounted

## §4.2 시도 게이트: 시도 인덱스마다 그 시드의 추첨 인지 정책이 두 목표를 통과하고, 캠페인 세 번째
## 영업부터는 무계획이 제공 2건 이상 또는 손익 1,500 이상 미달해야 합니다(pressure-rebalance.md §4.1·§4.2).
## 실패 문장은 "attempt N: <이유>" 꼴이며, tests/test_seed_gate.gd와 tests/sweep_policies.gd --gate가 같은 판정을 씁니다.

const Policies := preload("res://tests/fixtures/m3_policies.gd")
const ScheduleGenerator := preload("res://content/schedule_generator.gd")
const NO_PLAN_SERVED_GAP: int = 2
const NO_PLAN_PROFIT_GAP: int = 1500


static func evaluate(campaign: Resource, scenario: Resource, attempts: Array[int]) -> Dictionary:
	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	var pressured: bool = campaign.scenarios.find(campaign.scenario_for(scenario.id)) >= 2
	for attempt: int in attempts:
		var seed_value: int = ScheduleGenerator.service_seed_for(scenario.id, attempt)
		var run: Dictionary = Policies.run_policy(scenario, Policies.draw_aware_policy(scenario, seed_value), 1, seed_value)
		var row: Dictionary = {"attempt": attempt, "seed": seed_value, "served": -1, "profit": 0, "no_plan_served": -1, "no_plan_profit": 0}
		if not run.accepted:
			failures.append("attempt %d: draw-aware policy rejected (%s)" % [attempt, run.reason])
		else:
			row["served"] = run.snapshot.accounting.served
			row["profit"] = run.snapshot.accounting.profit
			if not Policies.passes_targets(scenario, run):
				failures.append("attempt %d: draw-aware policy misses the targets (%d served, %d profit)" % [attempt, row["served"], row["profit"]])
		if pressured:
			var no_plan: Dictionary = Policies.run_policy(scenario, {}, 1, seed_value)
			if no_plan.accepted:
				row["no_plan_served"] = no_plan.snapshot.accounting.served
				row["no_plan_profit"] = no_plan.snapshot.accounting.profit
				if not no_plan_misses(scenario, no_plan):
					failures.append("attempt %d: no plan misses by less than %d orders and %d profit (%d served, %d profit)"
						% [attempt, NO_PLAN_SERVED_GAP, NO_PLAN_PROFIT_GAP, row["no_plan_served"], row["no_plan_profit"]])
		rows.append(row)
	return {"passed": failures.is_empty(), "failures": failures, "rows": rows}


## 무계획 미달 폭: 제공 2건 이상 또는 손익 1,500 이상(§4.1과 §4.2가 같은 폭을 씁니다).
static func no_plan_misses(scenario: Resource, run: Dictionary) -> bool:
	var served_gap: int = maxi(scenario.minimum_served - run.snapshot.accounting.served, 0)
	var profit_gap: int = maxi(scenario.minimum_profit - run.snapshot.accounting.profit, 0)
	return served_gap >= NO_PLAN_SERVED_GAP or profit_gap >= NO_PLAN_PROFIT_GAP
