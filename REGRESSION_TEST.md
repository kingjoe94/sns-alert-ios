# Regression Test Checklist (MVP)

This checklist is the fixed regression flow for `SNSalert`.
Run it before release and after any change to monitoring/reset logic.

## 0. Preconditions

- Device: real iPhone/iPad (not Simulator)
- Screen Time: enabled
- App permission: approved (`Screen Time許可: OK`)
- Selected apps: 2 apps (call them App A / App B)
- Limits:
  - App A: 1 min
  - App B: 1 min
- Debug log UI visible (DEBUG build)

## 0.5 Automated Unit Tests

Run pure logic tests before device regression:

```bash
cd /Users/kinjoushizuma/dev/apr/SNSalert
swift test
```

Expected:
- All `MonitoringLogicTests` pass with 0 failures.

## 0.6 Run Modes (10 min / 30 min)

### Quick Smoke (about 10 min)

Run this on every small change:

1. `TC-01 Start monitoring`
2. `TC-02 Per-app block (App A first)`
3. `TC-04 Reset unlock`
4. `TC-06 No-use false block check`

Quick Smoke pass criteria:
- All four test cases pass.
- No immediate false block after reset.
- No reset drift to next day while still blocked.

### Full Regression (about 30 min)

Run this before release or after monitoring/reset logic changes:

- `TC-01` to `TC-16` all cases in order.

## 1. Core Flow (Start -> Block -> Reset -> Re-block)

### TC-01 Start monitoring

Steps:
1. Tap `停止` (if monitoring is already on).
2. Tap `監視開始`.

Expected:
- Status changes to monitoring.
- Debug log includes:
  - `監視開始を要求`
  - `intervalDidStart`
  - `監視開始に成功`

### TC-02 Per-app block (App A first)

Steps:
1. Use only App A for >= 70 seconds.
2. Do not open App B.

Expected:
- App A is blocked.
- App B is not blocked yet.
- Debug log includes `しきい値到達: limit_idx_0` (or app index mapped to App A).

### TC-03 Second app block (App B)

Steps:
1. Use App B for >= 70 seconds.

Expected:
- App B also becomes blocked.
- Debug log includes `しきい値到達: limit_idx_1` (or mapped index).

### TC-04 Reset unlock

Steps:
1. Set reset time to 1-2 minutes in the future.
2. Wait for reset.
3. Open App A and App B once.

Expected:
- Both apps are unblocked after reset.
- Debug log includes `intervalDidStart` at reset boundary.
- No "next day" drift behavior.

### TC-05 Re-block after reset

Steps:
1. After reset, use App A for >= 70 seconds.
2. Then use App B for >= 70 seconds.

Expected:
- App A and App B are blocked again.
- Debug log shows fresh `しきい値到達` for both apps after reset.

## 2. Guard Flow (False positives and missed blocks)

### TC-06 No-use false block check

Steps:
1. Immediately after reset, do not open selected apps for 3+ minutes.

Expected:
- No app is blocked while unused.
- If logs show `しきい値を使用量未同期で無視`, that is acceptable.
- App must remain usable until real usage reaches limit.

### TC-07 Background monitoring

Steps:
1. Start monitoring.
2. Move app to background or terminate app process.
3. Use App A until limit.

Expected:
- Block still applies when limit is reached.

### TC-08 Stop/resume same day

Steps:
1. Start monitoring and consume part of App A time.
2. Tap `停止`.
3. Tap `監視開始` again on same day.

Expected:
- Usage is not reset by stop/start alone.
- Block timing resumes from remaining time.
- `監視開始`直後（最初の10秒程度）に即ブロックされない。

## 3. UI Rule Check

### TC-09 Edit lock during monitoring

Steps:
1. Turn monitoring on.
2. Try changing app limits/reset time/selection.

Expected:
- Monitoring state is view-only (no editing).

### TC-10 Edit enabled when stopped

Steps:
1. Turn monitoring off.
2. Change limits/reset time/selection.
3. Start monitoring again.

Expected:
- Changes apply on next start.

### TC-11 Error message: permission required

Steps:
1. Disable Screen Time permission for the app in iOS settings.
2. Open app and tap `監視開始`.

Expected:
- Error text is exactly `Screen Timeの許可が必要です`.
- Monitoring does not start.

### TC-12 Error message: monitor start failure

Steps:
1. Keep Screen Time permission enabled.
2. Clear selected apps (0 apps selected).
3. Tap `監視開始`.

Expected:
- Error text is exactly `監視開始に失敗しました`.
- Monitoring does not start.

### TC-13 Error message: sync failure

Steps:
1. Start monitoring.
2. Turn on `同期失敗シミュレーション: ON` in DEBUG section.
3. Wait for next sync tick.

Expected:
- Error text is exactly `使用時間の同期に失敗しています`.
- Existing usage state is kept (no forced reset to zero).
- Existing block state is kept; no forced unblock is performed only by sync error text.

### TC-14 Remaining time display updates

