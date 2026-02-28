# p - jump to a project directory by partial name match
# Usage: p [query]
#   p          - list all projects
#   p foo      - cd to project matching "foo" (substring, case-insensitive)
#   p foo<Tab> - tab-complete project names (prefix match)

p() {
  local base="$HOME/projects"
  local query="$1"

  # Find leaf project dirs (contain a project marker, exclude build artifacts)
  local dirs
  dirs=$(find "$base" -maxdepth 5 -type f \( \
    -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \
    -o -name 'pyproject.toml' -o -name 'Makefile' \
  \) -not -path '*/node_modules/*' -not -path '*/.next/*' \
     -not -path '*/.nuxt/*' -not -path '*/dist/*' \
     -not -path '*/target/*' -not -path '*/.cache/*' \
  | sed 's|/[^/]*$||' | sort -u)

  # Also include dirs with .git (find -name .git -type d)
  local git_dirs
  git_dirs=$(find "$base" -maxdepth 5 -name '.git' -type d \
    -not -path '*/node_modules/*' \
  | sed 's|/\.git$||' | sort -u)

  # Merge and deduplicate
  dirs=$(printf '%s\n%s' "$dirs" "$git_dirs" | sort -u | grep -v '^$')

  # Filter by query if provided
  if [[ -n "$query" ]]; then
    dirs=$(echo "$dirs" | while IFS= read -r d; do
      local name="${d##*/}"
      if [[ "${name,,}" == *"${query,,}"* ]]; then
        echo "$d"
      fi
    done)
  fi

  # Count matches
  local count
  count=$(echo "$dirs" | grep -c .)

  if [[ "$count" -eq 0 ]]; then
    echo "No projects matching '$query'"
    return 1
  elif [[ "$count" -eq 1 ]]; then
    cd "$dirs" || return 1
    echo "→ $(pwd)"
  else
    echo "Multiple matches:"
    local i=1
    local arr=()
    while IFS= read -r d; do
      local rel="${d#$base/}"
      printf "  %d) %s\n" "$i" "$rel"
      arr+=("$d")
      ((i++))
    done <<< "$dirs"
    echo ""
    read -rp "Pick [1-$count]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      cd "${arr[$((choice-1))]}" || return 1
      echo "→ $(pwd)"
    else
      echo "Cancelled."
      return 1
    fi
  fi
}

_p_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local base="$HOME/projects"
  local cache_file="/tmp/_p_completion_cache_$(id -u)"
  local cache_ttl=300

  # Rebuild cache if missing or stale (>5 min)
  if [[ ! -f "$cache_file" ]] || \
     [[ $(( $(date +%s) - $(stat -c %Y "$cache_file") )) -gt $cache_ttl ]]; then
    {
      find "$base" -maxdepth 5 -type f \( \
        -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \
        -o -name 'pyproject.toml' -o -name 'Makefile' \
      \) -not -path '*/node_modules/*' -not -path '*/.next/*' \
         -not -path '*/.nuxt/*' -not -path '*/dist/*' \
         -not -path '*/target/*' -not -path '*/.cache/*' \
      | sed 's|/[^/]*$||'
      find "$base" -maxdepth 5 -name '.git' -type d \
        -not -path '*/node_modules/*' \
      | sed 's|/\.git$||'
    } | sort -u | grep -v '^$' | xargs -I{} basename {} | sort -u > "$cache_file"
  fi

  COMPREPLY=( $(compgen -W "$(cat "$cache_file")" -- "$cur") )
}
complete -F _p_completion p

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
    read -rp "Project name (kebab-case): " name
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
  read -rp "Pick [1-${#categories[@]}]: " choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#categories[@]} )); then
    echo "Cancelled."
    return 1
  fi

  local selected="${categories[$((choice-1))]}"
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
  esac

  # 4. Check if already exists
  if [[ -d "$target" ]]; then
    echo "Directory already exists: $target"
    return 1
  fi

  # 5. Optional git init
  read -n1 -rp "Initialize git repo? (y/n) " do_git
  echo ""

  # 6. Confirm and create
  echo ""
  echo "  Name:  $name"
  echo "  Path:  ${target#$base/}"
  echo "  Git:   $([[ "$do_git" =~ ^[Yy]$ ]] && echo "yes" || echo "no")"
  echo ""
  read -n1 -rp "Create project? (y/n) " confirm
  echo ""
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return 1
  fi

  mkdir -p "$target"
  echo "Created: ${target#$base/}"

  if [[ "$do_git" =~ ^[Yy]$ ]]; then
    git -C "$target" init
  fi

  cd "$target" || return 1
  echo "→ $(pwd)"
}
