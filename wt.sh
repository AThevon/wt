#!/bin/bash

# =============================================================================
# wt - Git Worktree Manager avec fzf
# =============================================================================
# Le script retourne UNIQUEMENT le path vers lequel naviguer sur stdout
# Tous les messages vont sur stderr pour ne pas polluer le résultat
# =============================================================================

VERSION="1.5.0"

# =============================================================================
# Options de ligne de commande
# =============================================================================

if [[ "$1" == "--version" || "$1" == "-v" ]]; then
  echo "wt $VERSION" >&2
  exit 0
fi

# Mode dev: génère une fonction shell pointant vers ce script local
if [[ "$1" == "--dev" ]]; then
  local_script="$(cd "$(dirname "$0")" && pwd)/wt.sh"
  cat <<EOF
# wt - Dev Mode (local script)
unalias wt 2>/dev/null
function wt() {
  if [[ "\$1" == "--release" ]]; then
    eval "\$(wt-core --shell-init)"
    echo "Switched to release mode: wt-core"
    return
  fi
  if [[ "\$1" == "--dev" ]]; then
    echo "Already in dev mode: $local_script"
    return
  fi

  local output=\$(WT_WRAPPED=1 "$local_script" "\$@")
  local target=""
  local claude_cmd=""

  while IFS= read -r line; do
    if [[ "\$line" == CLAUDE:* ]]; then
      claude_cmd="\$line"
    elif [[ -n "\$line" && -d "\$line" ]]; then
      target="\$line"
    fi
  done <<< "\$output"

  if [[ -n "\$target" ]]; then
    local current_wt=\$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "\$current_wt" && "\$current_wt" != "\$target" ]]; then
      echo "\$current_wt" > ~/.wt_prev
    fi
    cd "\$target"
    echo "Navigated to: \$target"
  fi
}
echo "Switched to dev mode: $local_script"
EOF
  exit 0
fi

if [[ "$1" == "--shell-init" ]]; then
  cat <<'EOF'
# wt - Git Worktree Manager
unalias wt 2>/dev/null
function wt() {
  # Handle --dev: switch to local script from current worktree
  if [[ "$1" == "--dev" ]]; then
    local local_script="$(git rev-parse --show-toplevel 2>/dev/null)/wt.sh"
    if [[ -f "$local_script" ]]; then
      eval "$("$local_script" --dev)"
      echo "Switched to dev mode: $local_script"
    else
      echo "No wt.sh found in current worktree" >&2
    fi
    return
  fi
  # Handle --release: switch back to wt-core from PATH
  if [[ "$1" == "--release" ]]; then
    eval "$(wt-core --shell-init)"
    echo "Switched to release mode: wt-core"
    return
  fi

  local output=$(WT_WRAPPED=1 wt-core "$@")
  local target=""
  local claude_cmd=""

  while IFS= read -r line; do
    if [[ "$line" == CLAUDE:* ]]; then
      claude_cmd="$line"
    elif [[ -n "$line" && -d "$line" ]]; then
      target="$line"
    fi
  done <<< "$output"

  if [[ -n "$target" ]]; then
    # Save current worktree before switching (for wt -)
    # Only save if we're in a git worktree (don't save random dirs)
    local current_wt=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$current_wt" && "$current_wt" != "$target" ]]; then
      echo "$current_wt" > ~/.wt_prev
    fi
    cd "$target"
    echo "Navigated to: $target"

    # Launch claude if marker present
    # Formats: CLAUDE:type:num:mode or CLAUDE:issue-auto:num
    if [[ -n "$claude_cmd" && "$claude_cmd" == CLAUDE:* ]]; then
      local type=$(echo "$claude_cmd" | cut -d: -f2)
      local num=$(echo "$claude_cmd" | cut -d: -f3)
      local mode=$(echo "$claude_cmd" | cut -d: -f4)

      local claude_flags=""
      local prompt=""

      # Handle auto-resolve (always forced, no mode param)
      if [[ "$type" == "issue-auto" ]]; then
        claude_flags="--dangerously-skip-permissions"
        echo ""
        echo ">> AUTO-RESOLVE: Issue #$num"
        echo "   Claude will plan, implement, and create a PR automatically."
        echo ""

        prompt="You are auto-resolving GitHub Issue #$num.

MISSION: Fully resolve this issue autonomously and create a Pull Request.

PHASE 1 - UNDERSTAND:
1. Run 'gh issue view $num' to read the issue details
2. Identify exactly what needs to be done
3. Note acceptance criteria and constraints

PHASE 2 - EXPLORE:
4. Explore the codebase to understand the architecture
5. Find relevant files and patterns
6. Identify what needs to change

PHASE 3 - IMPLEMENT:
7. Make the necessary code changes
8. Follow existing code patterns and conventions
9. Handle edge cases and errors appropriately
10. Add tests if the project has them

PHASE 4 - VERIFY:
11. Detect the package manager (check for pnpm-lock.yaml, yarn.lock, or package-lock.json)
12. Run the project's test/build commands if available (pnpm/yarn/npm test, build, etc.)
13. Fix any errors before proceeding - do not push broken code

PHASE 5 - DELIVER:
14. Commit your changes with a clear message referencing #$num
15. Push the branch
16. Create a PR with 'gh pr create' that:
    - References the issue (Closes #$num)
    - Describes what was changed and why
    - Lists any considerations or trade-offs

Be thorough but efficient. Ship working code."

      elif [[ "$type" == "ci-fix" ]]; then
        claude_flags="--dangerously-skip-permissions"
        echo ""
        echo ">> AUTO-FIX CI: PR #$num"
        echo "   Claude will fetch CI logs, fix the issues, and push."
        echo ""

        prompt="You are fixing CI failures for Pull Request #$num.

MISSION: Analyze the CI failure logs, fix the issues, and push the fix.

PHASE 1 - GET CI LOGS:
1. Run 'gh run list --branch \$(git branch --show-current) --limit 5' to find recent workflow runs
2. Find the failed run ID
3. Run 'gh run view <run-id> --log-failed' to get the failure logs
4. If needed, run 'gh run view <run-id> --log' for full logs

PHASE 2 - ANALYZE:
5. Identify the root cause of the failure
6. Understand what needs to be fixed (tests, lint, build, types, etc.)

PHASE 3 - FIX:
7. Make the necessary code changes to fix the CI errors
8. Detect package manager (check for pnpm-lock.yaml, yarn.lock, or package-lock.json)
9. Run the same checks locally to verify the fix (lint, test, build, typecheck)
10. Make sure all checks pass before proceeding

PHASE 4 - PUSH:
11. Commit with a clear message like 'fix: resolve CI failures'
12. Push to the branch (git push)

IMPORTANT:
- Focus ONLY on fixing the CI errors, don't refactor unrelated code
- If multiple issues, fix them all
- Verify locally before pushing"

      else
        # Build flags based on mode
        case "$mode" in
          forced)
            claude_flags="--dangerously-skip-permissions"
            echo ""
            echo ">> Starting Claude in FORCED mode..."
            ;;
          ask)
            claude_flags=""
            echo ""
            echo "?> Starting Claude in ASK mode..."
            ;;
          plan)
            claude_flags="--permission-mode=plan"
            echo ""
            echo "## Starting Claude in PLAN mode..."
            ;;
        esac
        echo ""

        # Build prompt based on type
        case "$type" in
          "pr-review")
            prompt="You are reviewing Pull Request #$num.

FIRST STEPS:
1. Run 'gh pr view $num' to get PR title, description, and metadata
2. Run 'gh pr diff $num' to see all code changes

CODE REVIEW CHECKLIST:
- Logic & Correctness: Does it work? Edge cases handled?
- Security: Injection, auth issues, data exposure?
- Performance: N+1 queries, memory leaks, blocking ops?
- Error Handling: Proper error messages?
- Code Quality: Readable, DRY, good abstractions?
- Testing: Tests present and meaningful?
- Breaking Changes: Could this break existing code?

OUTPUT:
- Summary of the PR
- [OK] What looks good
- [~] Concerns (with file:line references)
- [!!] Blocking issues
- [?] Optional improvements
- Recommendation: Approve / Request Changes / Discuss"
            ;;

          "pr-work")
            prompt="You are working on Pull Request #$num.

FIRST STEPS:
1. Run 'gh pr view $num' to understand the PR context
2. Run 'gh pr diff $num' to see current changes

You are now in the PR branch. Help the user with whatever they need:
- Understanding the code
- Making additional changes
- Fixing issues
- Responding to review comments

Ask what they'd like to do."
            ;;

          "issue-work")
            prompt="You are working on GitHub Issue #$num.

FIRST STEPS:
1. Run 'gh issue view $num' to read the full issue
2. Identify the core problem or feature request
3. Note requirements and acceptance criteria

EXPLORATION:
4. Explore the codebase structure
5. Find related code and patterns
6. Identify dependencies and impact areas

PLANNING:
7. Break down into clear steps
8. Consider edge cases and testing

OUTPUT:
- Summary of the issue
- Files to create/modify
- Implementation approach
- Questions if any"
            ;;
        esac
      fi

      [[ -n "$prompt" ]] && claude $claude_flags "$prompt"
    fi
  fi
}
EOF
  exit 0
fi

