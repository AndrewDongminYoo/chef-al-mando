# 캠페인 운영 압력 검증

작성일: 2026-09-11.
[주방 운영 후속 계획](../plans/kitchen-operations-redesign.md)의 네 번째 절에 따라 첫 두 영업 뒤의 여섯 시나리오에 주문 파동과 공간 규칙을 적용했습니다.
이 기록은 자동 정책 비교와 저장 마이그레이션 근거를 다루며 실기기 재미 판정을 대신하지 않습니다.

## 자동 정책 결과

무계획은 발주, 프렙, 배치, 담당과 메뉴 우선순위를 초기값으로 둔 실행입니다.
기준 전략은 각 시나리오가 가르치는 기존 준비 명령을 사용합니다.

| 영업            | 목표 제공 | 목표 손익 | 무계획 제공 | 무계획 손익 | 기준 제공 | 기준 손익 | 대체 제공 | 대체 손익 | 주요 선택               |
| --------------- | --------: | --------: | ----------: | ----------: | --------: | --------: | --------: | --------: | ----------------------- |
| `hot_queue`     |        12 |      4750 |           8 |       -1850 |        12 |      4750 |        12 |      4750 | 혼합 프렙·우선순위      |
| `shared_stock`  |        17 |      4000 |          15 |        2300 |        18 |      4850 |        18 |      5050 | 발주·프렙               |
| `long_route`    |        21 |     12000 |           3 |      -10100 |        22 |     13700 |        21 |     12200 | 프렙·배치               |
| `split_duties`  |        26 |     12000 |          23 |        8750 |        26 |     12350 |        26 |     12350 | 프렙·담당               |
| `rush_hour`     |        23 |      8500 |          21 |        4650 |        23 |      8900 |        25 |      9500 | 프렙·우선순위           |
| `final_service` |        25 |     10000 |          18 |        1500 |        25 |     10800 |        26 |     10700 | 집중 프렙·배치·우선순위 |

위 표는 2026-09-11 기준이며 `split_duties`·`rush_hour`·`final_service`의 현재 기준·대체 값은 아래 "2026-09-20 정정: 미장 항목 기준"이 권위입니다.

모든 기준 전략과 대체 전략은 같은 입력을 1배속과 4배속으로 실행했을 때 각각 같은 최종 상태 해시를 만들어야 합니다.
같은 시나리오의 기준 전략과 대체 전략은 서로 다른 최종 상태 해시를 만들어 실제 선택 차이를 입증합니다.
작은 여유는 목표보다 최대 1건 더 제공하고 목표 손익보다 최대 2,000 높은 결과로 정의합니다.
무계획 정책은 목표보다 제공 수가 2건 이상 부족하거나 손익이 1,500 이상 부족해야 합니다.
후반 여섯 영업은 한 번에 둘 이상 도착하는 묶음과 다음 묶음 전 회복 구간을 모두 갖습니다.
재료 보관대와 출고대는 고정하며 이동 가능한 조리 설비는 작업 위치 중첩과 냉온 직접 인접을 만들 수 없습니다.

## 스테이지별 세 전략 검증

2026-09-14 운영자는 각 스테이지에 목표를 통과하는 실질적으로 다른 방법을 최소 3개 확보하도록 요구했습니다.
각 행의 기준·대체 A·대체 B는 준비·발주·배치·담당·우선순위 중 서로 다른 플레이어 선택을 제출합니다.
세 정책은 실제 `ServiceSim`을 마감까지 실행해 제공 수와 손익 목표를 모두 통과하며, 같은 스테이지 안에서 최종 상태 해시가 쌍별로 다릅니다.

| 영업            | 기준 제공·손익 | 대체 A 제공·손익 | 대체 B 제공·손익 | 구분되는 접근                                     |
| --------------- | -------------: | ---------------: | ---------------: | ------------------------------------------------- |
| `first_shift`   |     12 · 3,200 |       12 · 3,200 |       11 · 2,800 | 기본 운영 / 샐러드 프렙 / 채소 발주 절감          |
| `lunch_prep`    |     18 · 6,600 |       18 · 6,600 |       14 · 4,300 | 수프·곡물샐러드 프렙 / 샐러드 프렙 / 발주 절감    |
| `hot_queue`     |     12 · 4,750 |       12 · 4,750 |       12 · 5,550 | 집중 프렙 / 분산 프렙 / 단백질 발주 절감          |
| `shared_stock`  |     18 · 4,850 |       18 · 5,050 |       17 · 4,450 | 혼합 프렙 / 발주·수프 프렙 / 수프 우선순위        |
| `long_route`    |    22 · 13,700 |      21 · 12,200 |      24 · 16,800 | 최단 배치 / 대체 배치 / 온식 담당 결합            |
| `split_duties`  |    26 · 12,350 |      26 · 12,350 |      26 · 12,350 | 담당·혼합 프렙 / 혼합 프렙 / 버섯샐러드 집중 프렙 |
| `rush_hour`     |     23 · 8,900 |       25 · 9,500 |      26 · 10,500 | 프렙·우선순위 / 이중 프렙 / 버섯수프 우선순위     |
| `final_service` |    25 · 10,800 |      26 · 10,700 |      27 · 12,600 | 프렙·우선순위 / 프렙·배치 / 단백질 발주 절감      |

