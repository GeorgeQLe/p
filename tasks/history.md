# Session History

## 2026-03-26 — Phase 1, Step 1.1: Write failing tests
- Added 5 failing tests to `tests/p.bats` for stale directory handling and `--prune`
- Tests: stale single entry, stale+valid mix, `--prune` with stale, `--prune` with none, `--help` mentions `--prune`
- All 5 tests fail as expected (red phase); no regressions in existing tests

## 2026-03-26 — Phase 1, Step 1.2: Implement `--prune` flag
- Added `--prune` handler to `rp()` in both `p.bash` and `p.zsh`
- Updated `--help` text and unknown-flag usage message to include `--prune`
- 3 of 5 new tests now pass (--prune tests + --help); 2 stale-filtering tests still fail (Step 1.3)

## 2026-03-26 — Phase 1, Step 1.3: Stale-entry filtering in rp read path
- Added stale-entry filtering after history read in `rp()` for both `p.bash` and `p.zsh`
- Stale entries auto-pruned on read, stderr message per removed entry, history file rewritten
- Fixed `> "$history_file"` to `true > "$history_file"` for portability in --prune handler
- All 120 tests pass (bash + zsh), shellcheck clean
- Phase 1 complete: all acceptance criteria met