# Switch to dev mode (use local script instead of wt-core)
if [[ "$1" == "--dev" ]]; then
  # Find wt.sh in current worktree
  local_script="$(git rev-parse --show-toplevel 2>/dev/null)/wt.sh"
  if [[ ! -f "$local_script" ]]; then
    echo "No wt.sh found in current worktree" >&2
    exit 1
  fi
  echo "# wt dev mode: $local_script"
  "$local_script" --shell-init | sed "s|wt-core|$local_script|g"
  exit 0
fi

# Switch back to release mode (use wt-core from PATH)
if [[ "$1" == "--release" ]]; then
  echo "# wt release mode: wt-core"
  wt-core --shell-init
  exit 0
fi

if [[ "$1" == "--setup" ]]; then
  # Colors for setup (defined early since msg() isn't available yet)
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    _GREEN=$'\033[32m'
    _RESET=$'\033[0m'
  else
    _GREEN='' _RESET=''
  fi
  _msg() { echo -e "$@" >&2; }

  _msg ""
  _msg "wt setup"
  _msg "--------"
  _msg ""

  # Detect shell
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)
      _msg "[!!] Unsupported shell: $shell_name"
      _msg "     Supported: zsh, bash"
      exit 1
      ;;
  esac
  _msg "[ok] Shell: $shell_name"
  _msg "[ok] Config: $rc_file"
  _msg ""

  # Check dependencies
  _msg "Dependencies:"
  deps_ok=true
  if command -v fzf &>/dev/null; then
    _msg "  [ok] fzf"
  else
    _msg "  [!!] fzf (required) - install with: brew install fzf"
    deps_ok=false
  fi
  if command -v gh &>/dev/null; then
    _msg "  [ok] gh"
  else
    _msg "  [--] gh (optional) - install with: brew install gh"
  fi
  if command -v jq &>/dev/null; then
    _msg "  [ok] jq"
  else
    _msg "  [--] jq (optional) - install with: brew install jq"
  fi
  if command -v claude &>/dev/null; then
    _msg "  [ok] claude"
  else
    _msg "  [--] claude (optional)"
  fi
  _msg ""

  if [[ "$deps_ok" == false ]]; then
    _msg "[!!] Install required dependencies first"
    exit 1
  fi

  # Check if wt-core is available
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if ! command -v wt-core &>/dev/null; then
    _msg "Setting up wt-core command..."

    # Determine install location
    if [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
      install_dir="/usr/local/bin"
    elif [[ -d "$HOME/.local/bin" ]]; then
      install_dir="$HOME/.local/bin"
    else
      mkdir -p "$HOME/.local/bin"
      install_dir="$HOME/.local/bin"
    fi

    # Create symlink
    ln -sf "$script_path" "$install_dir/wt-core"
    _msg "[ok] Created: $install_dir/wt-core -> $script_path"

    # Check if install_dir is in PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
      _msg ""
      _msg "[!!] $install_dir is not in your PATH"
      _msg "     Add this to your $rc_file:"
      _msg ""
      _msg "     export PATH=\"$install_dir:\$PATH\""
      _msg ""
    fi
  else
    _msg "[ok] wt-core already in PATH"
  fi

  # Check if already configured
  init_line='command -v wt-core &>/dev/null && eval "$(wt-core --shell-init)"'
  if grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
    _msg "[ok] Already configured in $rc_file"
  else
    _msg ""
    _msg "Adding wt to $rc_file..."
    echo "" >> "$rc_file"
    echo "# wt - Git Worktree Manager" >> "$rc_file"
    echo "$init_line" >> "$rc_file"
    _msg "[ok] Added to $rc_file"
  fi

  _msg ""
  _msg "--------"
  _msg "${_GREEN}Setup complete!${_RESET}"
  _msg ""
  _msg "To activate now, run:"
  _msg ""
  _msg "  source $rc_file"
  _msg ""
  _msg "Or restart your terminal."
  _msg ""
  exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat >&2 <<EOF
wt - Git Worktree Manager with fzf

Usage: wt [options] [name]

Arguments:
  name             Quick switch: fuzzy match on worktrees
  -                Switch to previous worktree (like cd -)
  .                Switch to main worktree

Options:
  --help, -h       Show this help message
  --version, -v    Show version number
  --setup          Install wt (add to shell, create symlinks)
  --dev            Switch to dev mode (use wt.sh from current worktree)
  --release        Switch back to release mode (use wt-core from PATH)

Keyboard shortcuts:
  Ctrl+E           Open in editor
  Ctrl+N           New worktree
  Ctrl+P           List PRs
  Ctrl+G           List issues (G = GitHub)
  Ctrl+D           Delete worktree(s)

Features:
  - Create worktrees from branch, PR, or GitHub issue
  - Multi-select delete with Space
  - Dirty indicator (*) for uncommitted changes
  - Claude Code integration (forced/ask/plan modes)

Quick start:
  wt --setup       One-time installation
  wt               Interactive menu
  wt <name>        Quick switch to worktree
  wt -             Switch to previous worktree (like cd -)
  wt .             Switch to main worktree

Dependencies: fzf (required), gh, jq, claude (optional)
EOF
  exit 0
fi

# Vérifier qu'on est dans un repo git (sauf pour wt -)
if [[ "$1" != "-" ]] && ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Not in a git repository" >&2
  exit 1
fi

# REPO_ROOT = worktree actuel (peut être secondaire)
# MAIN_REPO = worktree principal (toujours le premier dans la liste)
REPO_ROOT=$(git rev-parse --show-toplevel)
MAIN_REPO=$(git worktree list --porcelain | grep "^worktree " | head -1 | cut -d' ' -f2-)
REPO_NAME=$(basename "$MAIN_REPO")
SCRIPT_PATH="${BASH_SOURCE[0]}"

# =============================================================================
# Colors & Style
# =============================================================================

# Colors (only if terminal supports it)
if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_WHITE=$'\033[37m'
  C_ORANGE=$'\033[1;38;5;208m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN=''
  C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE='' C_ORANGE=''
fi

# =============================================================================
# Helpers - TOUT sur stderr sauf le path final
# =============================================================================

has_fzf() {
  command -v fzf &> /dev/null
}

has_gh() {
  command -v gh &> /dev/null && gh auth status &> /dev/null
}

has_claude() {
  command -v claude &> /dev/null
}

get_editor() {
  if command -v cursor &>/dev/null; then echo "cursor"
  elif command -v code &>/dev/null; then echo "code"
  elif [[ -n "$EDITOR" ]]; then echo "$EDITOR"
  else echo "vim"
  fi
}

# Messages sur stderr uniquement
msg() {
  echo -e "$@" >&2
}

msg_success() {
  echo -e "${C_GREEN}✓${C_RESET} $*" >&2
}

msg_error() {
  echo -e "${C_RED}✗${C_RESET} $*" >&2
}

msg_info() {
  echo -e "${C_CYAN}→${C_RESET} $*" >&2
}

msg_warn() {
  echo -e "${C_YELLOW}!${C_RESET} $*" >&2
}

# Loading bar animation
# Usage: loader_start "message" ; do_stuff ; loader_stop
LOADER_PID=""
loader_start() {
  local msg="${1:-Loading...}"
  (
    local chars=('▓' '░')
    local width=20
    local i=0
    while true; do
      local filled=$((i % (width + 1)))
      local empty=$((width - filled))
      local bar=""
      for ((j=0; j<filled; j++)); do bar+="▓"; done
      for ((j=0; j<empty; j++)); do bar+="░"; done
      printf "\r  ${C_ORANGE}%s${C_RESET} %s" "$bar" "$msg" >&2
      sleep 0.08
      ((i++))
    done
  ) &
  LOADER_PID=$!
  disown
}

loader_stop() {
  if [[ -n "$LOADER_PID" ]]; then
    kill "$LOADER_PID" 2>/dev/null
    wait "$LOADER_PID" 2>/dev/null
    LOADER_PID=""
    printf "\r\033[K" >&2  # Clear line
  fi
}

# Print 3D ASCII logo
print_logo() {
  local use_color=false

  # Check if we should use colors (stderr is a terminal and TERM is not dumb)
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    use_color=true
  fi

  if $use_color; then
    # Orange color for the logo, bold
    echo -e "\033[1;38;5;208m" >&2
  fi

  cat >&2 << 'EOF'
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
EOF

  if $use_color; then
    # Reset color, then dim for subtitle
    echo -e "\033[0m\033[2m  Git Worktree Manager v$VERSION\033[0m" >&2
  else
    msg "  Git Worktree Manager v$VERSION"
  fi
  msg ""
}

# =============================================================================
# GitHub Auth Setup
# =============================================================================

setup_github_auth() {
  if has_gh; then
    return 0  # Déjà authentifié
  fi

  if ! command -v gh &> /dev/null; then
    msg "GitHub CLI (gh) is not installed"
    msg "PR features will be disabled"
    msg "Install with: brew install gh"
    return 1
  fi

  local choice=$(printf "%s\n" \
    "Login via browser (recommended)" \
    "Login with a token" \
    "Continue without GitHub" \
    "Quit" | \
    fzf --height=40% \
        --layout=reverse \
        --border \
        --header="GitHub CLI is not configured")

  case "$choice" in
    *"browser"*)
      gh auth login --web </dev/tty
      ;;
    *"token"*)
      gh auth login </dev/tty
      ;;
    *"Continue"*)
      return 1  # Continue sans auth
      ;;
    *)
      exit 0
      ;;
  esac
}

# =============================================================================
# Worktrees
# =============================================================================

get_worktrees() {
  # Prune stale entries first
  git -C "$MAIN_REPO" worktree prune 2>/dev/null
  git worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-
}