테스트를 먼저 확장한 실행은 8개 스테이지 모두에서 정책 수 부족을 보고하며 1,051개 검사 중 8개가 실패했습니다.
각 스테이지에 두 대체 정책을 고정한 뒤 같은 명령은 1,101개 검사, 실패 0으로 통과했습니다.
세 정책 각각은 반복 실행과 1배속·4배속 실행에서 같은 최종 상태 해시를 냅니다.
이 검증은 최소 세 경로의 재현 가능한 도달 가능성을 보장하지만 사람이 전략 차이를 얼마나 크게 느끼는지는 판정하지 않습니다.

### 2026-09-19 정정: 시드 0 기준

[수요 예보·미장·리뷰 명세](../specs/mise-forecast-reviews.md)에 따라 주문 구성은 시드로 정해집니다.
위 표와 `check.sh m3`의 3전략·무계획 격차는 시드 0, 곧 작성된 일정에 대한 결과이며 다른 시드로 넓히지 않습니다.

### 2026-09-20 정정: 미장 항목 기준

[미장 항목 계획 2a](../plans/mise-items-implementation.md)에 따라 메뉴당 프렙 8종을 공유 미장 6종(`prepped_vegetable`·`prepped_grain`·`prepped_mushroom`·`soup_base`·`thawed_protein`·`marinated_protein`)으로 바꿨습니다.
한 메뉴는 자기 미장 집합이 전부 재고에 있을 때만 손질을 건너뛰므로, 먼저 도착한 샐러드가 덮밥 몫의 손질 토마토를 가져가면 덮밥은 원재료 경로로 떨어집니다.
목표값(`minimum_served`·`minimum_profit`), 시드 0, 빈 `forecast_slack`은 그대로이고, 원재료 발주와 레시피 재료 사전도 바뀌지 않았으므로 여섯 압력 영업의 무계획 결과는 위 표와 같습니다.
계획서의 시작 정책은 옛 레시피 수량을 항목별 합으로 옮긴 값이며 권위는 커밋된 `tests/fixtures/m3_policies.gd`에 있습니다.

`labor_units`와 `prep_labor_capacity`는 바꾸지 않았습니다.
`split_duties`는 원래 담당(직원 1·2 냉식, 3·4 온식)을 유지한 채 상한 15 안의 프렙 수량 2,561가지와 상한 18의 4,425가지를 모두 실행해도 최고가 각각 24건·9,750원과 25건·10,750원이어서 목표에 닿지 못했습니다.
발주도 지렛대가 아닙니다: `split_duties`의 주문 26건(샐러드 7·양송이 샐러드 7·현미 볶음밥 6·연어 덮밥 6)이 쓰는 원재료는 토마토 20·양송이 13·현미 12·연어 6으로 시나리오 발주량과 정확히 같아, 더 사면 팔 주문이 없고 덜 사면 주문을 잃습니다.
그래서 상한은 15로 되돌리고, 기준 정책의 담당을 직원 2 냉식·직원 3·4 온식(직원 1은 전 담당)으로 바꿨습니다.
이 담당과 손질 토마토 6·불린 현미 3·손질 양송이 6은 26건·12,350원으로 26건 전부를 제공합니다.

| 영업            | 기준 정책 (미장 ID: 수량 · 노동량/상한)                                                                  | 대체 A                                                                                                  | 대체 B                                         |
| --------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `first_shift`   | 없음                                                                                                     | prepped_vegetable 2                                                                                     | 토마토 발주 11                                 |
| `lunch_prep`    | prepped_grain 4, soup_base 4, prepped_vegetable 1 · 9/9                                                  | prepped_vegetable 6                                                                                     | 토마토 발주 19                                 |
| `hot_queue`     | marinated_protein 1, prepped_vegetable 3 · 6/6 · 구이 우선순위 2                                         | marinated_protein 1, prepped_grain 1, soup_base 1, prepped_vegetable 1 · 우선순위                       | 기준 + 연어 발주 5                             |
| `shared_stock`  | prepped_grain 4, soup_base 4, prepped_vegetable 1 · 9/9                                                  | 토마토 발주 29 + prepped_grain 4, soup_base 4                                                           | 수프 우선순위 2                                |
| `long_route`    | marinated_protein 4 · 12/12 · 최단 배치                                                                  | marinated_protein 4 · 대체 배치                                                                         | 기준 + 직원 3 온식                             |
| `split_duties`  | 직원 2 냉식·직원 3·4 온식 + prepped_vegetable 6, prepped_grain 3, prepped_mushroom 6 · 15/15             | prepped_vegetable 3, prepped_grain 4, thawed_protein 1, prepped_mushroom 4 · 12/15                      | prepped_vegetable 6, prepped_mushroom 1 · 7/15 |
| `rush_hour`     | prepped_vegetable 4, prepped_grain 3, thawed_protein 1, prepped_mushroom 1 · 9/18 · 구이·덮밥 우선순위 2 | marinated_protein 1, prepped_vegetable 4, prepped_grain 2, thawed_protein 3, prepped_mushroom 1 · 13/18 | 양송이 수프 우선순위 0                         |
| `final_service` | marinated_protein 4, prepped_vegetable 4, prepped_grain 2 · 18/18 · 구이 우선순위 2                      | marinated_protein 6 · 18/18 + 화구 2 배치                                                               | 기준 + 연어 발주 7                             |

