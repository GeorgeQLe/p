# Session History

## 2026-03-26 — Phase 1, Step 1.1: Write failing tests
- Added 5 failing tests to `tests/p.bats` for stale directory handling and `--prune`
- Tests: stale single entry, stale+valid mix, `--prune` with stale, `--prune` with none, `--help` mentions `--prune`
- All 5 tests fail as expected (red phase); no regressions in existing tests