get_secondary_worktrees() {
  get_worktrees | tail -n +2
}

format_worktree_line() {
  local wt_path="$1"
  local branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "detached")
  local short_path="${wt_path/#$HOME/~}"

  # Dirty check
  local dirty=""
  if [[ -n $(git -C "$wt_path" status --porcelain 2>/dev/null) ]]; then
    dirty="*"
  fi

  printf "%-50s %s[%s]\n" "$short_path" "$dirty" "$branch"
}

format_all_worktrees() {
  while IFS= read -r wt; do
    format_worktree_line "$wt"
  done < <(get_worktrees)
}

# =============================================================================
# PRs
# =============================================================================

get_formatted_prs() {
  if ! has_gh; then
    msg "gh not installed or not authenticated"
    return 1
  fi

  gh pr list --json number,title,headRefName,author,reviewDecision,statusCheckRollup,isDraft 2>/dev/null | \
    /usr/bin/jq -r '.[] |
      (if .isDraft then "\u001b[2m[draft]\u001b[0m"
       elif (.statusCheckRollup | length) == 0 then "\u001b[2m[--]\u001b[0m"
       elif ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length) > 0 then "\u001b[31m[fail]\u001b[0m"
       elif ([.statusCheckRollup[] | select(.status == "COMPLETED")] | length) < (.statusCheckRollup | length) then "\u001b[33m[..]\u001b[0m"
       else "\u001b[32m[ok]\u001b[0m" end) as $ci |
      (if .reviewDecision == "APPROVED" then "\u001b[32m✓\u001b[0m"
       elif .reviewDecision == "CHANGES_REQUESTED" then "\u001b[31m✗\u001b[0m"
       else " " end) as $review |
      "#\(.number)\t\($ci) \($review)\t\(.title[0:50])\t\u001b[2m@\(.author.login)\u001b[0m\t\(.headRefName)"'
}

pr_preview() {
  local pr_num="$1"
  if [[ -z "$pr_num" ]]; then
    echo "Select a PR"
    return
  fi

  echo "================================================"
  gh pr view "$pr_num" --json title,body,labels,reviewDecision,additions,deletions,changedFiles 2>/dev/null | \
    /usr/bin/jq -r '"Title: \(.title)\n\nStats: +\(.additions) -\(.deletions) (\(.changedFiles) files)\n\nLabels: \(if (.labels | length) > 0 then (.labels | map(.name) | join(", ")) else "none" end)\n\nReview: \(.reviewDecision // "Pending")\n\n" + (if .body then "Description:\n\(.body[0:500])" else "" end)'
  echo ""
  echo "================================================"
  echo "Changed files:"
  gh pr diff "$pr_num" --stat 2>/dev/null | /usr/bin/head -20
}

# =============================================================================
# Issues
# =============================================================================

get_formatted_issues() {
  if ! has_gh; then
    msg "gh not installed or not authenticated"
    return 1
  fi

  gh issue list --limit 20 --json number,title,author,labels,state 2>/dev/null | \
    /usr/bin/jq -r '.[] |
      (if (.labels | length) > 0 then (.labels | map(.name) | join(","))[0:15] else "-" end) as $labels |
      "#\(.number)\t\(.title[0:50])\t@\(.author.login)\t\($labels)"'
}

issue_preview() {
  local issue_num="$1"
  if [[ -z "$issue_num" ]]; then
    echo "Select an issue"
    return
  fi

  echo "================================================"
  gh issue view "$issue_num" --json title,body,labels,state,comments 2>/dev/null | \
    /usr/bin/jq -r '"Title: \(.title)\n\nState: \(.state)\n\nLabels: \(if (.labels | length) > 0 then (.labels | map(.name) | join(", ")) else "none" end)\n\nComments: \(.comments | length)\n\n" + (if .body then "Description:\n\(.body[0:800])" else "No description" end)'
  echo ""
  echo "================================================"
}

# =============================================================================
# Claude Code Integration
# =============================================================================

# Sélecteur de mode Claude avec fzf
# Retourne le mode sélectionné ou vide si annulé
select_claude_mode() {
  local context_type="$1"  # pr-review, pr-work, issue-work
  local context_num="$2"

  local header
  case "$context_type" in
    "pr-review") header="Claude mode for PR #$context_num review" ;;
    "pr-work")   header="Claude mode for PR #$context_num" ;;
    "issue-work") header="Claude mode for Issue #$context_num" ;;
    *) header="Select Claude mode" ;;
  esac

  local options=">> Forced (full auto)
?> Ask (confirm actions)
## Plan (plan first)"

  local mode
  mode=$(fzf --height=25% \
        --layout=reverse \
        --border \
        --header="$header" \
        --preview="
          case {} in
            *Forced*)
              echo 'Mode: --dangerously-skip-permissions'
              echo ''
              echo 'Claude executes all actions automatically'
              echo 'without asking for confirmation.'
              echo ''
              echo '!! Full autonomy - use with caution'
              ;;
            *Ask*)
              echo 'Mode: default (interactive)'
              echo ''
              echo 'Claude asks for confirmation before'
              echo 'executing impactful actions.'
              echo ''
              echo '* Recommended for most cases'
              ;;
            *Plan*)
              echo 'Mode: --plan'
              echo ''
              echo 'Claude analyzes and creates a plan'
              echo 'before any execution.'
              echo ''
              echo '* Best for complex tasks'
              ;;
          esac
        " \
        --preview-window=right:50% <<< "$options")

  case "$mode" in
    *"Forced"*)
      echo "forced"
      ;;
    *"Ask"*)
      echo "ask"
      ;;
    *"Plan"*)
      echo "plan"
      ;;
    *)
      echo ""
      ;;
  esac
}

# =============================================================================
# Actions de création - retournent le path sur stdout
# =============================================================================

# Créer un worktree à partir de la branche actuelle (duplicate)
create_from_current() {
  local current_branch=$(git branch --show-current 2>/dev/null || echo "HEAD")
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local sanitized=$(echo "$current_branch" | sed 's|/|-|g')
  local worktree_name="${REPO_NAME}-${sanitized}-copy-${timestamp}"
  # Toujours créer à côté du repo PRINCIPAL
  local worktree_path="$(dirname "$MAIN_REPO")/${worktree_name}"
  local new_branch="temp/${sanitized}-${timestamp}"

  msg "Creating worktree..."

  if git worktree add -b "$new_branch" "$worktree_path" HEAD >/dev/null 2>&1; then
    msg "Worktree created: $worktree_path"
    msg "Branch: $new_branch"
    echo "$worktree_path"  # SEUL output sur stdout
  else
    msg "Error creating worktree"
    return 1
  fi
}

# Créer un worktree à partir d'une branche
create_from_branch() {
  msg "Fetching branches..."
  git fetch --all --prune >/dev/null 2>&1

  local branch_name
  branch_name=$(git branch -a --format='%(refname:short)' | \
    grep -v '^HEAD' | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --header="Select a branch (ESC to cancel)" \
        --preview="git log --oneline --graph --color=always -10 {}" \
        --preview-window=right:50%)

  if [[ -z "$branch_name" ]]; then
    msg "No branch selected"
    return 1
  fi

  local sanitized=$(echo "$branch_name" | sed 's|^origin/||' | sed 's|/|-|g')
  # Toujours créer à côté du repo PRINCIPAL
  local worktree_path="$(dirname "$MAIN_REPO")/${REPO_NAME}-${sanitized}"

  msg "Creating worktree..."

  if git worktree add "$worktree_path" "$branch_name" >/dev/null 2>&1; then
    msg "Worktree created: $worktree_path"
    echo "$worktree_path"  # SEUL output sur stdout
  else
    msg "Error creating worktree"
    return 1
  fi
}

