# Current Phase: Phase 3 of 3 — Config & Doctor Polish

> Project: p (project directory jumper and scaffolder)
> Full plan: tasks/roadmap.md

**Goal**: Harden config management edge cases and improve diagnostic accuracy.

**Scope**:
- `_pconfig_remove`: prevent removing the last category
- `_p_classify_dirs`: optimize from O(n²) to O(n) using parent-stack
- `_p_doctor`: report empty cache files accurately

---

### Tests First
- [x] Step 3.1: Write failing tests for all three items

### Implementation
- [x] Step 3.2: Add last-category guard to `_pconfig_remove`
- [x] Step 3.3: Optimize `_p_classify_dirs` with parent-stack approach
- [x] Step 3.4: Fix `_p_doctor` cache reporting for empty files
- [x] Step 3.5: Run tests and verify all pass

### Milestone: Config & Doctor Polish Complete
**Acceptance Criteria:**
- [x] `pconfig remove` with only 1 category remaining refuses and shows a clear message
- [x] Test covers the last-category guard
- [x] `_p_classify_dirs` produces identical output to the current implementation (verified by existing tests) with reduced iteration count
- [x] `p --doctor` reports cache as "empty" when cache file exists but is zero bytes
- [x] Test covers doctor cache reporting for empty vs. populated cache files
- [x] Both p.bash and p.zsh updated in lockstep
- [x] All tests pass, no regressions

---

**Implementation plan for Steps 3.2-3.4:**

All three fixes are small and independent. Implement them together.

**Step 3.2: Last-category guard in `_pconfig_remove`**
- p.bash (line ~1165): after the `(( ${#_p_categories[@]} == 0 ))` check, add:
  ```bash
  if (( ${#_p_categories[@]} == 1 )); then
    echo "Cannot remove last category."
    return 1
  fi
  ```
- p.zsh: same guard (same line range, same syntax works)

**Step 3.3: Optimize `_p_classify_dirs` — parent-stack approach**
- p.bash (lines 32-59): replace inner loop with a stack of standalone parents
  - After sorting, maintain an array of "active parents" (standalone dirs)
  - For each dir, only check if it starts with the most recent standalone entry (not all previous entries)
  - Since dirs are sorted, a child always comes right after its parent
  - Pop stack entries that are no longer ancestors of the current dir
  ```bash
  local stack=()
  for (( i=0; i<${#dirs_arr[@]}; i++ )); do
    d="${dirs_arr[$i]}"
    # Pop stack entries that are not ancestors of d
    while (( ${#stack[@]} > 0 )) && [[ "$d" != "${stack[-1]}/"* ]]; do
      unset 'stack[-1]'
    done
    if (( ${#stack[@]} > 0 )); then
      echo "P $d"
    else
      echo "S $d"
      stack+=("$d")
    fi
  done
  ```
- p.zsh: same logic with 1-based indexing and `${stack[-1]}` → `${stack[-1]}` (same in zsh), `unset 'stack[-1]'` → `stack[-1]=(); stack=(${stack[@]})` or use shift/pop

**Step 3.4: Fix `_p_doctor` cache reporting**
- p.bash (line ~206): change the cache reporting block to check `-s` (non-empty):
  ```bash
  if [[ -s "$cfile" ]]; then
    # ... compute age ...
    echo "  ✓ $cname cache: valid ($age_min min old)"
  else
    echo "  ⚠ $cname cache: present (empty)"
  fi
  ```
  Keep the outer `[[ -f "$cfile" ]]` check, nest `-s` inside it.
- p.zsh: same fix

**Verification:**
- `bats tests/p.bats` — all 134 tests should pass (0 failures)
- `TEST_SHELL=zsh bats tests/p.bats` — all pass
- `shellcheck -s bash p.bash` — clean