`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3`는 1,113개 검사를 실패 없이 통과했습니다(기준 정책 명령 수가 바뀌어 `test_m3_ui.gd`의 검사 수가 달라졌습니다).
`build/check/m3.log`의 `M3_PRESSURE` 회계 발췌는 다음과 같습니다.

| 영업            | 목표 제공 | 목표 손익 | 무계획 제공 | 무계획 손익 | 기준 제공 | 기준 손익 | 대체 A 제공·손익 | 대체 B 제공·손익 |
| --------------- | --------: | --------: | ----------: | ----------: | --------: | --------: | ---------------: | ---------------: |
| `hot_queue`     |        12 |      4750 |           8 |       -1850 |        12 |      4750 |       12 · 4,750 |       12 · 5,550 |
| `shared_stock`  |        17 |      4000 |          15 |        2300 |        18 |      4850 |       18 · 5,050 |       17 · 4,450 |
| `long_route`    |        21 |     12000 |           3 |      -10100 |        22 |     13700 |      21 · 12,200 |      24 · 16,800 |
| `split_duties`  |        26 |     12000 |          23 |        8750 |        26 |     12350 |      26 · 12,350 |      26 · 12,350 |
| `rush_hour`     |        23 |      8500 |          21 |        4650 |        24 |      9800 |      26 · 10,700 |      26 · 10,500 |
| `final_service` |        25 |     10000 |          18 |        1500 |        25 |     10700 |      26 · 10,700 |      25 · 10,600 |

```log
M3_PRESSURE split_duties goals={"profit": 12000, "served": 26} no_plan.accounting={"cancelled": 0, "cash": 21750, "expired": 3, "labor_cost": 3200, "profit": 8750, "purchased_cost": 8800, "revenue": 20750, "served": 23, "waste_cost": 1350} reference.accounting={"cancelled": 0, "cash": 25350, "expired": 0, "labor_cost": 3200, "profit": 12350, "purchased_cost": 8800, "revenue": 24350, "served": 26, "waste_cost": 0}
M3_PRESSURE rush_hour goals={"profit": 8500, "served": 23} no_plan.accounting={"cancelled": 0, "cash": 19050, "expired": 9, "labor_cost": 3200, "profit": 4650, "purchased_cost": 10200, "revenue": 18050, "served": 21, "waste_cost": 4150} reference.accounting={"cancelled": 0, "cash": 24200, "expired": 6, "labor_cost": 3200, "profit": 9800, "purchased_cost": 10200, "revenue": 23200, "served": 24, "waste_cost": 2150}
M3_PRESSURE final_service goals={"profit": 10000, "served": 25} no_plan.accounting={"cancelled": 0, "cash": 16900, "expired": 14, "labor_cost": 3200, "profit": 1500, "purchased_cost": 11200, "revenue": 15900, "served": 18, "waste_cost": 5550} reference.accounting={"cancelled": 0, "cash": 26100, "expired": 7, "labor_cost": 3200, "profit": 10700, "purchased_cost": 11200, "revenue": 25100, "served": 25, "waste_cost": 2550}
```

`hot_queue`·`shared_stock`·`long_route`는 1:1로 옮긴 미장이 옛 프렙과 같은 재고를 만들므로 기준·대체·무계획 결과가 위 표와 같고, 첫 두 영업도 같습니다.
같은 명령을 두 번 실행한 `M3_PRESSURE`·`M3_STRATEGY` 줄은 서로 같았고, 각 정책의 반복 실행과 1배속·4배속 해시 일치는 `test_m3_playthrough.gd`가 검사합니다.

### 2026-09-21 정정: 부분 프렙 기준

[부분 프렙 계획 2b](../plans/partial-prep-implementation.md)에 따라 한 메뉴는 미장 집합 가운데 재고에 있는 항목은 그 미장을, 없는 항목은 그 항목의 원재료를 함께 예약·소비하고, `prep` 공정 시간은 부족 항목 비율만큼 정수 올림으로 줄어듭니다.
2a에서는 먼저 도착한 샐러드가 손질 토마토를 가져가면 현미 샐러드가 전부 원재료로 떨어져 불린 현미가 남았지만, 지금은 그 현미 샐러드가 불린 현미를 쓰고 `prep`을 절반만 하므로 같은 정책의 재고 소진 순서와 공정 시간이 달라지고, 그래서 기준·대체 정책의 회계가 움직였습니다.
무계획 영업은 프렙이 없어 모든 항목이 부족하므로 원재료 사전과 원래 `prep` 시간이 그대로 나오고, 여섯 압력 영업의 `no_plan` 회계는 위 2026-09-20 표와 정확히 같았습니다(혼합 소비 코드가 프렙 없는 경로를 바꾸지 않았다는 증거입니다).

