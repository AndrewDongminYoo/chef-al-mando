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

### 2026-09-21 탐침: `hot_queue` 시도 2의 여유

[압력 영업 재조율 계획](../plans/pressure-rebalance-implementation.md) Task 2의 측정입니다.
계획 3은 `hot_queue` 시도 2에서 프렙 조합 104가지 전부가 실패해 멈췄고, 이 절은 콘텐츠를 바꾸기 전에 명세의 여유 수단(준비 노동량 상한, 시작 예산)이 그 시도를 풀 수 있는지를 잽니다.
모든 실행은 위 `tests/sweep_policies.gd`로 돌렸고, `hot_queue.tres`의 `menu_ids` 줄 앞에 `forecast_slack = Dictionary[String, int]({"grill": 2, "soup": 1, "salad": 1})`를 스윕 동안만 넣었습니다(이 줄이 없으면 시도 1–5의 추첨이 작성 순서와 같아 시도 2가 따로 존재하지 않습니다).
상한과 예산도 값마다 `.tres`를 바꿔 저장했고, 끝나고 `git checkout -- content/campaign/scenarios/hot_queue.tres`로 되돌린 뒤 `git status --short`가 비어 있음을 이 절을 쓰기 전에 확인했습니다.
목표값·상한·예산·발주는 바꾸지 않았고, 이 절이 남기는 것은 명령·표·결론뿐입니다.

시작 slack의 게이트는 `"$GODOT_BIN" --headless --path <워크트리> --script tests/sweep_policies.gd -- --scenario hot_queue --gate`로 읽었습니다.

| 시도 |      시드 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 판정 |
| ---: | --------: | -------------: | -------------: | ----------: | ----------: | ---- |
|    0 |         0 |             12 |          4,750 |           8 |      -1,850 | 통과 |
|    1 | 104076537 |             11 |          2,550 |           8 |      -1,850 | 미달 |
|    2 |  53743680 |              9 |           -450 |           8 |      -2,450 | 미달 |
|    3 |  70521299 |             11 |          4,000 |           8 |      -1,450 | 미달 |
|    4 | 154409394 |             13 |          5,300 |           9 |        -950 | 통과 |
|    5 | 171187013 |             10 |          2,900 |           8 |      -1,450 | 미달 |

`SEED_GATE_VERDICT`는 `passed: false`이고 실패 문장은 시도 1·2·3·5의 `draw-aware policy misses the targets (...)` 넷이므로, 계획 3의 기록대로 시도 1–5 가운데 통과는 시도 4 하나입니다.
시도 2의 실패 문장은 `misses the targets (9 served, -450 profit)`이지 `rejected (... insufficient_budget ...)`가 아니므로, 시도 2의 추첨 인지 발주는 시작 예산 9,250에서 거부되지 않았습니다.
scratchpad에만 두고 커밋하지 않은 탐침 스크립트로 시도별 추첨을 찍어 보면 시도 2의 주문은 구이 9·국 5·샐러드 6(작성 순서는 10·5·5)이고 추첨 인지 발주는 `grain 5, protein 10, vegetable 16`(6,350원)이어서, `9,250 − 2,000 − 6,350 = 900`이 남아 예산이 묶이지 않습니다.
구이가 작성 순서보다 늘어난 시도는 없어 "구이 +2가 연어 +2(800)를 요구한다"는 전제는 이 slack의 어느 시도에서도 성립하지 않았습니다.
시도 1은 시도 2와 주문 구성(구이 9·국 5·샐러드 6)과 추첨 인지 발주가 같은데도 11건·2,550원이므로, 시도 2를 가르는 것은 주문 구성이 아니라 도착 순서입니다(시도 2는 4·5번째 주문이 샐러드 둘, 13–15번째가 구이 셋입니다).

상한 스윕은 `prep_labor_capacity`를 6부터 11까지 1씩 바꾸며 `"$GODOT_BIN" --headless --path <워크트리> --script tests/sweep_policies.gd -- --scenario hot_queue --attempt 2 --purchases draw --items marinated_protein:3,prepped_vegetable:9,prepped_grain:9,soup_base:9 --best`를 돌렸습니다.
`--keep`을 생략해 기준 정책의 구이 우선순위 2는 유지됩니다.
상한 12부터는 `set_prep marinated_protein 4`(노동량 12)가 받아들여져 `_test_hot_queue_focus`의 `insufficient_labor` 검사가 깨지므로 11에서 멈췄습니다.
`--items`의 9는 노동량 1인 세 항목이 상한 9까지만 노동량 상한에 잘려 상한 10·11에서는 이 인자가 먼저 묶이므로, 그 두 값은 `--items marinated_protein:3,prepped_vegetable:11,prepped_grain:11,soup_base:11`로 다시 돌려 표에는 그 값을 적었습니다(9로 돌린 값은 394·500, 통과 0, 최댓값 같음).
모든 실행의 `SWEEP_SUMMARY`는 `attempt 2, seed 53743680, purchases draw`이고 `SWEEP` 줄은 한 줄도 없었습니다.
상한 6의 통과 무관 최댓값은 게이트 시도 2 행과 같은 9건·-450원이므로 `--purchases draw` 스윕과 게이트가 같은 정책 형태를 돌립니다.

