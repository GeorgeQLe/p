#!/usr/bin/env bats

# Test suite for p — project directory jumper and scaffolder
#
# By default tests p.bash. Set TEST_SHELL=zsh to test p.zsh instead.
# Requires bash 4+ (Homebrew bash on macOS) since p.bash has a version guard.
#
# Run:
#   bats tests/p.bats                  # test bash variant
#   TEST_SHELL=zsh bats tests/p.bats   # test zsh variant

setup() {
  TEST_DIR="$(mktemp -d)"
  export P_BASE="$TEST_DIR/projects"
  export P_CONFIG="$TEST_DIR/categories.conf"
  export HOME="$TEST_DIR/home"
  mkdir -p "$P_BASE" "$HOME"

  SCRIPT_DIR="$BATS_TEST_DIRNAME/.."
  SHELL_VARIANT="${TEST_SHELL:-bash}"

  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    SOURCE_FILE="$SCRIPT_DIR/p.zsh"
  else
    SOURCE_FILE="$SCRIPT_DIR/p.bash"
  fi
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a fake project with .git dir
_make_project() {
  local dir="$P_BASE/$1"
  mkdir -p "$dir/.git"
}

# Helper: run a p command in the correct shell.
# For bash, we spawn a new bash 4+ process to avoid the version guard.
# For zsh, we spawn zsh with compdef stubbed out.
_p() {
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  fi
}

# ============================================================
# Version and help
# ============================================================

@test "p --version prints version" {
  run _p p --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
}

@test "p -V prints version" {
  run _p p -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
}

@test "p --help shows usage info" {
  run _p p --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"project directory jumper"* ]]
  [[ "$output" == *"P_BASE"* ]]
}

@test "p -h shows usage info" {
  run _p p -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"project directory jumper"* ]]
}

@test "sp --help shows usage info" {
  run _p sp --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"search for projects"* ]]
}

@test "np --help shows usage info" {
  run _p np --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"create a new project"* ]]
  [[ "$output" == *"--category"* ]]
}

# ============================================================
# P_BASE validation
# ============================================================