기준 정책은 `shared_stock`·`split_duties`·`rush_hour`·`final_service` 네 영업에서 목표에 미달했고(`hot_queue`·`long_route`는 그대로), 대체 정책은 `split_duties` 둘, `rush_hour` A, `final_service` B가 미달했습니다.
목표값·`labor_units`·`prep_labor_capacity`·시나리오 `purchases`·레시피 재료 사전은 바꾸지 않았고, 아래 정책만 바꿨습니다.
`final_service` 대체 B의 `set_purchase protein` 명령이 7에서 6으로 바뀐 것은 플레이어 선택인 정책의 발주 명령이지 시나리오 발주량이 아닙니다.
`final_service` 기준 정책은 구이 우선순위 2를 잃고 프렙만 남았습니다: 구이 우선순위 2를 고정한 채 프렙 수량 15,807가지를 돌려도 최고가 24건·10,400원 또는 25건·8,900원이어서 목표(25건·10,000원)에 닿지 않았고, 화구 2 배치까지 더한 6,160가지도 통과가 없었으며, 우선순위 없는 6,160가지 가운데 통과는 `marinated_protein 5, prepped_grain 3` 하나뿐이었습니다.
`rush_hour` 기준 정책은 `thawed_protein 1`을 빼고 `prepped_mushroom`을 1에서 3으로 올렸습니다.
권위는 커밋된 `tests/fixtures/m3_policies.gd`에 있고, 위 2026-09-20 표의 정책 열은 이 절이 대체합니다.

| 영업            | 항목   | 이전                                                                                                     | 이후                                                                                                    |
| --------------- | ------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `shared_stock`  | 기준   | prepped_grain 4, soup_base 4, prepped_vegetable 1 · 9/9                                                  | prepped_grain 1, soup_base 6, prepped_mushroom 2 · 9/9                                                  |
| `split_duties`  | 기준   | 직원 2 냉식·직원 3·4 온식 + prepped_vegetable 6, prepped_grain 3, prepped_mushroom 6 · 15/15             | 같은 담당 + prepped_vegetable 6, prepped_grain 3, prepped_mushroom 4, thawed_protein 2 · 15/15          |
| `split_duties`  | 대체 A | prepped_vegetable 3, prepped_grain 4, thawed_protein 1, prepped_mushroom 4 · 12/15                       | prepped_vegetable 3, prepped_grain 4, thawed_protein 1, prepped_mushroom 5 · 13/15                      |
| `split_duties`  | 대체 B | prepped_vegetable 6, prepped_mushroom 1 · 7/15                                                           | prepped_vegetable 6, prepped_mushroom 4 · 10/15                                                         |
| `rush_hour`     | 기준   | prepped_vegetable 4, prepped_grain 3, thawed_protein 1, prepped_mushroom 1 · 9/18 · 구이·덮밥 우선순위 2 | prepped_vegetable 4, prepped_grain 3, prepped_mushroom 3 · 10/18 · 구이·덮밥 우선순위 2                 |
| `rush_hour`     | 대체 A | marinated_protein 1, prepped_vegetable 4, prepped_grain 2, thawed_protein 3, prepped_mushroom 1 · 13/18  | marinated_protein 1, prepped_vegetable 5, prepped_grain 3, thawed_protein 1, prepped_mushroom 3 · 15/18 |
| `final_service` | 기준   | marinated_protein 4, prepped_vegetable 4, prepped_grain 2 · 18/18 · 구이 우선순위 2                      | marinated_protein 5, prepped_grain 3 · 18/18                                                            |
| `final_service` | 대체 B | 기준 + 연어 발주 7                                                                                       | 기준 + 연어 발주 6                                                                                      |

`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3`는 1,108개 검사를 실패 없이 통과했습니다(기준 정책 명령 수가 바뀌어 `test_m3_ui.gd`의 검사 수가 1,113에서 달라졌습니다).
`build/check/m3.log`의 `M3_PRESSURE` 회계 발췌는 다음과 같습니다(무계획 열은 2026-09-20 표와 같습니다).

| 영업            | 목표 제공 | 목표 손익 | 무계획 제공 | 무계획 손익 | 기준 제공 | 기준 손익 | 대체 A 제공·손익 | 대체 B 제공·손익 |
| --------------- | --------: | --------: | ----------: | ----------: | --------: | --------: | ---------------: | ---------------: |
| `hot_queue`     |        12 |      4750 |           8 |       -1850 |        12 |      4750 |       12 · 4,750 |       12 · 5,550 |
| `shared_stock`  |        17 |      4000 |          15 |        2300 |        18 |      4700 |       17 · 4,150 |       17 · 4,450 |
| `long_route`    |        21 |     12000 |           3 |      -10100 |        22 |     13700 |      21 · 12,200 |      24 · 16,800 |
| `split_duties`  |        26 |     12000 |          23 |        8750 |        26 |     12350 |      26 · 12,350 |      26 · 12,350 |
| `rush_hour`     |        23 |      8500 |          21 |        4650 |        24 |      9200 |       25 · 9,100 |      26 · 10,500 |
| `final_service` |        25 |     10000 |          18 |        1500 |        25 |     10300 |      26 · 10,700 |      26 · 10,900 |