| 상한 | 조합 | 통과 | 통과 최댓값 | 통과 무관 최댓값                                                           |
| ---: | ---: | ---: | ----------- | -------------------------------------------------------------------------- |
|    6 |  104 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450                                |
|    7 |  155 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450                                |
|    8 |  220 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450                                |
|    9 |  300 |    0 | 없음        | `prepped_grain 4, prepped_vegetable 1, soup_base 4` · 노동량 9 · 10 · -550 |
|   10 |  395 |    0 | 없음        | `prepped_grain 4, prepped_vegetable 1, soup_base 4` · 노동량 9 · 10 · -550 |
|   11 |  504 |    0 | 없음        | `marinated_protein 1, prepped_grain 4, soup_base 4` · 노동량 11 · 10 · 50  |

예산 스윕은 상한을 6으로 되돌리고 `starting_budget`을 9,750·10,250·10,750으로 바꿔 같은 명령을 돌렸습니다.

| 예산   | 상한 | 조합 | 통과 | 통과 최댓값 | 통과 무관 최댓값                            |
| ------ | ---: | ---: | ---: | ----------- | ------------------------------------------- |
| 9,750  |    6 |  104 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450 |
| 10,250 |    6 |  104 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450 |
| 10,750 |    6 |  104 |    0 | 없음        | `marinated_protein 1` · 노동량 3 · 9 · -450 |

예산 세 값의 결과가 상한 6·예산 9,250과 정확히 같은 이유는 `sim/`에서 `starting_budget`을 읽는 곳이 `preparation_plan.gd`의 발주 수락(`remaining_budget`)과 `service_sim.gd`의 `cash` 계산뿐이라(`grep -rn starting_budget sim/ content/`, 나머지는 `campaign_progress.gd`·`scenario_def.gd`의 범위 검증) 예산은 조합을 잘라내지 않고 손익도 바꾸지 않으며, 결과를 바꾸는 유일한 경로인 발주 거부가 위와 같이 9,250에서도 일어나지 않기 때문입니다.

결론: 상한 11과 예산 +1,500(10,750)까지 시도 2에 통과 조합은 없습니다.
상한 11의 통과 무관 최댓값이 10건·50원이고 목표는 12건·4,750원이므로 두 여유 수단 모두 이 시도를 목표 근처로도 끌어오지 못합니다.
계획의 중단 분기대로 §5의 여유 수단은 가장 어려운 영업에서 작동하지 않고, `hot_queue`는 구성(§5의 3단계) 재설계 대상이며 그 재설계는 승인 대상입니다.

#### slack 축소 (§4.4)

명세 §4.4는 수단을 다 쓴 뒤 재설계 전에 그 영업의 slack을 줄이라고 하므로, 재설계 판단 전에 같은 방법으로 두 slack을 쟀습니다.
가장 큰 값을 1 줄인 A는 `{"grill": 1, "soup": 1, "salad": 1}`, 그다음(모두 같으므로 `menu_ids` 순서로 첫 메뉴)인 B는 `{"grill": 0, "soup": 1, "salad": 1}`이며, 그다음 `{"grill": 0, "soup": 0, "salad": 1}`은 한 메뉴에만 폭이 있어 §4.4가 작성을 금하므로 B에서 멈춥니다.
slack마다 상한 6의 작성값에서 `--gate`를 읽고, 실패한 시도마다 상한 11에서 `--attempt N --purchases draw --items marinated_protein:3,prepped_vegetable:11,prepped_grain:11,soup_base:11 --best`를 돌렸습니다.
상한 11에서 통과가 0인 시도가 하나라도 있으면 그 slack은 상한 6–11 어디에서도 실현 불가능하므로 더 낮은 상한은 재지 않았습니다.
`.tres`는 스윕 뒤 `git checkout --`으로 되돌렸고 `git status --short`가 비어 있음을 이 절을 쓰기 전에 확인했습니다.

slack A의 게이트는 시도 1–5 전부가 `misses the targets`로 실패했고, 무계획은 모든 시도에서 제공 2건 이상 미달(8–9건 대 12건)이라 §4.2의 폭을 지킵니다.