# Créer un worktree avec une nouvelle branche
create_new_branch() {
  # 1. Input nom de branche
  msg "Enter new branch name:"
  local input_branch_name
  read -r input_branch_name </dev/tty

  if [[ -z "$input_branch_name" ]]; then
    msg "No branch name provided"
    return 1
  fi

  # 2. Sélectionner branche de base
  msg "Fetching branches..."
  git fetch --all --prune >/dev/null 2>&1

  local current_branch=$(git branch --show-current 2>/dev/null || echo "HEAD")
  local base_branch
  base_branch=$(printf "%s\n" "$current_branch (current)" $(git branch -a --format='%(refname:short)' | grep -v '^HEAD') | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --header="Select base branch (ESC to use current: $current_branch)" \
        --preview="
          branch=\$(echo {} | sed 's/ (current)\$//')
          git log --oneline --graph --color=always -10 \"\$branch\" 2>/dev/null
        " \
        --preview-window=right:50%)

  # Si rien sélectionné ou "(current)", utiliser la branche actuelle
  if [[ -z "$base_branch" || "$base_branch" == *"(current)" ]]; then
    base_branch="$current_branch"
  fi

  # 3. Incrémenter si la branche existe déjà
  local branch_name="$input_branch_name"
  local counter=2
  while git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null || \
        git show-ref --verify --quiet "refs/remotes/origin/$branch_name" 2>/dev/null; do
    branch_name="${input_branch_name}-${counter}"
    ((counter++))
  done

  # 4. Créer le worktree
  local sanitized=$(echo "$branch_name" | sed 's|/|-|g')
  local worktree_path="$(dirname "$MAIN_REPO")/${REPO_NAME}-${sanitized}"

  msg "Creating worktree with new branch '$branch_name' from '$base_branch'..."

  if git worktree add -b "$branch_name" "$worktree_path" "$base_branch" >/dev/null 2>&1; then
    msg "Worktree created: $worktree_path"
    msg "New branch: $branch_name (based on $base_branch)"
    echo "$worktree_path"  # SEUL output sur stdout
  else
    msg "Error creating worktree"
    return 1
  fi
}

# Créer un worktree depuis une PR
create_from_pr() {
  local pr_branch="$1"
  local sanitized=$(echo "$pr_branch" | sed 's|^origin/||' | sed 's|/|-|g')
  # Toujours créer à côté du repo PRINCIPAL, avec préfixe "reviewing"
  local worktree_path="$(dirname "$MAIN_REPO")/${REPO_NAME}-reviewing-${sanitized}"

  # Check if worktree already exists at this path
  if [[ -d "$worktree_path" ]]; then
    msg "Using existing worktree: $worktree_path"
    echo "$worktree_path"
    return 0
  fi

  # Check if branch is already checked out in another worktree
  local existing_wt
  existing_wt=$(git -C "$MAIN_REPO" worktree list | grep "\[$pr_branch\]" | awk '{print $1}')
  if [[ -n "$existing_wt" ]]; then
    msg "Branch already checked out at: $existing_wt"
    echo "$existing_wt"
    return 0
  fi

  msg "Fetching branch..."
  git -C "$MAIN_REPO" fetch origin "$pr_branch" >/dev/null 2>&1

  msg "Creating worktree..."
  local git_output
  git_output=$(git -C "$MAIN_REPO" worktree add "$worktree_path" "$pr_branch" 2>&1)
  local ret=$?

  if [[ $ret -eq 0 ]]; then
    msg "Worktree created: $worktree_path"
    echo "$worktree_path"
  else
    # If failed because branch is already checked out, find and use that worktree
    if echo "$git_output" | grep -q "already used by worktree"; then
      existing_wt=$(echo "$git_output" | grep -o "at '.*'" | sed "s/at '//;s/'//")
      if [[ -n "$existing_wt" && -d "$existing_wt" ]]; then
        msg "Using existing worktree: $existing_wt"
        echo "$existing_wt"
        return 0
      fi
    fi
    msg "Error creating worktree:"
    msg "$git_output"
    return 1
  fi
}

# Créer un worktree depuis une issue GitHub
create_from_issue() {
  local issue_num="$1"
  local issue_title="$2"

  # Créer un slug à partir du titre
  local slug=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-30)
  local base_branch_name="feature/${issue_num}-${slug}"
  local branch_name="$base_branch_name"

  # Incrémenter si la branche existe déjà
  local counter=2
  while git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null || \
        git show-ref --verify --quiet "refs/remotes/origin/$branch_name" 2>/dev/null; do
    branch_name="${base_branch_name}-${counter}"
    ((counter++))
  done

  local sanitized=$(echo "$branch_name" | sed 's|/|-|g')
  local worktree_path="$(dirname "$MAIN_REPO")/${REPO_NAME}-${sanitized}"

  # Récupérer la branche par défaut du repo
  local default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  msg "Creating worktree with new branch '$branch_name' from '$default_branch'..."

  if git worktree add -b "$branch_name" "$worktree_path" "origin/$default_branch" >/dev/null 2>&1; then
    msg "Worktree created: $worktree_path"
    msg "Branch: $branch_name"
    echo "$worktree_path"  # SEUL output sur stdout
  else
    msg "Error creating worktree"
    return 1
  fi
}

# =============================================================================
# Menu Review PR
# =============================================================================

select_pr_action() {
  local pr_num="$1"
  local ci_failed="$2"

  local options="Review this PR
Launch Claude
Just create worktree"

  # Add "Fix CI issues" option if CI has failed
  if [[ "$ci_failed" == "true" ]]; then
    options="Fix CI issues (auto)
$options"
  fi

  local action
  action=$(fzf --height=30% \
        --layout=reverse \
        --border \
        --header="PR #$pr_num - What do you want to do?" \
        --preview="
          case {} in
            *Fix\ CI*)
              echo 'AUTO-FIX CI FAILURES'
              echo ''
              echo 'Claude will automatically:'
              echo '  1. Fetch failed CI logs from GitHub'
              echo '  2. Analyze the errors'
              echo '  3. Fix the code'
              echo '  4. Push the fix'
              echo ''
              echo '!! Runs in FORCED mode (full auto)'
              ;;
            *Review*)
              echo 'Code review mode'
              echo ''
              echo 'Claude will analyze the PR for:'
              echo '  - Bugs and logic errors'
              echo '  - Security issues'
              echo '  - Performance problems'
              echo '  - Code quality'
              ;;
            *Launch*)
              echo 'Work on this PR'
              echo ''
              echo 'Claude will help you:'
              echo '  - Understand the changes'
              echo '  - Make modifications'
              echo '  - Fix issues'
              ;;
            *Just*)
              echo 'Create worktree only'
              echo ''
              echo 'No Claude integration.'
              echo 'Just checkout the PR branch.'
              ;;
          esac
        " \
        --preview-window=right:50% <<< "$options")

  echo "$action"
}

menu_review_pr() {
  if ! has_gh; then
    setup_github_auth
    if ! has_gh; then
      return 1
    fi
  fi

  loader_start "Fetching PRs..."
  local prs=$(get_formatted_prs)
  loader_stop
  if [[ -z "$prs" ]]; then
    msg ""
    msg "No open PRs found."
    msg "Press Enter to continue..."
    read -r </dev/tty
    return 1
  fi

  # Boucle pour permettre Ctrl+O sans quitter
  while true; do
    local result=$(echo -e "$prs" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --ansi \
          --header="Open PRs | Enter: select | Ctrl+O: open in browser" \
          --delimiter='\t' \
          --with-nth=1,2,3,4 \
          --preview="bash \"$SCRIPT_PATH\" --pr-preview {1}" \
          --preview-window=right:50% \
          --expect=ctrl-o)

    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    if [[ -z "$selected" ]]; then
      return 1
    fi

    local pr_num=$(echo "$selected" | cut -f1 | tr -d '#')
    local pr_branch=$(echo "$selected" | cut -f5)
    # Check if CI has failed (look for [fail] in the line)
    local ci_failed="false"
    if echo "$selected" | grep -q '\[fail\]'; then
      ci_failed="true"
    fi

    if [[ "$key" == "ctrl-o" ]]; then
      gh pr view "$pr_num" --web >/dev/null 2>&1
    else
      # Select action (pass CI status)
      local action=$(select_pr_action "$pr_num" "$ci_failed")

      if [[ -z "$action" ]]; then
        continue  # Back to PR list
      fi

      # Create worktree
      local wt_path
      wt_path=$(create_from_pr "$pr_branch")
      local ret=$?

      if [[ $ret -eq 0 && -n "$wt_path" ]]; then
        case "$action" in
          *"Fix CI"*)
            if has_claude; then
              echo "CLAUDE:ci-fix:$pr_num"
            else
              msg_warn "Claude not installed - skipping auto-fix"
            fi
            ;;
          *"Review"*)
            if has_claude; then
              local mode=$(select_claude_mode "pr-review" "$pr_num")
              [[ -n "$mode" ]] && echo "CLAUDE:pr-review:$pr_num:$mode"
            else
              msg_warn "Claude not installed - skipping review"
            fi
            ;;
          *"Launch"*)
            if has_claude; then
              local mode=$(select_claude_mode "pr-work" "$pr_num")
              [[ -n "$mode" ]] && echo "CLAUDE:pr-work:$pr_num:$mode"
            else
              msg_warn "Claude not installed"
            fi
            ;;
        esac
        echo "$wt_path"
      fi
      return $ret
    fi
  done
}

# =============================================================================
# Menu From Issue
# =============================================================================

select_issue_action() {
  local issue_num="$1"

  local options="Auto-resolve (full auto)
Launch Claude
Just create worktree"

  local action
  action=$(fzf --height=25% \
        --layout=reverse \
        --border \
        --header="Issue #$issue_num - What do you want to do?" \
        --preview="
          case {} in
            *Auto-resolve*)
              echo 'Full autonomous mode'
              echo ''
              echo 'Claude will automatically:'
              echo '  1. Read and analyze the issue'
              echo '  2. Explore the codebase'
              echo '  3. Plan the implementation'
              echo '  4. Write the code'
              echo '  5. Create a PR'
              echo ''
              echo '!! No human intervention required'
              ;;
            *Launch*)
              echo 'Interactive mode'
              echo ''
              echo 'Claude will help you:'
              echo '  - Understand the issue'
              echo '  - Plan implementation'
              echo '  - Write code with guidance'
              echo ''
              echo 'You choose the level of autonomy.'
              ;;
            *Just*)
              echo 'Create worktree only'
              echo ''
              echo 'No Claude integration.'
              echo 'Branch: feature/{issue}-{title}'
              ;;
          esac
        " \
        --preview-window=right:50% <<< "$options")

  echo "$action"
}

