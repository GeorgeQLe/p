# p - project directory jumper and scaffolder for zsh
# https://github.com/GeorgeQLe/p
# shellcheck disable=SC2154  # zsh read -r "var?prompt" assigns vars shellcheck can't see

_P_VERSION="1.0.0"

# Ensure zsh completion system is available
if ! typeset -f compdef > /dev/null 2>&1; then
  autoload -Uz compinit && compinit
fi

# Directory where this script lives (captured at source time)
_p_origin_dir="${0:A:h}"

# Returns all project directory paths (one per line)
_p_find_all_dirs() {
  local base="${P_BASE:-$HOME/projects}"
  if [[ ! -d "$base" ]]; then
    echo "p: P_BASE directory does not exist: $base" >&2
    return 1
  fi
  find "$base" -maxdepth 5 -name '.git' -type d \
    -not -path '*/node_modules/*' \
    2>/dev/null \
  | sed 's|/\.git$||' | sort -u
}

# Classifies dirs as S (standalone) or P (sub-package)
# A dir is a sub-package if any other dir is a proper parent of it
_p_classify_dirs() {
  local all_dirs="$1"
  local dirs_arr=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && dirs_arr+=("$d")
  done <<< "$all_dirs"

  # Sort so parents come before children — enables linear scan
  local sorted=("${(@o)dirs_arr}")
  local d i j
  for (( i=1; i<=${#sorted[@]}; i++ )); do
    d="${sorted[$i]}"
    # Check if d is a sub-package (child of an earlier entry)
    local is_subpkg=false
    for (( j=i-1; j>=1; j-- )); do
      if [[ "$d" == "${sorted[$j]}/"* ]]; then
        is_subpkg=true
        break
      fi
    done
    if [[ "$is_subpkg" == true ]]; then
      echo "P $d"
    else
      echo "S $d"
    fi
  done
}

_p_show_help() {
  cat <<'EOF'
p - project directory jumper and scaffolder

Usage:
  p [query]        Jump to a project matching query (substring, case-insensitive)
  p                List all projects
  p --origin       cd to the directory containing this script
  p --help         Show this help message
  p --version      Show version

  sp <query>       Search for projects and show results with paths
  sp --help        Show sp help

  np [name]        Create a new project (interactive scaffolder)
  np --help        Show np help
  np name --category CAT [--sandbox-type TYPE]
                   Create a project non-interactively

Environment Variables:
  P_BASE           Projects root directory (default: ~/projects)
  P_CONFIG         Path to categories.conf (default: ~/.config/p/categories.conf)

See https://github.com/GeorgeQLe/p for full documentation.
EOF
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
  if [[ "$1" == "--origin" ]]; then
    cd "$_p_origin_dir" || return 1
    echo "→ $(pwd)"
    return 0
  fi

  # Treat -- as end-of-flags
  local query
  if [[ "$1" == "--" ]]; then
    query="$2"
  elif [[ -n "$1" && "$1" == -* && "$1" != "--" ]]; then
    echo "p: unknown option: $1" >&2
    echo "Usage: p [--help | --version | --origin | query]" >&2
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
    local q="${(L)query}"

    # Phase 1: basename match
    local sa_basename=() sp_basename=()
    for d in "${standalone[@]}"; do
      local name="${d##*/}"
      [[ "${(L)name}" == *"$q"* ]] && sa_basename+=("$d")
    done
    for d in "${subpkg[@]}"; do
      local name="${d##*/}"
      [[ "${(L)name}" == *"$q"* ]] && sp_basename+=("$d")
    done

    if (( ${#sa_basename[@]} + ${#sp_basename[@]} > 0 )); then
      matches=("${sa_basename[@]}" "${sp_basename[@]}")
    else
      # Phase 2: relative path fallback
      local sa_path=() sp_path=()
      for d in "${standalone[@]}"; do
        local rel="${d#"$base"/}"
        [[ "${(L)rel}" == *"$q"* ]] && sa_path+=("$d")
      done
      for d in "${subpkg[@]}"; do
        local rel="${d#"$base"/}"
        [[ "${(L)rel}" == *"$q"* ]] && sp_path+=("$d")
      done
      matches=("${sa_path[@]}" "${sp_path[@]}")
    fi
  else
    # No query: all dirs, standalone first
    matches=("${standalone[@]}" "${subpkg[@]}")
  fi

  local count=${#matches[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "No projects matching '$query'" >&2
    return 1
  elif [[ "$count" -eq 1 ]]; then
    cd "${matches[1]}" || return 1
    echo "→ $(pwd)"
  else
    echo "Multiple matches:"
    local i=1
    for d in "${matches[@]}"; do
      local rel="${d#"$base"/}"
      printf "  %d) %s\n" "$i" "$rel"
      ((i++))
    done
    echo ""
    read -r "choice?Pick [1-$count]: "
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      cd "${matches[$choice]}" || return 1
      echo "→ $(pwd)"
    else
      echo "Cancelled."
      return 1
    fi
  fi
}

_p_completion() {
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
  local cache_file="$cache_dir/p_completion"

  # Rebuild cache if missing or stale (>5 min)
  if [[ ! -f "$cache_file" ]] || \
     [[ -n "$(find "$cache_file" -mmin +5 2>/dev/null)" ]]; then
    local all_dirs classified
    all_dirs=$(_p_find_all_dirs) || return 1
    classified=$(_p_classify_dirs "$all_dirs")

    # Standalone basenames sorted, then sub-package basenames sorted, deduped
    {
      echo "$classified" | grep '^S ' | sed 's|^S .*/||' | sort
      echo "$classified" | grep '^P ' | sed 's|^P .*/||' | sort
    } | awk '!seen[$0]++' > "$cache_file"
  fi

  # shellcheck disable=SC2086  # zsh (f) flag handles splitting correctly
  compadd - ${(f)"$(cat "$cache_file")"}
}
compdef _p_completion p

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

  local q="${(L)query}"

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
      [[ "${(L)name}" == *"$q"* ]] && matches+=("$dir")
    done < <(find "$top" -maxdepth 4 -name '.git' -type d \
      -not -path '*/node_modules/*' \
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
  read -r "choice?cd to a project? [1-$count / n]: "
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
    cd "${matches[$choice]}" || return 1
    echo "→ $(pwd)"
  else
    echo "Done."
  fi
}

_sp_completion() {
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
  local cache_file="$cache_dir/sp_completion"

  if [[ ! -f "$cache_file" ]] || \
     [[ -n "$(find "$cache_file" -mmin +5 2>/dev/null)" ]]; then
    find "${P_BASE:-$HOME/projects}" -mindepth 2 -maxdepth 5 -name '.git' -type d \
      -not -path '*/node_modules/*' \
      2>/dev/null | sed 's|/\.git$||' | sed 's|.*/||' | sort -u > "$cache_file"
  fi

  # shellcheck disable=SC2086  # zsh (f) flag handles splitting correctly
  compadd - ${(f)"$(cat "$cache_file")"}
}
compdef _sp_completion sp

_p_load_categories() {
  local -ga _p_categories
  local -ga _p_sandbox_types
  _p_categories=()
  _p_sandbox_types=()

  local config="${P_CONFIG:-$HOME/.config/p/categories.conf}"
  if [[ -f "$config" ]]; then
    local lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      ((lineno++))
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == sandbox_type:* ]]; then
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
      "tools|lifecycle|Desktop and CLI tools"
      "web|lifecycle|Web applications"
    )
  fi
  if (( ${#_p_sandbox_types[@]} == 0 )); then
    _p_sandbox_types=("web" "tools")
  fi
}

np() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
np - create a new project

Usage:
  np [name]        Interactive project scaffolder
  np --help        Show this help message
  np name --category CAT [--sandbox-type TYPE]
                   Non-interactive mode

Options:
  --category CAT       Category name (required for non-interactive mode)
  --sandbox-type TYPE  Sandbox sub-type (required if category type is sandbox)

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
  local name="" opt_category="" opt_sandbox_type=""
  local positional_set=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        if [[ -n "$1" ]] && [[ "$positional_set" == false ]]; then
          name="$1"
          positional_set=true
          shift
        fi
        ;;
      --category)
        opt_category="$2"
        shift 2
        ;;
      --sandbox-type)
        opt_sandbox_type="$2"
        shift 2
        ;;
      -*)
        echo "np: unknown option: $1" >&2
        echo "Usage: np [name] [--category CAT] [--sandbox-type TYPE]" >&2
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

  # 1. Get project name (prompt if not given)
  if [[ -z "$name" ]]; then
    read -r "name?Project name (kebab-case): "
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
      echo "Available categories: $(printf '%s' "${categories[@]}" | sed 's/|[^|]*|[^|]*/ /g' | tr '\n' ' ')" >&2
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
    read -r "choice?Pick [1-${#categories[@]}]: "
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#categories[@]} )); then
      echo "Cancelled."
      return 1
    fi

    selected="${categories[$choice]}"
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
        read -r "st_choice?Pick [1-${#sandbox_types[@]}]: "
        if [[ ! "$st_choice" =~ ^[0-9]+$ ]] || (( st_choice < 1 || st_choice > ${#sandbox_types[@]} )); then
          echo "Cancelled."
          return 1
        fi
        target="$base/sandbox/${sandbox_types[$st_choice]}/$name"
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
    echo ""
    read -r -k1 "confirm?Create project? (y/n) "
    echo ""
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      return 1
    fi
  fi

  mkdir -p "$target"
  echo "Created: ${target#"$base"/}"

  if command -v git >/dev/null 2>&1; then
    git -C "$target" init
  else
    echo "np: warning: git not found, skipping git init" >&2
  fi

  cd "$target" || return 1
  echo "→ $(pwd)"
}
