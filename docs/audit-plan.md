# Beamlet Codebase Audit — Action Plan

**Date:** 2026-04-01
**Audited by:** Claude Code

## Summary Stats

| Severity | Count | Issues |
|----------|-------|--------|
| Critical | 6 | #39, #40, #41, #42, #43, #44 |
| High | 6 | #45, #46, #47, #48, #49, #50 |
| Medium | 4 | #51, #52, #53, #54 |
| Low | 3 | #55, #56, #57 |
| **Total** | **19** | |

| Category | Count |
|----------|-------|
| Security | 8 |
| Bug | 7 |
| Dead Code | 3 |
| Tech Debt | 3 |
| Code Quality | 2 |
| Docs / Config | 1 |

## Recommended Order

### Sprint 1: Security (Critical) — Do First

These are exploitable vulnerabilities in a public-facing server.

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 1 | #39 | IDOR on all file endpoints | Small |
| 2 | #41 | Upload bypasses contact system | Small |
| 3 | #44 | Container runs as root | Small |
| 4 | #46 | Content-Disposition header injection | Small |
| 5 | #40 | O(N) bcrypt auth (DoS vector) | Medium |
| 6 | #47 | No rate limiting | Medium |

**Why first:** These are exploitable by any authenticated user (#39, #41) or by unauthenticated attackers (#40, #47). The IDOR allows downloading any user's files.

### Sprint 2: Crash Fixes + Security (Critical/High)

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 7 | #42 | Force unwraps crash on malformed URLs | Small |
| 8 | #43 | Security-scoped resource leak | Small |
| 9 | #45 | Auth token in UserDefaults → Keychain | Medium |
| 10 | #48 | Nil deref panic on deleted invite creator | Small |
| 11 | #49 | Graceful shutdown broken | Small |

### Sprint 3: Bugs + Dead Code (High/Medium)

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 12 | #50 | Delete 3 unused iOS files + wire up widget | Small |
| 13 | #51 | Server bugs: wrong field names, missing columns, orphans, TOCTOU | Medium |
| 14 | #52 | Server dead code: duplicate handlers, unused methods | Small |
| 15 | #53 | iOS bugs: race conditions, silent errors, missing callbacks | Medium |

### Sprint 4: Infrastructure + Cleanup (Medium/Low)

| # | Issue | Description | Effort |
|---|-------|-------------|--------|
| 16 | #54 | Missing DB index, CI improvements, Docker hardening | Medium |
| 17 | #55 | Swallowed errors across server | Small |
| 18 | #56 | iOS redundant code, unused imports, magic numbers | Small |
| 19 | #57 | Documentation gaps and stale config | Small |

## Quick Wins (< 5 minutes each)

- **#39**: Add 1 ownership check to each file handler (5 lines of code)
- **#41**: Add 1 `AreContacts` check in UploadFile (3 lines)
- **#42**: Change 2 force unwraps to `guard let` (2 lines each)
- **#43**: Add `stopAccessingSecurityScopedResource()` call (1 line)
- **#44**: Add `USER` directive to Dockerfile (2 lines)
- **#46**: Use `mime.FormatMediaType` for filename (1 line)
- **#48**: Add nil check on creator lookup (3 lines)
- **#50**: Delete FileRowView.swift, FileDetailView.swift, InAppBanner.swift

## Dependency Chain

```
#40 (O(N) bcrypt) → #47 (rate limiting)
   Rate limiting is a band-aid; fixing the bcrypt scan is the real fix.
   Do #40 first, then #47 adds defense-in-depth.

#45 (Keychain) → #50 (dead code cleanup)
   Wire up KeychainService before deleting it as dead code.

#51 (server bugs: wrong field name) → #53 (iOS sent tab wrong name)
   The iOS sent tab bug is caused by the server returning the wrong field.
   Fix server first, then iOS displays correctly.

#52 (remove duplicate handler) → #54 (CI improvements)
   Clean up dead code before adding stricter linting.
```

## Effort Estimates

| Effort | Issues | Time |
|--------|--------|------|
| Small | #39, #41, #42, #43, #44, #46, #48, #49, #50, #52, #55, #56, #57 | ~1-2 hours total |
| Medium | #40, #45, #47, #51, #53, #54 | ~4-6 hours total |
| **Total** | 19 issues | ~5-8 hours |
