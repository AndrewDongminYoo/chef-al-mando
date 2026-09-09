# Project Instructions

## Scope

These instructions apply to the complete `chef-al-mando` repository.
Follow the global operator rules in addition to this file.

## Sources of Truth

Use [docs/plans/PLAN.md](docs/plans/PLAN.md) as the product and technical baseline.
Use `README.md` as the concise project entry point.
Use an approved milestone specification as the implementation contract for that milestone.

If the code and the blueprint conflict, report the conflict.
Do not silently change the blueprint or reinterpret the code as the new requirement.

Blueprint approval does not authorize source implementation.
Until an M0-M1 implementation specification is approved, limit project work to authorized documentation and read-only investigation.

If a request changes a locked product direction or architecture boundary, update the blueprint only after explicit approval.
Do not start the changed implementation before that approval.

## Current Baseline

The approved product is an offline 2D kitchen-management simulation for iOS and Android phones and tablets.
The primary view is landscape and top-down.
The campaign uses fixed scenarios.
Employees can pass through each other.
The player can pause the simulation at any time.

The repository has the M1 service loop, M2 preparation and analysis, the M3 campaign, and M4 session persistence, localization, and settings.
It also has a lifecycle adapter, local checks, and mobile export presets.
Use [the M4 verification record](docs/notes/m4-verification.md) for current local evidence and deferred acceptance checks.
The `project.godot` file declares the `4.7` feature tag and the `GL Compatibility` renderer.
The M0 implementation specification pins the Godot version recorded in `.godot-version` and the matching export templates.
Use [the M0 verification record](docs/notes/m0-verification.md) to distinguish local checks from physical-device evidence.

On 2026-09-07, the operator approved M0 preparation before an Android reference device is available.
After the initial iPhone observations, the operator also approved M1 implementation while Android physical-device verification remains deferred.
Instrumented input-count verification on iPhone remains pending.
This exception permits M1 implementation and its available local, export, and iPhone checks.
M0 approval and full M1 acceptance still require the deferred Android physical-device evidence.

On 2026-09-08, the operator approved the final M1 iPhone build and [the M2 specification](docs/specs/m2-preparation.md).
This approval permits M2 implementation while Android physical-device verification remains deferred.
It includes preparation, placement, result analysis, representative art, and available local, export, and iPhone checks.
It does not establish full M0 or M1 acceptance or the M2 user-test result.

On 2026-09-08, the operator merged M3 PR #6 and requested the next milestone through subagent TDD and the PR loop.
This approval permits [M4 implementation](docs/specs/m4-mobile.md), local verification, PR review, and merge after the required checks pass.
Android physical-device verification and the five-user test remain deferred.
This scope does not authorize device writes or establish full M4 physical-device acceptance.

The M0-M1 specification defines the exact stable Godot version, the matching export-template version, the reference iPhone, the three menu fixtures, the 20-order fixture, and the exact local and CI verification commands.
The reference Android device is not defined yet.
The 2026-09-07 exception above permits M1 work while the Android device and its verification remain pending.

The operator approved the [M4 PR split](docs/plans/m4-pr-split.md) on 2026-09-09.
Submit storage core first and presentation integration as a dependent PR.
Keep original PR #7 as a draft until both replacement PRs are confirmed merged.

## Product Invariants

- Make preparation and operational decisions the main source of mastery.
- Keep real-time play with pause and `1x`, `2x`, and `4x` speed controls.
- Show a readable reason whenever an employee or order waits.
- Use scenario-specific starting budgets and inventory.
- Preserve completion records and best results.
- Do not let previous failures make later scenarios impossible.
- Treat 6,600 KRW as an unvalidated pricing hypothesis.
- Treat v1 content counts as caps and initial targets.
- Reduce content when M2 evidence shows that production cost is too high.
- Do not promise playtime before measurement.

Do not add these excluded systems to v1:

- Advertisements, in-app purchases, energy, gacha, login rewards, or mandatory accounts.
- Servers, multiplayer, cloud synchronization, or online-only behavior.
- Multi-location management, open worlds, or procedural campaigns.
- Free-form recipe editing or real-recipe imports.
- Employee relationships, personal stories, or a complex fatigue model.
- Equipment failures, fires, or maintenance systems.
- Dining-room seating, serving NPCs, POS, taxes, wage negotiation, or ERP features.
- PC-store, web, or console distribution promises.

## Architecture Boundaries

Use Godot 4.x Standard and typed GDScript.
Start with the Compatibility renderer.
Verify both mobile platforms on physical devices.

Use these layer responsibilities:

- `sim/` owns time, orders, work assignment, inventory, movement progress, and accounting.
- `content/` owns static menu, ingredient, station, employee, and scenario definitions.
- `presentation/` owns scenes, animation, audio, input, and read-only state display.
- `persistence/` owns snapshot versions, validation, backup, replacement, and recovery.
- `platform/` owns application lifecycle, safe-area behavior, and export integration.
- `tests/` owns headless rule, determinism, persistence, path, and content checks.
- `docs/` owns plans, specifications, and implementation notes.

Build the simulation from `RefCounted` objects that can run without a `SceneTree`.
Do not build an engine-independent library.
Keep static definitions in `Resource` objects.
Keep runtime state in separate objects.

The presentation layer submits commands and consumes read-only state and events.
It must not decide simulation outcomes.
Animation completion must not decide cooking completion.

Do not add an engine fork, Rust FFI, ECS, a general-purpose framework, a custom content editor, or spreadsheet automation without measured evidence and explicit approval.

