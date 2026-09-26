# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) owns the product invariants, layer boundaries, fixed-tick contract, simulation and persistence rules, and milestone discipline.
This file adds only the commands and the cross-file structure that `AGENTS.md` does not state.

## Commands

Godot must match `.godot-version` exactly; `scripts/check.sh` refuses any other build.
Set `GODOT_BIN` to that binary when `godot` on `PATH` is missing or a different version.
On a Linux x86_64 container (CI, Codex Cloud), `bash setup.sh` installs the pinned Godot and the other check tools; it refuses to run on macOS (see `README.md`).

```bash
"$GODOT_BIN" --path .                 # run the game (main scene: presentation/campaign.tscn)
bash scripts/check.sh <suite>         # import, then run one suite headless; default suite is m0
```

A suite passes only when its log ends with `PASS: <suite> checks=N failures=0` and contains no `SCRIPT ERROR:`, `ERROR:` or `FAIL:` line; logs land in `build/check/<suite>.log`.
Suite names and their entry scripts are registered in `tests/run_tests.gd` (`SUITES`); each entry script lists its child test files, so a single test file runs through the parent suite that includes it.

CI (`.github/workflows/check.yml`) is the full gate; its step list is the source of truth for the local gate order.
It runs every registered suite except `ui-regressions`, the Python checks under `tests/`, and `bash scripts/check-export.sh`, which needs the matching export templates.

Lint and format run through Trunk (`.trunk/trunk.yaml`): `trunk check` and `trunk fmt`, also installed as pre-commit and pre-push hooks.
GDScript is formatted by `gdformat` and linted by `gdlint` (settings in `gdformatrc` and `gdlintrc`); CI runs neither, so the Trunk hooks are their only gate.
`trunk.yaml` excludes `tests/fixtures/content_limits.gd` from `gdformat`, and its comment says why.

Balance tooling runs as a standalone `SceneTree` script, for example `tests/sweep_policies.gd`; its usage lives in `docs/notes/kitchen-pressure-verification.md`.

## Structure that spans files

- `presentation/campaign.tscn` (`campaign_screen.gd`) is the app root. It owns `CampaignStore`, `CampaignProgress` and `AppPreferences`, instances the service screen `presentation/main.tscn` (`main.gd`) per service, and writes a save whenever the service screen emits `checkpoint_requested(reason)` (`automatic` every 100 ticks, `preparation`, `pause`).
- `main.gd` drives `sim/service_sim.gd` through `presentation/tick_driver.gd` and submits commands; `platform/app_lifecycle.gd` (a child node of `main.tscn`) emits `backgrounded`, which pauses the service and requests the `pause` checkpoint.
- Static content is `Resource` data under `content/` (`campaign/`, `scenarios/`, `recipes/`, `ingredients/`, loaded through `content/campaign_def.gd`); per-attempt order menus come from `content/schedule_generator.gd` using the scenario's `forecast_slack` and a seed.
- `persistence/campaign_store.gd` owns the save document and its version stamp (`VERSIONS`: schema, content and sim versions) plus the readable older versions. `persistence/service_session.gd` serializes an in-progress `ServiceSim`, and every read re-validates it with `ServiceSession.restore` unless that store has already accepted the identical session under identical records (`_session_restores`); the caller's session in a save always gets a full restore.
- Save compatibility across content versions depends on the hand-maintained tables `LEGACY_COMPLETION_TARGETS` and `LEGACY_PROFIT_CAPS` in `sim/campaign_progress.gd`. A content change that lowers a cap or changes a target without a matching entry makes old saves load as corrupt.
- Pressure-service balance is guarded by fixtures in `tests/fixtures/` (`m3_policies.gd` reference and lever-free policies, `seed_gate.gd`) checked by the `m3` and `mise` suites; `docs/specs/pressure-rebalance.md` owns the rules.

## Gotchas

- `Array.duplicate(true)` does not copy `Resource` elements, so mutating a scenario from a duplicated campaign pollutes the cached resource for later suites in the same process; load mutable fixtures with `ResourceLoader.CACHE_MODE_IGNORE_DEEP`.
- `dict.key = value` stores a `StringName` key, which `ServiceSession` rejects; write `dict["key"] = value` for anything that reaches a session.
- Assigning an untyped dictionary literal to a typed exported dictionary through `resource.set(...)` silently leaves it empty; assign a typed local instead.
- `Dictionary ==` ignores key order, so a test that stores an order as dictionary keys (the campaign order in `tests/fixtures/content_limits.gd`) must also compare `keys()`.
