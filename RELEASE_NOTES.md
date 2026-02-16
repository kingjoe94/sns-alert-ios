# Release Notes

## v0.1.2 (2026-02-16)

### Included
- Fixed post-reset no-block regression by normalizing per-app limit keys (`tokenKey` and `idx_<index>`) across app and monitor extension.
- Changed unsynced threshold-ignore behavior to a bounded grace window so threshold checks recover after the window ends.
- Restricted sync-failure simulation branches to `#if DEBUG` paths only.

### Validation Snapshot
- Local `swift test --scratch-path .build/.swiftpm`: pass (9 tests, 0 failures).
- Real-device focused verification: block triggered at 2-minute and 4-minute limits, and re-block after reset also passed.

### Remaining Validation
- Full manual regression (`TC-01` to `TC-13`) is still required before release.

## v0.1.1 (2026-02-13)

### Included
- Stabilized monitoring/reset behavior across app and extensions.
- Maintained per-app limit mapping via stable `limit_idx_<index>` event names.
- Unified user-facing error messages for permission, monitor start, and sync failures.
- Added pure logic tests (`UsageMonitorLogic`) for reset anchor and threshold-guard behavior.
- Added CI gate with `logic-test` -> `build` in GitHub Actions.
- Expanded `REGRESSION_TEST.md` with fixed scenarios and error-display checks.

### Validation Snapshot
- GitHub Actions `iOS Build Check #5`: Success (`logic-test`, `build`)
- Local `swift test --scratch-path .build/.swiftpm`: 9 tests passed, 0 failed

### Remaining Validation
- Real-device manual regression (`TC-01` to `TC-13`) should be executed per `REGRESSION_TEST.md`.

## Operational Update (2026-02-13)

### Included
- Added `AGENTS.md` as the repository operation policy for Codex-driven development.
- Defined fixed workflow, implementation constraints, test policy, and reporting format.
- Added mobile release gates (iOS-first, Android-future) and security/privacy baseline.
