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
