# wt

A fast, interactive git worktree manager with fzf and GitHub PR integration.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Why wt?

Git worktrees are powerful but managing them manually is tedious. `wt` provides:

- **One command** to navigate, create, and delete worktrees
- **PR review workflow** - create a worktree directly from a GitHub PR
- **Automatic navigation** - `cd` into worktrees after selection/creation
- **Smart naming** - worktrees are named consistently (e.g., `myapp-reviewing-feature-branch`)

## Installation

```bash
brew tap AThevon/wt
brew install wt
```

Add to your `~/.zshrc`:

```bash
eval "$(wt-core --shell-init)"
```

Restart your terminal or run `source ~/.zshrc`.

## Usage

Run `wt` in any git repository:

```bash
wt
```

### Main Menu

```
┌────────────────────────────────────────────────────────┐
│ Worktrees - myapp                                      │
├────────────────────────────────────────────────────────┤
│ > ~/projects/myapp                          [main]     │
│   ~/projects/myapp-feature-auth             [feature]  │
│   ~/projects/myapp-reviewing-fix-bug        [fix/bug]  │
├────────────────────────────────────────────────────────┤
│   Create a worktree                                    │
│   Remove a worktree                                    │
│   Quit                                                 │
└────────────────────────────────────────────────────────┘
```

### PR Review

When selecting "Review a PR", you'll see all open PRs with their status:

```
┌────────────────────────────────────────────────────────┐
│ Open PRs | Enter: create worktree | Ctrl+O: browser    │
├────────────────────────────────────────────────────────┤
│ > #142  ✅     feat: add dark mode           @john     │
│   #140  ❌     fix: memory leak              @jane     │
│   #138  ⏳ ✓   chore: update deps            @bob      │
└────────────────────────────────────────────────────────┘
```

**Status icons:**
| Icon | Meaning |
|------|---------|
| ✅ | All CI checks passed |
| ❌ | CI checks failed |
| ⏳ | CI checks running |
| ⚪ | No CI checks |
| 📝 | Draft PR |
| ✓ | PR approved |
| ✗ | Changes requested |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Select / Create worktree |
| `Ctrl+O` | Open PR in browser (PR view only) |
| `Esc` | Go back / Cancel |

## Features

### Create Worktrees

- **From current branch** - Creates a copy with timestamp
- **From any branch** - Browse all local/remote branches
- **From a PR** - Creates worktree with `reviewing-` prefix

### Smart Worktree Placement

Worktrees are always created next to your main repository:

```
~/projects/
├── myapp/                    # Main repo
├── myapp-feature-auth/       # From branch
├── myapp-reviewing-fix-bug/  # From PR
└── myapp-main-copy-20250116/ # From current
```

### GitHub Integration

On first use, if GitHub CLI is not configured, `wt` will guide you through authentication:

```
┌────────────────────────────────────────────────────────┐
│ GitHub CLI is not configured                           │
├────────────────────────────────────────────────────────┤
│ > Login via browser (recommended)                      │
│   Login with a token                                   │
│   Continue without GitHub                              │
│   Quit                                                 │
└────────────────────────────────────────────────────────┘
```

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| [fzf](https://github.com/junegunn/fzf) | Yes | Interactive selection |
| [gh](https://cli.github.com/) | No | GitHub PR integration |
| [jq](https://stedolan.github.io/jq/) | No | JSON parsing for PRs |

All dependencies are automatically installed via Homebrew.

## Uninstall

```bash
brew uninstall wt
brew untap AThevon/wt
```

Remove from `~/.zshrc`:
```bash
eval "$(wt-core --shell-init)"
```

## License

MIT
