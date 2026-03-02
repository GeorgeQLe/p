# p - jump to a project directory by partial name match
# Usage: p [query]
#   p           - list all projects
#   p foo       - cd to project matching "foo" (substring, case-insensitive)
#   p foo<Tab>  - tab-complete project names (prefix match)
#   p --origin  - cd to the directory containing this script

# Directory where this script lives (captured at source time)
_p_origin_dir="${0:A:h}"

# Returns all project directory paths (one per line)
_p_find_all_dirs() {
  local base="$HOME/projects"
  find "$base" -maxdepth 5 -name '.git' -type d \
    -not -path '*/node_modules/*' \
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

  local d other
  for d in "${dirs_arr[@]}"; do
    local is_subpkg=false
    for other in "${dirs_arr[@]}"; do
      if [[ "$d" != "$other" && "$d" == "$other/"* ]]; then
        is_subpkg=true
        break
      fi
    done
    if $is_subpkg; then
      echo "P $d"
    else
      echo "S $d"
    fi
  done
}

p() {
  if [[ "$1" == "--origin" ]]; then
    cd "$_p_origin_dir" || return 1
    echo "→ $(pwd)"
    return 0
  fi

  local base="$HOME/projects"
  local query="$1"

  local all_dirs
  all_dirs=$(_p_find_all_dirs)

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
        local rel="${d#$base/}"
        [[ "${(L)rel}" == *"$q"* ]] && sa_path+=("$d")
      done
      for d in "${subpkg[@]}"; do
        local rel="${d#$base/}"
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
    echo "No projects matching '$query'"
    return 1
  elif [[ "$count" -eq 1 ]]; then
    cd "${matches[1]}" || return 1
    echo "→ $(pwd)"
  else
    echo "Multiple matches:"
    local i=1
    for d in "${matches[@]}"; do
      local rel="${d#$base/}"
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
  local cache_file="/tmp/_p_completion_cache_$(id -u)"
  local cache_ttl=300

  # Rebuild cache if missing or stale (>5 min)
  if [[ ! -f "$cache_file" ]] || \
     [[ $(( $(date +%s) - $(stat -f %m "$cache_file") )) -gt $cache_ttl ]]; then
    local all_dirs classified
    all_dirs=$(_p_find_all_dirs)
    classified=$(_p_classify_dirs "$all_dirs")

    # Standalone basenames sorted, then sub-package basenames sorted, deduped
    {
      echo "$classified" | grep '^S ' | sed 's|^S .*/||' | sort
      echo "$classified" | grep '^P ' | sed 's|^P .*/||' | sort
    } | awk '!seen[$0]++' > "$cache_file"
  fi

  compadd - ${(f)"$(cat "$cache_file")"}
}
compdef _p_completion p

# sp - search if a project exists within ~/projects top-level categories
# Usage: sp <query>
#   sp foo      - search for directories matching "foo" within category folders
#   sp foo<Tab> - tab-complete project names (prefix match)
sp() {
  local base="$HOME/projects"
  local query="$1"

  if [[ -z "$query" ]]; then
    echo "Usage: sp <query>"
    echo "Search for projects within ~/projects category directories."
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

  # Deduplicate and sort
  local unique=()
  local seen=()
  for m in "${matches[@]}"; do
    local already=false
    for s in "${seen[@]}"; do
      [[ "$m" == "$s" ]] && already=true && break
    done
    $already || { unique+=("$m"); seen+=("$m"); }
  done
  matches=("${unique[@]}")

  local count=${#matches[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "No projects matching '$query' found."
    return 1
  fi

  echo "Found $count match(es) for '$query':"
  echo ""
  local i=1
  for d in "${matches[@]}"; do
    local rel="${d#$base/}"
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
  local cache_file="/tmp/_sp_completion_cache_$(id -u)"
  local cache_ttl=300

  if [[ ! -f "$cache_file" ]] || \
     [[ $(( $(date +%s) - $(stat -f %m "$cache_file") )) -gt $cache_ttl ]]; then
    find "$HOME/projects" -mindepth 2 -maxdepth 5 -name '.git' -type d \
      -not -path '*/node_modules/*' \
      2>/dev/null | sed 's|/\.git$||' | sed 's|.*/||' | sort -u > "$cache_file"
  fi

  compadd - ${(f)"$(cat "$cache_file")"}
}
compdef _sp_completion sp

np() {
  local base="$HOME/projects"

  # Categories: name|type|description (lifecycle, flat, sandbox)
  local categories=(
    "clones|flat|Followed tutorials and cloned repos"
    "engines|flat|Game and app engines"
    "games|lifecycle|Video game projects"
    "gcanbuild|flat|YouTube channel content"
    "libs|flat|Reusable libraries and SDKs"
    "mobile|lifecycle|Mobile apps"
    "poke|lifecycle|Poke-branded apps"
    "sandbox|sandbox|Experiments and learning"
    "scripts|flat|CLI tools and dev utilities"
    "starters|flat|Reusable project templates"
    "static-web|lifecycle|Static websites and landing pages"
    "tools|lifecycle|Desktop and CLI tools"
    "web|lifecycle|Web applications"
  )

  local sandbox_types=("web" "games" "tools")

  # 1. Get project name (accept as argument or prompt)
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -r "name?Project name (kebab-case): "
  fi
  if [[ -z "$name" ]] || [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Invalid name. Use lowercase letters, numbers, and hyphens."
    return 1
  fi

  # 2. Pick category
  echo ""
  echo "Categories:"
  local i=1
  for entry in "${categories[@]}"; do
    local cat_name="${entry%%|*}"
    local cat_desc="${entry##*|}"
    printf "  %2d) %-12s %s\n" "$i" "$cat_name" "$cat_desc"
    ((i++))
  done
  echo ""
  read -r "choice?Pick [1-${#categories[@]}]: "
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#categories[@]} )); then
    echo "Cancelled."
    return 1
  fi

  local selected="${categories[$choice]}"
  local cat_name="${selected%%|*}"
  local remainder="${selected#*|}"
  local cat_type="${remainder%%|*}"

  # 3. Build target path
  local target
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
  esac

  # 4. Check if already exists
  if [[ -d "$target" ]]; then
    echo "Directory already exists: $target"
    return 1
  fi

  # 5. Confirm and create
  echo ""
  echo "  Name:  $name"
  echo "  Path:  ${target#$base/}"
  echo ""
  read -r -k1 "confirm?Create project? (y/n) "
  echo ""
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return 1
  fi

  mkdir -p "$target"
  echo "Created: ${target#$base/}"

  git -C "$target" init

  cd "$target" || return 1
  echo "→ $(pwd)"
}
