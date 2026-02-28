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
