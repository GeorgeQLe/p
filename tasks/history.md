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

## 2026-03-26 — Phase 2, Step 2.1: Write failing tests for completion functions
- Added 8 bash-only completion tests to `tests/p.bats` with `_run_completion` helper
- Tests cover: _p_completion (cache, skip-after-first-arg, spaces), _sp_completion (cache, skip), _rp_completion (history, skip, missing-history)
- 7 of 8 pass; test 123 (spaces in names) fails as expected (red phase for Step 2.2)
- All zsh tests skip correctly; no regressions

## 2026-03-26 — Phase 2, Steps 2.2-2.3: Space-safe bash completion
- Replaced `compgen -W` with line-by-line prefix matching in `_p_completion`, `_sp_completion`, `_rp_completion` (p.bash only)
- Zsh versions already handle spaces via `compadd` — no changes needed
- All 128 tests pass (bash + zsh), shellcheck clean
- Phase 2 complete: all acceptance criteria met

## 2026-03-26 — Phase 3, Step 3.1: Write failing tests
- Added 3 tests: last-category guard, empty cache doctor, populated cache doctor
- 2 fail as expected (red phase for Steps 3.2 and 3.4), 1 passes (populated cache)
- 134 total tests, same 2 expected failures in both bash and zsh

## 2026-03-26 — Phase 3, Steps 3.2-3.4: Implementation
- Added last-category guard to `_pconfig_remove` (both files)
- Optimized `_p_classify_dirs` from O(n²) to O(n) with parent-stack approach (both files)
- Fixed `_p_doctor` cache reporting: empty files now show "present (empty)" instead of "valid"
- Fixed test to account for 5 default categories (not 3)
- All 134 tests pass (bash + zsh), shellcheck clean
- Phase 3 complete: all acceptance criteria met
- Also removed `.github/workflows/ci.yml` per user request

## 2026-04-11 — P_NP_HOOK: Post-creation hook for `np`
- Added `P_NP_HOOK` extension point to `np()` in both p.bash and p.zsh
- Hook fires after project creation, receives 4 args: name, category, type, path
- Failure warns but doesn't abort (project already created)
- Added 4 bats tests with `_p_hook` helper for env var forwarding
- Documented in README.md: Hooks section + env var table entry
- Created `scripts/np-hook` (shell entry point) and `scripts/add-product.ts` (TS worker) in lexcorp repo
- All 135 tests pass, no regressions

## 2026-04-13 — `np --clone`: Clone support for `np`
- Added `_np_name_from_url` helper to both p.bash and p.zsh (derives kebab-case name from git URL)
- Added `--clone URL` flag to `np` arg parsing, help text, and usage errors
- Name auto-derived from URL when not explicitly provided
- Interactive clone prompt added (after category selection, before confirmation)
- Clone URL shown in confirmation display
- Conditional logic: `git clone` when `--clone` set, `git init` otherwise
- Clone failure returns clean error message
- Added 8 tests with `_p_withpath`/`_install_fakegit` helpers for fake git injection
- All 143 tests pass, no regressions

## 2026-04-21 — Completion performance audit and optimization
- Added `scripts/time-p.sh` to time project scan, classification, cache build, filtering, and cold/warm completion paths
- Changed project discovery to prune `node_modules` and `.git` directories instead of only filtering output
- Added shared atomic completion cache rebuild for both `p_completion` and `sp_completion`
- Changed completion to serve stale caches immediately and refresh them in the background behind a lock
- Added explicit cache rebuild commands: `p --warm-cache` and `pconfig rebuild-cache`
- Documented the stale-cache refresh behavior in README and added focused tests
- Preserved the mobile default category/config example update already present in the worktree
- Validation: shellcheck clean for both shell variants and timing script; all 145 tests pass in bash and zsh
- Timing: cold `_p_completion` now measures about 140-160 ms locally, warm about 10-13 ms, stale-cache completion about 8-12 ms

## 2026-04-21 — Follow-up: remove missing-cache completion blocking
- User reported tab completion still felt laggy after the first cache optimization
- Found missing-cache completion still rebuilt synchronously on Tab, which kept the roughly 170 ms scan after invalidation or when `sp_completion` was absent
- Changed `p` and `sp` completion to start cache refresh asynchronously and return immediately when their cache file is missing
- Throttled stale-cache age checks in the completion hot path to avoid repeated `stat`/`date` work during normal repeated Tab presses
- Changed zsh completion to read cache files in-shell and pass only prefix-matched candidates to `compadd`
- Updated timing diagnostics to report missing-cache completion separately from explicit cache priming
- Timing: missing-cache `_p_completion` now returns in about 14-18 ms while refresh runs in the background; warm completion measures about 5-7 ms locally