@test "p fails when P_BASE does not exist" {
  P_BASE="$TEST_DIR/nonexistent"
  run _p p foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "sp fails when P_BASE does not exist" {
  P_BASE="$TEST_DIR/nonexistent"
  run _p sp foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "np fails when P_BASE does not exist" {
  P_BASE="$TEST_DIR/nonexistent"
  run _p np testproj --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================
# _p_find_all_dirs
# ============================================================

@test "_p_find_all_dirs finds git directories" {
  _make_project "libs/my-lib"
  _make_project "web/dev/my-app"
  run _p _p_find_all_dirs
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-lib"* ]]
  [[ "$output" == *"my-app"* ]]
}

@test "_p_find_all_dirs returns empty for empty P_BASE" {
  run _p _p_find_all_dirs
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "_p_find_all_dirs excludes node_modules" {
  _make_project "web/dev/my-app"
  mkdir -p "$P_BASE/web/dev/my-app/node_modules/dep/.git"
  run _p _p_find_all_dirs
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-app"* ]]
  [[ "$output" != *"node_modules"* ]]
}

# ============================================================
# _p_classify_dirs
# ============================================================

@test "_p_classify_dirs marks standalone correctly" {
  _make_project "libs/my-lib"
  local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    run zsh -f -c "
      compdef() { :; }; autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_classify_dirs \"\$(_p_find_all_dirs)\"
    "
  else
    run "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_classify_dirs \"\$(_p_find_all_dirs)\"
    "
  fi
  [[ "$output" == *"S "* ]]
  [[ "$output" == *"my-lib"* ]]
}

@test "_p_classify_dirs marks sub-packages correctly" {
  # Parent at depth 2, child at depth 3 — both within maxdepth 5
  _make_project "libs/my-app"
  _make_project "libs/my-app/sub"
  # Run classify through a single shell invocation
  local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    run zsh -f -c "
      compdef() { :; }; autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_classify_dirs \"\$(_p_find_all_dirs)\"
    "
  else
    run "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_classify_dirs \"\$(_p_find_all_dirs)\"
    "
  fi
  [[ "$output" == *"S "*"my-app"* ]]
  [[ "$output" == *"P "*"sub"* ]]
}

# ============================================================
# p — jump / list / multi-match
# ============================================================

@test "p with exact match jumps to project" {
  _make_project "libs/my-lib"
  run _p p my-lib
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
}

@test "p with substring match jumps to project" {
  _make_project "libs/my-awesome-lib"
  run _p p awesome
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
}

@test "p with no match returns error" {
  _make_project "libs/my-lib"
  run _p p nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects matching"* ]]
}

@test "p matching is case-insensitive" {
  _make_project "libs/my-lib"
  run _p p MY-LIB
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
}

@test "p falls back to path match when basename doesn't match" {
  _make_project "special-cat/my-app"
  # "special-cat" matches the path but not the basename "my-app"
  run _p p special-cat
  [[ "$output" == *"my-app"* ]]
}

# ============================================================
# p — flag handling
# ============================================================

@test "p rejects unknown flags" {
  run _p p --badopt
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "p -- allows flag-like query" {
  _make_project "libs/test-proj"
  # -- should prevent "-t" from being interpreted as a flag
  run _p p -- test-proj
  [[ "$output" != *"unknown option"* ]]
}

# ============================================================
# sp — search
# ============================================================

@test "sp with no query shows usage" {
  run _p sp
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "sp finds matching projects" {
  _make_project "libs/foo-bar"
  _make_project "web/dev/foo-baz"
  run _p sp foo <<< "n"
  [[ "$output" == *"foo-bar"* ]]
  [[ "$output" == *"foo-baz"* ]]
  [[ "$output" == *"2 match"* ]]
}

@test "sp with no match returns error" {
  _make_project "libs/my-lib"
  run _p sp nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects matching"* ]]
}

@test "sp rejects unknown flags" {
  run _p sp --badopt
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

# ============================================================
# np — name validation
# ============================================================

@test "np rejects empty name non-interactively" {
  run _p np "" --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid name"* ]]
}

@test "np rejects uppercase names" {
  run _p np MyProject --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid name"* ]]
}

@test "np rejects trailing hyphens" {
  run _p np "my-project-" --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid name"* ]]
}

@test "np rejects leading hyphens" {
  run _p np -- "-my-project" --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid name"* ]]
}

@test "np rejects names with spaces" {
  run _p np "my project" --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid name"* ]]
}

@test "np accepts valid kebab-case" {
  run _p np my-cool-project --category libs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created"* ]]
}

@test "np accepts single character name" {
  run _p np a --category libs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created"* ]]
}

@test "np accepts name with numbers" {
  run _p np lib2go --category libs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created"* ]]
}

# ============================================================
# np — non-interactive mode
# ============================================================

@test "np --category flat creates correct path" {
  run _p np my-lib --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-lib" ]
  [ -d "$P_BASE/libs/my-lib/.git" ]
  [[ "$output" == *"libs/my-lib"* ]]
}

@test "np --category lifecycle creates correct path" {
  run _p np my-app --category web
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/web/dev/my-app" ]
  [[ "$output" == *"web/dev/my-app"* ]]
}

@test "np --category sandbox requires --sandbox-type" {
  run _p np my-exp --category sandbox
  [ "$status" -ne 0 ]
  [[ "$output" == *"--sandbox-type required"* ]]
}

@test "np --category sandbox with --sandbox-type creates correct path" {
  run _p np my-exp --category sandbox --sandbox-type web
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/sandbox/web/my-exp" ]
  [[ "$output" == *"sandbox/web/my-exp"* ]]
}

@test "np --category unknown fails" {
  run _p np my-proj --category nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown category"* ]]
}

@test "np rejects unknown flags" {
  run _p np --badopt
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "np refuses to create over existing directory" {
  _make_project "libs/my-lib"
  run _p np my-lib --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

# ============================================================
# np — config loading and validation
# ============================================================

@test "np uses default categories when no config exists" {
  rm -f "$P_CONFIG"
  run _p np my-lib --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-lib" ]
}

@test "np loads custom categories from config" {
  cat > "$P_CONFIG" <<'CONF'
# custom config
mycat|flat|My custom category
CONF
  run _p np my-proj --category mycat
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/mycat/my-proj" ]
}

@test "np warns on malformed config lines" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Good line
bad line without pipes
web|lifecycle|Another good line
CONF
  run _p np my-lib --category libs
  [[ "$output" == *"warning"* ]]
  [[ "$output" == *"malformed"* ]]
  # Should still work with valid lines
  [ "$status" -eq 0 ]
}

@test "np warns on unknown category type in config" {
  cat > "$P_CONFIG" <<'CONF'
libs|badtype|My libs
web|lifecycle|Web apps
CONF
  run _p np my-app --category web
  [[ "$output" == *"warning"* ]]
  [[ "$output" == *"unknown category type"* ]]
  [ "$status" -eq 0 ]
}

@test "np warns on empty sandbox_type in config" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
sandbox_type:
sandbox_type:web
CONF
  run _p np my-lib --category libs
  [[ "$output" == *"warning"* ]]
  [[ "$output" == *"empty sandbox_type"* ]]
  [ "$status" -eq 0 ]
}

# ============================================================
# Edge cases
# ============================================================

@test "paths with spaces in project name work" {
  mkdir -p "$P_BASE/libs/my lib/.git"
  run _p p "my lib"
  [[ "$output" == *"→"* ]] || [[ "$output" == *"my lib"* ]]
}

@test "depth-5 boundary: project at depth 5 is found" {
  mkdir -p "$P_BASE/a/b/c/d/deep-proj/.git"
  run _p p deep-proj
  [[ "$output" == *"deep-proj"* ]]
}

@test "depth-6 boundary: project beyond depth 5 is NOT found" {
  mkdir -p "$P_BASE/a/b/c/d/e/too-deep/.git"
  run _p p too-deep
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects"* ]]
}

@test "empty P_BASE directory returns no matches for p" {
  run _p p foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects"* ]]
}

# ============================================================
# Bash version guard (bash-only)
# ============================================================

@test "bash version guard rejects bash 3.x" {
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    skip "bash-only test"
  fi
  # /bin/bash must be bash 3.x for this test to be meaningful
  local bin_bash_ver
  bin_bash_ver=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')
  if (( bin_bash_ver >= 4 )); then
    skip "/bin/bash is bash ${bin_bash_ver}.x (need 3.x to test version guard)"
  fi
  # return in a sourced context exits 0, but prints warning and skips definitions
  run /bin/bash -c "source '$SOURCE_FILE' 2>&1; echo FUNC_DEFINED=\$(type -t p 2>/dev/null || echo none)"
  [[ "$output" == *"bash 4.0+ required"* ]]
  [[ "$output" == *"FUNC_DEFINED=none"* ]]
}

# ============================================================
# p --doctor
# ============================================================

@test "p --doctor exits 0 and contains header" {
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"p doctor"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "p --doctor reports P_BASE exists" {
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"P_BASE:"*"exists"* ]]
}

@test "p --doctor reports P_BASE missing" {
  P_BASE="$TEST_DIR/nonexistent"
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"P_BASE:"*"not found"* ]]
}

@test "p --doctor reports git availability" {
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git:"* ]]
}

@test "p --doctor reports project count" {
  _make_project "libs/my-lib"
  _make_project "web/dev/my-app"
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 projects found"* ]]
}

@test "p --doctor reports config defaults when no config file" {
  rm -f "$P_CONFIG"
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found, using defaults"* ]]
  [[ "$output" == *"built-in defaults"* ]]
}

@test "p --doctor reports custom config when file exists" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"P_CONFIG:"*"found"* ]]
}

# ============================================================
# pconfig --help
# ============================================================

@test "pconfig --help shows help text" {
  run _p pconfig --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"pconfig"* ]]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"add"* ]]
  [[ "$output" == *"remove"* ]]
}

