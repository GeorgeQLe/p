# p - project directory jumper and scaffolder for bash
# https://github.com/GeorgeQLe/p

_P_VERSION="1.0.0"
_P_HISTORY_MAX=50

# Bash 4.0+ required for ${var,,} (lowercase), associative arrays, etc.
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "p: bash 4.0+ required (you have $BASH_VERSION). On macOS, install bash via Homebrew: brew install bash" >&2
  # shellcheck disable=SC2317
  return 2>/dev/null || exit 1
fi

# Directory where this script lives (captured at source time)
_p_origin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Returns all project directory paths (one per line)
_p_find_all_dirs() {
  local base="${P_BASE:-$HOME/projects}"
  if [[ ! -d "$base" ]]; then
    echo "p: P_BASE directory does not exist: $base" >&2
    return 1
  fi
  find "$base" -maxdepth 5 -type d \
    \( -name node_modules -prune -o -name .git -prune -print \) \
    2>/dev/null \
  | sed 's|/\.git$||' | sort -u
}

_p_cache_dir() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}/p"
}

_p_cache_file_stale() {
  local file="$1"
  local ttl="${2:-300}"
  local mtime now

  [[ -f "$file" ]] || return 0
  if mtime=$(stat -f %m "$file" 2>/dev/null); then
    :
  elif mtime=$(stat -c %Y "$file" 2>/dev/null); then
    :
  else
    return 0
  fi
  now=$(date +%s)
  (( now - mtime > ttl ))
}

_p_rebuild_completion_caches() {
  local cache_dir
  cache_dir="$(_p_cache_dir)"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir" || return 1

  local all_dirs classified p_tmp sp_tmp status_code
  all_dirs=$(_p_find_all_dirs) || return 1
  classified=$(_p_classify_dirs "$all_dirs")

  p_tmp="$(mktemp "$cache_dir/p_completion.XXXXXX")" || return 1
  sp_tmp="$(mktemp "$cache_dir/sp_completion.XXXXXX")" || {
    rm -f "$p_tmp"
    return 1
  }

  {
    echo "$classified" | grep '^S ' | sed 's|^S .*/||' | sort
    echo "$classified" | grep '^P ' | sed 's|^P .*/||' | sort
  } | awk '!seen[$0]++' > "$p_tmp" &&
    {
      if [[ -n "$all_dirs" ]]; then
        printf '%s\n' "$all_dirs" | sed 's|.*/||' | sort -u
      fi
    } > "$sp_tmp" &&
    mv "$p_tmp" "$cache_dir/p_completion" &&
    mv "$sp_tmp" "$cache_dir/sp_completion"
  status_code=$?

  rm -f "$p_tmp" "$sp_tmp"
  return "$status_code"
}

