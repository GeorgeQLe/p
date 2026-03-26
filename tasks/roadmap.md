# Roadmap: p

> Generated from: expert code review findings (2026-03-26)
> Date: 2026-03-26
> Total Phases: 3

## Summary

Address all findings from the expert code review, sequenced by user impact: first harden `rp` history handling (the only high-severity item plus related stale-entry cleanup), then improve tab completion robustness and test coverage, and finally polish config edge cases and diagnostics.

## Phase Overview
| Phase | Title | Key Deliverable | Est. Complexity |
|-------|-------|-----------------|-----------------|
| 1     | History robustness | `rp` validates dirs exist, auto-prunes stale entries, adds `rp --prune` | S |
| 2     | Completion hardening | Space-safe bash completion, `return 0` fixes, tests for all 3 completion functions | M |
| 3     | Config & doctor polish | Remove-all-categories guard, O(n^2) classify optimization, doctor cache accuracy | S |

---

## Phase 1: History Robustness

**Goal**: Ensure `rp` never silently fails on deleted projects. This is the only high-severity finding and directly impacts the user experience of the most recent feature (`rp`).

**Scope**:
- `rp` validates that history entries point to existing directories before offering them or attempting `cd`
- Stale entries are auto-pruned from history on read (both bash and zsh)
- Clear user-facing message when a stale entry is encountered: `"rp: project no longer exists: <path> (removed from history)"`
- Add `rp --prune` command to manually remove all stale entries at once
- Update `rp --help` text to mention `--prune`

**Acceptance Criteria:**
- [ ] `rp` with a history entry pointing to a deleted directory shows a clear message and removes the entry
- [ ] `rp` with a mix of valid and stale entries only shows valid ones in the picker
- [ ] `rp --prune` removes all entries pointing to nonexistent directories and reports count
- [ ] `rp --prune` with no stale entries reports "No stale entries found"
- [ ] Tests cover: stale single entry, stale entry in multi-list, `--prune` with stale entries, `--prune` with no stale entries
- [ ] Both p.bash and p.zsh updated in lockstep

### Tests First
- Step 1.1: Write failing tests for stale directory handling and `--prune`
  - File: modify `tests/p.bats`
  - Test: `rp with stale single entry shows message and removes it` — create project, visit it, delete dir, run `rp`, assert output contains "no longer exists" and status is non-zero (no valid entries left)
  - Test: `rp with mix of valid and stale entries only shows valid ones` — create two projects, visit both, delete one, run `rp`, assert stale project not in picker list, valid project auto-jumps
  - Test: `rp --prune removes stale entries and reports count` — create two projects, visit both, delete both, run `rp --prune`, assert output contains "Removed 2 stale" and history file is empty or gone
  - Test: `rp --prune with no stale entries reports nothing to prune` — create project, visit it, run `rp --prune`, assert output contains "No stale entries"
  - Test: `rp --help mentions --prune` — assert help text contains "--prune"

### Implementation
- Step 1.2: Add `--prune` flag handling to `rp` in both shells
  - Files: modify `p.bash` (rp function, ~line 551), modify `p.zsh` (rp function, ~line 550)
  - Add `--prune` block after `--clear` block
  - Read history, filter to entries where `[[ ! -d "$entry" ]]`, write back, report count
  - Update `--help` heredoc to include `rp --prune`
  - Update unknown-flag error message to include `--prune`

- Step 1.3: Add stale-entry filtering to the main `rp` read path in both shells
  - Files: modify `p.bash` (rp function, ~line 574-578), modify `p.zsh` (rp function, ~line 573-577)
  - After reading `all_entries` from history, filter out entries where directory doesn't exist
  - For each removed entry, print `"rp: removed stale project: <basename> (<path>)"` to stderr
  - Write the pruned list back to the history file (reuse the atomic write pattern from `_p_record_visit`)
  - Use the pruned `all_entries` for the rest of the function (query matching, display)

### Green
- Step 1.4: Run tests and verify all pass
  - `bats tests/p.bats` (bash)
  - `TEST_SHELL=zsh bats tests/p.bats` (zsh)
  - `shellcheck -s bash p.bash`
  - `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`