| 시도 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 상한 11 조합 | 상한 11 통과 | 상한 11 통과 최댓값                                                         | 상한 11 통과 무관 최댓값                                                    |
| ---: | -------------: | -------------: | ----------: | ----------: | -----------: | -----------: | --------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
|    1 |             10 |          1,900 |           8 |        -850 |          531 |            0 | 없음                                                                        | `marinated_protein 2, soup_base 5` · 노동량 11 · 11 · 3,400                 |
|    2 |             10 |          1,050 |           9 |        -950 |          504 |            0 | 없음                                                                        | `marinated_protein 1, prepped_grain 2, soup_base 2` · 노동량 7 · 11 · 1,550 |
|    3 |             11 |          4,000 |           8 |      -1,450 |          531 |            0 | 없음                                                                        | `marinated_protein 1` · 노동량 3 · 11 · 4,000                               |
|    4 |             12 |          3,750 |           9 |        -750 |          498 |           59 | `marinated_protein 1, prepped_grain 3, soup_base 3` · 노동량 9 · 14 · 6,150 | 같음                                                                        |
|    5 |             10 |          2,900 |           8 |      -1,450 |          531 |            0 | 없음                                                                        | `marinated_protein 1, soup_base 2` · 노동량 5 · 11 · 3,400                  |

slack B의 게이트는 시도 1·2·5가 12건·4,750원으로 통과하고 시도 3·4가 실패했으며, 무계획은 모든 시도에서 제공 2건 이상 미달(7–9건)입니다.

| 시도 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 상한 11 조합 | 상한 11 통과 | 상한 11 통과 최댓값                                                          | 상한 11 통과 무관 최댓값                      |
| ---: | -------------: | -------------: | ----------: | ----------: | -----------: | -----------: | ---------------------------------------------------------------------------- | --------------------------------------------- |
|    1 |             12 |          4,750 |           8 |      -1,850 |              |              | 게이트 통과라 스윕 안 함                                                     |                                               |
|    2 |             12 |          4,750 |           9 |      -1,350 |              |              | 게이트 통과라 스윕 안 함                                                     |                                               |
|    3 |             11 |          4,000 |           7 |      -2,350 |          531 |            0 | 없음                                                                         | `marinated_protein 1` · 노동량 3 · 11 · 4,000 |
|    4 |             11 |          4,250 |           8 |      -1,850 |          498 |           17 | `marinated_protein 1, prepped_grain 4, soup_base 4` · 노동량 11 · 12 · 4,750 | 같음                                          |
|    5 |             12 |          4,750 |           8 |      -2,250 |              |              | 게이트 통과라 스윕 안 함                                                     |                                               |

시도 3은 위 탐침 스크립트로 찍은 시작 slack과 B에서 똑같이 구이 10·국 6·샐러드 4를 추첨하고(추첨 인지 발주 `grain 6, protein 10, vegetable 16`), A에서는 게이트 행(11건·4,000원, 무계획 8건·-1,450원)과 상한 11 스윕 요약(531가지, 최댓값 `marinated_protein 1` · 11 · 4,000)이 B와 같습니다.
따라서 이 시도를 떨어뜨리는 것은 구이 slack이 아니라 국 +1·샐러드 −1 이동이며, 국과 샐러드 둘 다에 폭이 있는 slack은 어느 것도 이 시도를 통과시키지 못합니다.
결론: 두 메뉴 이상에 폭이 있는 slack 가운데 상한 11 이하에서 시도 1–5를 모두 통과시키는 (slack, 상한) 쌍은 없습니다(A는 시도 1·2·3·5, B는 시도 3에서 통과 0).
따라서 §4.4의 slack 축소로도 `hot_queue`는 풀리지 않고, 위 결론대로 구성 재설계가 남은 유일한 수단입니다.

#### slack C·D (두 메뉴에 폭이 있는 나머지 둘)

위 A·B는 계획의 "가장 큰 값을 `menu_ids` 순서로 줄이기" 순서이고 §4.4가 금하는 것은 전부 0과 이동 불가 slack뿐이므로, 두 메뉴에 폭이 있는 나머지 둘도 같은 방법으로 쟀습니다.
C는 `{"grill": 1, "soup": 0, "salad": 1}`(구이–샐러드 사이 이동만), D는 `{"grill": 1, "soup": 1, "salad": 0}`(구이–국 사이 이동만)이며, 명령·상한·복원 확인은 A·B와 같습니다.

slack C의 게이트는 시도 1·2가 통과(13건·6,250원, 13건·5,150원)하고 시도 3·4·5가 실패했으며, 무계획은 모든 시도에서 제공 2건 이상 미달(7–8건)입니다.

| 시도 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 상한 11 조합 | 상한 11 통과 | 상한 11 통과 최댓값                                    | 상한 11 통과 무관 최댓값                               |
| ---: | -------------: | -------------: | ----------: | ----------: | -----------: | -----------: | ------------------------------------------------------ | ------------------------------------------------------ |
|    1 |             13 |          6,250 |           7 |      -3,350 |              |              | 게이트 통과라 스윕 안 함                               |                                                        |
|    2 |             13 |          5,150 |           8 |      -1,850 |              |              | 게이트 통과라 스윕 안 함                               |                                                        |
|    3 |             11 |          3,850 |           7 |      -2,350 |          498 |            0 | 없음                                                   | `marinated_protein 1` · 노동량 3 · 11 · 3,850          |
|    4 |              6 |         -3,850 |           8 |      -2,450 |          498 |            0 | 없음                                                   | `prepped_grain 3, soup_base 3` · 노동량 6 · 12 · 4,150 |
|    5 |              9 |           -850 |           8 |      -1,850 |          504 |            1 | `prepped_grain 1, soup_base 6` · 노동량 7 · 12 · 5,050 | `prepped_grain 1, soup_base 4` · 노동량 5 · 13 · 4,550 |

