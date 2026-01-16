#!/bin/bash

# =============================================================================
# wt - Git Worktree Manager avec fzf
# =============================================================================
# Le script retourne UNIQUEMENT le path vers lequel naviguer sur stdout
# Tous les messages vont sur stderr pour ne pas polluer le résultat
# =============================================================================

VERSION="1.0.0"

# =============================================================================
# Options de ligne de commande
# =============================================================================

if [[ "$1" == "--version" || "$1" == "-v" ]]; then
  echo "wt $VERSION"
  exit 0
fi

if [[ "$1" == "--shell-init" ]]; then
  cat <<'EOF'
# wt - Git Worktree Manager
unalias wt 2>/dev/null
function wt() {
  local target=$(wt-core "$@")
  if [[ -n "$target" && -d "$target" ]]; then
    cd "$target"
    echo "Navigated to: $target"
  fi
}
EOF
  exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  cat <<EOF
wt - Git Worktree Manager with fzf

Usage: wt [options]

Options:
  --help, -h       Show this help message
  --version, -v    Show version number
  --shell-init     Output shell function for automatic cd

Interactive commands:
  Run 'wt' in a git repository to open the interactive menu.

For automatic directory changing, add to your .zshrc:
  eval "\$(wt-core --shell-init)"

Dependencies: fzf, gh (optional, for PR features), jq
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

# Messages sur stderr uniquement
msg() {
  echo "$@" >&2
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
  printf "%-50s [%s]\n" "$short_path" "$branch"
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

  gh pr list --limit 20 --json number,title,headRefName,author,reviewDecision,statusCheckRollup 2>/dev/null | \
    /usr/bin/jq -r '.[] |
      (if (.statusCheckRollup | length) == 0 then "?"
       elif ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length) > 0 then "x"
       elif ([.statusCheckRollup[] | select(.status == "COMPLETED")] | length) < (.statusCheckRollup | length) then "~"
       else "+" end) as $ci |
      (if .reviewDecision == "APPROVED" then "ok"
       elif .reviewDecision == "CHANGES_REQUESTED" then "!!"
       else "  " end) as $review |
      "#\(.number)\t\($ci)\($review)\t\(.title[0:45])\t@\(.author.login)\t\(.headRefName)"'
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
      create_from_pr "$pr_branch"
      return $?
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
      *"branch"*)
        create_from_branch
        return $?
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

  while true; do
    local worktrees_formatted=$(format_all_worktrees)
    local secondary_count=$(get_secondary_worktrees | wc -l | tr -d ' ')

    # Construire les actions dynamiquement
    local actions="Create a worktree"
    if [[ "$secondary_count" -ge 1 ]]; then
      actions+=$'\n'"Remove a worktree"
    fi
    if [[ "$secondary_count" -ge 2 ]]; then
      actions+=$'\n'"Remove all worktrees"
    fi
    actions+=$'\n'"Quit"

    local menu="${worktrees_formatted}
${actions}"

    local selected=$(echo "$menu" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --header="Worktrees - $REPO_NAME" \
          --preview="
            line={}
            if [[ \"\$line\" == \"Quit\"* ]]; then
              echo 'Exit wt'
            elif [[ \"\$line\" == \"Create\"* ]]; then
              echo 'Open submenu to create a worktree:'
              echo ''
              echo '  - From current branch (copy)'
              echo '  - From a branch'
              echo '  - Review a PR'
            elif [[ \"\$line\" == \"Remove a\"* ]]; then
              echo 'Remove a secondary worktree'
            elif [[ \"\$line\" == \"Remove all\"* ]]; then
              echo 'Remove all secondary worktrees'
            else
              path=\$(echo \"\$line\" | awk '{print \$1}' | sed \"s|^~|\$HOME|\")
              if [[ -d \"\$path\" ]]; then
                echo \"Path: \$path\"
                echo ''
                git -C \"\$path\" log --oneline --graph --color=always -5 2>/dev/null || true
                echo ''
                /bin/ls -la \"\$path\" 2>/dev/null | /usr/bin/head -15
              fi
            fi
          " \
          --preview-window=right:50%)

    case "$selected" in
      "Create"*)
        # Capture stdout (le path) séparément
        local path
        path=$(menu_create_worktree)
        if [[ -n "$path" && -d "$path" ]]; then
          echo "$path"  # Propager le path vers la fonction shell
          return 0
        fi
        # Pas de path = retour au menu
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

main_menu
