# wt

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
```

A fast, interactive git worktree manager with fzf, GitHub integration, and Claude Code support.

![Version](https://img.shields.io/badge/version-1.3.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey)

## Why wt?

Git worktrees are powerful but managing them manually is tedious. `wt` provides:

- **One command** to navigate, create, and delete worktrees
- **PR review workflow** - create a worktree directly from a GitHub PR
- **Issue workflow** - create a worktree from a GitHub issue with auto-named branch
- **Claude Code integration** - launch Claude with context for PR review, CI fixing, or issue auto-resolve
- **Quick switch** - `wt <name>` to fuzzy-match and jump to a worktree
- **Dirty indicator** - see which worktrees have uncommitted changes

## Installation

### macOS (Homebrew)

```bash
brew tap AThevon/wt
brew install wt
```

Then run the setup command:

```bash
wt --setup
```

This will:
- Check dependencies (fzf required, gh/jq/claude optional)
- Create the `wt-core` symlink if needed
- Add the shell initialization to your `~/.zshrc` or `~/.bashrc`

### Linux / WSL

```bash
git clone https://github.com/AThevon/wt.git
cd wt
./install-linux.sh
```

Then run:

```bash
wt --setup
```

### Manual Shell Setup

If you prefer manual setup, add to your `~/.zshrc` (or `~/.bashrc`):

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

### Command Line Options

| Option | Description |
|--------|-------------|
| `wt` | Interactive menu |
| `wt <name>` | Quick switch to matching worktree |
| `wt --setup` | One-time installation |
| `wt --help` | Show help |
| `wt --version` | Show version |

## Main Menu

```
                                   __,,,,_
                    _ __..-;''`--/'/ /.',-`-.
                ...

  Git Worktree Manager v1.3.0

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
| `Enter` | Select / Navigate to worktree |
| `Ctrl+E` | Open worktree in editor |
| `Ctrl+N` | Create new worktree |
| `Ctrl+P` | List PRs |
| `Ctrl+G` | List GitHub issues |
| `Ctrl+D` | Delete worktree(s) |
| `Ctrl+O` | Open in browser (PR/Issue view) |
| `Tab` | Multi-select (delete mode) |
| `Esc` | Go back / Cancel |

## Features

### Create Worktrees

| Option | Description |
|--------|-------------|
| New branch | Enter name, select base branch |
| From existing branch | Browse all local/remote branches |
| From current (quick copy) | Creates a copy with timestamp |
| From an issue | Creates `feature/{issue-num}-{title}` branch |
| Review a PR | Creates worktree with `reviewing-` prefix |

### GitHub Issue Integration

Select "From an issue" to see open issues:

```
┌────────────────────────────────────────────────────────────┐
│ Open Issues | Enter: select | Ctrl+O: open in browser      │
├────────────────────────────────────────────────────────────┤
│ > #7   Add dark mode support                    @john      │
│   #5   Fix memory leak in parser                @jane      │
│   #3   Update documentation                     @bob       │
└────────────────────────────────────────────────────────────┘
```

After selecting an issue, choose an action:

| Action | Description |
|--------|-------------|
| **Auto-resolve (full auto)** | Claude reads the issue, implements it, and creates a PR automatically |
| **Launch Claude** | Start Claude with issue context in your preferred mode |
| **Just create worktree** | Create the branch without Claude |

### PR Review

```
┌────────────────────────────────────────────────────────────┐
│ Open PRs | Enter: select | Ctrl+O: open in browser         │
├────────────────────────────────────────────────────────────┤
│ > #142  [ok] ✓   feat: add dark mode            @john      │
│   #140  [fail]   fix: memory leak               @jane      │
│   #138  [..]     chore: update deps             @bob       │
└────────────────────────────────────────────────────────────┘
```

**Status indicators:**

| CI Status | Meaning |
|-----------|---------|
| `[ok]` | All CI checks passed |
| `[fail]` | CI checks failed |
| `[..]` | CI checks running |
| `[--]` | No CI checks |
| `[draft]` | Draft PR |

| Review Status | Meaning |
|---------------|---------|
| `✓` | PR approved |
| `✗` | Changes requested |

After selecting a PR, choose an action:

| Action | Description |
|--------|-------------|
| **Fix CI issues (auto)** | Claude fetches failed CI logs, fixes the issues, and pushes (only shown if CI failed) |
| **Review this PR** | Claude performs a code review |
| **Launch Claude** | Start Claude with PR context |
| **Just create worktree** | Checkout the PR branch without Claude |

### Claude Code Integration

When launching Claude from an issue or PR, choose your preferred mode:

```
┌────────────────────────────────────────────────────────────┐
│ Claude mode for Issue #7                                   │
├────────────────────────────────────────────────────────────┤
│ > >> Forced (full auto)                                    │
│   ?> Ask (confirm actions)                                 │
│   ## Plan (plan first)                                     │
└────────────────────────────────────────────────────────────┘
```

| Mode | Flag | Description |
|------|------|-------------|
| **Forced** | `--dangerously-skip-permissions` | Claude executes all actions automatically |
| **Ask** | (default) | Claude asks for confirmation before impactful actions |
| **Plan** | `--permission-mode=plan` | Claude analyzes and creates a plan first |

### Auto-Resolve Issues

Select "Auto-resolve" on an issue and Claude will autonomously:

1. Read and analyze the issue
2. Explore the codebase
3. Implement the solution
4. Run tests/build to verify
5. Commit and push
6. Create a Pull Request

### Auto-Fix CI Failures

When a PR has failed CI checks, select "Fix CI issues" and Claude will:

1. Fetch the failed CI logs from GitHub
2. Analyze the errors
3. Fix the code
4. Verify locally
5. Push the fix

### Stash Management

Access "Manage stashes" from the main menu to:

- List all stashes with diff preview
- Apply, pop, or drop stashes
- Create new stashes (Ctrl+N)

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
| [jq](https://stedolan.github.io/jq/) | No | JSON parsing for PR/Issue display |
| [claude](https://claude.ai/code) | No | Claude Code integration |

Run `wt --setup` to check your dependencies status.

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
# wt - Git Worktree Manager
eval "$(wt-core --shell-init)"
```

## License

MIT