slack D의 게이트는 시도 1–5 전부가 실패했고, 무계획은 모든 시도에서 제공 2건 이상 미달(8–9건)입니다.

| 시도 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 상한 11 조합 | 상한 11 통과 | 상한 11 통과 최댓값 | 상한 11 통과 무관 최댓값                                                    |
| ---: | -------------: | -------------: | ----------: | ----------: | -----------: | -----------: | ------------------- | --------------------------------------------------------------------------- |
|    1 |             11 |          2,650 |           8 |      -1,850 |          498 |            0 | 없음                | `prepped_vegetable 10` · 노동량 10 · 11 · 3,250                             |
|    2 |             12 |          4,400 |           8 |      -1,850 |          542 |            0 | 없음                | `marinated_protein 1, prepped_grain 2, soup_base 2` · 노동량 7 · 12 · 4,400 |
|    3 |             10 |          3,350 |           8 |      -1,850 |          498 |            0 | 없음                | `marinated_protein 1, soup_base 3` · 노동량 6 · 11 · 3,850                  |
|    4 |             10 |          2,150 |           9 |      -1,550 |          498 |            0 | 없음                | `marinated_protein 1, prepped_grain 1, soup_base 3` · 노동량 7 · 11 · 3,650 |
|    5 |             11 |          2,300 |           8 |      -1,850 |          542 |            0 | 없음                | `marinated_protein 2, soup_base 5` · 노동량 11 · 12 · 3,800                 |

탐침 스크립트로 찍은 추첨은 C에서 시도 3이 구이 11·국 5·샐러드 4(발주 `grain 5, protein 11, vegetable 15`), 시도 4가 작성 구성과 같은 구이 10·국 5·샐러드 5이고, D에서 시도 1·4가 작성 구성 그대로, 시도 3이 구이 11·국 4·샐러드 5, 시도 2·5가 구이 9·국 6·샐러드 5입니다.
C의 시도 4와 D의 시도 1·4는 작성 구성과 건수가 같고 도착 순서만 다른데도 상한 11에서 통과 조합이 없으므로, 이 영업을 떨어뜨리는 것은 구성의 변동 폭이 아니라 같은 구성의 순서 변동 자체입니다.
결론: C는 시도 3·4, D는 시도 1–5에서 통과 0이므로 두 메뉴에 폭이 있는 네 slack(A·B·C·D) 어느 것도 상한 11 이하에서 시도 1–5를 모두 통과시키지 못하며, 가장 작은 실현 가능한 (slack, 상한) 쌍은 없습니다.
따라서 재설계는 구성 값(`order_recipe_ids`·`order_arrival_ticks`)을 순서 변동에 견디도록 바꾸는 것이어야 하고, 그 재설계는 승인 대상입니다.

#### 우선순위 지도와 실패 원인

위 스윕은 모두 우선순위를 기준 정책의 `{"grill": 2}`로 고정했는데 우선순위는 `hot_queue`의 지렛대(§4.3)이므로, 재설계 판단 전에 우선순위 지도 전체를 scratchpad 스크립트로 쟀습니다.
스크립트는 커밋하지 않았고 `"$GODOT_BIN" --headless --path <워크트리> --script <scratchpad>/priority_probe.gd`와 `... --script <scratchpad>/mechanism_probe.gd`로 돌렸으며, 캠페인을 읽어 `hot_queue`를 `duplicate()`한 뒤 `forecast_slack`과 `prep_labor_capacity`를 코드에서 넣고 `Policies.run_policy(scenario, policy, 1, seed)`를 직접 호출하므로 `.tres`는 건드리지 않았습니다(`git status --short`는 이 절 편집 전에 비어 있었습니다).
주문의 우선순위 기본값은 1입니다(`sim/service_sim.gd`의 `OrderState.priority = 1`, 도착 시 `_menu_priorities.get(recipe_id, 1)`), `set_priority`는 0–2만 받으며, `run_policy`는 정책의 `priorities`에 있는 메뉴마다 그 주문의 도착 tick + 1에 `set_priority`를 넣습니다.
지도는 세 메뉴 × {0, 1, 2}의 27가지이고 `{1, 1, 1}`이 "우선순위 없음"과 같으며, 프렙 집합은 기준 프렙 `marinated_protein 1, prepped_vegetable 3`과 상한 안에서 노동량을 나눈 7가지(상한 6: `marinated_protein 1, prepped_grain 1, soup_base 1, prepped_vegetable 1` / `marinated_protein 2` / `soup_base 3, prepped_grain 3` / `marinated_protein 1, soup_base 3` / `marinated_protein 1, prepped_grain 3` / `prepped_vegetable 6` / `soup_base 2, prepped_grain 2, prepped_vegetable 2`, 상한 11: `marinated_protein 1, prepped_grain 4, soup_base 4` / `marinated_protein 2, soup_base 5` / `marinated_protein 3, prepped_vegetable 2` / `prepped_grain 4, soup_base 4, prepped_vegetable 3` / `marinated_protein 1, prepped_grain 2, soup_base 2, prepped_vegetable 4` / `marinated_protein 2, prepped_grain 2, soup_base 3` / `soup_base 5, prepped_grain 5`)로, 해당 상한 11 스윕이 통과 행을 하나도 찍지 않아 상위 8행을 가져올 수 없었기 때문입니다.
발주는 그 시도의 추첨 인지 발주로 고정했고, 경우마다 27 × 8 = 216쌍이 전부 수락됐습니다.

