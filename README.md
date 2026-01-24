<p align="center">
  <img src="https://wt-tiger.vercel.app/og-image.png" alt="wt - Git Worktree Manager" width="600" />
</p>

<h1 align="center">wt</h1>

<p align="center">
  <strong>Git worktrees, on steroids.</strong>
  <br />
  A fast, interactive git worktree manager with GitHub and Claude integration.
</p>

<p align="center">
  <a href="https://wt-tiger.vercel.app">Website</a> •
  <a href="https://wt-tiger.vercel.app/docs">Documentation</a> •
  <a href="#installation">Installation</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.6.0-orange" alt="Version" />
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License" />
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey" alt="Platform" />
</p>

---

## Why wt?

Git worktrees are powerful but managing them manually is tedious. `wt` provides:

- **One command** to navigate, create, and delete worktrees
- **Quick switch** — `wt feat` to fuzzy-match and jump to a worktree
- **PR workflow** — create a worktree directly from a GitHub PR
- **Issue workflow** — create a worktree from a GitHub issue with auto-named branch
- **Claude integration** — auto-resolve issues, fix CI failures, review PRs
- **Dirty indicator** — see which worktrees have uncommitted changes

## Installation

### macOS (Homebrew)

```bash
brew tap AThevon/wt && brew install wt
```

### Linux / WSL

```bash
git clone https://github.com/AThevon/wt.git && cd wt && ./install-linux.sh
```

### Setup

Run the setup wizard:

```bash
wt --setup
```

This will check dependencies, create symlinks, and configure your shell.

## Usage

### Interactive Mode

```bash
wt          # Open interactive menu
wt feat     # Quick switch (fuzzy match)
wt -        # Previous worktree
wt .        # Main worktree
```

### Main Menu

```
                                   __,,,,_
                    _ __..-;''`--/'/ /.',-`-.
                (`/' ` |  \ \ \\ / / / / .-'/`,_
               /'`\ \   |  \ | \| // // / -.,/_,'-,
              /<7' ;  \ \  | ; ||/ /| | \/    |`-/,/-.,_,/')
             /  _.-, `,-\,__|  _-| / \ \/|_/  |    '-/.;.\'
             `-`  f/ ;      / __/ \__ `/ |__/ |
  _      ________ `-'      |  -| =|\_  \  |-' |
 | | /| / /_  __/       __/   /_..-' `  ),'  //
 | |/ |/ / / /         ((__.-'((___..-'' \__.'
 |__/|__/ /_/

  Git Worktree Manager v1.6.0

┌─────────────────────────────────────────────────────────────────────────┐
│ myapp │ ^E: editor │ ^N: new │ ^P: PRs │ ^G: issues │ ^D: delete        │
├─────────────────────────────────────────────────────────────────────────┤
│ > ~/projects/myapp                                          [main]      │
│   ~/projects/myapp-feature-auth                          *  [feature]   │
│   ~/projects/myapp-reviewing-fix-bug                        [fix/bug]   │
│ -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-     │
│   Create a worktree                                                     │
│   Manage stashes                                                        │
│   Delete worktree(s)                                                    │
│   Quit                                                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

The `*` indicates worktrees with uncommitted changes.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Select / Navigate |
| `Ctrl+N` | Create new worktree |
| `Ctrl+E` | Open in editor |
| `Ctrl+P` | List PRs |
| `Ctrl+G` | List issues |
| `Ctrl+D` | Delete worktree(s) |
| `Ctrl+O` | Open in browser |
| `Tab` | Multi-select |
| `Esc` | Back / Cancel |

## Features

### Create Worktrees

- **New branch** — enter name and select base branch
- **From existing branch** — browse local/remote branches
- **From current** — quick copy with timestamp
- **From an issue** — creates `feature/{issue-num}-{title}` branch
- **Review a PR** — creates worktree with `reviewing-` prefix

### Claude Integration

Launch Claude from any issue or PR with three modes:

| Mode | Description |
|------|-------------|
| **Forced** | Full auto — Claude executes everything |
| **Ask** | Claude confirms before impactful actions |
| **Plan** | Claude creates a plan first |

**Auto-resolve issues:** Claude reads the issue, implements the solution, and creates a PR.

**Fix CI failures:** Claude fetches logs, fixes the code, and pushes.

**Review PRs:** Claude performs a comprehensive code review.

### Stash Management

The stash menu provides a complete workflow with rich information:

- **Enhanced list** — age, file count, original branch
- **Preview panel** — stash info, impacted files, conflict detection
- **Partial stash** — select specific files with `Space`
- **Multi-select drop** — delete multiple stashes at once
- **Create worktree from stash** — `Ctrl+W`
- **Create branch from stash** — `Ctrl+B`
- **Resolve conflicts with Claude** — `Ctrl+R`
- **Export to .patch** — `Ctrl+X`
- **Rename stash** — `Ctrl+E`

| Key | Action |
|-----|--------|
| `Ctrl+A` | Apply stash |
| `Ctrl+P` | Pop stash |
| `Ctrl+D` | Drop stash(es) |
| `Ctrl+W` | Create worktree from stash |
| `Ctrl+B` | Create branch from stash |
| `Ctrl+N` | New stash |
| `Ctrl+E` | Rename stash |
| `Ctrl+R` | Resolve conflicts (Claude) |
| `Ctrl+S` | Partial stash (select files) |
| `Ctrl+X` | Export to .patch |
| `?` | Show all shortcuts |

### PR Status Indicators

| CI | Review | Meaning |
|----|--------|---------|
| `[ok]` | `✓` | Passed / Approved |
| `[fail]` | `✗` | Failed / Changes requested |
| `[..]` | | Running |
| `[draft]` | | Draft PR |

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| [fzf](https://github.com/junegunn/fzf) | Yes | Interactive selection |
| [gh](https://cli.github.com/) | No | GitHub integration |
| [jq](https://stedolan.github.io/jq/) | No | JSON parsing |
| [claude](https://claude.ai/code) | No | AI features |

## Uninstall

**macOS:**
```bash
brew uninstall wt && brew untap AThevon/wt
```

**Linux/WSL:**
```bash
sudo rm /usr/local/bin/wt-core
# Remove from ~/.zshrc or ~/.bashrc:
# eval "$(wt-core --shell-init)"
```

## License

GPL-3.0
