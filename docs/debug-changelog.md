# Debug Changelog

## 2026-04-21 — Completion lag remained visible after cache optimization

- Symptom: Tab completion still felt laggy after the shared stale-cache optimization; user reported it felt about the same.
- Category: performance
- Severity: medium
- Root cause: `_p_completion` and `_sp_completion` still synchronously rebuilt completion caches when the target cache file was missing, so cache invalidation or a missing `sp_completion` could keep a roughly 170 ms Tab-path scan. Warm completion also paid repeated cache age checks, and zsh loaded all cached candidates through a `cat` command substitution before zsh filtered them.
- Fix: Added async cache mode for completion callers, made missing-cache completion start a background refresh and return without blocking, throttled async stale checks to once per shell every 60 seconds, and changed zsh completion to read the cache in-shell while only passing prefix-matched candidates to `compadd`.
- Test results: `shellcheck -s bash p.bash`; `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`; `shellcheck scripts/time-p.sh`; `bats tests/p.bats`; `TEST_SHELL=zsh bats tests/p.bats`; `scripts/time-p.sh --shell zsh --query p --prefix p`; `scripts/time-p.sh --shell bash --query p --prefix p`.
- Related entries: none; this is the first debug changelog entry. It follows the 2026-04-21 completion performance audit in `tasks/history.md`.
- Systemic: yes. Completion diagnostics measured rebuild cost, but did not distinguish missing-cache completion behavior from warm cached behavior.