| 경우                   | 시도 | 상한 |  쌍 | 통과 | 최고 (지도 grill·soup·salad / 프렙 / 제공 / 손익)                        |
| ---------------------- | ---: | ---: | --: | ---: | ------------------------------------------------------------------------ |
| 시작 slack `{2, 1, 1}` |    2 |    6 | 216 |    0 | 0·1·0 / `marinated_protein 1, prepped_vegetable 3` / 12 / 650            |
| 시작 slack `{2, 1, 1}` |    2 |   11 | 216 |    0 | 0·0·1 / `prepped_grain 5, soup_base 5` / 12 / 1,250                      |
| slack B `{0, 1, 1}`    |    3 |    6 | 216 |    0 | 1·0·0 / `marinated_protein 1, prepped_vegetable 3` / 11 / 4,000          |
| slack B `{0, 1, 1}`    |    3 |   11 | 216 |    0 | 1·0·0 / `marinated_protein 1, prepped_vegetable 3` / 11 / 4,000          |
| slack C `{1, 0, 1}`    |    3 |   11 | 216 |    0 | 1·0·0 / `marinated_protein 1, prepped_vegetable 3` / 11 / 3,850          |
| slack C `{1, 0, 1}`    |    4 |   11 | 216 |    0 | 1·0·0 / `marinated_protein 1, prepped_grain 4, soup_base 4` / 12 / 4,150 |

어느 경우에도 통과 쌍이 없으므로 시도별 검사는 돌릴 대상이 없었습니다(수치는 `priority-probe.log`).
시도 2에서 12건은 우선순위로 닿지만 그 12건은 국·샐러드로 채워져 손익이 650·1,250에 그치고, 시도 3은 어떤 지도로도 11건이 최대입니다.

실패 원인은 시드 0 기준 실행과 시작 slack 시도 2 기준 실행(둘 다 상한 6, 추첨 인지 정책)의 최종 스냅샷으로 읽었습니다(수치는 `mechanism-probe.log`).
시드 0은 구이 7 제공·3 만료, 국 0 제공·5 만료, 샐러드 5 제공으로 12건·매출 13,000·손익 4,750이고, 시도 2는 구이 3 제공·6 만료, 국 1 제공·4 만료, 샐러드 5 제공·1 만료로 9건·매출 7,900·손익 -450입니다.
대기 사유 합계(`metrics.orders`)는 시드 0이 `no_responsible_employee` 3,327·`station_in_use` 143·`moving` 1,325·`working` 4,150, 시도 2가 3,288·392·1,295·3,855이고 `missing_ingredients`는 둘 다 0이며, 화구 `hot_01`의 예약 tick은 시드 0 2,705, 시도 2 2,495(영업 3,000 tick)입니다.
도착 tick은 추첨과 무관하게 고정이라 두 온식(구이·국, `cook_role = "hot"`) 주문이 같은 tick에 오는 것은 두 실행 모두 10과 700뿐이며, 시드 0의 작성 순서는 그 밖의 모든 쌍에서 온식 하나에 냉식(샐러드) 하나를 붙입니다.
시도 2가 무너지는 지점은 700 파동입니다: 시드 0에서는 700에 같이 온 국 6·구이 7 가운데 구이가 1140에 제공되고 국이 만료되는데, 시도 2에서는 같은 700의 국 6이 1135에 제공되고 구이 7이 1200에 만료됩니다.
두 실행의 차이는 그 앞 상태뿐입니다: 시드 0은 400의 구이 5가 855까지 화구를 쓰고 있어 700에 온식이 바로 들어갈 수 없지만, 시도 2는 270·400이 둘 다 샐러드여서 구이 3이 끝난 585부터 화구가 비어 있고, 700 도착 시점의 두 주문은 우선순위가 모두 기본값 1이며 구이의 우선순위 2 명령은 701에야 적용되므로(`run_policy`의 `apply_tick = tick + 1`) 빈 화구 앞의 첫 배정을 우선순위가 가르지 못하고 준비가 짧은 국(60 대 90 tick)이 먼저 화구에 들어갑니다.
이어서 구이 9(960)가 1460에, 국 10·11과 1390 파동의 샐러드 12까지 만료되고(두 직원이 모두 묶여 `no_responsible_employee`), 1520·1650·1780에 연달아 온 구이 13–15는 한 화구에서 조리 240 tick씩 720 tick이 필요해 인내 500 tick 안에 하나도 끝나지 않습니다(시드 0의 같은 자리 구이·국·구이도 셋 다 만료라 이 구간은 순서와 무관한 손실입니다).
손익 산술도 여유가 없습니다: 시드 0의 통과는 구이 7 × 1,500 + 샐러드 5 × 500 = 13,000에서 발주 6,250·인건비 2,000을 뺀 4,750으로 정확히 목표이고, 시도 2는 추첨 인지 발주가 채소 16으로 6,350이라 같은 조합이라도 4,650으로 미달이며, 4,750에는 매출 13,100 이상, 곧 구이 7에 국 하나를 더하거나 구이 8이 필요한데 그것은 화구 하나가 순서 바뀐 열에서 끝낼 수 있는 온식 작업량을 넘습니다.
따라서 순서가 바뀐 추첨이 실패하는 이유는 화구 하나의 온식 처리량이 목표에 딱 맞게 잡혀 있어(시드 0 여유 0) 온식 두 건이 같은 파동에 오거나 온식이 연달아 오는 순서마다 한 건씩 잃기 때문이고, 우선순위 지도는 도착 tick 다음 tick에 적용되므로 빈 화구를 잡는 첫 배정을 바꾸지 못합니다.

