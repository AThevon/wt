#!/bin/bash

# =============================================================================
# wt - Git Worktree Manager avec fzf
# =============================================================================
# Le script retourne UNIQUEMENT le path vers lequel naviguer sur stdout
# Tous les messages vont sur stderr pour ne pas polluer le résultat
# =============================================================================

VERSION="1.3.0"

# =============================================================================
# Options de ligne de commande
# =============================================================================

if [[ "$1" == "--version" || "$1" == "-v" ]]; then
  echo "wt $VERSION" >&2
  exit 0
fi

if [[ "$1" == "--shell-init" ]]; then
  cat <<'EOF'
# wt - Git Worktree Manager
unalias wt 2>/dev/null
function wt() {
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

if [[ "$1" == "--setup" ]]; then
  echo ""
  echo "wt setup"
  echo "--------"
  echo ""

  # Detect shell
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)
      echo "[!!] Unsupported shell: $shell_name"
      echo "     Supported: zsh, bash"
      exit 1
      ;;
  esac
  echo "[ok] Shell: $shell_name"
  echo "[ok] Config: $rc_file"
  echo ""

  # Check dependencies
  echo "Dependencies:"
  deps_ok=true
  if command -v fzf &>/dev/null; then
    echo "  [ok] fzf"
  else
    echo "  [!!] fzf (required) - install with: brew install fzf"
    deps_ok=false
  fi
  if command -v gh &>/dev/null; then
    echo "  [ok] gh"
  else
    echo "  [--] gh (optional) - install with: brew install gh"
  fi
  if command -v jq &>/dev/null; then
    echo "  [ok] jq"
  else
    echo "  [--] jq (optional) - install with: brew install jq"
  fi
  if command -v claude &>/dev/null; then
    echo "  [ok] claude"
  else
    echo "  [--] claude (optional)"
  fi
  echo ""

  if [[ "$deps_ok" == false ]]; then
    echo "[!!] Install required dependencies first"
    exit 1
  fi

  # Check if wt-core is available
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if ! command -v wt-core &>/dev/null; then
    echo "Setting up wt-core command..."

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
    echo "[ok] Created: $install_dir/wt-core -> $script_path"

    # Check if install_dir is in PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
      echo ""
      echo "[!!] $install_dir is not in your PATH"
      echo "     Add this to your $rc_file:"
      echo ""
      echo "     export PATH=\"$install_dir:\$PATH\""
      echo ""
    fi
  else
    echo "[ok] wt-core already in PATH"
  fi

  # Check if already configured
  init_line='eval "$(wt-core --shell-init)"'
  if grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
    echo "[ok] Already configured in $rc_file"
  else
    echo ""
    echo "Adding wt to $rc_file..."
    echo "" >> "$rc_file"
    echo "# wt - Git Worktree Manager" >> "$rc_file"
    echo "$init_line" >> "$rc_file"
    echo "[ok] Added to $rc_file"
  fi

  echo ""
  echo "--------"
  echo ""
  echo "To activate now, run:"
  echo ""
  echo "  source $rc_file"
  echo ""
  echo "Or restart your terminal."
  echo ""
  exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat >&2 <<EOF
wt - Git Worktree Manager with fzf

Usage: wt [options] [name]

Arguments:
  name             Quick switch: fuzzy match on worktrees

Options:
  --help, -h       Show this help message
  --version, -v    Show version number
  --setup          Install wt (add to shell, create symlinks)

Keyboard shortcuts:
  Ctrl+E           Open in editor
  Ctrl+N           New worktree
  Ctrl+P           List PRs
  Ctrl+G           List issues (G = GitHub)
  Ctrl+D           Delete worktree(s)

Features:
  - Create worktrees from branch, PR, or GitHub issue
  - Multi-select delete with Tab
  - Dirty indicator (*) for uncommitted changes
  - Claude Code integration (forced/ask/plan modes)

Quick start:
  wt --setup       One-time installation
  wt               Interactive menu
  wt <name>        Quick switch to worktree

Dependencies: fzf (required), gh, jq, claude (optional)
EOF
  exit 0
fi

# Vérifier qu'on est dans un repo git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
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
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN=''
  C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
fi

# ASCII Art Logo
LOGO="
  ${C_CYAN}┬ ┬┌┬┐${C_RESET}
  ${C_CYAN}│││ │ ${C_RESET} ${C_DIM}Git Worktree Manager${C_RESET}
  ${C_CYAN}└┴┘ ┴${C_RESET}
"