# ============================================================
# pconfig show
# ============================================================

@test "pconfig show displays default categories when no config" {
  rm -f "$P_CONFIG"
  run _p pconfig show
  [ "$status" -eq 0 ]
  [[ "$output" == *"libs"* ]]
  [[ "$output" == *"web"* ]]
  [[ "$output" == *"sandbox"* ]]
  [[ "$output" == *"built-in defaults"* ]]
}

@test "pconfig show displays custom categories from config file" {
  cat > "$P_CONFIG" <<'CONF'
mycat|flat|My custom category
sandbox_type:special
CONF
  run _p pconfig show
  [ "$status" -eq 0 ]
  [[ "$output" == *"mycat"* ]]
  [[ "$output" == *"special"* ]]
}

@test "pconfig with no args shows config (same as show)" {
  rm -f "$P_CONFIG"
  run _p pconfig
  [ "$status" -eq 0 ]
  [[ "$output" == *"p config"* ]]
  [[ "$output" == *"Categories"* ]]
}

# ============================================================
# pconfig init
# ============================================================

@test "pconfig init creates config file with defaults" {
  rm -f "$P_CONFIG"
  run _p pconfig init
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created config file"* ]]
  [ -f "$P_CONFIG" ]
}

@test "pconfig init refuses to overwrite existing config" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  run _p pconfig init
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "pconfig init creates directory if missing" {
  P_CONFIG="$TEST_DIR/newdir/subdir/categories.conf"
  run _p pconfig init
  [ "$status" -eq 0 ]
  [ -f "$P_CONFIG" ]
}

# ============================================================
# pconfig path
# ============================================================

@test "pconfig path prints config path" {
  run _p pconfig path
  [ "$status" -eq 0 ]
  [[ "$output" == *"categories.conf"* ]]
}

# ============================================================
# pconfig remove
# ============================================================

@test "pconfig remove with piped input removes correct category" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Remove first category (libs)
  run _p pconfig remove <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed category: libs"* ]]
  # Verify libs is gone from config
  run _p pconfig show
  [[ "$output" != *"[flat]"*"Reusable libraries"* ]]
}