menu_from_issue() {
  if ! has_gh; then
    setup_github_auth
    if ! has_gh; then
      return 1
    fi
  fi

  loader_start "Fetching issues..."
  local issues=$(get_formatted_issues)
  loader_stop
  if [[ -z "$issues" ]]; then
    msg ""
    msg "No open issues found."
    msg "Press Enter to continue..."
    read -r </dev/tty
    return 1
  fi

  # Boucle pour permettre Ctrl+O sans quitter
  while true; do
    local result=$(echo "$issues" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --header="Open Issues | Enter: select | Ctrl+O: open in browser" \
          --delimiter='\t' \
          --with-nth=1,2,3,4 \
          --preview="bash \"$SCRIPT_PATH\" --issue-preview {1}" \
          --preview-window=right:50% \
          --expect=ctrl-o)

    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    if [[ -z "$selected" ]]; then
      return 1
    fi

    local issue_num=$(echo "$selected" | cut -f1 | tr -d '#')
    local issue_title=$(echo "$selected" | cut -f2)

    if [[ "$key" == "ctrl-o" ]]; then
      gh issue view "$issue_num" --web >/dev/null 2>&1
    else
      # Select action
      local action=$(select_issue_action "$issue_num")

      if [[ -z "$action" ]]; then
        continue  # Back to issue list
      fi

      # Create worktree
      local wt_path
      wt_path=$(create_from_issue "$issue_num" "$issue_title")
      local ret=$?

      if [[ $ret -eq 0 && -n "$wt_path" ]]; then
        case "$action" in
          *"Auto-resolve"*)
            if has_claude; then
              echo "CLAUDE:issue-auto:$issue_num"
            else
              msg_warn "Claude not installed - skipping auto-resolve"
            fi
            ;;
          *"Launch"*)
            if has_claude; then
              local mode=$(select_claude_mode "issue-work" "$issue_num")
              [[ -n "$mode" ]] && echo "CLAUDE:issue-work:$issue_num:$mode"
            else
              msg_warn "Claude not installed"
            fi
            ;;
        esac
        echo "$wt_path"
      fi
      return $ret
    fi
  done
}

# =============================================================================
# Menu Créer un worktree
# =============================================================================

