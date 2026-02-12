# Release Notes

## v0.1.0 (2026-02-13)

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