@test "pconfig remove refuses to remove last category" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Init creates 5 default categories. Remove 4.
  run _p pconfig remove <<< "1"
  [ "$status" -eq 0 ]
  run _p pconfig remove <<< "1"
  [ "$status" -eq 0 ]
  run _p pconfig remove <<< "1"
  [ "$status" -eq 0 ]
  run _p pconfig remove <<< "1"
  [ "$status" -eq 0 ]
  # Now only 1 remains — should refuse
  run _p pconfig remove <<< "1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot remove last category"* ]]
}

# ============================================================
# p --doctor — cache reporting
# ============================================================

@test "p --doctor reports empty cache as empty" {
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  true > "$cache_dir/p_completion"
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"p_completion"*"empty"* ]]
}

@test "p --doctor reports populated cache as valid" {
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  echo "foo" > "$cache_dir/p_completion"
  run _p p --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"p_completion"*"valid"* ]]
}

# ============================================================
# pconfig add-sandbox-type / remove-sandbox-type
# ============================================================

@test "pconfig add-sandbox-type with piped input adds type" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  run _p pconfig add-sandbox-type <<< "mobile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added sandbox type: mobile"* ]]
  # Verify it shows up
  run _p pconfig show
  [[ "$output" == *"mobile"* ]]
}

@test "pconfig remove-sandbox-type with piped input removes type" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Remove first sandbox type (web)
  run _p pconfig remove-sandbox-type <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed sandbox type: web"* ]]
}

# ============================================================
# p config alias
# ============================================================

@test "p config show delegates to pconfig" {
  rm -f "$P_CONFIG"
  run _p p config show
  [ "$status" -eq 0 ]
  [[ "$output" == *"p config"* ]]
  [[ "$output" == *"Categories"* ]]
}

# ============================================================
# pconfig add validation
# ============================================================

@test "pconfig add rejects duplicate category names" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Try to add "libs" which already exists
  run _p pconfig add <<< $'libs\nflat\nDuplicate'
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "pconfig add rejects invalid category types" {
  rm -f "$P_CONFIG"
  run _p pconfig add <<< $'newcat\nbadtype\nSome desc'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be flat, lifecycle, or sandbox"* ]]
}

# ============================================================
# Config round-trip: written config is loadable
# ============================================================

@test "config file written by pconfig is loadable by _p_load_categories" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Now use np with the pconfig-written config to verify it's parseable
  run _p np my-lib --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-lib" ]
}

# ============================================================
# pconfig unknown command
# ============================================================

@test "pconfig unknown command errors" {
  run _p pconfig badcommand
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}

# ============================================================
# p — no arguments lists all projects
# ============================================================

@test "p with no arguments lists all projects" {
  _make_project "libs/alpha"
  _make_project "web/dev/beta"
  # No query, multiple projects => "Multiple matches:" with numbered list
  run _p p <<< ""
  [ "$status" -ne 0 ]  # Cancelled (empty input to picker)
  [[ "$output" == *"Multiple matches:"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "p with no arguments and empty P_BASE shows 'No projects found'" {
  run _p p
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects found"* ]]
  # Must NOT contain the ugly "No projects matching ''"
  [[ "$output" != *"matching ''"* ]]
}

# ============================================================
# p — multi-match selection
# ============================================================

@test "p with multiple matches and piped selection jumps correctly" {
  _make_project "libs/foo-one"
  _make_project "libs/foo-two"
  # Both match "foo", pick #2
  run _p p foo <<< "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"foo-two"* ]]
}

@test "p with multiple matches and invalid selection cancels" {
  _make_project "libs/foo-one"
  _make_project "libs/foo-two"
  run _p p foo <<< "bad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cancelled"* ]]
}

# ============================================================
# sp — piped selection
# ============================================================

@test "sp with piped selection jumps to project" {
  _make_project "libs/bar-proj"
  run _p sp bar <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"bar-proj"* ]]
}

# ============================================================
# p --origin
# ============================================================

@test "p --origin changes to script directory" {
  run _p p --origin
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
}

# ============================================================
# pconfig add — happy path
# ============================================================

@test "pconfig add happy path creates category" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Pipe: name, type, description
  run _p pconfig add <<< $'games\nflat\nGame projects'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added category: games (flat)"* ]]
  # Verify it shows up
  run _p pconfig show
  [[ "$output" == *"games"* ]]
  [[ "$output" == *"Game projects"* ]]
}

# ============================================================
# pconfig add — path traversal rejection (issue #2)
# ============================================================

@test "pconfig add rejects path-traversal category names" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  run _p pconfig add <<< $'../../etc\nflat\nEvil'
  [ "$status" -ne 0 ]
  [[ "$output" == *"kebab-case"* ]]
}