menu_create_worktree() {
  while true; do
    local choice=$(printf "%s\n" \
      "New branch" \
      "From existing branch" \
      "From current (quick copy)" \
      "From an issue" \
      "Review a PR" \
      "Back" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --header="Create a worktree")

    case "$choice" in
      "New branch"*)
        local wt_path
        wt_path=$(create_new_branch)
        local ret=$?
        if [[ $ret -eq 0 && -n "$wt_path" ]]; then
          echo "$wt_path"
          return 0
        fi
        return $ret
        ;;
      "From existing"*)
        local wt_path
        wt_path=$(create_from_branch)
        local ret=$?
        if [[ $ret -eq 0 && -n "$wt_path" ]]; then
          echo "$wt_path"
          return 0
        fi
        return $ret
        ;;
      *"current"*|*"quick copy"*)
        local wt_path
        wt_path=$(create_from_current)
        local ret=$?
        if [[ $ret -eq 0 && -n "$wt_path" ]]; then
          echo "$wt_path"
          return 0
        fi
        return $ret
        ;;
      "From an issue"*)
        local output
        output=$(menu_from_issue)
        local ret=$?
        if [[ $ret -eq 0 && -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        return $ret
        ;;
      *"PR"*)
        local output
        output=$(menu_review_pr)
        local ret=$?
        if [[ $ret -eq 0 && -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        return $ret
        ;;
      *"Back"*|"")
        return 1
        ;;
    esac
  done
}

# =============================================================================
# Stash Management - Helper functions
# =============================================================================

# Formatte l'âge d'un stash de manière lisible
_stash_age() {
  local stash_ref="$1"
  local stash_date=$(git log -1 --format="%ci" "$stash_ref" 2>/dev/null)
  if [[ -z "$stash_date" ]]; then
    echo "?"
    return
  fi

  local stash_ts=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$stash_date" "+%s" 2>/dev/null || date -d "$stash_date" "+%s" 2>/dev/null)
  local now_ts=$(date "+%s")
  local diff=$((now_ts - stash_ts))

  if [[ $diff -lt 3600 ]]; then
    echo "$((diff / 60))m"
  elif [[ $diff -lt 86400 ]]; then
    echo "$((diff / 3600))h"
  elif [[ $diff -lt 604800 ]]; then
    echo "$((diff / 86400))d"
  elif [[ $diff -lt 2592000 ]]; then
    echo "$((diff / 604800))w"
  else
    echo "$((diff / 2592000))mo"
  fi
}

# Compte les fichiers dans un stash
_stash_file_count() {
  local stash_ref="$1"
  git stash show --name-only "$stash_ref" 2>/dev/null | wc -l | tr -d ' '
}

# Extrait la branche d'origine du stash
_stash_branch() {
  local stash_line="$1"
  echo "$stash_line" | sed -n 's/.*on \([^:]*\):.*/\1/p'
}

# Extrait le message du stash
_stash_message() {
  local stash_line="$1"
  local msg=$(echo "$stash_line" | sed 's/.*: //')
  # Tronquer si trop long
  if [[ ${#msg} -gt 40 ]]; then
    echo "${msg:0:37}..."
  else
    echo "$msg"
  fi
}

# Génère la liste formatée des stashes
_format_stash_list() {
  local stashes="$1"
  while IFS= read -r line; do
    local ref=$(echo "$line" | cut -d: -f1)
    local age=$(_stash_age "$ref")
    local files=$(_stash_file_count "$ref")
    local branch=$(_stash_branch "$line")
    local message=$(_stash_message "$line")

    # Tronquer la branche si trop longue
    if [[ ${#branch} -gt 12 ]]; then
      branch="${branch:0:9}..."
    fi

    # Format: stash@{0} │ 3d │ 5f │ main │ message
    printf "%-11s │ %4s │ %3sf │ %-12s │ %s\n" "$ref" "$age" "$files" "$branch" "$message"
  done <<< "$stashes"
}

# Créer un stash partiel (sélection de fichiers)
_stash_partial() {
  local modified=$(git diff --name-only 2>/dev/null)
  local staged=$(git diff --cached --name-only 2>/dev/null)
  local untracked=$(git ls-files --others --exclude-standard 2>/dev/null)

  local all_files=$(printf "%s\n%s\n%s" "$modified" "$staged" "$untracked" | sort -u | grep -v '^$')

  if [[ -z "$all_files" ]]; then
    msg "No changes to stash"
    return 1
  fi

  msg "Select files to stash (Space to select, Enter to confirm):"

  local selected=$(echo "$all_files" | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --multi \
        --marker='+ ' \
        --bind 'space:toggle+down' \
        --header="Space: select | Enter: stash selected | Esc: cancel" \
        --preview="git diff --color=always -- {} 2>/dev/null || git diff --cached --color=always -- {} 2>/dev/null || cat {}" \
        --preview-window=right:50%)

  if [[ -z "$selected" ]]; then
    return 1
  fi

  msg "Enter stash message (or leave empty):"
  local stash_msg
  read -r stash_msg </dev/tty

  # Identifier les fichiers non trackés parmi la sélection
  local untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null)
  local files_to_add=""

  while IFS= read -r file; do
    if echo "$untracked_files" | grep -qx "$file" 2>/dev/null; then
      files_to_add="${files_to_add}${file}"$'\n'
    fi
  done <<< "$selected"

  # Ajouter les fichiers non trackés à l'index temporairement
  if [[ -n "$files_to_add" ]]; then
    echo "$files_to_add" | xargs git add 2>/dev/null
  fi

  # Stash uniquement les fichiers sélectionnés
  local stash_result
  if [[ -n "$stash_msg" ]]; then
    stash_result=$(echo "$selected" | xargs git stash push -m "$stash_msg" -- 2>&1)
  else
    stash_result=$(echo "$selected" | xargs git stash push -- 2>&1)
  fi

  if [[ $? -eq 0 ]]; then
    msg "Partial stash created"
  else
    msg "Error creating stash: $stash_result"
    # Rollback: unstage les fichiers qu'on avait ajoutés
    if [[ -n "$files_to_add" ]]; then
      echo "$files_to_add" | xargs git reset HEAD -- 2>/dev/null
    fi
  fi
}

# =============================================================================
# Stash Management - Main menu
# =============================================================================

menu_stash() {
  while true; do
    local stashes=$(git stash list 2>/dev/null)

    if [[ -z "$stashes" ]]; then
      # Proposer de créer un stash
      local choice=$(printf "%s\n" \
        "Create stash (all changes)" \
        "Create partial stash (select files)" \
        "Back" | \
        fzf --height=30% \
            --layout=reverse \
            --border \
            --header="No stashes found")

      case "$choice" in
        "Create stash (all"*)
          msg "Enter stash message (or leave empty):"
          local stash_msg
          read -r stash_msg </dev/tty
          if [[ -n "$stash_msg" ]]; then
            git stash push -u -m "$stash_msg" >/dev/null 2>&1
          else
            git stash push -u >/dev/null 2>&1
          fi
          msg "Stash created"
          ;;
        "Create partial"*)
          _stash_partial
          ;;
        *)
          return 1
          ;;
      esac
      continue
    fi

    # Générer la liste formatée
    local formatted_list=$(_format_stash_list "$stashes")

    # Header simplifié
    local header="ref         │ age  │ files │ branch       │ message
────────────┴──────┴───────┴──────────────┴─────────────────────────────
Enter: actions menu │ Space: multi-select │ ?: show all shortcuts"

    # Aide complète pour le raccourci ?
    local help_text='
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  KEYBOARD SHORTCUTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ACTIONS
  ───────
  Enter     Open actions menu
  Ctrl+A    Apply stash (keep it)
  Ctrl+P    Pop stash (apply + remove)
  Ctrl+D    Drop stash(es) (delete)

  CREATE
  ──────
  Ctrl+N    New stash (all changes)
  Ctrl+E    Partial stash (select files)

  ADVANCED
  ────────
  Ctrl+W    Create worktree from stash
  Ctrl+B    Create branch from stash
  Ctrl+R    Apply + resolve conflicts (Claude)

  VIEW / EXPORT
  ─────────────
  Ctrl+S    Show full diff
  Ctrl+X    Export as .patch file

  SELECTION
  ─────────
  Space     Toggle selection
  Esc       Back / Cancel

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Press any key to return to stash info
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
'

    # Afficher les stashes avec actions
    local result=$(echo "$formatted_list" | \
      fzf --height=80% \
          --layout=reverse \
          --border \
          --ansi \
          --multi \
          --marker='> ' \
          --bind 'space:toggle+down' \
          --bind "?:preview(echo '$help_text')" \
          --header="$header" \
          --preview='
            stash_ref=$(echo {} | cut -d" " -f1)

            # Date de création
            stash_date=$(git log -1 --format="%ci" "$stash_ref" 2>/dev/null | cut -d" " -f1,2)

            # Branche d origine
            stash_info=$(git stash list 2>/dev/null | grep "^$stash_ref")
            branch=$(echo "$stash_info" | sed -n "s/.*on \([^:]*\):.*/\1/p")

            # Stats
            stats=$(git stash show --stat "$stash_ref" 2>/dev/null | tail -1)
            files=$(echo "$stats" | grep -oE "[0-9]+ file" | grep -oE "[0-9]+")
            insertions=$(echo "$stats" | grep -oE "[0-9]+ insertion" | grep -oE "[0-9]+")
            deletions=$(echo "$stats" | grep -oE "[0-9]+ deletion" | grep -oE "[0-9]+")

            [ -z "$files" ] && files="0"
            [ -z "$insertions" ] && insertions="0"
            [ -z "$deletions" ] && deletions="0"

            # Vérifier les conflits potentiels
            stash_files=$(git stash show --name-only "$stash_ref" 2>/dev/null)
            modified_files=$(git diff --name-only HEAD 2>/dev/null)
            staged_files=$(git diff --cached --name-only 2>/dev/null)

            conflict_files=""
            while IFS= read -r sf; do
              if echo "$modified_files" | grep -qx "$sf" 2>/dev/null || echo "$staged_files" | grep -qx "$sf" 2>/dev/null; then
                conflict_files="${conflict_files}  ! ${sf}\n"
              fi
            done <<< "$stash_files"

            # Affichage
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  STASH INFO"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "  Date    : $stash_date"
            echo "  Branch  : $branch"
            echo "  Stats   : $files files | +$insertions -$deletions lines"
            echo ""

            # Warning conflits
            if [ -n "$conflict_files" ]; then
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  ⚠ POTENTIAL CONFLICTS"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              printf "$conflict_files"
              echo ""
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  FILES CHANGED"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            # Liste des fichiers avec stats
            git stash show --numstat "$stash_ref" 2>/dev/null | while IFS=$(printf "\t") read -r added removed file; do
              if [ "$added" = "-" ]; then
                added="bin"
                removed="bin"
              fi
              printf "  %4s %4s  %s\n" "+$added" "-$removed" "$file"
            done
          ' \
          --preview-window=right:50% \
          --expect=ctrl-n,ctrl-a,ctrl-p,ctrl-d,ctrl-b,ctrl-s,ctrl-e,ctrl-x)

    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    # Actions avec raccourcis directs
    case "$key" in
      "ctrl-n")
        # Nouveau stash (tous les changements)
        msg "Enter stash message (or leave empty):"
        local stash_msg
        read -r stash_msg </dev/tty
        if [[ -n "$stash_msg" ]]; then
          git stash push -u -m "$stash_msg" >/dev/null 2>&1
        else
          git stash push -u >/dev/null 2>&1
        fi
        msg "Stash created"
        continue
        ;;
      "ctrl-e")
        # Stash partiel
        _stash_partial
        continue
        ;;
      "ctrl-a")
        # Apply direct
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          if git stash apply "$stash_ref" 2>&1; then
            msg "Stash $stash_ref applied"
          else
            msg "Error applying stash (conflicts?)"
          fi
        fi
        continue
        ;;
      "ctrl-p")
        # Pop direct
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          if git stash pop "$stash_ref" 2>&1; then
            msg "Stash $stash_ref popped"
          else
            msg "Error popping stash (conflicts?)"
          fi
        fi
        continue
        ;;
      "ctrl-d")
        # Drop (multi-select supporté)
        if [[ -n "$selected" ]]; then
          local count=$(echo "$selected" | wc -l | tr -d ' ')
          local confirm=$(printf "%s\n" "Yes, delete $count stash(es)" "No, cancel" | \
            fzf --height=20% --layout=reverse --border --header="Delete selected stash(es)?")
          if [[ "$confirm" == "Yes"* ]]; then
            # Drop en ordre inverse pour éviter les problèmes d'index
            echo "$selected" | tac | while IFS= read -r line; do
              local ref=$(echo "$line" | cut -d' ' -f1)
              git stash drop "$ref" >/dev/null 2>&1
            done
            msg "$count stash(es) dropped"
          fi
        fi
        continue
        ;;
      "ctrl-b")
        # Créer une branche depuis le stash
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          msg "Enter branch name:"
          local branch_name
          read -r branch_name </dev/tty
          if [[ -n "$branch_name" ]]; then
            if git stash branch "$branch_name" "$stash_ref" 2>&1; then
              msg "Branch '$branch_name' created from $stash_ref"
              return 0
            else
              msg "Error creating branch"
            fi
          fi
        fi
        continue
        ;;
      "ctrl-x")
        # Export en patch
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          local stash_num=$(echo "$stash_ref" | grep -oE '[0-9]+')
          local patch_file="stash-${stash_num}-$(date +%Y%m%d-%H%M%S).patch"
          git stash show -p "$stash_ref" > "$patch_file"
          msg "Exported to $patch_file"
        fi
        continue
        ;;
      "ctrl-s")
        # Show diff complet
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          git stash show -p "$stash_ref" | less </dev/tty
        fi
        continue
        ;;
      "ctrl-w")
        # Créer un worktree depuis le stash
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)
          msg "Enter worktree/branch name:"
          local wt_name
          read -r wt_name </dev/tty
          if [[ -n "$wt_name" ]]; then
            local main_repo=$(git rev-parse --show-toplevel 2>/dev/null)
            local parent_dir=$(dirname "$main_repo")
            local repo_name=$(basename "$main_repo")
            local wt_path="$parent_dir/${repo_name}-${wt_name}"

            # Créer le worktree avec une nouvelle branche
            if git worktree add -b "$wt_name" "$wt_path" 2>&1; then
              # Appliquer le stash dans le nouveau worktree
              if (cd "$wt_path" && git stash apply "$stash_ref" 2>&1); then
                msg "Worktree created at $wt_path with stash applied"
                # Proposer de drop le stash
                local drop_confirm=$(printf "%s\n" "Yes, drop the stash" "No, keep it" | \
                  fzf --height=20% --layout=reverse --border --header="Drop $stash_ref?")
                if [[ "$drop_confirm" == "Yes"* ]]; then
                  git stash drop "$stash_ref" >/dev/null 2>&1
                  msg "Stash dropped"
                fi
                # Retourner le path pour navigation
                echo "$wt_path"
                return 0
              else
                msg "Worktree created but stash apply failed (conflicts?)"
                echo "$wt_path"
                return 0
              fi
            else
              msg "Error creating worktree"
            fi
          fi
        fi
        continue
        ;;
      "ctrl-r")
        # Apply + résoudre conflits avec Claude
        if [[ -n "$selected" ]]; then
          local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)

          # Appliquer le stash (même si conflits)
          local apply_output=$(git stash apply "$stash_ref" 2>&1)
          local apply_status=$?

          # Vérifier s'il y a des conflits
          local conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

          if [[ -n "$conflict_files" ]]; then
            msg "Conflicts detected, launching Claude to resolve..."
            local files_list=$(echo "$conflict_files" | tr '\n' ' ')
            # Lancer Claude pour résoudre les conflits
            if command -v claude &>/dev/null; then
              claude "Resolve the merge conflicts in these files: $files_list. The conflicts come from applying stash $stash_ref. Please fix all conflict markers (<<<<<<, ======, >>>>>>) and keep the best version of the code."
            else
              msg "Claude not found. Conflict files: $files_list"
            fi
          elif [[ $apply_status -eq 0 ]]; then
            msg "Stash $stash_ref applied (no conflicts)"
          else
            msg "Error applying stash: $apply_output"
          fi
        fi
        continue
        ;;
    esac

    # Si Esc ou aucune sélection
    if [[ -z "$selected" ]]; then
      return 1
    fi

    # Si Enter: menu d'actions classique
    local stash_ref=$(echo "$selected" | head -1 | cut -d' ' -f1)

    # Détecter les conflits potentiels
    local stash_files=$(git stash show --name-only "$stash_ref" 2>/dev/null)
    local modified_files=$(git diff --name-only HEAD 2>/dev/null)
    local staged_files=$(git diff --cached --name-only 2>/dev/null)
    local has_conflicts=""

    while IFS= read -r sf; do
      if echo "$modified_files" | grep -qx "$sf" 2>/dev/null || echo "$staged_files" | grep -qx "$sf" 2>/dev/null; then
        has_conflicts="yes"
        break
      fi
    done <<< "$stash_files"

    # Construire le menu dynamiquement
    local menu_options="Apply (keep stash)