_p_refresh_completion_caches_async() {
  local cache_dir lock_dir
  cache_dir="$(_p_cache_dir)"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir" || return 0
  lock_dir="$cache_dir/completion_refresh.lock"

  if [[ -d "$lock_dir" ]] && [[ -n "$(find "$lock_dir" -mmin +10 2>/dev/null)" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi

  if mkdir "$lock_dir" 2>/dev/null; then
    (
      _p_rebuild_completion_caches >/dev/null 2>&1
      rmdir "$lock_dir" 2>/dev/null || true
    ) >/dev/null 2>&1 &
    disown "$!" 2>/dev/null || true
  fi
}

_p_ensure_completion_cache() {
  local cache_file="$1"

  if [[ ! -f "$cache_file" ]]; then
    _p_rebuild_completion_caches >/dev/null 2>&1
  elif _p_cache_file_stale "$cache_file"; then
    _p_refresh_completion_caches_async
  fi
}

# Classifies dirs as S (standalone) or P (sub-package)
# A dir is a sub-package if any other dir is a proper parent of it
_p_classify_dirs() {
  local all_dirs="$1"
  local dirs_arr=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && dirs_arr+=("$d")
  done <<< "$all_dirs"

  # Sort so parents come before children
  IFS=$'\n' read -r -d '' -a dirs_arr < <(printf '%s\n' "${dirs_arr[@]}" | sort) || true

  # Parent-stack approach: O(n) instead of O(n²)
  # Since dirs are sorted, a child always follows its parent.
  # Maintain a stack of standalone ancestors; pop non-ancestors.
  local d stack=()
  for (( i=0; i<${#dirs_arr[@]}; i++ )); do
    d="${dirs_arr[$i]}"
    while (( ${#stack[@]} > 0 )) && [[ "$d" != "${stack[-1]}/"* ]]; do
      unset 'stack[-1]'
    done
    if (( ${#stack[@]} > 0 )); then
      echo "P $d"
    else
      echo "S $d"
    fi
    stack+=("$d")
  done
}

_p_show_help() {
  cat <<'EOF'
p - project directory jumper and scaffolder

Usage:
  p [query]        Jump to a project matching query (substring, case-insensitive)
  p                List all projects
  p --dev [query]  Jump to project and launch AI CLI tool (claude, codex, etc.)
  p --origin       cd to the directory containing this script
  p --warm-cache   Rebuild tab-completion caches
  p --doctor       Check your p setup for issues
  p --help         Show this help message
  p --version      Show version
  p config [cmd]   Manage configuration (alias for pconfig)

  sp <query>       Search for projects and show results with paths
  sp --help        Show sp help

  rp [query]       Jump to a recently-visited project
  rp --clear       Clear project history
  rp --help        Show rp help

  np [name]        Create a new project (interactive scaffolder)
  np --help        Show np help
  np name --category CAT [--sandbox-type TYPE]
                   Create a project non-interactively

  pconfig [cmd]    Manage categories and sandbox types
  pconfig --help   Show pconfig help

Environment Variables:
  P_BASE           Projects root directory (default: ~/projects)
  P_CONFIG         Path to categories.conf (default: ~/.config/p/categories.conf)
  P_DEV_TOOL       Override AI CLI tool for p --dev (e.g. claude, codex, gemini)

See https://github.com/GeorgeQLe/p for full documentation.
EOF
}

_p_doctor() {
  echo "p doctor (v$_P_VERSION)"
  echo ""

  # --- Environment ---
  echo "Environment:"

  local base="${P_BASE:-$HOME/projects}"
  if [[ -d "$base" ]]; then
    local entry_count
    entry_count=$(find "$base" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✓ P_BASE: $base (exists, $entry_count entries)"
  else
    echo "  ✗ P_BASE: $base (not found)"
  fi

  if [[ -n "${BASH_VERSION:-}" ]]; then
    echo "  ✓ Shell:  bash $BASH_VERSION"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    echo "  ✓ Shell:  zsh $ZSH_VERSION"
  else
    echo "  ⚠ Shell:  unknown"
  fi

  if command -v git >/dev/null 2>&1; then
    local git_ver
    git_ver=$(git --version 2>/dev/null | sed 's/git version //')
    echo "  ✓ Git:    git $git_ver"
  else
    echo "  ✗ Git:    not found"
  fi

  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
  if [[ -f "$config" ]]; then
    echo "  ✓ P_CONFIG: $config (found)"
  else
    echo "  ✗ P_CONFIG: $config (not found, using defaults)"
  fi

  echo ""

  # --- Config ---
  echo "Config:"

  _p_load_categories
  local cat_count=${#_p_categories[@]}
  local st_count=${#_p_sandbox_types[@]}
  local cat_names=()
  for entry in "${_p_categories[@]}"; do
    cat_names+=("${entry%%|*}")
  done
  local names_str
  names_str=$(IFS=', '; echo "${cat_names[*]}")
  echo "  ✓ $cat_count categories loaded ($names_str)"
  echo "  ✓ $st_count sandbox types ($(IFS=', '; echo "${_p_sandbox_types[*]}"))"

  if [[ ! -f "$config" ]]; then
    echo "  ⚠ Config is using built-in defaults (run \`pconfig init\` to customize)"
  fi

  echo ""

  # --- Projects ---
  echo "Projects:"

  if [[ -d "$base" ]]; then
    local all_dirs
    all_dirs=$(_p_find_all_dirs 2>/dev/null) || true
    if [[ -n "$all_dirs" ]]; then
      local classified
      classified=$(_p_classify_dirs "$all_dirs")
      local total=0 standalone_count=0 subpkg_count=0
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((total++))
        if [[ "$line" == S\ * ]]; then
          ((standalone_count++))
        else
          ((subpkg_count++))
        fi
      done <<< "$classified"
      echo "  ✓ $total projects found ($standalone_count standalone, $subpkg_count sub-packages)"
    else
      echo "  ⚠ No projects found in $base"
    fi
  else
    echo "  ✗ Cannot scan (P_BASE does not exist)"
  fi

  echo ""

  # --- Cache ---
  echo "Cache:"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  local cache_names=("p_completion" "sp_completion" "p_history")
  for cname in "${cache_names[@]}"; do
    local cfile="$cache_dir/$cname"
    if [[ -f "$cfile" ]]; then
      if [[ -s "$cfile" ]]; then
        local mtime now age_sec age_min
        if stat -f %m "$cfile" >/dev/null 2>&1; then
          mtime=$(stat -f %m "$cfile")
        else
          mtime=$(stat -c %Y "$cfile")
        fi
        now=$(date +%s)
        age_sec=$(( now - mtime ))
        age_min=$(( age_sec / 60 ))
        echo "  ✓ $cname cache: valid ($age_min min old)"
      else
        echo "  ⚠ $cname cache: present (empty)"
      fi
    else
      echo "  ⚠ $cname cache: not found"
    fi
  done
}

_p_record_visit() {
  local dir="$1"
  [[ -z "$dir" ]] && return
  local history_file="${XDG_CACHE_HOME:-$HOME/.cache}/p/p_history"
  local history_dir
  history_dir="$(dirname "$history_file")"
  [[ -d "$history_dir" ]] || mkdir -p "$history_dir"

  # Read existing entries, removing duplicates of this path
  local entries=()
  if [[ -f "$history_file" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && "$line" != "$dir" ]] && entries+=("$line")
    done < "$history_file"
  fi

  # Append new entry at end (most recent)
  entries+=("$dir")

  # Trim to max entries (keep most recent)
  local count=${#entries[@]}
  if (( count > _P_HISTORY_MAX )); then
    entries=("${entries[@]:$((count - _P_HISTORY_MAX))}")
  fi

  # Write back atomically
  local tmpfile
  tmpfile="$(mktemp)" || return
  printf '%s\n' "${entries[@]}" > "$tmpfile"
  mv "$tmpfile" "$history_file"
}

p() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    _p_show_help
    return 0
  fi
  if [[ "$1" == "--version" || "$1" == "-V" ]]; then
    echo "p $_P_VERSION"
    return 0
  fi
  if [[ "$1" == "--doctor" ]]; then
    _p_doctor
    return $?
  fi
  if [[ "$1" == "--origin" ]]; then
    cd "$_p_origin_dir" || return 1
    echo "→ $(pwd)"
    return 0
  fi
  if [[ "$1" == "--warm-cache" ]]; then
    _p_rebuild_completion_caches || return 1
    echo "p: completion cache rebuilt"
    return 0
  fi
  if [[ "$1" == "--dev" ]]; then
    shift
    local dev_tool
    dev_tool=$(_p_resolve_dev_tool) || return 1
    if ! command -v "$dev_tool" >/dev/null 2>&1; then
      echo "p: dev tool not found: $dev_tool" >&2
      echo "Install it or change with: pconfig set-dev-tool" >&2
      return 1
    fi
    if [[ $# -eq 0 ]]; then
      cd "$_p_origin_dir" || return 1
      echo "→ $(pwd)"
    else
      p "$@" || return $?
    fi
    "$dev_tool"
    return $?
  fi
  if [[ "$1" == "config" ]]; then
    shift
    pconfig "$@"
    return $?
  fi

  # Treat -- as end-of-flags
  local query
  if [[ "$1" == "--" ]]; then
    query="$2"
  elif [[ -n "$1" && "$1" == -* && "$1" != "--" ]]; then
    echo "p: unknown option: $1" >&2
    echo "Usage: p [--help | --version | --origin | --warm-cache | query]" >&2
    return 1
  else
    query="$1"
  fi

  local base="${P_BASE:-$HOME/projects}"

  local all_dirs
  all_dirs=$(_p_find_all_dirs) || return 1

  local classified
  classified=$(_p_classify_dirs "$all_dirs")

  # Parse into standalone and subpkg arrays
  local standalone=() subpkg=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local tag="${line%% *}"
    local path="${line#* }"
    if [[ "$tag" == "S" ]]; then
      standalone+=("$path")
    else
      subpkg+=("$path")
    fi
  done <<< "$classified"

  local matches=()

  if [[ -n "$query" ]]; then
    local q="${query,,}"

    # Phase 1: basename match
    local sa_basename=() sp_basename=()
    for d in "${standalone[@]}"; do
      local name="${d##*/}"
      [[ "${name,,}" == *"$q"* ]] && sa_basename+=("$d")
    done
    for d in "${subpkg[@]}"; do
      local name="${d##*/}"
      [[ "${name,,}" == *"$q"* ]] && sp_basename+=("$d")
    done

    if (( ${#sa_basename[@]} + ${#sp_basename[@]} > 0 )); then
      matches=("${sa_basename[@]}" "${sp_basename[@]}")
    else
      # Phase 2: relative path fallback
      local sa_path=() sp_path=()
      for d in "${standalone[@]}"; do
        local rel="${d#"$base"/}"
        [[ "${rel,,}" == *"$q"* ]] && sa_path+=("$d")
      done
      for d in "${subpkg[@]}"; do
        local rel="${d#"$base"/}"
        [[ "${rel,,}" == *"$q"* ]] && sp_path+=("$d")
      done
      matches=("${sa_path[@]}" "${sp_path[@]}")
    fi
  else
    # No query: all dirs, standalone first
    matches=("${standalone[@]}" "${subpkg[@]}")
  fi

  local count=${#matches[@]}

  if [[ "$count" -eq 0 ]]; then
    if [[ -n "$query" ]]; then
      echo "No projects matching '$query'" >&2
    else
      echo "No projects found" >&2
    fi
    return 1
  elif [[ "$count" -eq 1 ]]; then
    cd "${matches[0]}" || return 1
    echo "→ $(pwd)"
    _p_record_visit "$(pwd)"
  else
    echo "Multiple matches:"
    local i=1
    for d in "${matches[@]}"; do
      local rel="${d#"$base"/}"
      printf "  %d) %s\n" "$i" "$rel"
      ((i++))
    done
    echo ""
    read -rp "Pick [1-$count]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      cd "${matches[$((choice-1))]}" || return 1
      echo "→ $(pwd)"
      _p_record_visit "$(pwd)"
    else
      echo "Cancelled."
      return 1
    fi
  fi
}

_p_completion() {
  # Only complete the first argument
  (( COMP_CWORD == 1 )) || return 0
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
  local cache_file="$cache_dir/p_completion"

  _p_ensure_completion_cache "$cache_file" || return 0
  [[ -f "$cache_file" ]] || return 0

  local candidates=()
  while IFS= read -r name; do
    [[ "$name" == "$cur"* ]] && candidates+=("$name")
  done < "$cache_file"
  COMPREPLY=("${candidates[@]}")
}
complete -F _p_completion p

# sp - search if a project exists within top-level categories
# Usage: sp <query>
#   sp foo      - search for directories matching "foo" within category folders
#   sp foo<Tab> - tab-complete project names (prefix match)
sp() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
sp - search for projects by name

Usage:
  sp <query>       Search for projects matching query within category directories
  sp <query><Tab>  Tab-complete project names
  sp --help        Show this help message

Searches within all top-level category directories under P_BASE.
EOF
    return 0
  fi

  local base="${P_BASE:-$HOME/projects}"

  # Treat -- as end-of-flags
  local query
  if [[ "$1" == "--" ]]; then
    query="$2"
  elif [[ -n "$1" && "$1" == -* ]]; then
    echo "sp: unknown option: $1" >&2
    echo "Usage: sp [--help | query]" >&2
    return 1
  else
    query="$1"
  fi

  if [[ -z "$query" ]]; then
    echo "Usage: sp <query>" >&2
    echo "Search for projects within $base category directories." >&2
    return 1
  fi

  if [[ ! -d "$base" ]]; then
    echo "sp: P_BASE directory does not exist: $base" >&2
    return 1
  fi

  local q="${query,,}"

  # Collect top-level category dirs
  local top_dirs=()
  for d in "$base"/*/; do
    [[ -d "$d" ]] && top_dirs+=("$d")
  done

  # Search within each category (depth 2-3 to cover flat + lifecycle + sandbox)
  local matches=()
  for top in "${top_dirs[@]}"; do
    while IFS= read -r dir; do
      [[ -z "$dir" ]] && continue
      local name="${dir##*/}"
      [[ "${name,,}" == *"$q"* ]] && matches+=("$dir")
    done < <(find "$top" -maxdepth 4 -type d \
      \( -name node_modules -prune -o -name .git -prune -print \) \
      2>/dev/null | sed 's|/\.git$||')
  done

  # Deduplicate via sort -u
  local unique=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && unique+=("$line")
  done < <(printf '%s\n' "${matches[@]}" | sort -u)
  matches=("${unique[@]}")

  local count=${#matches[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "No projects matching '$query' found." >&2
    return 1
  fi

  echo "Found $count match(es) for '$query':"
  echo ""
  local i=1
  for d in "${matches[@]}"; do
    local rel="${d#"$base"/}"
    local name="${d##*/}"
    printf "  %d) %s\n" "$i" "$name"
    printf "     %s\n" "$rel"
    ((i++))
  done
  echo ""
  read -rp "cd to a project? [1-$count / n]: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
    cd "${matches[$((choice-1))]}" || return 1
    echo "→ $(pwd)"
    _p_record_visit "$(pwd)"
  else
    echo "Done."
  fi
}

_sp_completion() {
  # Only complete the first argument
  (( COMP_CWORD == 1 )) || return 0
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
  local cache_file="$cache_dir/sp_completion"

  _p_ensure_completion_cache "$cache_file" || return 0
  [[ -f "$cache_file" ]] || return 0

  local candidates=()
  while IFS= read -r name; do
    [[ "$name" == "$cur"* ]] && candidates+=("$name")
  done < "$cache_file"
  COMPREPLY=("${candidates[@]}")
}
complete -F _sp_completion sp

# rp - jump to a recently-visited project
rp() {
  local history_file="${XDG_CACHE_HOME:-$HOME/.cache}/p/p_history"

  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
rp - jump to a recently-visited project

Usage:
  rp [query]       Jump to a recently-visited project (substring match)
  rp               List recent projects (most recent first)
  rp --clear       Clear project history
  rp --prune       Remove stale entries (deleted directories)
  rp --help        Show this help message
EOF
    return 0
  fi

  if [[ "$1" == "--clear" ]]; then
    rm -f "$history_file"
    echo "Project history cleared."
    return 0
  fi

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
      if (( ${#keep[@]} > 0 )); then
        printf '%s\n' "${keep[@]}" > "$history_file"
      else
        true > "$history_file"
      fi
      echo "Removed $removed stale entries."
    fi
    return 0
  fi

  # Treat -- as end-of-flags
  local query
  if [[ "$1" == "--" ]]; then
    query="$2"
  elif [[ -n "$1" && "$1" == -* ]]; then
    echo "rp: unknown option: $1" >&2
    echo "Usage: rp [--help | --clear | --prune | query]" >&2
    return 1
  else
    query="$1"
  fi

  if [[ ! -f "$history_file" ]] || [[ ! -s "$history_file" ]]; then
    echo "No project history yet. Use p, sp, or np to visit projects." >&2
    return 1
  fi

  # Read history into array
  local all_entries=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && all_entries+=("$line")
  done < "$history_file"

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
  if (( stale_count > 0 )); then
    if (( ${#valid_entries[@]} > 0 )); then
      printf '%s\n' "${valid_entries[@]}" > "$history_file"
    else
      true > "$history_file"
    fi
  fi
  all_entries=("${valid_entries[@]}")
  if (( ${#all_entries[@]} == 0 )); then
    echo "No project history yet. Use p, sp, or np to visit projects." >&2
    return 1
  fi

  # Filter by query if given
  local matches=()
  if [[ -n "$query" ]]; then
    local q="${query,,}"
    for entry in "${all_entries[@]}"; do
      local name="${entry##*/}"
      if [[ "${name,,}" == *"$q"* || "${entry,,}" == *"$q"* ]]; then
        matches+=("$entry")
      fi
    done
  else
    matches=("${all_entries[@]}")
  fi

  local count=${#matches[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "No recent projects matching '$query'" >&2
    return 1
  elif [[ "$count" -eq 1 ]]; then
    cd "${matches[0]}" || return 1
    echo "→ $(pwd)"
    _p_record_visit "$(pwd)"
  else
    # Display reversed (most recent = #1)
    echo "Recent projects:"
    local i=1
    for (( j=count-1; j>=0; j-- )); do
      local entry="${matches[$j]}"
      local name="${entry##*/}"
      printf "  %d) %s\n" "$i" "$name"
      printf "     %s\n" "$entry"
      ((i++))
    done
    echo ""
    read -rp "Pick [1-$count]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      local idx=$(( count - choice ))
      cd "${matches[$idx]}" || return 1
      echo "→ $(pwd)"
      _p_record_visit "$(pwd)"
    else
      echo "Cancelled."
      return 1
    fi
  fi
}

_rp_completion() {
  # Only complete the first argument
  (( COMP_CWORD == 1 )) || return 0
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local history_file="${XDG_CACHE_HOME:-$HOME/.cache}/p/p_history"
  [[ -f "$history_file" ]] || return 0
  local candidates=()
  while IFS= read -r name; do
    [[ "$name" == "$cur"* ]] && candidates+=("$name")
  done < <(sed 's|.*/||' "$history_file" | sort -u)
  COMPREPLY=("${candidates[@]}")
}
complete -F _rp_completion rp

_p_load_categories() {
  _p_categories=()
  _p_sandbox_types=()
  _p_dev_tool=""

  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
  if [[ -f "$config" ]]; then
    local lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      ((lineno++))
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == dev_tool:* ]]; then
        _p_dev_tool="${line#dev_tool:}"
        continue
      elif [[ "$line" == sandbox_type:* ]]; then
        local st_val="${line#sandbox_type:}"
        if [[ -z "$st_val" ]]; then
          echo "np: warning: empty sandbox_type at $config:$lineno" >&2
          continue
        fi
        _p_sandbox_types+=("$st_val")
      else
        # Validate format: name|type|description
        if [[ ! "$line" == *"|"*"|"* ]]; then
          echo "np: warning: malformed category line at $config:$lineno: $line" >&2
          continue
        fi
        local cat_type="${line#*|}"
        cat_type="${cat_type%%|*}"
        if [[ "$cat_type" != "flat" && "$cat_type" != "lifecycle" && "$cat_type" != "sandbox" ]]; then
          echo "np: warning: unknown category type '$cat_type' at $config:$lineno" >&2
          continue
        fi
        _p_categories+=("$line")
      fi
    done < "$config"
  fi

  if (( ${#_p_categories[@]} == 0 )); then
    _p_categories=(
      "libs|flat|Reusable libraries and SDKs"
      "sandbox|sandbox|Experiments and learning"
      "scripts|flat|CLI tools and dev utilities"
      "mobile|lifecycle|Mobile applications"
      "tools|lifecycle|Desktop and CLI tools"
      "web|lifecycle|Web applications"
    )
  fi
  if (( ${#_p_sandbox_types[@]} == 0 )); then
    _p_sandbox_types=("web" "tools")
  fi
}

_p_resolve_dev_tool() {
  # 1. Env var wins
  if [[ -n "${P_DEV_TOOL:-}" ]]; then
    echo "$P_DEV_TOOL"
    return 0
  fi

  # 2. Config file value
  _p_load_categories
  if [[ -n "${_p_dev_tool:-}" ]]; then
    echo "$_p_dev_tool"
    return 0
  fi

  # 3. Interactive prompt
  echo "No dev tool configured." >&2
  echo "" >&2
  echo "Pick your AI CLI tool:" >&2
  echo "  1) claude   (Claude Code)" >&2
  echo "  2) codex    (OpenAI Codex)" >&2
  echo "  3) gemini   (Gemini CLI)" >&2
  echo "  4) custom" >&2
  echo "" >&2
  read -rp "Pick [1-4]: " choice
  local tool
  case "$choice" in
    1) tool="claude" ;;
    2) tool="codex" ;;
    3) tool="gemini" ;;
    4)
      read -rp "Command: " tool
      if [[ -z "$tool" ]]; then
        echo "p: no command entered" >&2
        return 1
      fi
      ;;
    *)
      echo "Cancelled." >&2
      return 1
      ;;
  esac

  # Save to config
  _p_load_categories
  _p_dev_tool="$tool"
  _pconfig_write
  echo "Saved dev tool: $tool" >&2
  echo "$tool"
}

_np_name_from_url() {
  local url="$1"
  # Strip trailing slashes and .git suffix
  url="${url%/}"
  url="${url%.git}"
  # Take last path segment
  local derived="${url##*/}"
  # Lowercase, replace _ . and spaces with hyphens, collapse doubles
  derived="${derived,,}"
  derived="${derived//[_. ]/-}"
  while [[ "$derived" == *--* ]]; do
    derived="${derived//--/-}"
  done
  # Strip leading/trailing hyphens
  derived="${derived#-}"
  derived="${derived%-}"
  printf '%s' "$derived"
}

np() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
np - create a new project

Usage:
  np [name]        Interactive project scaffolder
  np --help        Show this help message
  np name --category CAT [--sandbox-type TYPE]
  np --clone URL [name] --category CAT [--sandbox-type TYPE]
                   Non-interactive mode

Options:
  --category CAT       Category name (required for non-interactive mode)
  --sandbox-type TYPE  Sandbox sub-type (required if category type is sandbox)
  --clone URL          Clone a git repo instead of creating an empty project

Creates the project directory, initializes a git repo, and cd's into it.
Project names must be kebab-case: lowercase letters, numbers, and hyphens.
EOF
    return 0
  fi

  local base="${P_BASE:-$HOME/projects}"

  if [[ ! -d "$base" ]]; then
    echo "np: P_BASE directory does not exist: $base" >&2
    return 1
  fi

  _p_load_categories
  local categories=("${_p_categories[@]}")
  local sandbox_types=("${_p_sandbox_types[@]}")

  # Parse arguments
  local name="" opt_category="" opt_sandbox_type="" opt_clone=""
  local positional_set=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        if [[ -n "${1:-}" ]] && [[ "$positional_set" == false ]]; then
          name="$1"
          positional_set=true
          shift
        fi
        ;;
      --category)
        if [[ $# -lt 2 ]]; then
          echo "np: --category requires a value" >&2
          return 1
        fi
        opt_category="$2"
        shift 2
        ;;
      --sandbox-type)
        if [[ $# -lt 2 ]]; then
          echo "np: --sandbox-type requires a value" >&2
          return 1
        fi
        opt_sandbox_type="$2"
        shift 2
        ;;
      --clone)
        if [[ $# -lt 2 ]]; then
          echo "np: --clone requires a URL" >&2
          return 1
        fi
        opt_clone="$2"
        shift 2
        ;;
      -*)
        echo "np: unknown option: $1" >&2
        echo "Usage: np [name] [--category CAT] [--sandbox-type TYPE] [--clone URL]" >&2
        return 1
        ;;
      *)
        if [[ "$positional_set" == false ]]; then
          name="$1"
          positional_set=true
        fi
        shift
        ;;
    esac
  done

  # 1. Get project name (prompt if not given, derive from clone URL if available)
  if [[ -z "$name" && -n "$opt_clone" ]]; then
    name="$(_np_name_from_url "$opt_clone")"
  fi
  if [[ -z "$name" ]]; then
    read -rp "Project name (kebab-case): " name
  fi
  # Validate: kebab-case, no trailing hyphen
  if [[ -z "$name" ]] || [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "Invalid name. Use lowercase letters, numbers, and hyphens (no leading/trailing hyphens)." >&2
    return 1
  fi

  local selected cat_name cat_type remainder target

  if [[ -n "$opt_category" ]]; then
    # Non-interactive mode: find category by name
    local found=false
    for entry in "${categories[@]}"; do
      local entry_name="${entry%%|*}"
      if [[ "$entry_name" == "$opt_category" ]]; then
        selected="$entry"
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      echo "np: unknown category: $opt_category" >&2
      return 1
    fi

    cat_name="${selected%%|*}"
    remainder="${selected#*|}"
    cat_type="${remainder%%|*}"

    case "$cat_type" in
      lifecycle)
        target="$base/$cat_name/dev/$name"
        ;;
      sandbox)
        if [[ -z "$opt_sandbox_type" ]]; then
          echo "np: --sandbox-type required for sandbox category" >&2
          return 1
        fi
        # Validate sandbox type
        local valid_st=false
        for st in "${sandbox_types[@]}"; do
          [[ "$st" == "$opt_sandbox_type" ]] && valid_st=true && break
        done
        if [[ "$valid_st" == false ]]; then
          echo "np: unknown sandbox type: $opt_sandbox_type" >&2
          return 1
        fi
        target="$base/sandbox/$opt_sandbox_type/$name"
        ;;
      flat)
        target="$base/$cat_name/$name"
        ;;
      *)
        echo "np: unknown category type '$cat_type' in config" >&2
        return 1
        ;;
    esac
  else
    # Interactive mode
    # 2. Pick category
    echo ""
    echo "Categories:"
    local i=1
    for entry in "${categories[@]}"; do
      local entry_name="${entry%%|*}"
      local cat_desc="${entry##*|}"
      printf "  %2d) %-12s %s\n" "$i" "$entry_name" "$cat_desc"
      ((i++))
    done
    echo ""
    read -rp "Pick [1-${#categories[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#categories[@]} )); then
      echo "Cancelled."
      return 1
    fi

    selected="${categories[$((choice-1))]}"
    cat_name="${selected%%|*}"
    remainder="${selected#*|}"
    cat_type="${remainder%%|*}"

    # 3. Build target path
    case "$cat_type" in
      lifecycle)
        target="$base/$cat_name/dev/$name"
        ;;
      sandbox)
        echo ""
        echo "Sandbox type:"
        local j=1
        for st in "${sandbox_types[@]}"; do
          printf "  %d) %s\n" "$j" "$st"
          ((j++))
        done
        echo ""
        read -rp "Pick [1-${#sandbox_types[@]}]: " st_choice
        if [[ ! "$st_choice" =~ ^[0-9]+$ ]] || (( st_choice < 1 || st_choice > ${#sandbox_types[@]} )); then
          echo "Cancelled."
          return 1
        fi
        target="$base/sandbox/${sandbox_types[$((st_choice-1))]}/$name"
        ;;
      flat)
        target="$base/$cat_name/$name"
        ;;
      *)
        echo "np: unknown category type '$cat_type' in config" >&2
        return 1
        ;;
    esac
  fi

  # Interactive clone prompt (only when --clone was not already provided)
  if [[ -z "$opt_category" && -z "$opt_clone" ]]; then
    echo ""
    read -rp "Clone from a git repo? (paste URL or leave blank to start fresh): " opt_clone
  fi

  # 4. Check if already exists
  if [[ -d "$target" ]]; then
    echo "Directory already exists: $target" >&2
    return 1
  fi

  # 5. Confirm (interactive) or create (non-interactive)
  if [[ -z "$opt_category" ]]; then
    echo ""
    echo "  Name:  $name"
    echo "  Path:  ${target#"$base"/}"
    if [[ -n "$opt_clone" ]]; then
      echo "  Clone: $opt_clone"
    fi
    echo ""
    read -n1 -rp "Create project? (y/n) " confirm
    echo ""
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      return 1
    fi
  fi

  if [[ -n "$opt_clone" ]]; then
    mkdir -p "$(dirname "$target")"
    if ! git clone "$opt_clone" "$target"; then
      echo "np: clone failed" >&2
      return 1
    fi
  else
    mkdir -p "$target"
    if command -v git >/dev/null 2>&1; then
      git -C "$target" init
    else
      echo "np: warning: git not found, skipping git init" >&2
    fi
  fi
  echo "Created: ${target#"$base"/}"

  cd "$target" || return 1
  echo "→ $(pwd)"
  _p_record_visit "$(pwd)"

  # Post-np hook (e.g., register project in external systems)
  if [[ -n "${P_NP_HOOK:-}" && -x "$P_NP_HOOK" ]]; then
    "$P_NP_HOOK" "$name" "$cat_name" "$cat_type" "$target" || \
      printf 'np: warning: post-hook exited %d\n' $? >&2
  fi

  # Invalidate completion cache so new project is immediately tab-completable
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  rm -f "$cache_dir/p_completion" "$cache_dir/sp_completion"
}

# pconfig - interactive config management for p
# Usage: pconfig [show|init|add|remove|add-sandbox-type|remove-sandbox-type|rebuild-cache|path|edit]

_pconfig_write() {
  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
  mkdir -p "$(dirname "$config")"

  local tmpfile
  tmpfile="$(mktemp)" || return 1

  {
    cat <<'HEADER'
# p - project category configuration
#
# Each line defines a category: name|type|description
#
# Types:
#   lifecycle  — projects go in <category>/dev/<name>
#   flat       — projects go in <category>/<name>
#   sandbox    — prompts for sub-type, goes in sandbox/<type>/<name>
#
# Managed by pconfig. Manual edits are fine too.
HEADER
    echo ""
    for entry in "${_p_categories[@]}"; do
      echo "$entry"
    done
    echo ""
    for st in "${_p_sandbox_types[@]}"; do
      echo "sandbox_type:$st"
    done
    if [[ -n "${_p_dev_tool:-}" ]]; then
      echo ""
      echo "dev_tool:$_p_dev_tool"
    fi
  } > "$tmpfile"

  mv "$tmpfile" "$config"
}

_pconfig_show() {
  _p_load_categories
  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"

  echo "p config"
  echo ""
  if [[ -f "$config" ]]; then
    echo "  Source: $config"
  else
    echo "  Source: built-in defaults"
  fi
  echo ""

  echo "Categories:"
  local i=1
  for entry in "${_p_categories[@]}"; do
    local name="${entry%%|*}"
    local remainder="${entry#*|}"
    local type="${remainder%%|*}"
    local desc="${remainder#*|}"
    printf "  %2d) %-12s %-10s %s\n" "$i" "$name" "[$type]" "$desc"
    ((i++))
  done
  echo ""

  echo "Sandbox types:"
  for st in "${_p_sandbox_types[@]}"; do
    echo "  - $st"
  done
  echo ""

  echo "Dev tool:"
  if [[ -n "${P_DEV_TOOL:-}" ]]; then
    echo "  $P_DEV_TOOL (from P_DEV_TOOL env var)"
  elif [[ -n "${_p_dev_tool:-}" ]]; then
    echo "  $_p_dev_tool"
  else
    echo "  (not configured)"
  fi
}

_pconfig_init() {
  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
  if [[ -f "$config" ]]; then
    echo "Config file already exists: $config" >&2
    echo "Use 'pconfig edit' to modify it, or remove it first." >&2
    return 1
  fi

  _p_load_categories
  _pconfig_write
  echo "Created config file: $config"
}

_pconfig_add() {
  _p_load_categories

  echo "Add a new category"
  echo ""
  read -rp "Category name: " cat_name
  if [[ -z "$cat_name" ]] || [[ ! "$cat_name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "Error: name must be kebab-case (lowercase letters, numbers, hyphens; no leading/trailing hyphens)." >&2
    return 1
  fi

  for entry in "${_p_categories[@]}"; do
    if [[ "${entry%%|*}" == "$cat_name" ]]; then
      echo "Error: category '$cat_name' already exists." >&2
      return 1
    fi
  done

  echo "Types: flat, lifecycle, sandbox"
  read -rp "Category type: " cat_type
  if [[ "$cat_type" != "flat" && "$cat_type" != "lifecycle" && "$cat_type" != "sandbox" ]]; then
    echo "Error: type must be flat, lifecycle, or sandbox." >&2
    return 1
  fi

  read -rp "Description: " cat_desc
  if [[ -z "$cat_desc" ]]; then
    echo "Error: description cannot be empty." >&2
    return 1
  fi

  _p_categories+=("$cat_name|$cat_type|$cat_desc")
  _pconfig_write
  echo "Added category: $cat_name ($cat_type)"
}

_pconfig_remove() {
  _p_load_categories

  if (( ${#_p_categories[@]} == 0 )); then
    echo "No categories to remove."
    return 0
  fi

  if (( ${#_p_categories[@]} == 1 )); then
    echo "Cannot remove last category."
    return 1
  fi

  echo "Categories:"
  local i=1
  for entry in "${_p_categories[@]}"; do
    local name="${entry%%|*}"
    printf "  %d) %s\n" "$i" "$name"
    ((i++))
  done
  echo ""
  read -rp "Remove which? [1-${#_p_categories[@]}]: " choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#_p_categories[@]} )); then
    echo "Cancelled."
    return 1
  fi

  local idx=$((choice - 1))
  local removed="${_p_categories[$idx]}"
  local removed_name="${removed%%|*}"
  local new_cats=()
  for (( j=0; j<${#_p_categories[@]}; j++ )); do
    (( j != idx )) && new_cats+=("${_p_categories[$j]}")
  done
  _p_categories=("${new_cats[@]}")

  _pconfig_write
  echo "Removed category: $removed_name"
}

_pconfig_add_sandbox_type() {
  _p_load_categories

  read -rp "New sandbox type name: " st_name
  if [[ -z "$st_name" ]]; then
    echo "Error: name cannot be empty." >&2
    return 1
  fi

  for st in "${_p_sandbox_types[@]}"; do
    if [[ "$st" == "$st_name" ]]; then
      echo "Error: sandbox type '$st_name' already exists." >&2
      return 1
    fi
  done

  _p_sandbox_types+=("$st_name")
  _pconfig_write
  echo "Added sandbox type: $st_name"
}

_pconfig_remove_sandbox_type() {
  _p_load_categories

  if (( ${#_p_sandbox_types[@]} == 0 )); then
    echo "No sandbox types to remove."
    return 0
  fi

  echo "Sandbox types:"
  local i=1
  for st in "${_p_sandbox_types[@]}"; do
    printf "  %d) %s\n" "$i" "$st"
    ((i++))
  done
  echo ""
  read -rp "Remove which? [1-${#_p_sandbox_types[@]}]: " choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#_p_sandbox_types[@]} )); then
    echo "Cancelled."
    return 1
  fi

  local idx=$((choice - 1))
  local removed="${_p_sandbox_types[$idx]}"
  local new_types=()
  for (( j=0; j<${#_p_sandbox_types[@]}; j++ )); do
    (( j != idx )) && new_types+=("${_p_sandbox_types[$j]}")
  done
  _p_sandbox_types=("${new_types[@]}")

  _pconfig_write
  echo "Removed sandbox type: $removed"
}

pconfig() {
  local cmd="${1:-show}"

  case "$cmd" in
    --help|-h)
      cat <<'EOF'
pconfig - manage p configuration

Usage:
  pconfig [show]              Display current categories and sandbox types
  pconfig init                Create config file from defaults
  pconfig add                 Add a new category (interactive)
  pconfig remove              Remove a category (interactive)
  pconfig add-sandbox-type    Add a sandbox sub-type
  pconfig remove-sandbox-type Remove a sandbox sub-type
  pconfig set-dev-tool [cmd]  Set AI CLI tool for p --dev
  pconfig rebuild-cache       Rebuild tab-completion caches
  pconfig path                Print config file path
  pconfig edit                Open config in $EDITOR
  pconfig --help              Show this help
EOF
      return 0
      ;;
    show)
      _pconfig_show
      ;;
    init)
      _pconfig_init
      ;;
    add)
      _pconfig_add
      ;;
    remove)
      _pconfig_remove
      ;;
    add-sandbox-type)
      _pconfig_add_sandbox_type
      ;;
    remove-sandbox-type)
      _pconfig_remove_sandbox_type
      ;;
    set-dev-tool)
      _p_load_categories
      local tool="${2:-}"
      if [[ -z "$tool" ]]; then
        echo "Pick your AI CLI tool:"
        echo "  1) claude   (Claude Code)"
        echo "  2) codex    (OpenAI Codex)"
        echo "  3) gemini   (Gemini CLI)"
        echo "  4) custom"
        echo ""
        read -rp "Pick [1-4]: " choice
        case "$choice" in
          1) tool="claude" ;;
          2) tool="codex" ;;
          3) tool="gemini" ;;
          4)
            read -rp "Command: " tool
            if [[ -z "$tool" ]]; then
              echo "pconfig: no command entered" >&2
              return 1
            fi
            ;;
          *)
            echo "Cancelled."
            return 1
            ;;
        esac
      fi
      _p_dev_tool="$tool"
      _pconfig_write
      echo "Dev tool set to: $tool"
      ;;
    rebuild-cache)
      _p_rebuild_completion_caches || return 1
      echo "Completion cache rebuilt"
      ;;
    path)
      echo "${P_CONFIG:-$HOME/.config/p/categories.conf}"
      ;;
    edit)
      local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
      if [[ ! -f "$config" ]]; then
        echo "No config file found. Run 'pconfig init' first." >&2
        return 1
      fi
      "${EDITOR:-vi}" "$config"
      ;;
    *)
      echo "pconfig: unknown command: $cmd" >&2
      echo "Run 'pconfig --help' for usage." >&2
      return 1
      ;;
  esac
}