@test "pconfig add rejects uppercase category names" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  run _p pconfig add <<< $'MyCategory\nflat\nBad name'
  [ "$status" -ne 0 ]
  [[ "$output" == *"kebab-case"* ]]
}

@test "pconfig add rejects category names with spaces" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  run _p pconfig add <<< $'my category\nflat\nBad name'
  [ "$status" -ne 0 ]
  [[ "$output" == *"kebab-case"* ]]
}

# ============================================================
# np --category / --sandbox-type missing value (issue #3)
# ============================================================

@test "np --category with no value gives clear error" {
  run _p np my-proj --category
  [ "$status" -ne 0 ]
  [[ "$output" == *"--category requires a value"* ]]
}

@test "np --sandbox-type with no value gives clear error" {
  run _p np my-proj --category sandbox --sandbox-type
  [ "$status" -ne 0 ]
  [[ "$output" == *"--sandbox-type requires a value"* ]]
}

# ============================================================
# np — cache invalidation (issue #6)
# ============================================================

@test "np invalidates completion cache after creating project" {
  # Create cache files
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  echo "stale" > "$cache_dir/p_completion"
  echo "stale" > "$cache_dir/sp_completion"
  # Create a project
  run _p np my-proj --category libs
  [ "$status" -eq 0 ]
  # Cache files should be deleted
  [ ! -f "$cache_dir/p_completion" ]
  [ ! -f "$cache_dir/sp_completion" ]
}

# ============================================================
# p --dev
# ============================================================

# Helper: run a p command with a mock dev tool.
# Creates a "mock-dev" script that just prints "DEV_LAUNCHED" so we
# can detect the tool was invoked without starting a real CLI.
_p_with_mock_dev() {
  local mock_dir="$TEST_DIR/bin"
  mkdir -p "$mock_dir"
  printf '#!/bin/sh\necho DEV_LAUNCHED\n' > "$mock_dir/mock-dev"
  chmod +x "$mock_dir/mock-dev"
  local saved_path="$PATH"
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export P_DEV_TOOL='mock-dev'
      export PATH='$mock_dir:$saved_path'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export P_DEV_TOOL='mock-dev'
      export PATH='$mock_dir:$saved_path'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  fi
}

@test "p --dev with no query cds to script dir and launches tool" {
  run _p_with_mock_dev p --dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"DEV_LAUNCHED"* ]]
}

@test "p --dev <query> with single match cds to project and launches tool" {
  _make_project "libs/my-lib"
  run _p_with_mock_dev p --dev my-lib
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"my-lib"* ]]
  [[ "$output" == *"DEV_LAUNCHED"* ]]
}

@test "p --dev with no match fails without launching tool" {
  _make_project "libs/my-lib"
  run _p_with_mock_dev p --dev nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No projects matching"* ]]
  [[ "$output" != *"DEV_LAUNCHED"* ]]
}

@test "P_DEV_TOOL env var overrides config dev_tool" {
  # Write a config with dev_tool:badtool
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
dev_tool:badtool
CONF
  # P_DEV_TOOL=mock-dev should override badtool
  run _p_with_mock_dev p --dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_LAUNCHED"* ]]
}

@test "p --dev with missing tool shows error" {
  local saved_path="$PATH"
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    run zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export P_DEV_TOOL='nonexistent-tool-xyz'
      export PATH='$saved_path'
      source '$SOURCE_FILE'
      p --dev
    "
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    run "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export P_DEV_TOOL='nonexistent-tool-xyz'
      export PATH='$saved_path'
      source '$SOURCE_FILE'
      p --dev
    "
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"dev tool not found"* ]]
}

@test "p --dev reads dev_tool from config file" {
  local mock_dir="$TEST_DIR/bin"
  mkdir -p "$mock_dir"
  printf '#!/bin/sh\necho TOOL_FROM_CONFIG\n' > "$mock_dir/my-tool"
  chmod +x "$mock_dir/my-tool"
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
dev_tool:my-tool
CONF
  local saved_path="$PATH"
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    run zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export PATH='$mock_dir:$saved_path'
      source '$SOURCE_FILE'
      p --dev
    "
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    run "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      export PATH='$mock_dir:$saved_path'
      source '$SOURCE_FILE'
      p --dev
    "
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOOL_FROM_CONFIG"* ]]
}

# ============================================================
# pconfig set-dev-tool
# ============================================================

@test "pconfig set-dev-tool saves tool directly" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  run _p pconfig set-dev-tool claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tool set to: claude"* ]]
  # Verify it persists in config
  run _p pconfig show
  [[ "$output" == *"claude"* ]]
}

@test "pconfig set-dev-tool with piped interactive selection saves tool" {
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Pick option 2 (codex)
  run _p pconfig set-dev-tool <<< "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tool set to: codex"* ]]
}

