#!/usr/bin/env bash
# Time the expensive phases used by p and tab completion.

set -u

usage() {
  cat <<'EOF'
Usage:
  scripts/time-p.sh [options]

Options:
  --shell bash|zsh        Shell variant to source (default: zsh if available)
  --query TEXT            Query to use for p-style matching (default: empty)
  --prefix TEXT           Prefix to use for completion filtering (default: query)
  --base DIR              Project base directory (default: P_BASE or ~/projects)
  --source FILE           Source file override (default: ./p.bash or ./p.zsh)
  --help                  Show this help

The script does not modify your real p cache. Cold/warm completion timings use
a temporary XDG_CACHE_HOME so stale-cache rebuild costs are reproducible.
EOF
}

die() {
  echo "time-p: $*" >&2
  exit 1
}

select_bash() {
  if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
    printf '%s\n' "$BASH"
  elif [ -n "${BASH_4_BIN:-}" ] && [ -x "$BASH_4_BIN" ]; then
    printf '%s\n' "$BASH_4_BIN"
  elif [ -x /opt/homebrew/bin/bash ]; then
    printf '%s\n' /opt/homebrew/bin/bash
  else
    command -v bash || return 1
  fi
}

now_seconds() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
  else
    date +%s
  fi
}

elapsed_ms() {
  awk -v start="$1" -v end="$2" 'BEGIN { printf "%.3f", (end - start) * 1000 }'
}

time_call() {
  label="$1"
  shift

  start="$(now_seconds)"
  "$@"
  status_code=$?
  end="$(now_seconds)"
  ms="$(elapsed_ms "$start" "$end")"
  printf '  %-28s %10s ms  status=%s\n' "$label" "$ms" "$status_code"
  return "$status_code"
}

line_count() {
  if [ -f "$1" ]; then
    wc -l < "$1" | tr -d ' '
  else
    printf '0'
  fi
}

cache_age() {
  file="$1"
  if [ ! -f "$file" ]; then
    printf 'missing'
    return 0
  fi

  if stat -f %m "$file" >/dev/null 2>&1; then
    mtime="$(stat -f %m "$file")"
  else
    mtime="$(stat -c %Y "$file")"
  fi
  now="$(date +%s)"
  age=$((now - mtime))
  printf '%ss' "$age"
}

step_find_all_dirs() {
  _p_find_all_dirs > "$tmp_dir/all_dirs"
}

step_classify_dirs() {
  all_dirs="$(cat "$tmp_dir/all_dirs")"
  _p_classify_dirs "$all_dirs" > "$tmp_dir/classified"
}

step_p_match() {
  awk -v base="$P_BASE" -v query="$p_query" '
    BEGIN {
      q = tolower(query)
    }
    {
      tag = $1
      path = $0
      sub(/^[SP] /, "", path)
      n = split(path, parts, "/")
      name = tolower(parts[n])
      rel = path
      sub("^" base "/", "", rel)

      if (q == "") {
        if (tag == "S") {
          standalone[++standalone_count] = path
        } else {
          subpkg[++subpkg_count] = path
        }
      } else if (index(name, q) > 0) {
        basename_matches[++basename_count] = path
      } else if (index(tolower(rel), q) > 0) {
        path_matches[++path_count] = path
      }
    }
    END {
      if (q == "") {
        for (i = 1; i <= standalone_count; i++) print standalone[i]
        for (i = 1; i <= subpkg_count; i++) print subpkg[i]
      } else if (basename_count > 0) {
        for (i = 1; i <= basename_count; i++) print basename_matches[i]
      } else {
        for (i = 1; i <= path_count; i++) print path_matches[i]
      }
    }
  ' "$tmp_dir/classified" > "$tmp_dir/p_matches"
}

step_completion_filter() {
  awk -v prefix="$completion_prefix" 'index($0, prefix) == 1 { print }' \
    "$tmp_dir/p_completion" > "$tmp_dir/p_candidates"
}