Pop (apply and remove)"

    # Ajouter l'option Claude seulement si conflits potentiels
    if [[ -n "$has_conflicts" ]]; then
      menu_options="$menu_options
Apply + resolve conflicts (Claude)"
    fi

    menu_options="$menu_options
Create worktree from stash
Drop (delete)
Create branch from stash
Export as patch
Show full diff
Rename stash
Back"

    # Menu d'actions pour le stash sélectionné
    local action=$(echo "$menu_options" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --header="Action for $stash_ref" \
          --preview='
            action=$(echo {} | cut -d" " -f1)
            case "$action" in
              "Apply")
                if [[ "{}" == *"resolve"* ]] || [[ "{}" == *"Claude"* ]]; then
                  echo "Apply the stash and resolve conflicts with Claude."
                  echo ""
                  echo "If conflicts occur, Claude will automatically"
                  echo "analyze and fix the conflict markers."
                  echo ""
                  echo "Requires: claude CLI installed"
                else
                  echo "Apply the stash changes to your working directory."
                  echo "The stash will remain in the stash list."
                  echo ""
                  echo "Equivalent to: git stash apply"
                fi
                ;;
              "Pop")
                echo "Apply the stash changes and remove it from the list."
                echo "Use this when you are done with the stash."
                echo ""
                echo "Equivalent to: git stash pop"
                ;;
              "Drop")
                echo "Permanently delete this stash."
                echo "This action cannot be undone!"
                echo ""
                echo "Equivalent to: git stash drop"
                ;;
              "Create")
                if [[ "{}" == *"worktree"* ]]; then
                  echo "Create a new worktree with this stash applied."
                  echo ""
                  echo "- Creates a new branch"
                  echo "- Creates a worktree in parent directory"
                  echo "- Applies the stash in the new worktree"
                  echo "- Optionally drops the stash after"
                  echo ""
                  echo "Perfect for isolating WIP work!"
                else
                  echo "Create a new branch from this stash."
                  echo "The stash will be applied and removed."
                  echo ""
                  echo "Equivalent to: git stash branch <name>"
                fi
                ;;
              "Export")
                echo "Export the stash as a .patch file."
                echo "Useful for sharing or backup."
                echo ""
                echo "Equivalent to: git stash show -p > file.patch"
                ;;
              "Show")
                echo "View the complete diff of this stash."
                echo "Opens in less for easy navigation."
                echo ""
                echo "Equivalent to: git stash show -p | less"
                ;;
              "Rename")
                echo "Rename this stash with a new message."
                echo "(Drops and recreates the stash)"
                ;;
              *)
                echo "Return to stash list"
                ;;
            esac
          ' \
          --preview-window=right:50%)

    case "$action" in
      "Apply (keep"*)
        if git stash apply "$stash_ref" 2>&1; then
          msg "Stash applied"
        else
          msg "Error applying stash (conflicts?)"
        fi
        ;;
      "Apply + resolve"*)
        # Apply + résoudre conflits avec Claude
        local apply_output=$(git stash apply "$stash_ref" 2>&1)
        local apply_status=$?
        local conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)
        if [[ -n "$conflict_files" ]]; then
          msg "Conflicts detected, launching Claude to resolve..."
          local files_list=$(echo "$conflict_files" | tr '\n' ' ')
          if command -v claude &>/dev/null; then
            claude "Resolve the merge conflicts in these files: $files_list. The conflicts come from applying stash $stash_ref. Please fix all conflict markers (<<<<<<, ======, >>>>>>) and keep the best version of the code."
          else
            msg "Claude not found. Conflict files: $files_list"
          fi
        elif [[ $apply_status -eq 0 ]]; then
          msg "Stash $stash_ref applied (no conflicts)"
        else
          msg "Error applying stash: $apply_output"
        fi
        ;;
      "Pop"*)
        if git stash pop "$stash_ref" 2>&1; then
          msg "Stash popped"
        else
          msg "Error popping stash (conflicts?)"
        fi
        ;;
      "Create worktree"*)
        msg "Enter worktree/branch name:"
        local wt_name
        read -r wt_name </dev/tty
        if [[ -n "$wt_name" ]]; then
          local main_repo=$(git rev-parse --show-toplevel 2>/dev/null)
          local parent_dir=$(dirname "$main_repo")
          local repo_name=$(basename "$main_repo")
          local wt_path="$parent_dir/${repo_name}-${wt_name}"
          if git worktree add -b "$wt_name" "$wt_path" 2>&1; then
            if (cd "$wt_path" && git stash apply "$stash_ref" 2>&1); then
              msg "Worktree created at $wt_path with stash applied"
              local drop_confirm=$(printf "%s\n" "Yes, drop the stash" "No, keep it" | \
                fzf --height=20% --layout=reverse --border --header="Drop $stash_ref?")
              if [[ "$drop_confirm" == "Yes"* ]]; then
                git stash drop "$stash_ref" >/dev/null 2>&1
                msg "Stash dropped"
              fi
              echo "$wt_path"
              return 0
            else
              msg "Worktree created but stash apply failed (conflicts?)"
              echo "$wt_path"
              return 0
            fi
          else
            msg "Error creating worktree"
          fi
        fi
        ;;
      "Drop"*)
        local confirm=$(printf "%s\n" "Yes, delete" "No, cancel" | \
          fzf --height=20% --layout=reverse --border --header="Delete $stash_ref?")
        if [[ "$confirm" == "Yes"* ]]; then
          git stash drop "$stash_ref" >/dev/null 2>&1
          msg "Stash dropped"
        fi
        ;;
      "Create branch"*)
        msg "Enter branch name:"
        local branch_name
        read -r branch_name </dev/tty
        if [[ -n "$branch_name" ]]; then
          if git stash branch "$branch_name" "$stash_ref" 2>&1; then
            msg "Branch '$branch_name' created from $stash_ref"
            return 0
          else
            msg "Error creating branch"
          fi
        fi
        ;;
      "Export"*)
        local stash_num=$(echo "$stash_ref" | grep -oE '[0-9]+')
        local patch_file="stash-${stash_num}-$(date +%Y%m%d-%H%M%S).patch"
        git stash show -p "$stash_ref" > "$patch_file"
        msg "Exported to $patch_file"
        ;;
      "Show"*)
        git stash show -p "$stash_ref" | less </dev/tty
        ;;
      "Rename"*)
        msg "Enter new stash message:"
        local new_msg
        read -r new_msg </dev/tty
        if [[ -n "$new_msg" ]]; then
          # Sauvegarder le contenu, drop, et recréer avec le nouveau message
          local temp_branch="temp-stash-rename-$$"
          if git stash branch "$temp_branch" "$stash_ref" >/dev/null 2>&1; then
            git stash push -m "$new_msg" >/dev/null 2>&1
            git checkout - >/dev/null 2>&1
            git branch -D "$temp_branch" >/dev/null 2>&1
            msg "Stash renamed"
          else
            msg "Error renaming stash"
          fi
        fi
        ;;
      *)
        # Back, continue loop
        ;;
    esac
  done
}

# =============================================================================
# Actions de suppression - retournent le repo principal pour y naviguer
# =============================================================================

