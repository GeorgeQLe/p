# Current Phase: Phase 2 of 3 — Completion Hardening

> Project: p (project directory jumper and scaffolder)
> Full plan: tasks/roadmap.md

**Goal**: Make tab completion robust for edge cases and add test coverage for completion functions, which are currently untested and the most shell-specific code paths.

**Scope**:
- Fix bash `_p_completion` to handle project names with spaces (replace `compgen -W "$(cat ...)"` with a space-safe approach)
- Add tests for `_p_completion` (bash and zsh)
- Add tests for `_sp_completion` (bash and zsh)
- Add tests for `_rp_completion` (bash and zsh)

---

### Tests First
- [x] Step 2.1: Write failing tests for completion functions
  - File: modify `tests/p.bats`
  - Tests to add:
    - `_p_completion populates candidates from cache` — set up cache file with known project names, simulate COMP_WORDS/COMP_CWORD (bash) or CURRENT/words (zsh), call the completion function, assert candidates contain expected names
    - `_p_completion does not complete after first argument` — set COMP_CWORD=2 (bash) or CURRENT=3 (zsh), call completion, assert no candidates
    - `_p_completion handles project names with spaces` — put a name with a space in the cache file, call completion with matching prefix, assert the spaced name appears in candidates (this will fail in bash due to `compgen -W`)
    - `_sp_completion populates candidates from cache` — set up sp_completion cache file, call completion, assert candidates match
    - `_sp_completion does not complete after first argument` — same pattern as _p_completion
    - `_rp_completion populates candidates from history` — set up p_history file, call completion, assert candidates match
    - `_rp_completion does not complete after first argument` — same pattern
    - `_rp_completion with missing history returns cleanly` — no history file, call completion, assert no error and no candidates

  **Technical details for testing completion:**
  - Bash completion testing: set `COMP_WORDS=("p" "prefix")`, `COMP_CWORD=1`, call `_p_completion`, check `COMPREPLY` array
  - Zsh completion testing: more complex since `compadd` is a builtin. Options:
    1. Mock `compadd` as a function that captures args
    2. Or test indirectly by verifying the cache file contents and the function's early-return behavior
  - The test helper already sources p.bash/p.zsh, so completion functions are available
  - For zsh tests (`TEST_SHELL=zsh`), the test runs `zsh -c "source p.zsh; ..."` — we can define a mock `compadd` function before calling the completion function

### Implementation
- Step 2.2: Fix bash `_p_completion` to handle spaces in project names
  - File: `p.bash` lines 412-413
  - Current (broken with spaces): `mapfile -t COMPREPLY < <(compgen -W "$(cat "$cache_file")" -- "$cur")`
  - Fix: Read cache file line-by-line, filter by prefix manually:
    ```bash
    local candidates=()
    while IFS= read -r name; do
      [[ "$name" == "$cur"* ]] && candidates+=("$name")
    done < "$cache_file"
    COMPREPLY=("${candidates[@]}")
    ```
  - Apply same fix to `_sp_completion` (p.bash line 531) and `_rp_completion` (p.bash line 688)
  - Zsh versions use `compadd` which already handles spaces correctly — no fix needed

- Step 2.3: Run tests and verify all pass
  - `bats tests/p.bats` (bash)
  - `TEST_SHELL=zsh bats tests/p.bats` (zsh)
  - `shellcheck -s bash p.bash`
  - `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`

### Milestone: Completion Hardening Complete
**Acceptance Criteria:**
- [ ] Bash completion correctly completes a project name containing a space
- [ ] All completion functions return 0 (not bare `return` or `return 1`) on early-exit paths
- [ ] At least one test per completion function verifying it populates candidates from cache/history
- [ ] At least one test verifying completion only fires on the first argument (no suggestions after arg 1)
- [ ] Tests pass for both `TEST_SHELL=bash` and `TEST_SHELL=zsh`
- [ ] Both p.bash and p.zsh updated in lockstep
- [ ] No regressions in previous tests

---

**Implementation plan for Step 2.1:**