step_shared_completion_cache_build() {
  local old_xdg_cache_home="${XDG_CACHE_HOME-}"
  local had_xdg_cache_home=0
  local status_code

  if [ "${XDG_CACHE_HOME+x}" = x ]; then
    had_xdg_cache_home=1
  fi

  export XDG_CACHE_HOME="$tmp_dir/shared-cache-home"
  rm -rf "$XDG_CACHE_HOME/p"
  _p_rebuild_completion_caches &&
    cp "$XDG_CACHE_HOME/p/p_completion" "$tmp_dir/p_completion" &&
    cp "$XDG_CACHE_HOME/p/sp_completion" "$tmp_dir/sp_completion"
  status_code=$?

  if [ "$had_xdg_cache_home" -eq 1 ]; then
    export XDG_CACHE_HOME="$old_xdg_cache_home"
  else
    unset XDG_CACHE_HOME
  fi

  return "$status_code"
}

step_rp_completion_names() {
  history_file="${XDG_CACHE_HOME:-$HOME/.cache}/p/p_history"
  if [ -f "$history_file" ]; then
    sed 's|.*/||' "$history_file" | sort -u > "$tmp_dir/rp_completion"
  else
    : > "$tmp_dir/rp_completion"
  fi
}

set_completion_state() {
  if [ "$shell_variant" = "zsh" ]; then
    # shellcheck disable=SC2034  # consumed by the sourced zsh completion function
    CURRENT=2
    # shellcheck disable=SC2034  # consumed by the sourced zsh completion function
    words=(p "$completion_prefix")
  else
    COMP_CWORD=1
    COMP_WORDS=(p "$completion_prefix")
    COMPREPLY=()
  fi
}

step_actual_p_completion_missing_cache() {
  export XDG_CACHE_HOME="$tmp_dir/cache-home"
  rm -rf "$XDG_CACHE_HOME/p"
  set_completion_state
  _p_completion >/dev/null
}

step_prime_actual_completion_cache() {
  export XDG_CACHE_HOME="$tmp_dir/cache-home"
  _p_rebuild_completion_caches >/dev/null
}

step_actual_p_completion_warm() {
  export XDG_CACHE_HOME="$tmp_dir/cache-home"
  set_completion_state
  _p_completion >/dev/null
}

inner=0
shell_variant=""
p_query=""
completion_prefix=""
source_override=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --inner)
      inner=1
      shift
      ;;
    --shell)
      shell_variant="$2"
      shift 2
      ;;
    --query)
      p_query="$2"
      shift 2
      ;;
    --prefix)
      completion_prefix="$2"
      shift 2
      ;;
    --base)
      export P_BASE="$2"
      shift 2
      ;;
    --source)
      source_override="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ -z "$shell_variant" ]; then
  if command -v zsh >/dev/null 2>&1; then
    shell_variant="zsh"
  else
    shell_variant="bash"
  fi
fi

if [ "$shell_variant" != "bash" ] && [ "$shell_variant" != "zsh" ]; then
  die "--shell must be bash or zsh"
fi

if [ "$inner" -eq 0 ]; then
  if [ "$shell_variant" = "zsh" ] && [ -z "${ZSH_VERSION:-}" ]; then
    zsh_bin="$(command -v zsh)" || die "zsh not found"
    if [ -n "$source_override" ]; then
      exec "$zsh_bin" -f "$0" --inner --shell "$shell_variant" \
        --query "$p_query" --prefix "$completion_prefix" \
        --base "${P_BASE:-$HOME/projects}" --source "$source_override"
    else
      exec "$zsh_bin" -f "$0" --inner --shell "$shell_variant" \
        --query "$p_query" --prefix "$completion_prefix" \
        --base "${P_BASE:-$HOME/projects}"
    fi
  fi

  if [ "$shell_variant" = "bash" ]; then
    bash_bin="$(select_bash)" || die "bash not found"
    if [ -z "${BASH_VERSION:-}" ] || [ "$BASH" != "$bash_bin" ]; then
      if [ -n "$source_override" ]; then
        exec "$bash_bin" "$0" --inner --shell "$shell_variant" \
          --query "$p_query" --prefix "$completion_prefix" \
          --base "${P_BASE:-$HOME/projects}" --source "$source_override"
      else
        exec "$bash_bin" "$0" --inner --shell "$shell_variant" \
          --query "$p_query" --prefix "$completion_prefix" \
          --base "${P_BASE:-$HOME/projects}"
      fi
    fi
  fi
