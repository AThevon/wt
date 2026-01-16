# wt

A fast, interactive git worktree manager with fzf, GitHub integration, and Claude Code support.

![Version](https://img.shields.io/badge/version-1.2.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey)

## Why wt?

Git worktrees are powerful but managing them manually is tedious. `wt` provides:

- **One command** to navigate, create, and delete worktrees
- **PR review workflow** - create a worktree directly from a GitHub PR
- **Issue workflow** - create a worktree from a GitHub issue with auto-named branch
- **Claude Code integration** - automatically start Claude with context for PR review or issue planning
- **Quick switch** - `wt <name>` to fuzzy-match and jump to a worktree
- **Dirty indicator** - see which worktrees have uncommitted changes

## Installation

### macOS (Homebrew)

```bash
brew tap AThevon/wt
brew install wt
```

### Linux / WSL

```bash
git clone https://github.com/AThevon/wt.git
cd wt
./install-linux.sh
```

### Shell setup

Add to your `~/.zshrc` (or `~/.bashrc`):

```bash
eval "$(wt-core --shell-init)"
```

Restart your terminal or run `source ~/.zshrc`.

## Usage

### Interactive Mode

Run `wt` in any git repository:

```bash
wt
```

### Quick Switch

Jump directly to a worktree by name:

```bash
wt feat    # Fuzzy matches "feature-auth", "feat-login", etc.
wt review  # Jumps to "reviewing-fix-bug"
```

## Main Menu

```
┌────────────────────────────────────────────────────────────┐
│ Worktrees - myapp | Ctrl+E: open in editor                 │
├────────────────────────────────────────────────────────────┤
│ > ~/projects/myapp                              [main]     │
│   ~/projects/myapp-feature-auth              *  [feature]  │
│   ~/projects/myapp-reviewing-fix-bug            [fix/bug]  │
├────────────────────────────────────────────────────────────┤
│   Create a worktree                                        │
│   Manage stashes                                           │
│   Remove a worktree                                        │
│   Quit                                                     │
└────────────────────────────────────────────────────────────┘
```

The `*` indicates worktrees with uncommitted changes.

## Features

### Create Worktrees

| Option | Description |
|--------|-------------|
| From current branch | Creates a copy with timestamp |
| From a branch | Browse all local/remote branches |
| Create new branch | Enter name, select base branch |
| From an issue | Creates `feature/{issue-num}-{title}` branch |
| Review a PR | Creates worktree with `reviewing-` prefix |

### GitHub Issue Integration

Select "From an issue" to see open issues:

```
┌────────────────────────────────────────────────────────────┐
│ Open Issues | Enter: create worktree | Ctrl+O: browser     │
├────────────────────────────────────────────────────────────┤
│ > #7   Add dark mode support                    @john      │
│   #5   Fix memory leak in parser                @jane      │
│   #3   Update documentation                     @bob       │
└────────────────────────────────────────────────────────────┘
```

Selecting an issue creates a branch like `feature/7-add-dark-mode-support`.

### PR Review

```
┌────────────────────────────────────────────────────────────┐
│ Open PRs | Enter: create worktree | Ctrl+O: browser        │
├────────────────────────────────────────────────────────────┤
│ > #142  ✅     feat: add dark mode              @john      │
│   #140  ❌     fix: memory leak                 @jane      │
│   #138  ⏳ ✓   chore: update deps               @bob       │
└────────────────────────────────────────────────────────────┘
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

### Claude Code Integration

After creating a worktree from an issue or PR, `wt` asks if you want to launch Claude Code:

```
Launch Claude Code for Issue #7 planning? [y/N]
```

If you say yes, Claude opens with a pre-filled prompt to:
- **For issues**: Read the issue and propose an implementation plan
- **For PRs**: Review the code changes for bugs and best practices

### Stash Management

Access "Manage stashes" from the main menu to:
- List all stashes with diff preview
- Apply, pop, or drop stashes
- Create new stashes (Ctrl+N)

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Select / Create worktree |
| `Ctrl+E` | Open worktree in editor (main menu) |
| `Ctrl+O` | Open in browser (PR/Issue view) |
| `Ctrl+N` | Create new stash (stash menu) |
| `Esc` | Go back / Cancel |

### Editor Detection

`Ctrl+E` auto-detects your editor in this order:
1. Cursor
2. VS Code
3. `$EDITOR`
4. vim

## Worktree Placement

Worktrees are always created next to your main repository:

```
~/projects/
├── myapp/                         # Main repo
├── myapp-feature-auth/            # From branch
├── myapp-feature-7-add-dark-mode/ # From issue
├── myapp-reviewing-fix-bug/       # From PR
└── myapp-main-copy-20250116/      # From current
```

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| [fzf](https://github.com/junegunn/fzf) | Yes | Interactive selection |
| [gh](https://cli.github.com/) | No | GitHub PR/Issue integration |
| [jq](https://stedolan.github.io/jq/) | No | JSON parsing |
| [claude](https://claude.ai/code) | No | Claude Code integration |

**macOS:** All dependencies except Claude are automatically installed via Homebrew.

**Linux/WSL:** The install script installs required dependencies via apt. For `gh`, see [GitHub CLI installation](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

## Uninstall

### macOS

```bash
brew uninstall wt
brew untap AThevon/wt
```

### Linux / WSL

```bash
sudo rm /usr/local/bin/wt-core
```

Then remove from `~/.zshrc` (or `~/.bashrc`):

```bash
eval "$(wt-core --shell-init)"
```

## License

MIT
