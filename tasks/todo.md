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
- [x] Step 1.2: Add `--prune` flag handling to `rp` in both shells
  - Files: modify `p.bash` (rp function, ~line 551), modify `p.zsh` (rp function, ~line 550)
  - Add `--prune` block after `--clear` block
  - Read history, filter to entries where `[[ ! -d "$entry" ]]`, write back, report count
  - Update `--help` heredoc to include `rp --prune`
  - Update unknown-flag error message to include `--prune`

  **Implementation plan for Step 1.2:**

  Both `p.bash` and `p.zsh` need identical logic changes in the `rp()` function:

  1. **Update `--help` heredoc** (~line 539-547 bash, ~line 538-546 zsh):
     Add `rp --prune      Remove stale entries (deleted directories)` line after the `--clear` line.

  2. **Add `--prune` handler** after the `--clear` block (~line 555 bash/zsh):
     ```bash
     if [[ "$1" == "--prune" ]]; then
       if [[ ! -f "$history_file" ]] || [[ ! -s "$history_file" ]]; then
         echo "No stale entries found."
         return 0
       fi
       local keep=() removed=0
       while IFS= read -r line; do
         [[ -n "$line" ]] || continue
         if [[ -d "$line" ]]; then
           keep+=("$line")
         else
           ((removed++))
         fi
       done < "$history_file"
       if (( removed == 0 )); then
         echo "No stale entries found."
       else
         printf '%s\n' "${keep[@]}" > "$history_file"  # or truncate if empty
         echo "Removed $removed stale entries."
       fi
       return 0
     fi
     ```

  3. **Update unknown-flag error** (~line 563 bash/zsh):
     Change `"Usage: rp [--help | --clear | query]"` to `"Usage: rp [--help | --clear | --prune | query]"`

  **Tests that should pass after this step:** tests 117, 118, 119 (--prune tests and --help --prune).
  **Tests still expected to fail:** tests 115, 116 (stale filtering in main read path — that's Step 1.3).

- [x] Step 1.3: Add stale-entry filtering to the main `rp` read path in both shells
  - Files: modify `p.bash` (rp function, ~line 574-578), modify `p.zsh` (rp function, ~line 573-577)
  - After reading `all_entries` from history, filter out entries where directory doesn't exist
  - For each removed entry, print `"rp: removed stale project: <basename> (<path>)"` to stderr
  - Write the pruned list back to the history file (reuse the atomic write pattern from `_p_record_visit`)
  - Use the pruned `all_entries` for the rest of the function (query matching, display)

  **Implementation plan for Step 1.3:**

  Both `p.bash` and `p.zsh` need the same change in the `rp()` function, right after the "Read history into array" block (bash:602-606, zsh:601-605).

  1. **After the `while` loop that reads `all_entries`**, insert a filtering block:
     ```bash
     # Filter out stale entries (deleted directories)
     local valid_entries=() stale_count=0
     for entry in "${all_entries[@]}"; do
       if [[ -d "$entry" ]]; then
         valid_entries+=("$entry")
       else
         echo "rp: removed stale project: ${entry##*/} ($entry)" >&2
         ((stale_count++))
       fi
     done
     ```

  2. **If any stale entries were found**, write the cleaned list back to the history file:
     ```bash
     if (( stale_count > 0 )); then
       if (( ${#valid_entries[@]} > 0 )); then
         printf '%s\n' "${valid_entries[@]}" > "$history_file"
       else
         > "$history_file"
       fi
     fi
     ```

  3. **Replace `all_entries` with `valid_entries`** for the rest of the function:
     ```bash
     all_entries=("${valid_entries[@]}")
     ```

  4. **After the reassignment**, add a check: if `all_entries` is now empty, print a message and return 1:
     ```bash
     if (( ${#all_entries[@]} == 0 )); then
       echo "No project history yet. Use p, sp, or np to visit projects." >&2
       return 1
     fi
     ```
     This handles the case where ALL entries were stale (test 115: status non-zero).

  **Test expectations:**
  - Test 115 (`rp with stale single entry`): expects status != 0, output matches "removed stale"
  - Test 116 (`rp with mix of valid and stale`): expects status 0, output contains "alpha" but not "beta" (or "stale")
  - All 3 `--prune` tests should continue to pass
  - No regressions in existing `rp` tests

### Green
- [x] Step 1.4: Run tests and verify all pass
  - `bats tests/p.bats` (bash)
  - `TEST_SHELL=zsh bats tests/p.bats` (zsh)
  - `shellcheck -s bash p.bash`
  - `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`
- [x] Step 1.5: Verify no regressions in existing `rp` tests

### Milestone: History Robustness Complete
**Acceptance Criteria:**
- [x] `rp` with a history entry pointing to a deleted directory shows a clear message and removes the entry
- [x] `rp` with a mix of valid and stale entries only shows valid ones in the picker
- [x] `rp --prune` removes all entries pointing to nonexistent directories and reports count
- [x] `rp --prune` with no stale entries reports "No stale entries found"
- [x] Tests cover: stale single entry, stale entry in multi-list, `--prune` with stale entries, `--prune` with no stale entries
- [x] Both p.bash and p.zsh updated in lockstep
- [x] All phase tests pass
- [x] No regressions in previous rp tests