Add the following tests to `tests/p.bats` (after the existing `rp` tests, before the end of file):

1. **`_p_completion populates candidates from cache`** (bash-only test):
   ```bash
   @test "_p_completion populates candidates from cache" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     local cache_dir="$TEST_CACHE_DIR"
     printf '%s\n' "alpha" "beta" "gamma" > "$cache_dir/p_completion"
     COMP_WORDS=("p" "al"); COMP_CWORD=1; COMPREPLY=()
     _p_completion
     [[ "${COMPREPLY[*]}" == *"alpha"* ]]
   }
   ```

2. **`_p_completion skips after first argument`**:
   ```bash
   @test "_p_completion skips completion after first argument" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "alpha" > "$TEST_CACHE_DIR/p_completion"
     COMP_WORDS=("p" "alpha" ""); COMP_CWORD=2; COMPREPLY=()
     _p_completion
     (( ${#COMPREPLY[@]} == 0 ))
   }
   ```

3. **`_p_completion handles project names with spaces`** (will fail before Step 2.2 fix):
   ```bash
   @test "_p_completion handles project names with spaces" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "my project" "other" > "$TEST_CACHE_DIR/p_completion"
     COMP_WORDS=("p" "my"); COMP_CWORD=1; COMPREPLY=()
     _p_completion
     [[ "${COMPREPLY[*]}" == *"my project"* ]]
   }
   ```

4. **`_sp_completion populates candidates from cache`**:
   ```bash
   @test "_sp_completion populates candidates from cache" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "subrepo-a" "subrepo-b" > "$TEST_CACHE_DIR/sp_completion"
     COMP_WORDS=("sp" "sub"); COMP_CWORD=1; COMPREPLY=()
     _sp_completion
     [[ "${COMPREPLY[*]}" == *"subrepo-a"* ]]
   }
   ```

5. **`_sp_completion skips after first argument`**:
   ```bash
   @test "_sp_completion skips completion after first argument" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "subrepo-a" > "$TEST_CACHE_DIR/sp_completion"
     COMP_WORDS=("sp" "subrepo-a" ""); COMP_CWORD=2; COMPREPLY=()
     _sp_completion
     (( ${#COMPREPLY[@]} == 0 ))
   }
   ```

6. **`_rp_completion populates candidates from history`**:
   ```bash
   @test "_rp_completion populates candidates from history" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "/home/user/projects/foo" "/home/user/projects/bar" > "$TEST_CACHE_DIR/p_history"
     COMP_WORDS=("rp" "f"); COMP_CWORD=1; COMPREPLY=()
     _rp_completion
     [[ "${COMPREPLY[*]}" == *"foo"* ]]
   }
   ```

7. **`_rp_completion skips after first argument`**:
   ```bash
   @test "_rp_completion skips completion after first argument" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     printf '%s\n' "/home/user/projects/foo" > "$TEST_CACHE_DIR/p_history"
     COMP_WORDS=("rp" "foo" ""); COMP_CWORD=2; COMPREPLY=()
     _rp_completion
     (( ${#COMPREPLY[@]} == 0 ))
   }
   ```

8. **`_rp_completion with missing history returns cleanly`**:
   ```bash
   @test "_rp_completion with missing history returns cleanly" {
     [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
     rm -f "$TEST_CACHE_DIR/p_history"
     COMP_WORDS=("rp" ""); COMP_CWORD=1; COMPREPLY=()
     _rp_completion
     (( ${#COMPREPLY[@]} == 0 ))
   }
   ```

**Key notes:**
- All completion tests are bash-only since zsh completion uses `compadd` which can't easily be tested in bats
- The `TEST_CACHE_DIR` variable (set in the test setup) points to `$XDG_CACHE_HOME/p` — the completion functions read cache from `${XDG_CACHE_HOME:-$HOME/.cache}/p`
- Test 3 (spaces) is the one that will fail before the Step 2.2 fix — this validates the TDD approach
- Check the test setup function to verify `TEST_CACHE_DIR` is correctly set to the XDG cache path used by the completion functions