Steps:
1. Set App A limit to 5 minutes and start monitoring.
2. Open App A detail view and confirm initial remaining time.
3. Use App A for 1-2 minutes.
4. Return to detail view and confirm remaining time.
5. Put app in background for about 1 minute.
6. Return to foreground and confirm remaining time again.

Expected:
- Initial remaining time is shown as limit-based value.
- After usage, remaining time decreases.
- After background -> foreground, remaining time reflects latest usage.
- Display format is always `X時間Y分`.

### TC-15 Remaining time display after reset

Steps:
1. Set reset time to 1-2 minutes in the future.
2. Consume App A until remaining time reaches 0 and block is applied.
3. Wait until reset time passes.
4. Open App A detail view and check remaining time.

Expected:
- After reset, remaining time returns to configured limit value.
- Display updates without requiring app restart.

### TC-16 Stop during day, resume after reset boundary

Steps:
1. Set reset time to 1-2 minutes in the future.
2. Start monitoring and consume App A close to limit (or block App A once).
3. Tap `停止` before/after the reset boundary and keep monitoring off.
4. Wait until reset time passes.
5. Tap `監視開始` and open App A detail view immediately.

Expected:
- If reset boundary was passed while stopped, usage is reset on next start.
- No immediate block occurs right after `監視開始`.
- Remaining time starts from configured limit value.

## 4. Pass Criteria

Release candidate is acceptable only if:

- TC-01 to TC-16 all pass.
- No reproduction of:
  - reset-time shift to next day while still blocked
  - post-reset permanent no-block state
  - immediate block without usage after reset

## 5. Test Result Template

Copy and fill this after each run:

```text
Run type: Quick Smoke / Full Regression
Date: YYYY-MM-DD HH:mm
Build: commit=<hash> / branch=<name>
Device: <model> / iOS <version>
Reset time setting: HH:mm

TC-01: PASS/FAIL
TC-02: PASS/FAIL
TC-03: PASS/FAIL
TC-04: PASS/FAIL
TC-05: PASS/FAIL
TC-06: PASS/FAIL
TC-07: PASS/FAIL
TC-08: PASS/FAIL
TC-09: PASS/FAIL
TC-10: PASS/FAIL
TC-11: PASS/FAIL
TC-12: PASS/FAIL
TC-13: PASS/FAIL
TC-14: PASS/FAIL
TC-15: PASS/FAIL
TC-16: PASS/FAIL

Notes:
- <debug log summary>
- <unexpected behavior if any>

Result: PASS / FAIL
```

## 6. Latest Recorded Run

```text
Run type: Automated (CI + local unit tests)
Date: 2026-02-13 07:22 JST
Build: commit=2af8f6b / branch=main
Device: N/A (CI/local Mac)
Reset time setting: N/A

TC-01: MANUAL_PENDING
TC-02: MANUAL_PENDING
TC-03: MANUAL_PENDING
TC-04: MANUAL_PENDING
TC-05: MANUAL_PENDING
TC-06: MANUAL_PENDING
TC-07: MANUAL_PENDING
TC-08: MANUAL_PENDING
TC-09: MANUAL_PENDING
TC-10: MANUAL_PENDING
TC-11: MANUAL_PENDING
TC-12: MANUAL_PENDING
TC-13: MANUAL_PENDING
TC-14: MANUAL_PENDING
TC-15: MANUAL_PENDING

Notes:
- GitHub Actions: latest successful run remained iOS Build Check #5 (logic-test, build)
- Local unit tests: `swift test --scratch-path .build/.swiftpm` passed
- Executed 9 tests, 0 failures

Result: AUTOMATED_PASS / MANUAL_PENDING
```

## 7. Latest Recorded Device Run (Focused Scope)

```text
Run type: Focused Manual (threshold/rearm verification)
Date: 2026-02-16
Build: working tree (unreleased) / branch=main
Device: iPhone (real device) / iOS version not recorded
Reset time setting: 06:16

TC-01: PASS
TC-02: PASS (limit=2min)
TC-03: NOT_RUN
TC-04: PASS
TC-05: PASS (limit=4min after reset)
TC-06: NOT_RUN
TC-07: NOT_RUN
TC-08: NOT_RUN
TC-09: NOT_RUN
TC-10: NOT_RUN
TC-11: NOT_RUN
TC-12: NOT_RUN
TC-13: NOT_RUN
TC-14: NOT_RUN
TC-15: NOT_RUN

Notes:
- Prior symptom ("limit reached but no block after reset") was observed before this fix.
- User report confirmed block at 2-minute limit and 4-minute limit.
- After reset, 4-minute limit also blocked again as expected.

Result: PASS (focused scope only)
```

## 8. Latest Recorded Device Run (Remaining-Time + Resume)

```text
Run type: Focused Manual (remaining-time and resume)
Date: 2026-02-17
Build: working tree (unreleased) / branch=main
Device: iPhone (real device) / iOS version not recorded
Reset time setting: test-time dependent

TC-14: PASS
TC-15: PASS
TC-16: PASS

Notes:
- Immediate block on monitoring start no longer reproduced.
- Remaining time now decreases during usage.
- After crossing reset boundary while stopped, remaining time resets on next start (expected behavior).

Result: PASS (focused scope only)
```