```log
M3_PRESSURE shared_stock goals={"profit": 4000, "served": 17} no_plan.accounting={"cancelled": 0, "cash": 11550, "expired": 7, "labor_cost": 2400, "profit": 2300, "purchased_cost": 5850, "revenue": 10550, "served": 15, "waste_cost": 2300} reference.accounting={"cancelled": 0, "cash": 13950, "expired": 4, "labor_cost": 2400, "profit": 4700, "purchased_cost": 5850, "revenue": 12950, "served": 18, "waste_cost": 1350}
M3_PRESSURE split_duties goals={"profit": 12000, "served": 26} no_plan.accounting={"cancelled": 0, "cash": 21750, "expired": 3, "labor_cost": 3200, "profit": 8750, "purchased_cost": 8800, "revenue": 20750, "served": 23, "waste_cost": 1350} reference.accounting={"cancelled": 0, "cash": 25350, "expired": 0, "labor_cost": 3200, "profit": 12350, "purchased_cost": 8800, "revenue": 24350, "served": 26, "waste_cost": 0}
M3_PRESSURE rush_hour goals={"profit": 8500, "served": 23} no_plan.accounting={"cancelled": 0, "cash": 19050, "expired": 9, "labor_cost": 3200, "profit": 4650, "purchased_cost": 10200, "revenue": 18050, "served": 21, "waste_cost": 4150} reference.accounting={"cancelled": 0, "cash": 23600, "expired": 6, "labor_cost": 3200, "profit": 9200, "purchased_cost": 10200, "revenue": 22600, "served": 24, "waste_cost": 2250}
M3_PRESSURE final_service goals={"profit": 10000, "served": 25} no_plan.accounting={"cancelled": 0, "cash": 16900, "expired": 14, "labor_cost": 3200, "profit": 1500, "purchased_cost": 11200, "revenue": 15900, "served": 18, "waste_cost": 5550} reference.accounting={"cancelled": 0, "cash": 25700, "expired": 7, "labor_cost": 3200, "profit": 10300, "purchased_cost": 11200, "revenue": 24700, "served": 25, "waste_cost": 2800}
```

스윕은 시나리오마다 위 표에 적힌 미장 항목의 프렙 수량을 0부터 순회하며 `PreparationPlan.initial_state`가 받아들이는 조합만(노동량이 `prep_labor_capacity` 안에 들고 시나리오 `purchases`가 원재료를 댈 수 있는 조합만) 남기고, 남은 조합마다 그 영업의 담당·배치·우선순위 같은 프렙 외 명령을 아래에 적은 대로 고정하거나 뺀 채 실행해 두 목표에 모두 도달한 조합 수를 셌습니다.
스윕 스크립트와 로그는 세션 스코프의 scratchpad에만 있었고 커밋하지 않아 지금은 남아 있지 않습니다.
위 방식으로 돌린 조합 수는 `shared_stock` 645(통과 14), `split_duties` 기준 담당 3,361(통과 723)과 담당 없음 3,361(통과 359), `rush_hour` 우선순위 고정 3,976(통과 480)과 우선순위 없음 3,976(통과 150), `final_service` 구이 우선순위 고정 6,104와 15,807(통과 0), 우선순위와 화구 2 배치 고정 6,160(통과 0), 우선순위 없음 6,160(통과 1)이고, `final_service` 대체 B는 기준 정책에 발주·우선순위 변형 44가지를 더한 `probe.gd`로 골랐습니다.
`split_duties`는 담당을 두지 않은 `thawed_protein 1`만으로도 26건·12,350원이 나와 담당 분리가 필수 조건이 아니게 됐고, 기준과 대체 둘의 회계가 같은 세 방향 동률은 2026-09-20 표와 마찬가지로 해시 차이로만 구분됩니다.

이후의 스윕은 세션마다 다시 작성하지 않고 커밋된 `tests/sweep_policies.gd`로 돌립니다.
`"$GODOT_BIN" --headless --path <워크트리> --script tests/sweep_policies.gd -- --scenario <영업 ID> [--attempt N] [--items id:상한,...] [--keep duties|priorities|placement,...] [--best]` 형태로 실행하며, 프렙 수량(`set_prep`)은 `--keep`과 무관하게 항상 스윕 대상이라 이 목록에 없고 `--items`로만 순회하며, `--items`를 생략하면 그 영업의 미장 전부를 상한 `prep_labor_capacity / labor_units`로 순회합니다.
`--keep`은 기준 정책에서 그대로 둘 프렙 외 명령 종류이고, 생략하면 담당·우선순위·배치를 전부 유지합니다.
`--keep`의 `purchases` 토큰은 지금은 기준 정책에 발주 명령이 없어 항상 작성값을 남기며, 이 토큰은 기준 정책에 `set_purchase`가 추가될 때에만 의미가 생깁니다(시도별로 발주를 바꾸는 것은 아래 `--purchases draw`의 몫입니다).
출력은 두 목표를 모두 통과한 조합마다 수량·노동량·제공·손익·진행중 작업을 담은 `SWEEP` 한 줄을 찍고, 끝에 시나리오·시도·시드·조합 수·통과 수·최댓값을 담은 `SWEEP_SUMMARY` 한 줄을 찍으며, `--best`를 주면 통과 여부와 무관한 사전순 최댓값도 그 줄에 함께 찍습니다.
같은 인자로 다시 돌리면 같은 조합 수와 같은 `best`가 나옵니다.
`--purchases draw`는 그 시도의 `draw_aware_policy`가 만드는 발주 명령을 기준 정책의 발주 대신 고정하고, `--without <종류,…>`는 `--keep`이 남긴 기준 명령에서 `set_purchase`·`set_duty`·`move_station`·`rotate_station`·`priorities`를 뺀 뒤 스윕하며, `--gate`는 다른 인자를 무시하고 시도 0~5의 `SEED_GATE_ROW`와 `SEED_GATE_VERDICT`만 찍습니다.
도구의 판정은 시도 0을 포함하므로 `test_seed_gate.gd`(시도 1–5)보다 엄격하며, 시도 0에서만 실패하면 그것은 `check.sh m3`의 시드 0 규칙이 다루는 문제입니다.
`--keep`에서 `duties`를 빼는 것과 `--without set_duty`는 같은 결과를 내며, `--keep`은 하위 호환으로 남깁니다.

