# dotfiles

## Setup

```bash
git clone https://github.com/GeorgeQLe/dotfiles ~/dotfiles
```

Add to `~/.bashrc`:

```bash
source "$HOME/dotfiles/p.bash"
```

## What's included

### `p.bash` — project jumper

Jump to any project directory under `~/projects` by partial name match.

```bash
p              # list all projects
p foo          # cd to project matching "foo" (substring, case-insensitive)
p foo<Tab>     # tab-complete project names (prefix match)
```

Detects projects by the presence of `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Makefile`, or `.git`. Tab completion uses a 5-minute cache to stay fast.

### `np` — new project scaffolder

Interactive function to create a new project directory in the right location based on category rules.

```bash
np             # prompts for name, category, and optional git init
np my-project  # skip the name prompt
```

Categories are organized by type:

- **Lifecycle-tracked** (`games/`, `mobile/`, `poke/`, `static-web/`, `tools/`, `web/`) — new projects go in `<category>/dev/<name>`
- **Flat** (`clones/`, `engines/`, `gcanbuild/`, `libs/`, `scripts/`, `starters/`) — projects go directly in `<category>/<name>`
- **Sandbox** — prompts for a sub-type (`web`, `games`, `tools`) and places in `sandbox/<type>/<name>`

Shows a confirmation summary before creating. Validates kebab-case naming and checks for existing directories.