### 2026-09-21 재조율: `shared_stock`

[압력 영업 재조율 계획](../plans/pressure-rebalance-implementation.md) Task 4의 기록이며, 같은 커밋이 [명세 §4.3](../specs/pressure-rebalance.md)의 지렛대 게이트를 `tests/test_m3_playthrough.gd`에 넣습니다.
지렛대는 `tests/fixtures/m3_policies.gd`의 `LEVER_KINDS`가 영업 ID별 명령 종류 목록으로 소유하고, 게이트는 두 층입니다: 기준 정책에서 지렛대 명령만 뺀 정책(`without_lever_policy`)이 시드 0에서 목표에 미달해야 하고, `--without <지렛대> --best` 스윕이 찾은 가장 강한 무지렛대 정책(`lever_free_policy`)도 미달해야 합니다.
값의 권위는 `.tres`와 `m3_policies.gd`이고, 이 절은 그 값을 고른 측정만 남깁니다.

#### 계획 작성 시점의 지렛대 측정

계획이 이 Task를 쓰기 전에 잰 값으로, 위 `reference_policy`에서 지렛대 종류를 뺀 정책을 `--import` 뒤 scratchpad 탐침으로 시드 0에서 한 번씩 돌린 것이며 탐침 스크립트는 커밋하지 않았습니다.
이 커밋의 `M3_LEVER` 줄은 `shared_stock`을 뺀 네 영업에서 같은 값을 다시 찍었습니다(그 네 영업의 `lever_free_policy`는 아직 스윕하지 않아 지렛대를 뺀 기준 정책이 그 자리를 채웁니다).

| 영업           | 뺀 종류                        | 제공 |  손익 | 판정                                    |
| -------------- | ------------------------------ | ---: | ----: | --------------------------------------- |
| `hot_queue`    | `priorities`                   |    9 |  -950 | 미달                                    |
| `shared_stock` | `set_purchase`                 |   18 | 4,700 | 통과(뺀 정책이 기준과 같아 게이트 실패) |
| `long_route`   | `move_station, rotate_station` |   15 | 4,500 | 미달                                    |
| `split_duties` | `set_duty`                     |   21 | 5,550 | 미달                                    |
| `rush_hour`    | `set_prep, priorities`         |   21 | 4,650 | 미달                                    |