### 2026-09-21 지렛대 측정과 목표

[예보 콘텐츠 계획](../plans/forecast-content-implementation.md) Task 5의 측정이며, 운영자 답은 `split_duties`는 준비 노동량 상한 스윕 허용, `final_service`는 목표를 올리지 않고 여유 측정입니다.
`forecast_slack`이 비어 있어(같은 계획의 Task 4 취소) 시도 1–5의 시드는 모두 작성 순서와 같으므로 아래는 시도 0(시드 0)만 측정했습니다.
모든 스윕은 위 `tests/sweep_policies.gd`로 `--attempt 0 --best`를 붙여 돌렸고, 발주는 도구의 인자가 아니라 항상 작성값입니다.
두 영업 모두 목표값·상한·발주는 바꾸지 않았고, 이 절이 남기는 것은 표와 결론뿐입니다.

`split_duties`의 미장은 `prepped_vegetable`·`prepped_grain`·`prepped_mushroom`·`thawed_protein` 넷이고 `marinated_protein`은 이 영업의 재료 목록에 없어 도구가 `--items marinated_protein:2`를 거부하므로, `--items prepped_vegetable:7,prepped_grain:6,prepped_mushroom:6,thawed_protein:3`으로 돌렸습니다.
담당 유지는 `--keep duties,priorities,placement`, 담당 없음은 `--keep priorities,placement`이며 기준 정책에 우선순위·배치 명령이 없어 후자는 프렙만 남습니다.
상한 15와 9는 `.tres`의 `prep_labor_capacity`를 바꿔 측정했고, 14–10은 상한 15의 통과 조합을 노동량별로 세어 도출했습니다.
도출이 성립하는 이유는 상한이 `sim/preparation_plan.gd`의 수량 거부에만 쓰이고 영업 시뮬레이션은 읽지 않아(`sim/service_analysis.gd`는 영업 뒤 조언에만 씀) 같은 조합의 회계가 상한과 무관하기 때문이며, 상한 9의 측정값이 도출값과 정확히 같았습니다.

| 상한 | 담당 유지 조합 | 담당 유지 통과 | 담당 없음 조합 | 담당 없음 통과 | 근거 |
| ---: | -------------: | -------------: | -------------: | -------------: | ---- |
|   15 |          1,373 |            554 |          1,373 |            225 | 측정 |
|   14 |                |            517 |                |            221 | 도출 |
|   13 |                |            471 |                |            215 | 도출 |
|   12 |                |            418 |                |            206 | 도출 |
|   11 |                |            351 |                |            191 | 도출 |
|   10 |                |            273 |                |            177 | 도출 |
|    9 |            554 |            195 |            554 |            160 | 측정 |

두 조건의 `best`는 상한 15와 9에서 모두 위 2026-09-21 정정 절의 최대치(제공·손익)와 같고, 담당 유지는 `prepped_mushroom 3, thawed_protein 2`(노동량 5), 담당 없음은 `thawed_protein 1`(노동량 1)이 그 값을 냅니다.
Step 2-A의 결론은 그 절과 같이 목표값으로는 담당 유무를 가를 수 없다는 것입니다.
Step 2-B의 결론은 상한을 9까지 내려도 담당 없음의 통과가 0이 되는 값이 없다는 것입니다: 담당 없음의 통과 조합 가운데 노동량 1이 셋(`thawed_protein 1`, `prepped_mushroom 1`, `prepped_grain 1`)이고 셋 다 최대치이므로 상한을 1까지 내려도 남고, 노동량 0(프렙 없음)은 통과하지 않아 무계획 결과와 일치합니다.
따라서 `prep_labor_capacity`는 15 그대로이고 `m3_policies.gd`도 바뀌지 않았습니다.
이 영업에서 지렛대는 담당이 아니라 "미장 한 단위라도 있는가"이며, 이를 가르려면 상한이 아닌 다른 값이 필요합니다(별도 승인 대상).

`final_service`는 `--items marinated_protein:6,prepped_vegetable:6,prepped_grain:4,prepped_mushroom:3,soup_base:2,thawed_protein:3`으로 돌렸습니다.
커밋된 기준 정책은 위 정정 절대로 우선순위가 없으므로 `--keep priorities,placement`는 빈 사전을 유지해 `--keep placement`와 같은 결과를 내며, "구이 우선순위 2 유지" 조건은 스윕 동안만 `tests/fixtures/m3_policies.gd`의 `final_service` 기준 정책에 `policy.priorities = {"grill": 2}` 한 줄을 넣어 돌리고 되돌렸습니다.
상한 21과 연어 발주 9의 탐침도 `.tres`를 스윕 동안만 바꾸고 `git checkout --`으로 되돌렸으며, 되돌린 뒤 `git status --short`가 비어 있음을 확인했습니다.