@test "pconfig show displays dev tool when configured" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
dev_tool:gemini
CONF
  run _p pconfig show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tool:"* ]]
  [[ "$output" == *"gemini"* ]]
}

@test "pconfig show displays (not configured) when no dev tool" {
  rm -f "$P_CONFIG"
  run _p pconfig show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev tool:"* ]]
  [[ "$output" == *"(not configured)"* ]]
}

@test "pconfig --help mentions set-dev-tool" {
  run _p pconfig --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"set-dev-tool"* ]]
}

@test "p --help mentions --dev" {
  run _p p --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dev"* ]]
  [[ "$output" == *"P_DEV_TOOL"* ]]
}

@test "_p_resolve_dev_tool interactive prompt saves to config" {
  rm -f "$P_CONFIG"
  run _p pconfig init
  [ "$status" -eq 0 ]
  # Pick option 1 (claude) via piped input
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    run zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_resolve_dev_tool
    " <<< "1"
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    run "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      _p_resolve_dev_tool
    " <<< "1"
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
  # Verify saved to config file
  [[ -f "$P_CONFIG" ]]
  grep -q "dev_tool:claude" "$P_CONFIG"
}

# ============================================================
# _p_record_visit — history recording
# ============================================================

@test "p records visit to history file after jump" {
  _make_project "libs/my-lib"
  run _p p my-lib
  [ "$status" -eq 0 ]
  local history_file="$HOME/.cache/p/p_history"
  [ -f "$history_file" ]
  grep -q "my-lib" "$history_file"
}

@test "_p_record_visit deduplicates entries" {
  _make_project "libs/my-lib"
  run _p p my-lib
  run _p p my-lib
  local history_file="$HOME/.cache/p/p_history"
  local count
  count=$(grep -c "my-lib" "$history_file")
  [ "$count" -eq 1 ]
}

@test "_p_record_visit moves duplicate to end" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  run _p p alpha
  local history_file="$HOME/.cache/p/p_history"
  # alpha should be the last line
  local last_line
  last_line=$(tail -n1 "$history_file")
  [[ "$last_line" == *"alpha"* ]]
}

@test "sp records visit to history file" {
  _make_project "libs/bar-proj"
  run _p sp bar <<< "1"
  [ "$status" -eq 0 ]
  local history_file="$HOME/.cache/p/p_history"
  [ -f "$history_file" ]
  grep -q "bar-proj" "$history_file"
}

@test "np records visit to history file" {
  run _p np my-new-proj --category libs
  [ "$status" -eq 0 ]
  local history_file="$HOME/.cache/p/p_history"
  [ -f "$history_file" ]
  grep -q "my-new-proj" "$history_file"
}

# ============================================================
# np — P_NP_HOOK post-creation hook
# ============================================================

# Helper: run a p command with P_NP_HOOK set
_p_hook() {
  local hook="$1"; shift
  if [[ "$SHELL_VARIANT" == "zsh" ]]; then
    zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME' P_NP_HOOK='$hook'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  else
    local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
    "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME' P_NP_HOOK='$hook'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  fi
}

@test "np calls P_NP_HOOK with correct arguments" {
  local hook="$TEST_DIR/test-hook"
  local log="$TEST_DIR/hook-log"
  cat > "$hook" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/hook-log"
SCRIPT
  chmod +x "$hook"
  run _p_hook "$hook" np my-proj --category libs
  [ "$status" -eq 0 ]
  [ -f "$HOME/hook-log" ]
  # 4 lines: name, category, type, path
  local lines
  lines=$(wc -l < "$HOME/hook-log")
  [ "$lines" -eq 4 ]
  head -1 "$HOME/hook-log" | grep -q "my-proj"
  sed -n '2p' "$HOME/hook-log" | grep -q "libs"
  sed -n '3p' "$HOME/hook-log" | grep -q "flat"
  sed -n '4p' "$HOME/hook-log" | grep -q "libs/my-proj"
}

@test "np warns but succeeds when P_NP_HOOK fails" {
  local hook="$TEST_DIR/fail-hook"
  cat > "$hook" <<'SCRIPT'
#!/usr/bin/env bash
exit 42
SCRIPT
  chmod +x "$hook"
  run _p_hook "$hook" np my-proj --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-proj" ]
  [[ "$output" == *"warning: post-hook exited 42"* ]]
}

@test "np does not call hook when P_NP_HOOK is unset" {
  local log="$TEST_DIR/hook-log"
  # P_NP_HOOK is not set in the normal _p helper
  run _p np my-proj --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-proj" ]
  [ ! -f "$log" ]
}

@test "np does not call hook when P_NP_HOOK is not executable" {
  local hook="$TEST_DIR/noexec-hook"
  cat > "$hook" <<'SCRIPT'
#!/usr/bin/env bash
touch "$HOME/hook-ran"
SCRIPT
  # intentionally NOT chmod +x
  run _p_hook "$hook" np my-proj --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-proj" ]
  [ ! -f "$HOME/hook-ran" ]
}