게이트를 넣고 `.tres`를 바꾸기 전의 `check.sh m3`는 1,136개 검사 가운데 5개가 실패했습니다: `shared_stock`의 `uses its lever`와 `misses a target without its lever`(뺀 정책이 기준과 같음), `_compare_choices`의 `purchases` 변형 둘(작성 재고 31이 시드 0 필요량과 같아 `set_purchase vegetable 31`이 아무것도 바꾸지 않음), 그리고 `long_route`의 `misses a target without its lever ["rotate_station"]`입니다.
마지막 것은 계획 밖의 발견입니다: 게이트 초안은 `LEVER_KINDS`의 종류마다 따로 뺀 정책을 검사했는데, `long_route`의 기준 정책은 `rotate_station`만 빼도 22건·13,700원으로 기준과 회계가 같습니다(회전은 해시만 바꿉니다; `move_station`만 빼면 10건·-1,500원, 둘 다 빼면 위 표의 15건·4,500원).
명세 §4.3 표는 배치를 두 명령 종류로 이루어진 한 지렛대로 적으므로, 게이트는 `PLACEMENT_KINDS`(`move_station`·`rotate_station`)를 한 지렛대로 묶어 빼고 지렛대가 둘인 영업(`rush_hour`)만 지렛대별과 전체를 따로 검사합니다.
`long_route`의 기준 정책과 값은 이 커밋에서 바뀌지 않았고, 회전이 회계를 바꾸지 않는다는 사실은 Task 8의 재조율이 볼 몫입니다.

#### 발주 지렛대와 시작 slack

시드 0 필요량은 레시피 재료 사전에서 셈합니다: 채소 31(샐러드 5 × 1 + 수프 9 × 2 + 현미 샐러드 4 × 1 + 양송이 샐러드 4 × 1), 현미 13, 양송이 4.
작성 `purchases`가 이 필요량과 정확히 같아 발주 명령이 결과를 바꿀 수 없었으므로, 작성 채소를 31에서 20으로 줄이고 기준 정책 앞에 `set_purchase vegetable 31`을 두었습니다.
`set_purchase`는 그 재료의 작성 수량을 덮어쓰므로(`sim/preparation_plan.gd`), 기준 정책의 31은 시드 0 필요량 이상이어야 `draw_aware_policy(scenario, 0)`가 기준 발주와 같다는 Task 1의 항등이 성립하며 31이 그 최솟값입니다.
`forecast_slack`은 `menu_ids` 줄 앞에 `{"salad": 1, "soup": 1, "grain_salad": 1, "mushroom_salad": 1}`로 넣었고, 기준 건수 5·9·4·4에서 `max(1, 기준 건수 / 5)`는 네 메뉴 모두 1이므로 이 값이 §4.4의 시작값이자 `test_service_seed.gd`가 허용하는 상한입니다.
작성 채소가 줄어 무계획은 시드 0에서 15건·2,300원에서 11건·400원으로 내려갔고(`missing_ingredients` 3,500 tick), 이 값이 `_compare_choices`의 `purchases` 변형이 비교하는 바탕입니다.

이 상태의 게이트(`--gate`, 상한 9, 기준 프렙 `prepped_grain 1, soup_base 6, prepped_mushroom 2`)는 시드 0에서 18건·4,700원으로 이전과 같고 시도 2·3·4·5가 `misses the targets`로 실패했습니다.

| 시도 |       시드 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 판정 |
| ---: | ---------: | -------------: | -------------: | ----------: | ----------: | ---- |
|    0 |          0 |             18 |          4,700 |          11 |         400 | 통과 |
|    1 | 2175864408 |             19 |          5,200 |          10 |        -550 | 통과 |
|    2 | 2226197265 |             15 |          2,350 |          10 |         -50 | 미달 |
|    3 | 2209419646 |             16 |          3,100 |          11 |         650 | 미달 |
|    4 | 2259752503 |             17 |          3,600 |           8 |      -1,550 | 미달 |
|    5 | 2242974884 |             17 |          3,400 |          11 |         400 | 미달 |

실패 문장에 `insufficient_budget`은 없었으므로 §5의 예산 수단은 쓰지 않았습니다(작성 채소를 줄여 남은 예산은 커졌지만 추첨 인지 발주의 채소는 어느 시도에서도 31 이상이라 그 여유는 게이트에 닿지 않습니다).

#### 프렙 스윕과 상한

공통 절차 4대로 시도 0–5 각각에 `"$GODOT_BIN" --headless --path <워크트리> --script tests/sweep_policies.gd -- --scenario shared_stock --attempt N --purchases draw --items prepped_grain:C,soup_base:C,prepped_mushroom:C,prepped_vegetable:C --best`를 돌리고(`C`는 그때의 상한과 같게 두어 `--items`가 상한보다 먼저 묶이지 않게 했습니다), 여섯 시도의 `SWEEP` 줄에서 수량 조합의 교집합을 scratchpad의 파이썬 스크립트로 구했습니다.
상한은 §5의 첫 수단이므로 9에서 1씩 올렸고, 값마다 여섯 시도를 다시 돌렸습니다.

| 상한 | 시도 0 조합·통과 | 시도 1 통과 | 시도 2 통과 | 시도 3 통과 | 시도 4 통과 | 시도 5 통과 | 교집합 | 시도 5 최고                                    |
| ---: | ---------------: | ----------: | ----------: | ----------: | ----------: | ----------: | -----: | ---------------------------------------------- |
|    9 |           645·14 |         174 |           7 |           7 |           3 |           1 |      0 | `prepped_mushroom 2, soup_base 7` · 18 · 4,300 |
|   10 |           875·50 |         322 |          26 |          41 |          19 |           7 |      0 | `prepped_mushroom 2, soup_base 7` · 18 · 4,300 |
|   11 |        1,155·128 |         535 |          76 |         123 |          58 |          26 |      1 | `prepped_grain 6, soup_base 5` · 18 · 4,500    |

