# p

Project directory jumper and scaffolder for bash and zsh.

`p` finds projects by scanning for `.git` directories under a root folder, then lets you jump to them by partial name match. It also includes `sp` for searching projects across categories, `rp` for jumping to recently-visited projects, and `np` for scaffolding new projects with configurable directory structures.

## Quickstart

### 1. Clone

```bash
git clone https://github.com/GeorgeQLe/p ~/.p
```

### 2. Source (add to your shell rc file)

**Bash** (4.0+ required) — add to `~/.bashrc`:

```bash
source "$HOME/.p/p.bash"
```

**Zsh** (macOS default) — add to `~/.zshrc`:

```zsh
source "$HOME/.p/p.zsh"
```

Both variants are functionally identical; they differ only in shell-specific syntax (completion system, case-folding, `read` builtins, etc.).

### 3. (Optional) Set a custom projects directory

By default all commands scan `~/projects`. To use a different root:

```bash
export P_BASE="$HOME/code"
```

### 4. (Optional) Customize np categories

```bash
mkdir -p ~/.config/p
cp ~/.p/categories.conf.example ~/.config/p/categories.conf
# edit categories.conf to add/remove categories
```

## Commands

### `p` — project jumper

Jump to any project directory under `$P_BASE` by partial name match.

```bash
p              # list all projects
p foo          # cd to project matching "foo" (substring, case-insensitive)
p foo<Tab>     # tab-complete project names
p --origin     # cd to the directory containing p.bash/p.zsh
p --warm-cache # rebuild tab-completion caches
p --doctor     # check your p setup for issues
p --help       # show help
p --version    # show version
p config show  # manage configuration (alias for pconfig)
```

Detects projects by `.git` directory presence. Directory scans run across top-level categories in parallel, defaulting to 4 jobs; set `P_FIND_PARALLELISM` to tune this. Tab completion uses a 5-minute cache; stale caches are served immediately while a background refresh rebuilds suggestions. If no completion cache exists yet, Tab starts a background rebuild and returns without blocking; run `p --warm-cache` when you want suggestions ready immediately.

### `sp` — project search

Search for a project by name across all category directories. Unlike `p` which matches and immediately jumps, `sp` lists all matches with their category paths and lets you pick one.

```bash
sp foo          # find projects matching "foo", show results with paths
sp foo<Tab>     # tab-complete project names
sp --help       # show help
```

### `rp` — recent projects

Jump to a recently-visited project. History is recorded automatically whenever `p`, `sp`, or `np` successfully cd to a project.

```bash
rp              # list recent projects (most recent first), pick one
rp foo          # filter recent projects matching "foo", jump or pick
rp foo<Tab>     # tab-complete from recent project names
rp --clear      # clear project history
rp --help       # show help
```

History is stored in `~/.cache/p/p_history` (max 50 entries, deduplicated). Revisiting a project moves it to the most-recent position.

### `np` — new project scaffolder

Create a new project directory in the right location based on category rules.

```bash
np                                     # fully interactive
np my-project                          # skip the name prompt
np my-project --category web           # non-interactive (for scripts)
np my-exp --category sandbox --sandbox-type web  # sandbox with sub-type
np --help                              # show help
```

Each category has a type that determines the directory structure:

| Type | Directory layout | Example |
|------|-----------------|---------|
| `lifecycle` | `<category>/dev/<name>` | `web/dev/my-app` |
| `flat` | `<category>/<name>` | `libs/my-lib` |
| `sandbox` | `sandbox/<sub-type>/<name>` | `sandbox/web/my-experiment` |

Project names must be kebab-case (lowercase letters, numbers, hyphens, no leading/trailing hyphens).

### `p --doctor` — setup diagnostics

Validate your `p` installation and environment. Checks P_BASE, shell, git, config, projects, and cache status.

```bash
p --doctor
```

Example output:

```
p doctor (v1.0.0)

Environment:
  ✓ P_BASE: ~/projects (exists, 12 entries)
  ✓ Shell:  bash 5.3.9
  ✓ Git:    git 2.43.0
  ✗ P_CONFIG: ~/.config/p/categories.conf (not found, using defaults)

Config:
  ✓ 5 categories loaded (libs, sandbox, scripts, tools, web)
  ✓ 2 sandbox types (web, tools)
  ⚠ Config is using built-in defaults (run `pconfig init` to customize)

Projects:
  ✓ 47 projects found (38 standalone, 9 sub-packages)

Cache:
  ✓ p completion cache: valid (2 min old)
  ✓ sp completion cache: valid (2 min old)
```

### `pconfig` — configuration management

Manage categories and sandbox types without hand-editing config files. Also available as `p config`.

```bash
pconfig              # show current config (same as pconfig show)
pconfig init         # create config file from defaults
pconfig add          # add a new category (interactive)
pconfig remove       # remove a category (interactive)
pconfig add-sandbox-type    # add a sandbox sub-type
pconfig remove-sandbox-type # remove a sandbox sub-type
pconfig rebuild-cache       # rebuild tab-completion caches
pconfig path         # print config file path
pconfig edit         # open config in $EDITOR
pconfig --help       # show help
```

`p config` is an alias for `pconfig`, so `p config show`, `p config add`, etc. all work.

## Hooks

### `P_NP_HOOK` — post-creation hook for `np`

Set `P_NP_HOOK` to the path of an executable script and it will be called every time `np` creates a new project. Use it to automate post-creation tasks like creating a GitHub repo, registering the project in a tracker, or notifying a channel.

```bash
export P_NP_HOOK="$HOME/.p/hooks/after-np"
```

The hook receives four positional arguments:

| Argument | Description | Example |
|----------|-------------|---------|
| `$1` | Project name | `my-app` |
| `$2` | Category name | `web` |
| `$3` | Category type | `lifecycle` |
| `$4` | Full path to the created directory | `/home/user/projects/web/dev/my-app` |

**Failure semantics:** If the hook exits non-zero, `np` prints a warning to stderr but still succeeds (the project directory is already created). The hook is skipped entirely if `P_NP_HOOK` is unset or points to a non-executable file.

**Example** — auto-create a GitHub repo:

```bash
#!/usr/bin/env bash
# ~/.p/hooks/after-np
name="$1" path="$4"
cd "$path" && gh repo create "$name" --private --source=. --push
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `P_BASE` | `~/projects` | Root directory to scan for projects |
| `P_CONFIG` | `~/.config/p/categories.conf` | Path to category configuration file |
| `P_NP_HOOK` | *(unset)* | Path to executable called after `np` creates a project |
| `P_FIND_PARALLELISM` | `4` | Number of top-level project directories to scan concurrently |

## Configuration

Categories are loaded from `$P_CONFIG`. If no config file exists, built-in defaults are used. See `categories.conf.example` for the format reference.

```bash
mkdir -p ~/.config/p
cp ~/.p/categories.conf.example ~/.config/p/categories.conf
```

The config file uses a simple line-based format:

```
# name|type|description
libs|flat|Reusable libraries and SDKs
web|lifecycle|Web applications
sandbox|sandbox|Experiments and learning

sandbox_type:web
sandbox_type:tools
```

## How it differs from z / zoxide / autojump

Those tools track shell `cd` history using frecency (frequency + recency). `p` takes a different approach:

- **Project-centric** — finds projects by `.git` directory presence, not cd history
- **Zero warm-up** — `p` works immediately without building a history database; `rp` tracks only project visits (not every `cd`)
- **Category scaffolding** — `np` creates new projects in structured directory layouts
- **Deterministic** — `p` results depend on filesystem state, not usage patterns; `rp` adds optional recall of recent projects

If you want smart `cd` for arbitrary directories, use zoxide. If you organize projects under a root directory and want fast jumping + scaffolding, use `p`.

## Development

### Running tests

```bash
# Install bats-core
brew install bats-core  # macOS
# or: apt install bats  # Ubuntu

# Run tests
bats tests/p.bats                  # test bash variant
TEST_SHELL=zsh bats tests/p.bats   # test zsh variant
```

### Shellcheck

```bash
shellcheck -s bash p.bash
shellcheck -s bash -e SC2168,SC2296,SC2299,SC2300,SC2312 p.zsh
```

## License

[MIT](LICENSE)