## Fixed-Tick Contract

Use a 100 ms game-time tick initially.
Change the number of executed ticks for speed controls.
Do not change the tick size.

Process each tick in this order:

1. Apply commands.
2. Process order arrivals and expirations.
3. Complete work and settle consumption.
4. Assign new work.
5. Update movement.
6. Publish events.

Attach an application tick and a sequence number to every command.
Expire an order at its deadline before processing work completion on the same tick.
Do not award revenue to an order in a terminal state.

Use integer progress for movement.
Interpolate only in the presentation layer.
Do not discard simulation ticks when processing falls behind.
Let real-time progress slow until profiling supports a per-frame processing cap.

Determinism requires a fixed seed, command order, iteration order, and PRNG state.
The compatibility boundary is the same engine, content, and simulation version.
Cross-update replay compatibility is not a v1 goal.

## Simulation Rules

### Orders and Accounting

- Use integer quantities for ingredients.
- Use integer minor currency units for money.
- End the service at game-time second 300.
- Mark unfinished orders as unserved at closing.
- Do not restore consumed ingredients at closing.
- Calculate service profit as served revenue minus purchased ingredient cost minus fixed labor cost.
- Do not subtract waste cost a second time.

### Ingredients and Work

- In M1, reserve all raw ingredients when an order starts.
- Consume required ingredients exactly once when the applicable process starts.
- Release reservations when the player cancels before a process starts.
- Preserve consumed-ingredient loss when the player cancels after a process starts.
- Use linear processes in the initial implementation.
- Allow one active task per employee.
- Allow one active task per station.
- Apply assignment order as player priority, order deadline, and stable work ID.
- Apply a responsibility change after the current process finishes.
- Make station reservation and ingredient validation one atomic assignment operation.

Report waiting with one of these reasons:

- Missing ingredients.
- No responsible employee.
- Station in use.
- No route.

### Movement and Placement

- Use a rectangular four-direction grid.
- Allow equipment placement changes only during preparation.
- Use `AStarGrid2D` for static-obstacle pathfinding only.
- Let employees pass through each other.
- Keep station work positions exclusive.
- Do not reserve corridor tiles.
- Reject placements that make a station unreachable.
- Release reservations after a runtime path failure.
- Show the path-failure reason to the player.

## Content and Persistence

Use stable string IDs for `IngredientDef`, `RecipeDef`, `StationDef`, `EmployeeDef`, and `ScenarioDef` references.
Reject duplicate IDs, missing references, negative quantities, non-positive process durations, process cycles, missing station roles, and scenarios that cannot sell their configured menus.

The save schema must include `schema_version`, `content_version`, `sim_version`, the current tick, PRNG state, active orders, employees, tasks, inventory, reservations, movement progress, and campaign records.
Validate every enum and ID during load.
Do not overwrite a save from an unknown future version.

Write saves only at safe tick boundaries.
Write and validate a temporary file before replacing the primary save.
Keep the last valid backup.
Offer backup recovery or scenario restart after corruption.
Do not silently reset corrupt data.

M1 supports scenario restart only.
Complete mid-service resume in M4.

## UI and Platform Rules

- Keep the kitchen central.
- Keep the order list in a side panel.
- Keep time controls in a fixed location.
- Use a collapsible detail panel on phones.
- Use parallel panels on tablets.
- Do not implement tablets as a scaled-up phone layout.
- Use tap-based priority controls.
- Do not require drag-only interaction.
- Combine color with icons and text.
- Validate text size, safe areas, and Korean line breaks.
- Pause automatically when the app enters the background.
- Do not resume service automatically when the app returns to the foreground.

Do not adopt an isometric view without a separate M2 evaluation and explicit approval.

## Milestone Discipline

Start a milestone only after the previous milestone has fresh passing evidence, except for the approved milestone exceptions in the blueprint.
On 2026-09-08, the operator approved M3 specification and implementation while deferring the five-user M2 validation.
Resume that validation only when the operator explicitly says the build is ready for user testing.
Do not recruit participants or treat this exception as an M2 pass.
The existing Android physical-device deferral remains in effect.
Do not mark a milestone complete because the project parses or launches on desktop.
Record what each gate inspects and obtain evidence for the property that the milestone protects.

Before M1 passes, do not start campaign expansion, branding, content automation, corridor reservation, or architecture generalization.
If M0 or M1 misses its initial seven-workday budget, identify whether deployment, rule design, or learning cost caused the miss.
Do not change the engine unless an engine-specific blocker is reproducible.

For simulation changes, test at least:

- Duplicate work assignment.
- Double ingredient consumption.
- Deadline and completion collision.
- Reservation release after cancellation.
- Closing accounting.
- Repeated fixed-seed command logs with final-state hash comparison.
- Equivalent results at `1x` and `4x` for the same game ticks.

For persistence, path, content, or platform changes, run the matching gates in the blueprint.
If the repository does not yet define an exact command, report `[UNKNOWN]`.
Do not claim that the gate passed.

## Documentation and Change Scope

Write product documentation and user-visible copy in Korean unless a specific artifact requires English.
Keep code identifiers and commit messages in English.
Use English for agent-facing technical instructions such as this file.

Keep `README.md` concise.
Keep the complete product and technical contract in `docs/plans/PLAN.md`.
Write milestone specifications in `docs/specs/`.
Write temporary implementation notes in `docs/notes/` only when the work needs a durable note.

Preserve the smallest shippable milestone.
Do not refactor adjacent code or expand the product while implementing a bounded requirement.