# ============================================================
# np --clone
# ============================================================

# Helper: install a fake git wrapper that simulates clone into $TEST_DIR/bin
_install_fakegit() {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/git" <<'FAKESCRIPT'
#!/bin/bash
if [[ "$1" == "clone" ]]; then
  mkdir -p "$3/.git"
  exit 0
elif [[ "$1" == "-C" && "$3" == "init" ]]; then
  mkdir -p "$2/.git"
  exit 0
elif [[ "$1" == "init" ]]; then
  exit 0
fi
FAKESCRIPT
  chmod +x "$TEST_DIR/bin/git"
}

# Helper: install a fake git wrapper that fails on clone
_install_fakegit_fail() {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/git" <<'FAKESCRIPT'
#!/bin/bash
if [[ "$1" == "clone" ]]; then
  echo "fatal: repository not found" >&2
  exit 128
elif [[ "$1" == "-C" && "$3" == "init" ]]; then
  exit 0
elif [[ "$1" == "init" ]]; then
  exit 0
fi
FAKESCRIPT
  chmod +x "$TEST_DIR/bin/git"
}

# Helper: run a p command with $TEST_DIR/bin prepended to PATH (for fake git)
_p_withpath() {
  local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
  if [[ "${SHELL_VARIANT:-bash}" == "zsh" ]]; then
    PATH="$TEST_DIR/bin:$PATH" zsh -f -c "
      compdef() { :; }
      autoload() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  else
    PATH="$TEST_DIR/bin:$PATH" "$bash_bin" -c "
      complete() { :; }
      export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
      source '$SOURCE_FILE'
      \"\$@\"
    " -- "$@"
  fi
}

@test "np --clone with explicit name clones into correct path" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  _install_fakegit
  run _p_withpath np my-clone --clone https://github.com/user/repo.git --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-clone/.git" ]
  [[ "$output" == *"Created:"* ]]
}

@test "np --clone derives name from URL when name omitted" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  _install_fakegit
  run _p_withpath np --clone https://github.com/user/my-cool-repo.git --category libs
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/libs/my-cool-repo/.git" ]
}

@test "np --clone name derivation converts underscores and dots to hyphens" {
  run _p _np_name_from_url "https://github.com/user/My_Cool.Repo.git"
  [ "$status" -eq 0 ]
  [[ "$output" == "my-cool-repo" ]]
}

@test "np --clone failure returns error gracefully" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  _install_fakegit_fail
  run _p_withpath np my-fail --clone https://github.com/user/nonexistent.git --category libs
  [ "$status" -ne 0 ]
  [[ "$output" == *"clone failed"* ]]
}

@test "np --clone with no value gives error" {
  run _p np --clone
  [ "$status" -ne 0 ]
  [[ "$output" == *"--clone requires a URL"* ]]
}

@test "np --clone into lifecycle category" {
  cat > "$P_CONFIG" <<'CONF'
tools|lifecycle|Tools
CONF
  _install_fakegit
  run _p_withpath np cloned-proj --clone https://github.com/user/repo --category tools
  [ "$status" -eq 0 ]
  [ -d "$P_BASE/tools/dev/cloned-proj/.git" ]
}

@test "np --clone records visit to history" {
  cat > "$P_CONFIG" <<'CONF'
libs|flat|Libraries
CONF
  _install_fakegit
  run _p_withpath np cloned-lib --clone https://github.com/user/repo.git --category libs
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
}

@test "_np_name_from_url handles various URL formats" {
  # HTTPS with .git
  run _p _np_name_from_url "https://github.com/user/my-repo.git"
  [[ "$output" == "my-repo" ]]

  # HTTPS without .git
  run _p _np_name_from_url "https://github.com/user/my-repo"
  [[ "$output" == "my-repo" ]]

  # SSH URL
  run _p _np_name_from_url "git@github.com:user/my-repo.git"
  [[ "$output" == "my-repo" ]]

  # Trailing slash
  run _p _np_name_from_url "https://github.com/user/my-repo/"
  [[ "$output" == "my-repo" ]]

  # Underscores and dots
  run _p _np_name_from_url "https://github.com/user/My_Project.Name.git"
  [[ "$output" == "my-project-name" ]]
}

# ============================================================
# rp — recent projects
# ============================================================

@test "rp --help shows usage" {
  run _p rp --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"recently-visited"* ]]
}

@test "rp with empty history returns error" {
  run _p rp
  [ "$status" -ne 0 ]
  [[ "$output" == *"No project history"* ]]
}

@test "rp with single entry auto-jumps" {
  _make_project "libs/my-lib"
  run _p p my-lib
  run _p rp
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"my-lib"* ]]
}

