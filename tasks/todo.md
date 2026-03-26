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
- Step 3.2: Add last-category guard to `_pconfig_remove`
- Step 3.3: Optimize `_p_classify_dirs` with parent-stack approach
- Step 3.4: Fix `_p_doctor` cache reporting for empty files
- Step 3.5: Run tests and verify all pass

### Milestone: Config & Doctor Polish Complete
**Acceptance Criteria:**
- [ ] `pconfig remove` with only 1 category remaining refuses and shows a clear message
- [ ] Test covers the last-category guard
- [ ] `_p_classify_dirs` produces identical output to the current implementation (verified by existing tests) with reduced iteration count
- [ ] `p --doctor` reports cache as "empty" when cache file exists but is zero bytes
- [ ] Test covers doctor cache reporting for empty vs. populated cache files
- [ ] Both p.bash and p.zsh updated in lockstep
- [ ] All tests pass, no regressions

---

**Implementation plan for Step 3.1:**

Add failing tests to `tests/p.bats`:

1. **`pconfig remove refuses to remove last category`**:
   - Init config, remove categories until 1 remains, then attempt to remove the last one
   - Assert exit status is non-zero and output contains "Cannot remove last category"
   - Currently will fail: `_pconfig_remove` has no guard (p.bash:1162-1195, p.zsh:1155-1187)

2. **`p --doctor reports empty cache as empty`**:
   - Create a zero-byte cache file: `touch "$HOME/.cache/p/p_completion"`
   - Run `p --doctor`
   - Assert output contains "empty" (not "valid") for the cache entry
   - Currently will fail: doctor just checks `[[ -f "$cfile" ]]` and reports "valid" (p.bash:196-206)

3. **`p --doctor reports populated cache correctly`**:
   - Create a cache file with content: `echo "foo" > "$HOME/.cache/p/p_completion"`
   - Run `p --doctor`
   - Assert output contains "valid" for the cache entry
   - This should pass already (existing behavior)

4. **`_p_classify_dirs produces correct output`** (regression guard for Step 3.3):
   - No new test needed — existing tests already verify classify output
   - The optimization must produce identical results

**Key details:**
- `_pconfig_remove` in p.bash (lines 1162-1195): needs a guard after `_p_load_categories` — if `${#_p_categories[@]} == 1`, print message and return 1
- `_pconfig_remove` in p.zsh (lines 1155-1187): same guard with zsh 1-based indexing
- `_p_doctor` cache section in p.bash (lines 190-210): after the `[[ -f "$cfile" ]]` check, add `[[ -s "$cfile" ]]` to distinguish empty from populated
- `_p_doctor` cache section in p.zsh: same fix
- For the last-category test: init config (gives 3 categories), remove 2 via piped input, then try to remove the last — pipe "1" three times
- The test helper `_p` runs commands in a subshell, so `read -rp` in `_pconfig_remove` reads from stdin (piped input works)