LOGO_SMALL="${C_CYAN}wt${C_RESET} ${C_DIM}│${C_RESET}"

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
      printf "\r  ${C_CYAN}%s${C_RESET} %s" "$bar" "$msg" >&2
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
            fi
            ;;
          *"Review"*)
            if has_claude; then
              local mode=$(select_claude_mode "pr-review" "$pr_num")
              [[ -n "$mode" ]] && echo "CLAUDE:pr-review:$pr_num:$mode"
            fi
            ;;
          *"Launch"*)
            if has_claude; then
              local mode=$(select_claude_mode "pr-work" "$pr_num")
              [[ -n "$mode" ]] && echo "CLAUDE:pr-work:$pr_num:$mode"
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
            fi
            ;;
          *"Launch"*)
            if has_claude; then
              local mode=$(select_claude_mode "issue-work" "$issue_num")
              [[ -n "$mode" ]] && echo "CLAUDE:issue-work:$issue_num:$mode"
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
# Stash Management
# =============================================================================

menu_stash() {
  while true; do
    local stashes=$(git stash list 2>/dev/null)

    if [[ -z "$stashes" ]]; then
      # Proposer de créer un stash
      local choice=$(printf "%s\n" \
        "Create a stash" \
        "Back" | \
        fzf --height=30% \
            --layout=reverse \
            --border \
            --header="No stashes found")

      case "$choice" in
        "Create"*)
          msg "Enter stash message (or leave empty):"
          local stash_msg
          read -r stash_msg </dev/tty
          if [[ -n "$stash_msg" ]]; then
            git stash push -m "$stash_msg" >/dev/null 2>&1
          else
            git stash push >/dev/null 2>&1
          fi
          msg "Stash created"
          ;;
        *)
          return 1
          ;;
      esac
      continue
    fi

    # Afficher les stashes avec actions
    local result=$(echo "$stashes" | \
      fzf --height=60% \
          --layout=reverse \
          --border \
          --header="Stashes | Enter: select action | Ctrl+N: new stash" \
          --preview="
            stash_ref=\$(echo {} | cut -d: -f1)
            echo 'Stash content:'
            echo '=============='
            git stash show -p \"\$stash_ref\" 2>/dev/null | /usr/bin/head -50
          " \
          --preview-window=right:60% \
          --expect=ctrl-n)

    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    if [[ "$key" == "ctrl-n" ]]; then
      msg "Enter stash message (or leave empty):"
      local stash_msg
      read -r stash_msg </dev/tty
      if [[ -n "$stash_msg" ]]; then
        git stash push -m "$stash_msg" >/dev/null 2>&1
      else
        git stash push >/dev/null 2>&1
      fi
      msg "Stash created"
      continue
    fi

    if [[ -z "$selected" ]]; then
      return 1
    fi

    local stash_ref=$(echo "$selected" | cut -d: -f1)

    # Menu d'actions pour le stash sélectionné
    local action=$(printf "%s\n" \
      "Apply (keep stash)" \
      "Pop (apply and remove)" \
      "Drop (delete)" \
      "Show diff" \
      "Back" | \
      fzf --height=30% \
          --layout=reverse \
          --border \
          --header="Action for $stash_ref")

    case "$action" in
      "Apply"*)
        if git stash apply "$stash_ref" >/dev/null 2>&1; then
          msg "Stash applied"
        else
          msg "Error applying stash (conflicts?)"
        fi
        ;;
      "Pop"*)
        if git stash pop "$stash_ref" >/dev/null 2>&1; then
          msg "Stash popped"
        else
          msg "Error popping stash (conflicts?)"
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
      "Show diff"*)
        git stash show -p "$stash_ref" | less
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

  # Multi-select with Tab, confirm with Enter
  local selected
  selected=$(fzf --height=60% \
        --layout=reverse \
        --border \
        --multi \
        --marker='x ' \
        --header="Select worktree(s) to delete | Tab: select | Enter: confirm" \
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
    actions+=$'\n'"<<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>>"
    actions+=$'\n'"  Create a worktree"
    actions+=$'\n'"  Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"  Delete worktree(s)"
    fi
    actions+=$'\n'"  Quit"

    local menu="${worktrees_formatted}${actions}"

    # Header avec raccourcis clavier
    local header="$REPO_NAME │ ^E: editor │ ^N: new │ ^P: PRs │ ^G: issues │ ^D: delete"

    local result=$(echo "$menu" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
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
              echo 'Use Tab to toggle selection.'
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

# Show splash
msg "$LOGO"

# Run main menu and capture result
result=$(main_menu)

if [[ -n "$result" ]]; then
  echo "$result"
fi

