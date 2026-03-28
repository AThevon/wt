#!/usr/bin/env bash
# lib/git.sh — Worktree operations and creation

# =============================================================================
# CLI Auth Setup
# =============================================================================

setup_cli_auth() {
  if has_cli; then
    return 0  # Déjà authentifié
  fi

  local platform=$(detect_platform)
  local cli_name=$(get_cli_name)
  local platform_name=$(get_platform_name)

  if ! command -v "$cli_name" &>/dev/null; then
    msg "$platform_name CLI ($cli_name) is not installed"
    msg "$(get_pr_term) features will be disabled"
    if [[ "$platform" == "gitlab" ]]; then
      msg "Install with: brew install glab"
    else
      msg "Install with: brew install gh"
    fi
    return 1
  fi

  local choice=$(printf "%s\n" \
    "Login via browser (recommended)" \
    "Login with a token" \
    "Continue without $platform_name" \
    "Quit" | \
    fzf --height=40% \
        --layout=reverse \
        --border \
        --header="$platform_name CLI is not configured")

  case "$choice" in
    *"browser"*)
      if [[ "$platform" == "gitlab" ]]; then
        glab auth login --web </dev/tty
      else
        gh auth login --web </dev/tty
      fi
      ;;
    *"token"*)
      if [[ "$platform" == "gitlab" ]]; then
        glab auth login </dev/tty
      else
        gh auth login </dev/tty
      fi
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

# Get the default branch (main or master)
get_default_branch() {
  local default_branch=$(git -C "$MAIN_REPO" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi
  echo "$default_branch"
}

# Check if a branch is new (never been pushed to remote)
is_new_local_branch() {
  local branch="$1"
  local default_branch=$(get_default_branch)

  [[ "$branch" == "$default_branch" ]] && return 1

  # No tracking config → never been pushed → new local branch
  [[ -z $(git -C "$MAIN_REPO" config "branch.$branch.remote" 2>/dev/null) ]]
}

# Check if a branch is merged into the default branch
# Supports both regular merges and squash merges — fully local, no network calls
# Uses origin/<default_branch> for comparison so a fetch is enough (no pull needed)
is_branch_merged() {
  local branch="$1"
  local default_branch=$(get_default_branch)
  local origin_default="origin/$default_branch"

  [[ "$branch" == "$default_branch" ]] && return 1

  # Method 1: Standard merge (branch is ancestor of default branch)
  if git -C "$MAIN_REPO" merge-base --is-ancestor "$branch" "$origin_default" 2>/dev/null; then
    return 0
  fi

  # Method 2: Squash merge detection via tree comparison
  # After a squash merge, the branch content is identical to main
  # even though the commit history differs. Comparing trees is instant and local.
  local branch_tree main_tree
  branch_tree=$(git -C "$MAIN_REPO" rev-parse "$branch^{tree}" 2>/dev/null) || return 1
  main_tree=$(git -C "$MAIN_REPO" rev-parse "$origin_default^{tree}" 2>/dev/null) || return 1
  [[ "$branch_tree" == "$main_tree" ]]
}

format_worktree_line() {
  local wt_path="$1"
  local branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "detached")
  local short_path="${wt_path/#$HOME/~}"
  local default_branch=$(get_default_branch)

  # Dirty check
  local dirty=""
  if [[ -n $(git -C "$wt_path" status --porcelain 2>/dev/null) ]]; then
    dirty=" *"
  fi

  # Status indicator at the beginning
  local status_icon
  local dir_name=$(basename "$wt_path")
  if [[ "$branch" == "$default_branch" ]]; then
    # Main branch - neutral
    status_icon="${C_DIM}●${C_RESET}"
  elif is_branch_merged "$branch"; then
    # Merged - green checkmark
    status_icon="${C_GREEN}✓${C_RESET}"
  elif [[ "$dir_name" == *"-reviewing-"* ]]; then
    # Review worktree - magenta eye
    status_icon="${C_MAGENTA}◎${C_RESET}"
  elif is_new_local_branch "$branch"; then
    # New local branch (never pushed) - yellow star
    status_icon="${C_YELLOW}★${C_RESET}"
  else
    # In progress (pushed, not merged) - orange circle
    status_icon="${C_ORANGE}○${C_RESET}"
  fi

  printf "%s %-48s %s[%s]\n" "$status_icon" "$short_path" "$dirty" "$branch"
}

