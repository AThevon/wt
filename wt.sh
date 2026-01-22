#!/bin/bash

# =============================================================================
# wt - Git Worktree Manager avec fzf
# =============================================================================
# Le script retourne UNIQUEMENT le path vers lequel naviguer sur stdout
# Tous les messages vont sur stderr pour ne pas polluer le résultat
# =============================================================================

VERSION="1.2.2"

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

  # Parse output: path on first line, optional CLAUDE marker on second
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
    if [[ "$claude_cmd" == CLAUDE:issue:* ]]; then
      local issue_num="${claude_cmd#CLAUDE:issue:}"
      echo ""
      echo "Starting Claude Code for Issue #$issue_num planning..."
      echo ""
      claude "Read issue #$issue_num with 'gh issue view $issue_num', then explore the codebase and propose an implementation plan."
    elif [[ "$claude_cmd" == CLAUDE:pr:* ]]; then
      local pr_num="${claude_cmd#CLAUDE:pr:}"
      echo ""
      echo "Starting Claude Code for PR #$pr_num review..."
      echo ""
      claude "Review PR #$pr_num. Run 'gh pr view $pr_num' and 'gh pr diff $pr_num' to get context, then analyze the code changes for bugs, security issues, and best practices."
    fi
  fi
}
EOF
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
  --shell-init     Output shell function for automatic cd

Interactive features:
  - Create worktrees (from branch, new branch, PR, or GitHub issue)
  - Dirty indicator (*) shows worktrees with uncommitted changes
  - Ctrl+E: Open worktree in editor (cursor > code > \$EDITOR > vim)
  - Manage git stashes
  - Claude Code integration for PR review and issue planning

For automatic directory changing, add to your .zshrc:
  eval "\$(wt-core --shell-init)"

Dependencies: fzf, gh (optional, for GitHub features), jq, claude (optional)
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
  echo "$@" >&2
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
                        ,----,
                      ,/   .`|
           .---.    ,`   .'  :
          /. ./|  ;    ;     /
      .--'.  ' ;.'___,/    ,'
     /__./ \ : ||    :     |
 .--'.  '   \' .;    |.';  ;
/___/ \ |    ' '`----'  |  |
;   \  \;      :    '   :  ;
 \   ;  `      |    |   |  '
  .   \    .\  ;    '   :  |
   \   \   ' \ |    ;   |.'
    :   '  |--"     '---'
     \   \ ;
      '---"
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
      (if .isDraft then "📝"
       elif (.statusCheckRollup | length) == 0 then "⚪"
       elif ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length) > 0 then "❌"
       elif ([.statusCheckRollup[] | select(.status == "COMPLETED")] | length) < (.statusCheckRollup | length) then "⏳"
       else "✅" end) as $ci |
      (if .reviewDecision == "APPROVED" then "✓"
       elif .reviewDecision == "CHANGES_REQUESTED" then "✗"
       else " " end) as $review |
      "#\(.number)\t\($ci) \($review)\t\(.title[0:50])\t@\(.author.login)\t\(.headRefName)"'
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

prompt_claude_pr_review() {
  local pr_num="$1"
  local wt_path="$2"

  if ! has_claude; then
    return 0
  fi

  msg ""
  msg "Launch Claude Code for PR #$pr_num review? [y/N] "
  local answer
  read -r answer </dev/tty

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    # Output marker for shell wrapper to launch claude
    echo "CLAUDE:pr:$pr_num"
  fi
}