action_delete_worktrees() {
  local worktrees=$(get_secondary_worktrees)

  if [[ -z "$worktrees" ]]; then
    msg "No secondary worktree to delete"
    return 1
  fi

  # Build formatted list
  local tmpfile=$(mktemp)
  get_secondary_worktrees | while IFS= read -r wt; do
    format_worktree_line "$wt"
  done > "$tmpfile"

  # Multi-select with Space, confirm with Enter
  local selected
  selected=$(fzf --height=60% \
        --layout=reverse \
        --border \
        --multi \
        --marker='x ' \
        --bind 'space:toggle+down' \
        --header="Select worktree(s) to delete | Space: select | Enter: confirm" \
        --preview="
          path=\$(echo {} | awk '{print \$1}' | sed \"s|^~|\$HOME|\")
          if [[ -d \"\$path\" ]]; then
            echo \"Path: \$path\"
            echo ''
            echo 'Status:'
            git -C \"\$path\" status --short 2>/dev/null | /usr/bin/head -10
            echo ''
            echo 'Recent commits:'
            git -C \"\$path\" log --oneline -5 2>/dev/null
          fi
        " \
        --preview-window=right:50% < "$tmpfile")

  rm -f "$tmpfile"

  if [[ -z "$selected" ]]; then
    return 1
  fi

  # Count selected
  local count=$(echo "$selected" | wc -l | tr -d ' ')

  # Check for uncommitted changes
  local dirty_list=""
  local dirty_count=0
  while IFS= read -r line; do
    local path=$(echo "$line" | awk '{print $1}' | sed "s|^~|$HOME|")
    if [[ -d "$path" ]] && [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]; then
      dirty_list+="  ${path/#$HOME/~}"$'\n'
      ((dirty_count++))
    fi
  done <<< "$selected"

  # Extra confirmation if dirty worktrees
  if [[ $dirty_count -gt 0 ]]; then
    local dirty_confirm
    dirty_confirm=$(printf "%s\n" "Yes, delete anyway (lose changes)" "Cancel" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --header="WARNING: $dirty_count worktree(s) have uncommitted changes!" \
          --preview="echo 'Uncommitted changes in:'; echo ''; echo '$dirty_list'" \
          --preview-window=right:50%)

    if [[ "$dirty_confirm" != "Yes"* ]]; then
      msg "Cancelled"
      return 1
    fi
  fi

  # Final confirmation
  local confirm
  confirm=$(printf "%s\n" "Yes, delete $count worktree(s)" "Cancel" | \
    fzf --height=20% \
        --layout=reverse \
        --border \
        --header="Confirm deletion?")

  if [[ "$confirm" == "Yes"* ]]; then
    echo "$selected" | while IFS= read -r line; do
      local to_remove=$(echo "$line" | awk '{print $1}' | sed "s|^~|$HOME|")
      # Try normal remove, then force, then manual cleanup
      if git -C "$MAIN_REPO" worktree remove "$to_remove" 2>/dev/null; then
        msg "Deleted: $to_remove"
      elif git -C "$MAIN_REPO" worktree remove --force "$to_remove" 2>/dev/null; then
        msg "Deleted (forced): $to_remove"
      else
        # Manual cleanup: remove dir and prune
        rm -rf "$to_remove"
        msg "Deleted (manual): $to_remove"
      fi
    done
    # Always prune from main repo to clean up any stale references
    git -C "$MAIN_REPO" worktree prune 2>/dev/null
    msg "Done"
    # Return to main repo
    echo "$MAIN_REPO"
  else
    msg "Cancelled"
    return 1
  fi
}

# =============================================================================
# Menu principal
# =============================================================================

main_menu() {
  if ! has_fzf; then
    msg "fzf is required"
    msg "Install with: brew install fzf"
    exit 1
  fi

  # Display logo on first launch
  print_logo

  while true; do
    local worktrees_formatted=$(format_all_worktrees)
    local secondary_count=$(get_secondary_worktrees | wc -l | tr -d ' ')
    local worktree_count=$(get_worktrees | wc -l | tr -d ' ')

    # Construire les actions
    local actions=""
    actions+=$'\n'"${C_DIM}-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=${C_RESET}"
    actions+=$'\n'"  Create a worktree"
    actions+=$'\n'"  Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"  Delete worktree(s)"
    fi
    actions+=$'\n'"  Quit"

    local menu="${worktrees_formatted}${actions}"

    # Header avec raccourcis clavier
    local header="${C_BOLD}$REPO_NAME${C_RESET}  ${C_DIM}^E editor · ^N new · ^P PRs · ^G issues · ^D delete${C_RESET}"

    local result=$(echo "$menu" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
          --expect=ctrl-e,ctrl-n,ctrl-p,ctrl-g,ctrl-d \
          --preview="
            line={}
            # Skip divider
            if [[ \"\$line\" == \"<<>>\"* ]]; then
              exit 0
            fi
            # Clean line (remove leading spaces for actions)
            clean_line=\$(echo \"\$line\" | sed 's/^  //')
            if [[ \"\$clean_line\" == \"Quit\"* ]]; then
              echo '> Exit wt'
            elif [[ \"\$clean_line\" == \"Create\"* ]]; then
              echo '> Create a new worktree'
              echo ''
              echo 'Options:'
              echo '  - New branch'
              echo '  - From existing branch'
              echo '  - From current (quick copy)'
              echo '  - From GitHub issue'
              echo '  - From GitHub PR'
              echo ''
              echo 'Tip: ^N for quick access'
            elif [[ \"\$clean_line\" == \"Delete\"* ]]; then
              echo '> Delete worktree(s)'
              echo ''
              echo 'Select one or multiple worktrees to delete.'
              echo 'Use Space to toggle selection.'
              echo ''
              echo 'Secondary worktrees ($secondary_count):'
              git worktree list --porcelain | grep '^worktree ' | cut -d' ' -f2- | tail -n +2 | while read wt; do
                echo \"  - \${wt/#\$HOME/~}\"
              done
            elif [[ \"\$clean_line\" == \"Manage stashes\"* ]]; then
              echo '> Manage git stashes'
              echo ''
              stash_count=\$(git stash list 2>/dev/null | wc -l | tr -d ' ')
              echo \"Current stashes: \$stash_count\"
              echo ''
              if [[ \$stash_count -gt 0 ]]; then
                git stash list 2>/dev/null | /usr/bin/head -5
              else
                echo 'No stashes found'
              fi
            else
              path=\$(echo \"\$line\" | awk '{print \$1}' | sed \"s|^~|\$HOME|\")
              if [[ -d \"\$path\" ]]; then
                branch=\$(git -C \"\$path\" branch --show-current 2>/dev/null || echo 'detached')

                # Header
                echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
                echo \"  Branch: \$branch\"
                echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
                echo ''

                # Sync status with remote
                tracking=\$(git -C \"\$path\" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
                if [[ -n \"\$tracking\" ]]; then
                  ahead=\$(git -C \"\$path\" rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
                  behind=\$(git -C \"\$path\" rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)
                  if [[ \$ahead -gt 0 && \$behind -gt 0 ]]; then
                    echo \"  ↑\$ahead ↓\$behind  (diverged from \$tracking)\"
                  elif [[ \$ahead -gt 0 ]]; then
                    echo \"  ↑\$ahead ahead of \$tracking\"
                  elif [[ \$behind -gt 0 ]]; then
                    echo \"  ↓\$behind behind \$tracking\"
                  else
                    echo \"  ✓ In sync with \$tracking\"
                  fi
                  echo ''
                fi

                # Uncommitted changes
                if [[ -n \$(git -C \"\$path\" status --porcelain 2>/dev/null) ]]; then
                  echo '  Uncommitted changes:'
                  git -C \"\$path\" status --short 2>/dev/null | /usr/bin/head -8
                  echo ''
                fi

                # Recent commits
                echo '  Recent commits:'
                git -C \"\$path\" log --oneline --graph --color=always -8 2>/dev/null
              else
                echo 'Invalid path'
              fi
            fi
          " \
          --preview-window=right:50%)

    # Parse key and selection from fzf --expect output
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    # Handle keyboard shortcuts
    case "$key" in
      ctrl-e)
        if [[ -n "$selected" && "$selected" != "───"* && "$selected" != "  "* ]]; then
          local path=$(echo "$selected" | awk '{print $1}' | sed "s|^~|$HOME|")
          if [[ -d "$path" ]]; then
            local editor=$(get_editor)
            msg "Opening in $editor: $path"
            "$editor" "$path" &
          fi
        fi
        continue
        ;;
      ctrl-n)
        local output
        output=$(menu_create_worktree)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-p)
        local output
        output=$(menu_review_pr)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-g)
        local output
        output=$(menu_from_issue)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        continue
        ;;
      ctrl-d)
        local path
        path=$(action_delete_worktrees)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        continue
        ;;
    esac

    # If fzf was cancelled (Escape/Ctrl+C) and no shortcut was pressed, exit
    if [[ -z "$key" && ( -z "$selected" || "$selected" =~ ^[[:space:]]*$ ) ]]; then
      return 0
    fi

    # Skip divider line
    if [[ "$selected" == "<<>>"* ]]; then
      continue
    fi

    # Clean action lines (remove leading spaces)
    local clean_selected=$(echo "$selected" | sed 's/^  //')

    case "$clean_selected" in
      "Create"*)
        local output
        output=$(menu_create_worktree)
        if [[ -n "$output" ]]; then
          echo "$output"
          return 0
        fi
        ;;
      "Manage stashes"*)
        menu_stash
        ;;
      "Delete"*)
        local path
        path=$(action_delete_worktrees)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        ;;
      "Quit"|"")
        return 0
        ;;
      *)
        # C'est un worktree existant - extraire et retourner le path
        local path=$(echo "$selected" | awk '{print $1}' | sed "s|^~|$HOME|")
        if [[ -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        ;;
    esac
  done
}

# =============================================================================
# Point d'entrée
# =============================================================================

if [[ "$1" == "--pr-preview" ]]; then
  pr_preview "$2"
  exit 0
fi

if [[ "$1" == "--issue-preview" ]]; then
  issue_preview "$2"
  exit 0
fi

# Switch to previous worktree (like cd -)
if [[ "$1" == "-" ]]; then
  if [[ -f ~/.wt_prev ]]; then
    prev=$(cat ~/.wt_prev)
    if [[ -d "$prev" ]]; then
      echo "$prev"
      exit 0
    else
      msg "Previous worktree no longer exists: $prev"
      exit 1
    fi
  else
    msg "No previous worktree (run 'wt --setup' to enable this feature)"
    exit 1
  fi
fi

# Switch to main worktree
if [[ "$1" == "." ]]; then
  main_wt=$(git worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2-)
  if [[ -n "$main_wt" && -d "$main_wt" ]]; then
    echo "$main_wt"
    exit 0
  else
    msg "Could not find main worktree"
    exit 1
  fi
fi

# Quick switch: wt <name> fuzzy matches on worktrees
if [[ -n "$1" && "$1" != "--"* ]]; then
  # Format worktrees for matching
  worktrees_list=$(format_all_worktrees)
  match=$(echo "$worktrees_list" | fzf --filter="$1" | head -1)
  if [[ -n "$match" ]]; then
    path=$(echo "$match" | awk '{print $1}' | sed "s|^~|$HOME|")
    if [[ -d "$path" ]]; then
      echo "$path"
      exit 0
    fi
  fi
  msg "No worktree matching '$1'"
  exit 1
fi

# Run main menu and capture result
result=$(main_menu)

if [[ -n "$result" ]]; then
  echo "$result"
fi

