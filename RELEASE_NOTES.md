# Release Notes

## Unreleased (2026-02-19)

### Included
- Added per-app continuous-usage notification settings (`連続通知`) with default `OFF`.
- Implemented monitor-side continuous session tracking:
  - updates streak on each `usage_idx_*` minute event
  - resets session on app switch, long gap (>120s), reset, and monitoring stop/start
  - sends local notification when per-app threshold is reached
- Set notification cooldown to the same value as each app's threshold.
- Fixed false post-reset blocking risk in `limit_idx_*` handling by keeping threshold ignores active until a real usage signal is observed.
- Added logic tests for:
  - continuous session reset decision
  - continuous notification decision with cooldown
  - threshold ignore behavior without usage signal
- Expanded docs:
  - `SPEC.md`: added `連続使用通知`
  - `REGRESSION_TEST.md`: added `TC-17` / `TC-18` / `TC-19`

### Validation Snapshot
- Local unit tests: `swift test --scratch-path .build/.swiftpm` passed (24 tests, 0 failures)
- Build check: `xcodebuild -project SNSalert.xcodeproj -target SNSalert -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build` passed
- Real-device focused validation: `TC-17` / `TC-18` / `TC-19` passed (2026-02-20)
- Real-device full regression: `TC-01` to `TC-19` passed (2026-02-22)

### Remaining Validation
- Full manual regression (`TC-01` to `TC-19`) completed on 2026-02-22.

## v0.1.3 (2026-02-17)

### Included
- Switched `UsageReportExtension` to ExtensionKit style configuration (Xcode template aligned):
  - target product type: `com.apple.product-type.extensionkit-extension`
  - embedded path: `SNSalert.app/Extensions/UsageReportExtension.appex`
  - `Info.plist` uses `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.deviceactivityui.report-extension`
- Stabilized hidden report trigger by using a broad daily `DeviceActivityFilter` in host view and mapping selected tokens in extension-side aggregation.
- Hardened usage key mapping in report extension by resolving `idx_<index>` with both:
  - token direct match (`Token<Application>`)
  - fallback sort-key match
- Added monitor-side minute fallback (`usage_idx_<index>` events):
  - `MonitorExt` now persists per-minute usage (`usageMinutes` / `usageUpdatedAt`) without relying on ReportExt execution
  - monitoring rearm now carries both `limit_idx_*` and next-minute `usage_idx_*` thresholds
  - app sync keeps fallback mode active when ReportExt heartbeat is missing
- Added duplicate-event guard for monitor-side minute sync:
  - ignores `usage_idx_*` events that arrive again within 50 seconds for the same index
  - prevents immediate false block caused by back-to-back threshold callbacks at monitor restart
- Fixed reset-anchor handling on monitoring start:
  - removed preemptive `lastResetAt` overwrite at `監視開始`
  - start now runs reset decision against stored `lastResetAt` before monitor registration
  - prevents false `resetスキップ` when reset boundary passed while monitoring was stopped
- Added reset-time drift guard on monitoring start:
  - compares configured reset time (`resetHour`/`resetMinute`) with persisted `lastResetAt`
  - if drift is detected (e.g. time changed during testing), usage/block state is reset before start
- Expanded spec/regression docs for remaining-time UI behavior:
  - Added `SPEC.md` section: `残り時間の表示更新`
  - Added `REGRESSION_TEST.md`: `TC-14` / `TC-15` / `TC-16`

### Validation Snapshot
- Local unit tests: `swift test --scratch-path .build/.swiftpm` passed (14 tests, 0 failures)
- Build check: `xcodebuild -project SNSalert.xcodeproj -scheme UsageMonitorExtension -configuration Debug -sdk iphoneos -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build` passed
- Build product verification:
  - `SNSalert.app/Extensions/UsageReportExtension.appex` exists
  - `UsageReportExtension.appex/Info.plist` has `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.deviceactivityui.report-extension`

### Remaining Validation
- Real-device focused manual validation completed: `TC-14` / `TC-15` / `TC-16` passed.
- Full manual regression (`TC-01` to `TC-16`) is still required before release.

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