prompt_claude_issue_plan() {
  local issue_num="$1"
  local wt_path="$2"

  if ! has_claude; then
    return 0
  fi

  msg ""
  msg "Launch Claude Code for Issue #$issue_num planning? [y/N] "
  local answer
  read -r answer </dev/tty

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    # Output marker for shell wrapper to launch claude
    echo "CLAUDE:issue:$issue_num"
  fi
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

  msg "Fetching branch..."
  git fetch origin "$pr_branch" >/dev/null 2>&1

  msg "Creating worktree..."
  if git worktree add "$worktree_path" "$pr_branch" >/dev/null 2>&1; then
    msg "Worktree created: $worktree_path"
    echo "$worktree_path"  # SEUL output sur stdout
  else
    msg "Error creating worktree"
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

menu_review_pr() {
  if ! has_gh; then
    setup_github_auth
    if ! has_gh; then
      return 1
    fi
  fi

  msg "Fetching PRs..."

  local prs=$(get_formatted_prs)
  if [[ -z "$prs" ]]; then
    msg "No open PRs"
    return 1
  fi

  # Boucle pour permettre Ctrl+O sans quitter
  while true; do
    local result=$(echo "$prs" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --header="Open PRs | Enter: create worktree | Ctrl+O: open in browser" \
          --delimiter='\t' \
          --with-nth=1,2,3,4 \
          --preview="bash \"$SCRIPT_PATH\" --pr-preview {1}" \
          --preview-window=right:50% \
          --expect=ctrl-o)

    # Première ligne = touche pressée, deuxième ligne = sélection
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    if [[ -z "$selected" ]]; then
      return 1
    fi

    local pr_num=$(echo "$selected" | cut -f1 | tr -d '#')
    local pr_branch=$(echo "$selected" | cut -f5)

    if [[ "$key" == "ctrl-o" ]]; then
      # Ouvrir dans le navigateur et continuer la boucle
      gh pr view "$pr_num" --web >/dev/null 2>&1
    else
      # Enter = créer le worktree et y aller
      local wt_path
      wt_path=$(create_from_pr "$pr_branch")
      local ret=$?
      if [[ $ret -eq 0 && -n "$wt_path" ]]; then
        # Proposer intégration Claude
        prompt_claude_pr_review "$pr_num" "$wt_path"
        echo "$wt_path"
      fi
      return $ret
    fi
  done
}

# =============================================================================
# Menu From Issue
# =============================================================================

menu_from_issue() {
  if ! has_gh; then
    setup_github_auth
    if ! has_gh; then
      return 1
    fi
  fi

  msg "Fetching issues..."

  local issues=$(get_formatted_issues)
  if [[ -z "$issues" ]]; then
    msg "No open issues"
    return 1
  fi

  # Boucle pour permettre Ctrl+O sans quitter
  while true; do
    local result=$(echo "$issues" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --header="Open Issues | Enter: create worktree | Ctrl+O: open in browser" \
          --delimiter='\t' \
          --with-nth=1,2,3,4 \
          --preview="bash \"$SCRIPT_PATH\" --issue-preview {1}" \
          --preview-window=right:50% \
          --expect=ctrl-o)

    # Première ligne = touche pressée, deuxième ligne = sélection
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    if [[ -z "$selected" ]]; then
      return 1
    fi

    local issue_num=$(echo "$selected" | cut -f1 | tr -d '#')
    local issue_title=$(echo "$selected" | cut -f2)

    if [[ "$key" == "ctrl-o" ]]; then
      # Ouvrir dans le navigateur et continuer la boucle
      gh issue view "$issue_num" --web >/dev/null 2>&1
    else
      # Enter = créer le worktree et y aller
      local wt_path
      wt_path=$(create_from_issue "$issue_num" "$issue_title")
      local ret=$?
      if [[ $ret -eq 0 && -n "$wt_path" ]]; then
        # Proposer intégration Claude
        prompt_claude_issue_plan "$issue_num" "$wt_path"
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
      "From current branch" \
      "From a branch" \
      "Create new branch" \
      "From an issue" \
      "Review a PR" \
      "Back" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --header="Create a worktree")

    case "$choice" in
      *"current"*)
        create_from_current
        return $?
        ;;
      "From a branch"*)
        create_from_branch
        return $?
        ;;
      "Create new branch"*)
        create_new_branch
        return $?
        ;;
      "From an issue"*)
        menu_from_issue
        local ret=$?
        [[ $ret -eq 0 ]] && return 0
        ;;
      *"PR"*)
        menu_review_pr
        local ret=$?
        # Si menu_review_pr a retourné un path (succès), propager
        [[ $ret -eq 0 ]] && return 0
        # Sinon continuer la boucle
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
            git stash show -p \"\$stash_ref\" 2>/dev/null | head -50
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

action_remove_worktree() {
  local worktrees=$(get_secondary_worktrees)

  if [[ -z "$worktrees" ]]; then
    msg "No secondary worktree to remove"
    return 1
  fi

  local formatted=""
  while IFS= read -r wt; do
    formatted+="$(format_worktree_line "$wt")"$'\n'
  done <<< "$worktrees"

  local selected=$(echo "$formatted" | \
    fzf --height=50% \
        --layout=reverse \
        --border \
        --header="Select worktree to remove" \
        --preview="/bin/ls -la {1} 2>/dev/null" \
        --preview-window=right:50%)

  if [[ -z "$selected" ]]; then
    return 1
  fi

  local to_remove=$(echo "$selected" | awk '{print $1}' | sed "s|^~|$HOME|")

  if git worktree remove "$to_remove" >/dev/null 2>&1; then
    msg "Worktree removed: $to_remove"
  else
    msg "Force removing..."
    rm -rf "$to_remove"
    git worktree prune
    msg "Worktree removed: $to_remove"
  fi

  # Retourner le repo principal pour y naviguer
  echo "$MAIN_REPO"
}

