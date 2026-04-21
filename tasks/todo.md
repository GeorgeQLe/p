# Current: Completion Performance

> Project: p (project directory jumper and scaffolder)
> Full plan: tasks/roadmap.md

**Goal**: Reduce tab-completion latency for `p` and make future performance regressions measurable.

---

### Implementation
- [x] Add `scripts/time-p.sh` timing diagnostic for completion phases
- [x] Prune `node_modules` and `.git` traversal in project discovery
- [x] Rebuild `p_completion` and `sp_completion` from one shared cache builder
- [x] Serve stale caches immediately and refresh them in the background
- [x] Add explicit cache refresh commands: `p --warm-cache` and `pconfig rebuild-cache`
- [x] Document completion cache behavior and refresh commands
- [x] Preserve existing mobile category default/config example update

### Verification
- [x] `shellcheck -s bash p.bash`
- [x] `shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh`
- [x] `shellcheck scripts/time-p.sh`
- [x] `bats tests/p.bats`
- [x] `TEST_SHELL=zsh bats tests/p.bats`
- [x] `scripts/time-p.sh --shell zsh --query p --prefix p`
- [x] `scripts/time-p.sh --shell bash --query p --prefix p`
- [x] Stale-cache completion smoke test for bash and zsh

### Results
- Cold zsh `_p_completion`: reduced from about 500 ms to about 140 ms in the timing diagnostic.
- Warm zsh `_p_completion`: about 10 ms.
- Stale-cache completion: about 8-12 ms while refresh runs in the background.

### Outstanding
- [ ] Manual smoke test in an interactive shell after re-sourcing `p.zsh` or `p.bash`: press Tab for `p <prefix>` and confirm suggestions appear without visible lag.