- Step 1.5: Verify no regressions in existing `rp` tests (rp --help, rp empty history, rp single entry, rp multi-entry, rp --clear, rp query, rp shows most recent first)

### Milestone: History Robustness Complete
**Acceptance Criteria:**
- [ ] `rp` with a history entry pointing to a deleted directory shows a clear message and removes the entry
- [ ] `rp` with a mix of valid and stale entries only shows valid ones in the picker
- [ ] `rp --prune` removes all entries pointing to nonexistent directories and reports count
- [ ] `rp --prune` with no stale entries reports "No stale entries found"
- [ ] Tests cover: stale single entry, stale entry in multi-list, `--prune` with stale entries, `--prune` with no stale entries
- [ ] Both p.bash and p.zsh updated in lockstep
- [ ] All phase tests pass
- [ ] No regressions in previous rp tests

**On Completion**:
- Deviations from plan:
- Tech debt / follow-ups:
- Ready for next phase: yes/no

---

## Phase 2: Completion Hardening

**Goal**: Make tab completion robust for edge cases and add test coverage for completion functions, which are currently untested and the most shell-specific code paths.

**Scope**:
- Fix bash `_p_completion` to handle project names with spaces (replace `compgen -W "$(cat ...)"` with a space-safe approach)
- Include the existing uncommitted `return` -> `return 0` fixes in completion functions (both shells)
- Include the existing uncommitted `return 1` -> `return 0` fix for `_p_find_all_dirs` failure in completion
- Add tests for `_p_completion` (bash and zsh)
- Add tests for `_sp_completion` (bash and zsh)
- Add tests for `_rp_completion` (bash and zsh)

**Acceptance Criteria:**
- [ ] Bash completion correctly completes a project name containing a space
- [ ] All completion functions return 0 (not bare `return` or `return 1`) on early-exit paths
- [ ] At least one test per completion function verifying it populates candidates from cache/history
- [ ] At least one test verifying completion only fires on the first argument (no suggestions after arg 1)
- [ ] Tests pass for both `TEST_SHELL=bash` and `TEST_SHELL=zsh`

**On Completion**:
- Deviations from plan:
- Tech debt / follow-ups:
- Ready for next phase: yes/no

---

## Phase 3: Config & Doctor Polish

**Goal**: Harden config management edge cases and improve diagnostic accuracy. All low-severity items that improve overall polish.

**Scope**:
- `_pconfig_remove`: prevent removing the last category, show `"Cannot remove last category"` message
- `_p_classify_dirs`: optimize from O(n^2) worst case to O(n) using a parent-stack approach (track most recent standalone entries, only check those)
- `_p_doctor`: check cache files are non-empty before reporting "valid"; report "empty" or "present (empty)" for zero-byte cache files

**Acceptance Criteria:**
- [ ] `pconfig remove` with only 1 category remaining refuses and shows a clear message
- [ ] Test covers the last-category guard
- [ ] `_p_classify_dirs` produces identical output to the current implementation (verified by existing tests) with reduced iteration count
- [ ] `p --doctor` reports cache as "empty" when cache file exists but is zero bytes
- [ ] Test covers doctor cache reporting for empty vs. populated cache files
- [ ] Both p.bash and p.zsh updated in lockstep

**On Completion**:
- Deviations from plan:
- Tech debt / follow-ups:
- Ready for next phase: yes/no

---

## Deferred / Future Work
- `_p_find_all_dirs` exclusion list (only `node_modules` currently) — no user reports of false positives, revisit if reported

## Cross-Phase Concerns
### Testing
- All phases must pass both bash and zsh test suites (`bats tests/p.bats` and `TEST_SHELL=zsh bats tests/p.bats`)
- All phases must pass shellcheck (`shellcheck -s bash p.bash` and the zsh variant)
### Dual-file Maintenance
- Every code change must be applied to both `p.bash` and `p.zsh` with appropriate shell-specific syntax adjustments
