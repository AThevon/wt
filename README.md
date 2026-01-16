# wt - Git Worktree Manager

Interactive git worktree manager with fzf and GitHub PR integration.

## Installation

```bash
brew tap YOUR_USERNAME/wt
brew install wt
```

Then add to your `.zshrc`:

```bash
eval "$(wt-core --shell-init)"
```

## Features

- Navigate between worktrees with fzf
- Create worktrees from current branch, any branch, or a PR
- Review PRs directly (creates a worktree with `reviewing-` prefix)
- Delete worktrees (single or all)
- Automatic `cd` to selected/created worktree

## Usage

Run `wt` in any git repository to open the interactive menu.

### Keyboard shortcuts

In PR review mode:
- `Enter` - Create worktree for selected PR
- `Ctrl+O` - Open PR in browser

## Dependencies

- `fzf` - Fuzzy finder
- `gh` - GitHub CLI (optional, for PR features)
- `jq` - JSON processor

## Manual installation

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/wt.git
cd wt

# Add to your .zshrc
echo 'source /path/to/wt/completions/wt.zsh' >> ~/.zshrc
echo 'alias wt-core="/path/to/wt/wt.sh"' >> ~/.zshrc
```

## License

MIT
