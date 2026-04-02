# Beamlet Codebase Audit — Action Plan

## Audit v1 (2026-04-01) — COMPLETED

19 issues found and fixed. All closed: #39-#57.

## Audit v2 (2026-04-02) — Re-audit after fixes

| Severity | Count | Issues |
|----------|-------|--------|
| Critical | 2 | #58, #59 |
| High | 6 | #60, #61, #62, #63, #64, #65 |
| Medium | 2 | #66, #67 |
| Low | 2 | #68, #69 |
| **Total** | **12** | |

| Category | Count |
|----------|-------|
| Security | 5 |
| Bug | 5 |
| Tech Debt | 3 |
| Code Quality | 2 |

## Recommended Order

### Sprint 1: Critical + Quick Security Wins

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 1 | #58 | O(N) bcrypt auth — store token prefix for indexed lookup | Medium |
| 2 | #59 | Security-scoped resource leak + multi-recipient send break | Small |
| 3 | #62 | XSS in invite page — use html.EscapeString() | Small |
| 4 | #65 | Missing NSPhotoLibraryAddUsageDescription — crash on save | Small |
| 5 | #61 | No body size limit on JSON endpoints — http.MaxBytesReader | Small |

### Sprint 2: High Priority Bugs

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 6 | #60 | HTTP server timeouts — add Read/Write/Idle timeouts | Small |
| 7 | #63 | Sent tab wrong name — fix model/query field | Small |
| 8 | #64 | requestVoid missing device token + error wrapping | Small |

### Sprint 3: Medium — Stability & Cleanup

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 9 | #66 | Server: duplicate route, TOCTOU, self-redeem, dead code, shutdown | Medium |
| 10 | #67 | iOS: nearby flicker, BLE leak, KeychainService, wrong-server invite | Medium |

### Sprint 4: Low — Polish

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 11 | #68 | Server: io.Copy errors, json.Encode errors, path validation | Small |
| 12 | #69 | iOS: isSending reset, credential flash, scanner flag, widget unwrap | Small |

## Quick Wins (< 5 minutes each)

- **#62**: Add `html.EscapeString()` to invite page handler (1 line each for name/URL)
- **#65**: Add `NSPhotoLibraryAddUsageDescription` to Info.plist (2 lines)
- **#61**: Wrap `r.Body` with `http.MaxBytesReader` in 2 handlers (1 line each)
- **#60**: Add 3 timeout fields to `http.Server{}` (3 lines)
- **#59**: Move file read before loop, stop after loop (move 2 lines)

## Effort Estimates

| Effort | Issues | Time |
|--------|--------|------|
| Small | #59, #60, #61, #62, #63, #64, #65, #68, #69 | ~2-3 hours |
| Medium | #58, #66, #67 | ~3-4 hours |
| **Total** | 12 issues | ~5-7 hours |
