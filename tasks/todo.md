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
- [x] Step 2.2: Fix bash `_p_completion` to handle spaces in project names
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

- [x] Step 2.3: Run tests and verify all pass
  - `bats tests/p.bats` (bash)
  - `TEST_SHELL=zsh bats tests/p.bats` (zsh)
  - `shellcheck -s bash p.bash`
  - `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`

### Milestone: Completion Hardening Complete
**Acceptance Criteria:**
- [x] Bash completion correctly completes a project name containing a space
- [x] All completion functions return 0 (not bare `return` or `return 1`) on early-exit paths
- [x] At least one test per completion function verifying it populates candidates from cache/history
- [x] At least one test verifying completion only fires on the first argument (no suggestions after arg 1)
- [x] Tests pass for both `TEST_SHELL=bash` and `TEST_SHELL=zsh`
- [x] Both p.bash and p.zsh updated in lockstep (zsh already correct, bash-only fix needed)
- [x] No regressions in previous tests

---

**Implementation plan for Step 2.2:**

Replace `compgen -W` (which splits on spaces) with line-by-line prefix matching in all 3 bash completion functions. Zsh versions use `compadd` which already handles spaces — no changes needed there.

**Files to modify:** `p.bash` only (3 functions)

1. **`_p_completion`** (p.bash line 412):
   Replace:
   ```bash
   mapfile -t COMPREPLY < <(compgen -W "$(cat "$cache_file")" -- "$cur")
   ```
   With:
   ```bash
   local candidates=()
   while IFS= read -r name; do
     [[ "$name" == "$cur"* ]] && candidates+=("$name")
   done < "$cache_file"
   COMPREPLY=("${candidates[@]}")
   ```

2. **`_sp_completion`** (p.bash line 531):
   Same replacement — replace the `mapfile -t COMPREPLY < <(compgen -W ...)` line with the same pattern reading from `$cache_file`.

3. **`_rp_completion`** (p.bash lines 687-688):
   Current:
   ```bash
   names=$(sed 's|.*/||' "$history_file" | sort -u)
   mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
   ```
   Replace with:
   ```bash
   local candidates=()
   while IFS= read -r name; do
     [[ "$name" == "$cur"* ]] && candidates+=("$name")
   done < <(sed 's|.*/||' "$history_file" | sort -u)
   COMPREPLY=("${candidates[@]}")
   ```

**Tests that should pass after this step:** All 128 tests, including test 123 (spaces).
**Verification:** `bats tests/p.bats`, `TEST_SHELL=zsh bats tests/p.bats`, `shellcheck -s bash p.bash`