상한 11의 교집합은 `prepped_grain 5, soup_base 6`(노동량 11) 하나이고, 시도 0–5의 제공은 19·18·19·18·18·18, 손익은 5,600·4,450·5,450·4,750·4,500·4,300입니다.
이 조합을 기준 프렙으로 두면 시드 0의 §4.1 여분은 제공 +2·손익 +1,600으로 2건·3,000원 안에 들고, 무계획 미달 폭은 모든 시도에서 제공 6건 이상이므로 공통 절차 6·7의 목표 상향은 필요하지 않았습니다(목표 17건·4,000원 유지).
확정값(권위는 `content/campaign/scenarios/shared_stock.tres`): 작성 `purchases` 채소 31 → 20(현미 13·양송이 4 유지), `forecast_slack` 없음 → 1·1·1·1, `prep_labor_capacity` 9 → 11, `starting_budget` 9,250과 목표 17건·4,000원은 그대로입니다.

최종 게이트(`--gate`)는 `passed: true`이고 실패 문장이 없습니다.

| 시도 |       시드 | 추첨 인지 제공 | 추첨 인지 손익 | 무계획 제공 | 무계획 손익 | 판정 |
| ---: | ---------: | -------------: | -------------: | ----------: | ----------: | ---- |
|    0 |          0 |             19 |          5,600 |          11 |         400 | 통과 |
|    1 | 2175864408 |             18 |          4,450 |          10 |        -550 | 통과 |
|    2 | 2226197265 |             19 |          5,450 |          10 |         -50 | 통과 |
|    3 | 2209419646 |             18 |          4,750 |          11 |         650 | 통과 |
|    4 | 2259752503 |             18 |          4,500 |           8 |      -1,550 | 통과 |
|    5 | 2242974884 |             18 |          4,300 |          11 |         400 | 통과 |

#### 지렛대 스윕과 정책

`... --scenario shared_stock --attempt 0 --without set_purchase --items prepped_grain:11,soup_base:11,prepped_mushroom:11,prepped_vegetable:11 --best`는 조합 1,140 가운데 통과 0이고, 통과 무관 최댓값은 `prepped_grain 6, soup_base 5` · 노동량 11 · 15건 · 3,700원입니다.
작성 채소 20으로는 프렙을 어떻게 두어도 17건에 닿지 못합니다: 샐러드·현미·양송이 샐러드 13건이 채소 13을 쓰고 남는 7로 수프 3건이 최대라 16건이 상한입니다.
이 최댓값이 `lever_free_policy("shared_stock")`에 고정됐고, `M3_LEVER shared_stock` 줄은 15건·3,700원을 찍습니다.
이 커밋부터 위 스윕 절의 `--keep purchases` 토큰은 `shared_stock`에서 실제 의미를 가지며(기준 정책의 `set_purchase vegetable 31`을 남기거나 뺍니다), 그 절의 "기준 정책에 발주 명령이 없어" 문장은 이 영업에는 더 이상 맞지 않습니다.

정책 변경(권위는 `tests/fixtures/m3_policies.gd`):

| 정책   | 이전                                                     | 이후                                                             | 시드 0     |
| ------ | -------------------------------------------------------- | ---------------------------------------------------------------- | ---------- |
| 기준   | prepped_grain 1, soup_base 6, prepped_mushroom 2 · 9/9   | set_purchase vegetable 31 + prepped_grain 5, soup_base 6 · 11/11 | 19 · 5,600 |
| 대체 A | set_purchase vegetable 29 + prepped_grain 4, soup_base 4 | 같음(29가 작성 20을 덮어쓰므로 결과가 이전과 같음)               | 17 · 4,150 |
| 대체 B | soup 우선순위 2                                          | set_purchase vegetable 31 + soup 우선순위 2                      | 17 · 4,450 |

세 정책의 해시는 쌍별로 다르고 1배·4배 해시가 같으며, `_compare_choices`의 `purchases` 변형은 이제 무계획(11건)에 기준 정책의 발주 명령만 더해 15건·2,300원이 나오므로 발주가 제공 건수를 바꿉니다.
`GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot bash scripts/check.sh m3`는 1,132개 검사를 실패 없이 통과했고(`long_route`의 배치 두 종류를 한 지렛대로 묶어 종류별 갈래 둘이 빠지면서 위 실패 실행의 1,136에서 4개 줄었습니다), `... check.sh mise`는 355개를 통과했습니다.
스윕 로그·교집합 스크립트·탐침은 세션 scratchpad에만 있고 커밋하지 않았습니다.

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
