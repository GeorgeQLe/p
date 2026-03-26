# Current Phase: Phase 1 of 3 — History Robustness

> Project: p (project directory jumper and scaffolder)
> Full plan: tasks/roadmap.md

**Goal**: Ensure `rp` never silently fails on deleted projects. This is the only high-severity finding and directly impacts the user experience of the most recent feature (`rp`).

**Scope**:
- `rp` validates that history entries point to existing directories before offering them or attempting `cd`
- Stale entries are auto-pruned from history on read (both bash and zsh)
- Clear user-facing message when a stale entry is encountered
- Add `rp --prune` command to manually remove all stale entries at once
- Update `rp --help` text to mention `--prune`

---

### Tests First
- [x] Step 1.1: Write failing tests for stale directory handling and `--prune`
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
- Step 1.5: Verify no regressions in existing `rp` tests

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
