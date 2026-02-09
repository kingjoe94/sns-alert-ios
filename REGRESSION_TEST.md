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

## 4. Pass Criteria

Release candidate is acceptable only if:

- TC-01 to TC-10 all pass.
- No reproduction of:
  - reset-time shift to next day while still blocked
  - post-reset permanent no-block state
  - immediate block without usage after reset