@test "rp with multiple entries shows list and picks" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  # Pick #1 (most recent = beta)
  run _p rp <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "rp <query> filters by basename" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  run _p rp alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"alpha"* ]]
}

@test "rp <query> matches full path" {
  _make_project "libs/my-proj"
  run _p p my-proj
  run _p rp libs
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"my-proj"* ]]
}

@test "rp with no matching query returns error" {
  _make_project "libs/my-lib"
  run _p p my-lib
  run _p rp nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No recent projects matching"* ]]
}

@test "rp --clear clears history" {
  _make_project "libs/my-lib"
  run _p p my-lib
  run _p rp --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
  run _p rp
  [ "$status" -ne 0 ]
  [[ "$output" == *"No project history"* ]]
}

@test "rp rejects unknown flags" {
  run _p rp --badopt
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "rp shows most recent first" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  # No query, cancel to see list
  run _p rp <<< ""
  # beta should be #1 (most recent), alpha should be #2
  [[ "$output" == *"1) beta"* ]]
  [[ "$output" == *"2) alpha"* ]]
}

@test "rp with stale single entry shows message and removes it" {
  _make_project "libs/stale-lib"
  run _p p stale-lib
  rm -rf "$P_BASE/libs/stale-lib"
  run _p rp
  [ "$status" -ne 0 ]
  [[ "$output" == *"no longer exists"* ]] || [[ "$output" == *"removed stale"* ]]
}

@test "rp with mix of valid and stale entries only shows valid ones" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  rm -rf "$P_BASE/libs/beta"
  run _p rp
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" != *"beta"* ]] || [[ "$output" == *"stale"* ]]
}

@test "rp --prune removes stale entries and reports count" {
  _make_project "libs/alpha"
  _make_project "libs/beta"
  run _p p alpha
  run _p p beta
  rm -rf "$P_BASE/libs/alpha" "$P_BASE/libs/beta"
  run _p rp --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed 2 stale"* ]]
}

@test "rp --prune with no stale entries reports nothing to prune" {
  _make_project "libs/my-lib"
  run _p p my-lib
  run _p rp --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"No stale entries"* ]]
}

@test "rp --help mentions --prune" {
  run _p rp --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--prune"* ]]
}

@test "p --help mentions rp" {
  run _p p --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"rp"* ]]
}

# ============================================================
# Completion functions (bash-only — zsh uses compadd)
# ============================================================

# Helper: run a completion function in a bash subprocess and print COMPREPLY
_run_completion() {
  local func="$1" cmd="$2" cur="$3" cword="${4:-1}"
  local bash_bin="${BASH_4_BIN:-/opt/homebrew/bin/bash}"
  "$bash_bin" -c "
    complete() { :; }
    export P_BASE='$P_BASE' P_CONFIG='$P_CONFIG' HOME='$HOME'
    source '$SOURCE_FILE'
    COMP_WORDS=($cmd $cur); COMP_CWORD=$cword; COMPREPLY=()
    $func
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
}

@test "_p_completion populates candidates from cache" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "alpha" "beta" "gamma" > "$cache_dir/p_completion"
  run _run_completion _p_completion p al
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" != *"beta"* ]]
}

@test "_p_completion skips completion after first argument" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "alpha" > "$cache_dir/p_completion"
  run _run_completion _p_completion "p alpha" "" 2
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "_p_completion handles project names with spaces" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "my project" "other" > "$cache_dir/p_completion"
  run _run_completion _p_completion p my
  [ "$status" -eq 0 ]
  [[ "$output" == *"my project"* ]]
}

@test "_sp_completion populates candidates from cache" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "subrepo-a" "subrepo-b" > "$cache_dir/sp_completion"
  run _run_completion _sp_completion sp sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"subrepo-a"* ]]
}

@test "_sp_completion skips completion after first argument" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "subrepo-a" > "$cache_dir/sp_completion"
  run _run_completion _sp_completion "sp subrepo-a" "" 2
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "_rp_completion populates candidates from history" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "/home/user/projects/foo" "/home/user/projects/bar" > "$cache_dir/p_history"
  run _run_completion _rp_completion rp f
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
  [[ "$output" != *"bar"* ]]
}

@test "_rp_completion skips completion after first argument" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  local cache_dir="$HOME/.cache/p"
  mkdir -p "$cache_dir"
  printf '%s\n' "/home/user/projects/foo" > "$cache_dir/p_history"
  run _run_completion _rp_completion "rp foo" "" 2
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "_rp_completion with missing history returns cleanly" {
  [[ "${TEST_SHELL:-bash}" == "bash" ]] || skip "bash-specific completion"
  rm -f "$HOME/.cache/p/p_history"
  run _run_completion _rp_completion rp ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}