fi

if [ "$shell_variant" = "bash" ] && { [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; }; then
  die "bash 4.0+ is required for the bash variant"
fi

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)" || exit 1
if [ -n "$source_override" ]; then
  source_file="$source_override"
elif [ "$shell_variant" = "zsh" ]; then
  source_file="$script_dir/p.zsh"
else
  source_file="$script_dir/p.bash"
fi

[ -f "$source_file" ] || die "source file not found: $source_file"

export P_BASE="${P_BASE:-$HOME/projects}"
[ -d "$P_BASE" ] || die "P_BASE does not exist: $P_BASE"

if [ -z "$completion_prefix" ]; then
  completion_prefix="$p_query"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/p-time.XXXXXX")" || exit 1
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

if [ "$shell_variant" = "zsh" ]; then
  compdef() { :; }
  compadd() { :; }
else
  complete() { :; }
fi

echo "p timing diagnostic"
echo "  shell:  $shell_variant"
echo "  source: $source_file"
echo "  P_BASE: $P_BASE"
echo "  query:  ${p_query:-<empty>}"
echo "  prefix: ${completion_prefix:-<empty>}"
echo ""

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/p"
echo "real cache state"
for cache_name in p_completion sp_completion p_history; do
  cache_file="$cache_dir/$cache_name"
  printf '  %-14s lines=%-6s age=%s\n' \
    "$cache_name" "$(line_count "$cache_file")" "$(cache_age "$cache_file")"
done
echo ""

echo "timings"
start="$(now_seconds)"
# shellcheck source=/dev/null
. "$source_file"
status_code=$?
end="$(now_seconds)"
printf '  %-28s %10s ms  status=%s\n' "source file" "$(elapsed_ms "$start" "$end")" "$status_code"
[ "$status_code" -eq 0 ] || exit "$status_code"

time_call "find .git dirs" step_find_all_dirs || exit 1
time_call "classify dirs" step_classify_dirs || exit 1
time_call "p query match" step_p_match || exit 1
time_call "build shared completion caches" step_shared_completion_cache_build || exit 1
time_call "filter p candidates" step_completion_filter || exit 1
time_call "build rp names" step_rp_completion_names || exit 1
time_call "actual _p_completion missing" step_actual_p_completion_missing_cache || exit 1
time_call "prime actual cache" step_prime_actual_completion_cache || exit 1
time_call "actual _p_completion warm" step_actual_p_completion_warm || exit 1

echo ""
echo "counts"
printf '  %-28s %s\n' "project dirs" "$(line_count "$tmp_dir/all_dirs")"
printf '  %-28s %s\n' "classified dirs" "$(line_count "$tmp_dir/classified")"
printf '  %-28s %s\n' "p matches" "$(line_count "$tmp_dir/p_matches")"
printf '  %-28s %s\n' "p completion names" "$(line_count "$tmp_dir/p_completion")"
printf '  %-28s %s\n' "p candidates" "$(line_count "$tmp_dir/p_candidates")"
printf '  %-28s %s\n' "sp completion names" "$(line_count "$tmp_dir/sp_completion")"
printf '  %-28s %s\n' "rp completion names" "$(line_count "$tmp_dir/rp_completion")"