| 조건                                 | 상한 | 연어 발주 |  조합 | 통과 | 통과 최댓값                                                                            | 통과 무관 최댓값                                                                               |
| ------------------------------------ | ---: | --------: | ----: | ---: | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `--keep placement` (우선순위 없음)   |   18 |         8 | 6,160 |    1 | `marinated_protein 5, prepped_grain 3` · 25 · 10,300                                   | 같음                                                                                           |
| `--keep priorities,placement` (동일) |   18 |         8 | 6,160 |    1 | 같음                                                                                   | 같음                                                                                           |
| 구이 우선순위 2 주입                 |   18 |         8 | 6,160 |    0 | 없음                                                                                   | `marinated_protein 5, prepped_mushroom 2` · 25 · 8,900                                         |
| 구이 우선순위 2 주입                 |   21 |         8 | 7,838 |   22 | `marinated_protein 5, prepped_vegetable 3, thawed_protein 2` · 노동량 20 · 27 · 12,200 | 같음                                                                                           |
| 구이 우선순위 2 주입                 |   18 |         9 | 6,160 |    0 | 없음                                                                                   | `marinated_protein 3, prepped_mushroom 2, prepped_vegetable 6, thawed_protein 1` · 24 · 10,000 |

상한 21의 통과 22가지는 노동량 19가 둘, 20이 일곱, 21이 열셋이므로 같은 도출로 상한 19부터 구이 우선순위 2를 둔 통과 조합이 생깁니다.
발주는 스윕 인자가 아니어서 단일 실행으로도 확인했습니다: 기준 프렙에 구이 우선순위 2와 `set_purchase protein`을 더한 정책은 8에서 23건·6,900원, 9에서 21건·4,400원으로 둘 다 미달이고 9가 더 나쁩니다.
구이 우선순위 지렛대를 되살리는 값은 상한 18 → 21(또는 19)뿐이며 연어 발주 8 → 9는 되살리지 못합니다.
값은 바꾸지 않았고 상한 변경은 별도 승인 대상입니다.

## 저장 호환성

새 쓰기가 쓰는 콘텐츠 버전은 `persistence/campaign_store.gd`의 `VERSIONS`가 소유하고, 그 버전 이력은 [M4 모바일 명세](../specs/m4-mobile.md)가 소유합니다.
콘텐츠 버전 1 파일은 읽기만으로 바꾸지 않습니다.
완료 기록과 최고 기록은 유지하며 진행 중 영업은 새 콘텐츠와 배치 규칙에 맞게 다시 시작합니다.
콘텐츠 버전 3의 완료 기록과 최고 기록도 유지합니다.
프렙 노동 한도와 정책 기준이 바뀌었으므로 콘텐츠 버전 3의 `hot_queue` 진행 중 영업은 이전 준비 선택을 복원하지 않고 다시 시작합니다.
다른 시나리오의 진행 중 영업은 현재 콘텐츠에서 전체 복원 검증을 통과할 때 보존합니다.
이전 목표로 완료한 기록에는 `legacy_completed` 표식을 붙이며, 새 목표를 달성하면 표식을 제거합니다.
콘텐츠 버전 2 파일도 완료 기록과 최고 기록을 그대로 유지하고 진행 중 영업을 다시 시작합니다.
미래 버전과 손상 파일의 기존 보호 동작은 유지합니다.

**2026-09-20 정정:** 콘텐츠 버전 5부터(커밋 9104c4e·ed32d1e) 위 문단의 "새 쓰기는 콘텐츠 버전 4"와 "다른 시나리오의 진행 중 영업은 보존" 서술은 더 이상 맞지 않습니다.
새 쓰기는 버전 5를 쓰고 버전 4 이하의 진행 중 영업은 모든 시나리오에서 재시작하며, 규칙의 권위는 [수요 예보·미장·리뷰 명세](../specs/mise-forecast-reviews.md) §8입니다.

## `hot_queue` 프렙 집중 보정

2026-09-13 실기기 플레이에서 단백질 구이 프렙 4개와 우선순위 변경이 무계획보다 낮은 점수를 만들었다는 운영자 피드백을 받았습니다.
고정 시드 탐색에서 기존 주방 배치와 목표를 유지한 채 구이 1개·샐러드 3개 프렙과 구이 우선순위 2가 제공 12건·손익 4,750원을 기록했습니다.
구이 1개·수프 1개·샐러드 1개 프렙과 구이 우선순위 2·수프 우선순위 0도 제공 12건·손익 4,750원을 기록했으며 최종 상태 해시는 기준 전략과 달랐습니다.
무계획은 제공 8건·손익 -1,850원으로 유지됐습니다.

프렙 노동 한도를 12에서 6으로 줄여 구이 4개에 노동을 모두 쓰는 선택을 거부하고, 안내 문구는 구이와 샐러드에 프렙을 나누도록 설명합니다.
`tests/test_m3_playthrough.gd`는 배치 명령 없이 프렙과 메뉴 우선순위만으로 목표를 통과하고 1배속·4배속의 최종 상태 해시가 같은지 검사합니다.
`tests/test_m4_store.gd`는 콘텐츠 버전 3 기록과 복원 가능한 다른 영업을 유지하고 `hot_queue` 영업만 재시작한 뒤 다음 쓰기에서 버전 4로 갱신하는지 검사합니다.