format_all_worktrees() {
  while IFS= read -r wt; do
    format_worktree_line "$wt"
  done < <(get_worktrees)
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
  local worktree_path="$(get_worktree_base_dir)/${worktree_name}"
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
  if [[ "${WT_AUTO_FETCH:-true}" != "false" ]]; then
    msg "Fetching branches..."
    git fetch --all --prune >/dev/null 2>&1
  fi

  local branch_name
  local branch_header="${C_BOLD}Select branch${C_RESET}  ${C_DIM}Enter select · Esc cancel${C_RESET}"
  branch_name=$(git branch -a --format='%(refname:short)' | \
    grep -v '^HEAD' | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$branch_header" \
        --preview="git log --oneline --graph --color=always -10 {}" \
        --preview-window=right:50%)

  if [[ -z "$branch_name" ]]; then
    msg "No branch selected"
    return 1
  fi

  local sanitized=$(echo "$branch_name" | sed 's|^origin/||' | sed 's|/|-|g')
  # Toujours créer à côté du repo PRINCIPAL
  local worktree_path="$(get_worktree_base_dir)/${REPO_NAME}-${sanitized}"

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
  if [[ "${WT_AUTO_FETCH:-true}" != "false" ]]; then
    msg "Fetching branches..."
    git fetch --all --prune >/dev/null 2>&1
  fi

  local current_branch=$(git branch --show-current 2>/dev/null || echo "HEAD")
  local base_header="${C_BOLD}Base branch${C_RESET}  ${C_DIM}Enter select · Esc use $current_branch${C_RESET}"
  local base_branch
  base_branch=$(printf "%s\n" "$current_branch (current)" $(git branch -a --format='%(refname:short)' | grep -v '^HEAD') | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$base_header" \
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
  local worktree_path="$(get_worktree_base_dir)/${REPO_NAME}-${sanitized}"

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
  local pr_num="$2"
  local sanitized=$(echo "$pr_branch" | sed 's|^origin/||' | sed 's|/|-|g')
  # Toujours créer à côté du repo PRINCIPAL, avec préfixe "reviewing"
  local worktree_path="$(get_worktree_base_dir)/${REPO_NAME}-reviewing-${sanitized}"

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
  if git -C "$MAIN_REPO" fetch origin "$pr_branch" >/dev/null 2>&1; then
    # Branch exists on origin — standard case
    msg "Creating worktree..."
    local git_output
    git_output=$(git -C "$MAIN_REPO" worktree add -B "$pr_branch" "$worktree_path" "origin/$pr_branch" 2>&1)
    local ret=$?

    if [[ $ret -eq 0 ]]; then
      msg "Worktree created: $worktree_path"
      echo "$worktree_path"
      return 0
    fi

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

  # Branch not on origin — likely a fork-based PR, use GitHub's PR refs
  if [[ -z "$pr_num" ]]; then
    msg "Error: branch '$pr_branch' not found on origin and no PR number provided"
    return 1
  fi

  msg "Branch not on origin, fetching PR #$pr_num..."
  if ! git -C "$MAIN_REPO" fetch origin "pull/$pr_num/head:$pr_branch" >/dev/null 2>&1; then
    msg "Error fetching PR #$pr_num"
    return 1
  fi

  msg "Creating worktree..."
  local git_output
  git_output=$(git -C "$MAIN_REPO" worktree add "$worktree_path" "$pr_branch" 2>&1)

  if [[ $? -eq 0 ]]; then
    msg "Worktree created: $worktree_path"
    echo "$worktree_path"
  else
    msg "Error creating worktree:"
    msg "$git_output"
    return 1
  fi
}

# Créer un worktree depuis une issue
create_from_issue() {
  local issue_num="$1"
  local issue_title="$2"

  # Créer un slug à partir du titre
  local slug=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-30)
  local _feature_prefix="${WT_FEATURE_PREFIX:-feature/}"
  local base_branch_name="${_feature_prefix}${issue_num}-${slug}"
  local branch_name="$base_branch_name"

  # Incrémenter si la branche existe déjà
  local counter=2
  while git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null || \
        git show-ref --verify --quiet "refs/remotes/origin/$branch_name" 2>/dev/null; do
    branch_name="${base_branch_name}-${counter}"
    ((counter++))
  done

  local sanitized=$(echo "$branch_name" | sed 's|/|-|g')
  local worktree_path="$(get_worktree_base_dir)/${REPO_NAME}-${sanitized}"

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
