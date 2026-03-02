# dotfiles

## Setup

```bash
git clone https://github.com/GeorgeQLe/dotfiles ~/dotfiles
```

**Bash** — add to `~/.bashrc`:

```bash
source "$HOME/dotfiles/p.bash"
```

**Zsh (macOS default)** — add to `~/.zshrc`:

```zsh
source "$HOME/dotfiles/p.zsh"
```

Both variants are functionally identical; they differ only in shell-specific syntax (completion system, case-folding, `read` builtins, etc.).

## What's included

### `p.bash` / `p.zsh` — project jumper

Jump to any project directory under `~/projects` by partial name match.

```bash
p              # list all projects
p foo          # cd to project matching "foo" (substring, case-insensitive)
p foo<Tab>     # tab-complete project names (prefix match)
p --origin     # cd to the directory containing p.bash
```

Detects projects by the presence of a `.git` directory. Tab completion uses a 5-minute cache to stay fast.

### `sp` — project search

Search for a project by name across all `~/projects` category directories. Unlike `p` which matches and immediately jumps, `sp` lists all matches with their category paths and lets you pick one.

```bash
sp foo          # find projects matching "foo", show results with paths
sp foo<Tab>     # tab-complete project names (prefix match)
```

### `np` — new project scaffolder

Interactive function to create a new project directory in the right location based on category rules.

```bash
np             # prompts for name and category, then git-inits
np my-project  # skip the name prompt
```

Categories are organized by type:

- **Lifecycle-tracked** (`games/`, `mobile/`, `poke/`, `static-web/`, `tools/`, `web/`) — new projects go in `<category>/dev/<name>`
- **Flat** (`clones/`, `engines/`, `gcanbuild/`, `libs/`, `scripts/`, `starters/`) — projects go directly in `<category>/<name>`
- **Sandbox** — prompts for a sub-type (`web`, `games`, `tools`) and places in `sandbox/<type>/<name>`

Shows a confirmation summary before creating. Always initializes a git repo. Validates kebab-case naming and checks for existing directories.