`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m2`는 486개 검사를 실패 없이 통과했습니다.
`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3`는 스테이지별 세 전략을 포함한 1,101개 검사를 실패 없이 통과했습니다.
`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m4`는 1,190개 검사를 실패 없이 통과했습니다.

## 검증 범위

`scripts/check.sh m3`는 모든 명시 도착 tick, 150 tick 이상의 회복 구간, 무계획 격차, 스테이지별 세 전략의 통과와 쌍별로 다른 플레이어 선택·최종 상태, 반복 실행, 1배속·4배속 결정론을 읽습니다.
`scripts/check.sh m4`는 콘텐츠 버전 1·2·3 파일의 기록 보존, 진행 중 영업 재시작, 원본 파일 비변경을 읽습니다.

| 검사                         | 실제로 읽은 대상                                              | 결과                 |
| ---------------------------- | ------------------------------------------------------------- | -------------------- |
| `scripts/check.sh m0`        | 엔진 버전·import·M0 상태·안전 영역                            | 25개 검사, 실패 0    |
| `scripts/check.sh m1`        | 고정 tick·작업·회계·결정론·주 화면 명령                       | 192개 검사, 실패 0   |
| `scripts/check.sh m2`        | 준비·배치·공간 규칙·분석                                      | 486개 검사, 실패 0   |
| `scripts/check.sh m3`        | 캠페인 파동·세 전략·무계획 격차·결정론·실제 장면              | 1,101개 검사, 실패 0 |
| `scripts/check.sh m4-core`   | 영업 상태·세션·파일·명령 관계                                 | 887개 검사, 실패 0   |
| `scripts/check.sh m4`        | 콘텐츠 마이그레이션·저장·복구·설정·화면 연결                  | 1,190개 검사, 실패 0 |
| `scripts/check.sh m5`        | 출시 준비 자산·저장·완주                                      | 583개 검사, 실패 0   |
| `tests/test_m4_restart.py`   | 별도 프로세스의 M4 재시작 경로                                | 10개 검사 통과       |
| `tests/test_export_check.py` | export preset과 정적 계약                                     | 10개 검사 통과       |
| `scripts/check-export.sh`    | 내보낸 팩의 M4 이어하기·현지화와 M5 캠페인 엔딩·라이선스 실행 | 두 실행 경로 통과    |
| `tests/capture_m3.gd`        | 기본·와이드폰·태블릿의 실제 캠페인 장면과 입력                | 화면별 194개, 실패 0 |
| `capture_product_polish.gd`  | 폰·태블릿, 한·영, 기본·큰 글씨의 텍스트와 조작 영역           | 432개 검사, 실패 0   |

2026-09-14에 소스 `1c7d4a232438ad65be9bc575e44fdff5f9779d12`로 만든 iOS 개발 빌드를 iPhone 16 Pro에 설치했습니다.
설치 성공과 기존 캠페인 주 파일·백업 파일의 바이트 보존은 [M5 검증 기록](m5-verification.md)의 아홉 번째 절에 기록합니다.
운영자는 기본 배치를 유지하고 구이 프렙 1개·샐러드 프렙 3개·구이 기본 우선순위 2를 적용한 `hot_queue` 플레이를 포함한 통합 체크리스트 1~7을 모두 통과했다고 보고했습니다.
기기에서 다시 읽은 저장은 4배속과 3000 tick 마감, 제공 12건·미제공 8건을 확인합니다.
제공 메뉴의 매출은 13,000원이고 재료비 6,250원과 인건비 2,000원을 적용한 이번 판의 손익은 4,750원으로 현재 목표를 정확히 통과합니다.
이 결과는 지정 전략 한 번의 iPhone 수용 근거입니다.
운영자는 일부 캠페인이 사실상 정답 조합이 좁고 다른 선택으로는 목표에 도달하기 어려운 점에서 난이도가 생기지만, 문제 될 정도는 아니라고 평가했습니다.
따라서 목표 도달과 현재 난이도는 수용하고, 이번 스테이지별 세 정책 게이트로 자동 도달 가능성 제약을 닫습니다.
사람이 세 경로를 직접 발견하는지와 체감 차이가 충분한지는 비차단 관찰 항목으로 유지합니다.
무계획·대체 전략의 실기기 비교와 다른 후반 영업의 체감 차이는 아직 `[NOT_EVALUATED]`입니다.

## 선례

개인 `chef-al-mando`에서 `difficulty strategy`와 `kitchen realism`을 조회한 Oracle 결과는 모두 `[no precedent found]`였습니다.
따라서 현재 제품 계약과 운영자의 PR #13 설치본 플레이 결과를 기준으로 범위를 정했습니다.
2026-09-14 `strategy diversity` 조회에서는 접근의 대상·메커니즘·원인 가정을 구분하라는 글로벌 휴리스틱을 반환했으며 출처는 `wiki/concepts/strategy-diversity-enforcement.md`입니다.
이는 디버깅 전략 선례이므로 캠페인 규칙으로 그대로 채택하지 않고, 플레이어 선택과 실제 최종 상태를 함께 구분하는 방향을 확인하는 데만 사용했습니다.
`campaign policies`에 대한 프로젝트 전용 선례는 `[no precedent found]`였습니다.