action_remove_all_worktrees() {
  local worktrees=$(get_secondary_worktrees)

  if [[ -z "$worktrees" ]]; then
    msg "No secondary worktree to remove"
    return 1
  fi

  local count=$(echo "$worktrees" | wc -l | tr -d ' ')

  msg ""
  msg "Worktrees to remove ($count):"
  echo "$worktrees" | while read -r wt; do
    msg "   $wt"
  done
  msg ""
  msg -n "Confirm deletion? (y/N) "
  read confirm </dev/tty

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$worktrees" | while read -r wt; do
      git worktree remove "$wt" >/dev/null 2>&1 || rm -rf "$wt"
      msg "Removed: $wt"
    done
    git worktree prune
    msg "All secondary worktrees removed"
    # Retourner le repo principal pour y naviguer
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

    # Construire les actions dynamiquement
    local actions="Create a worktree"
    actions+=$'\n'"Manage stashes"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"Remove a worktree"
    fi
    if [[ "$secondary_count" -ge 2 ]]; then
      actions+=$'\n'"Remove all worktrees"
    fi
    actions+=$'\n'"Quit"

    local menu="${worktrees_formatted}
${actions}"

    local result=$(echo "$menu" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --header="Worktrees - $REPO_NAME | Ctrl+E: open in editor" \
          --expect=ctrl-e \
          --preview="
            line={}
            if [[ \"\$line\" == \"Quit\"* ]]; then
              echo 'Exit wt'
            elif [[ \"\$line\" == \"Create\"* ]]; then
              echo 'Open submenu to create a worktree:'
              echo ''
              echo '  - From current branch (copy)'
              echo '  - From a branch'
              echo '  - Create new branch'
              echo '  - Review a PR'
            elif [[ \"\$line\" == \"Remove a\"* ]]; then
              echo 'Remove a secondary worktree'
            elif [[ \"\$line\" == \"Remove all\"* ]]; then
              echo 'Remove all secondary worktrees'
            elif [[ \"\$line\" == \"Manage stashes\"* ]]; then
              echo 'Manage git stashes'
            else
              path=\$(echo \"\$line\" | awk '{print \$1}' | sed \"s|^~|\$HOME|\")
              if [[ -d \"\$path\" ]]; then
                echo \"Path: \$path\"
                echo ''
                echo 'Ctrl+E to open in editor'
                echo ''
                git -C \"\$path\" log --oneline --graph --color=always -5 2>/dev/null || true
                echo ''
                /bin/ls -la \"\$path\" 2>/dev/null | /usr/bin/head -15
              fi
            fi
          " \
          --preview-window=right:50%)

    # Parse key and selection from fzf --expect output
    local key=$(echo "$result" | head -1)
    local selected=$(echo "$result" | tail -n +2)

    # Handle Ctrl+E: open in editor and stay in menu
    if [[ "$key" == "ctrl-e" && -n "$selected" ]]; then
      local path=$(echo "$selected" | awk '{print $1}' | sed "s|^~|$HOME|")
      if [[ -d "$path" ]]; then
        local editor=$(get_editor)
        msg "Opening in $editor: $path"
        "$editor" "$path" &
      fi
      continue
    fi

    case "$selected" in
      "Create"*)
        # Capture stdout (le path + éventuellement CLAUDE marker)
        local output
        output=$(menu_create_worktree)
        if [[ -n "$output" ]]; then
          # Passer tout l'output (path + CLAUDE marker) au wrapper
          echo "$output"
          return 0
        fi
        # Pas d'output = retour au menu
        ;;
      "Manage stashes"*)
        menu_stash
        # Stash menu doesn't return a path, just continue
        ;;
      "Remove a"*)
        local path
        path=$(action_remove_worktree)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"
          return 0
        fi
        ;;
      "Remove all"*)
        local path
        path=$(action_remove_all_worktrees)
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

# Run main menu and capture result
result=$(main_menu)

if [[ -n "$result" ]]; then
  echo "$result"

  # Show setup hint if not running through wrapper
  if [[ -z "$WT_WRAPPED" ]]; then
    msg ""
    msg "Tip: To enable auto-cd, add this to your .zshrc:"
    msg ""
    msg "  eval \"\$(wt-core --shell-init)\""
    msg ""
    msg "Then run: source ~/.zshrc"
  fi
fi
