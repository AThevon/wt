#!/usr/bin/env bash
# lib/menus.sh — PR, issue, create, delete, settings, wizards

# =============================================================================
# PRs / MRs
# =============================================================================

get_formatted_prs() {
  if ! has_cli; then
    msg "$(get_cli_name) not installed or not authenticated"
    return 1
  fi
  cli_pr_list
}

pr_preview() {
  local pr_num="$1"
  if [[ -z "$pr_num" ]]; then
    echo "Select a $(get_pr_term)"
    return
  fi

  echo "================================================"
  cli_pr_view "$pr_num"
  echo ""
  echo "================================================"
  echo "Changed files:"
  cli_pr_diff_stat "$pr_num"
}

# =============================================================================
# Issues
# =============================================================================

get_formatted_issues() {
  if ! has_cli; then
    msg "$(get_cli_name) not installed or not authenticated"
    return 1
  fi
  cli_issue_list
}

issue_preview() {
  local issue_num="$1"
  if [[ -z "$issue_num" ]]; then
    echo "Select an issue"
    return
  fi

  echo "================================================"
  cli_issue_view "$issue_num"
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

  # If a default mode is configured, bypass the picker
  if [[ -n "${WT_CLAUDE_MODE:-}" ]]; then
    case "$WT_CLAUDE_MODE" in
      forced|ask|plan)
        echo "$WT_CLAUDE_MODE"
        return
        ;;
    esac
  fi

  local title
  case "$context_type" in
    "pr-review") title="PR #$context_num review" ;;
    "pr-work")   title="PR #$context_num" ;;
    "issue-work") title="Issue #$context_num" ;;
    *) title="Claude mode" ;;
  esac

  local header="${C_BOLD}$title${C_RESET}  ${C_DIM}^F forced · ^A ask · ^P plan${C_RESET}"

  local options=">> Forced (full auto)
?> Ask (confirm actions)
## Plan (plan first)"

  local result
  result=$(fzf --height=25% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header" \
        --expect=ctrl-f,ctrl-a,ctrl-p \
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

  local key=$(echo "$result" | head -1)
  local mode=$(echo "$result" | tail -n +2)

  # Handle shortcuts
  case "$key" in
    ctrl-f) mode=">> Forced (full auto)" ;;
    ctrl-a) mode="?> Ask (confirm actions)" ;;
    ctrl-p) mode="## Plan (plan first)" ;;
  esac

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
# Menu Review PR
# =============================================================================

select_pr_action() {
  local pr_num="$1"
  local ci_failed="$2"
  local pr_term=$(get_pr_term)
  local platform_name=$(get_platform_name)

  local options="Review this $pr_term
Launch Claude
Just create worktree"

  # Add "Fix CI issues" option if CI has failed
  local shortcuts="^R review · ^L claude · ^W worktree"
  if [[ "$ci_failed" == "true" ]]; then
    options="Fix CI issues (auto)
$options"
    shortcuts="^F fix CI · $shortcuts"
  fi

  local header="${C_BOLD}$pr_term #$pr_num${C_RESET}  ${C_DIM}$shortcuts${C_RESET}"

  local result
  result=$(fzf --height=30% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header" \
        --expect=ctrl-f,ctrl-r,ctrl-l,ctrl-w \
        --preview="
          case {} in
            *Fix\ CI*)
              echo 'AUTO-FIX CI FAILURES'
              echo ''
              echo 'Claude will automatically:'
              echo '  1. Fetch failed CI logs'
              echo '  2. Analyze the errors'
              echo '  3. Fix the code'
              echo '  4. Push the fix'
              echo ''
              echo '!! Runs in FORCED mode (full auto)'
              ;;
            *Review*)
              echo 'Code review mode'
              echo ''
              echo 'Claude will analyze the $pr_term for:'
              echo '  - Bugs and logic errors'
              echo '  - Security issues'
              echo '  - Performance problems'
              echo '  - Code quality'
              ;;
            *Launch*)
              echo 'Work on this $pr_term'
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
              echo 'Just checkout the $pr_term branch.'
              ;;
          esac
        " \
        --preview-window=right:50% <<< "$options")

  local key=$(echo "$result" | head -1)
  local action=$(echo "$result" | tail -n +2)

  # Handle shortcuts
  case "$key" in
    ctrl-f) action="Fix CI issues (auto)" ;;
    ctrl-r) action="Review this $pr_term" ;;
    ctrl-l) action="Launch Claude" ;;
    ctrl-w) action="Just create worktree" ;;
  esac

  echo "$action"
}

menu_review_pr() {
  if ! has_cli; then
    setup_cli_auth
    if ! has_cli; then
      return 1
    fi
  fi

  local pr_term=$(get_pr_term)
  loader_start "Fetching ${pr_term}s..."
  local prs=$(get_formatted_prs)
  loader_stop
  if [[ -z "$prs" ]]; then
    msg ""
    msg "No open ${pr_term}s found."
    msg "Press Enter to continue..."
    read -r </dev/tty
    return 1
  fi

  # Boucle pour permettre Ctrl+O sans quitter
  local header="${C_BOLD}Open ${pr_term}s${C_RESET}  ${C_DIM}Enter select · ^O browser${C_RESET}"
  while true; do
    local result=$(echo -e "$prs" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
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
      cli_open_pr_in_browser "$pr_num"
    else
      # Select action (pass CI status)
      local action=$(select_pr_action "$pr_num" "$ci_failed")

      if [[ -z "$action" ]]; then
        continue  # Back to PR list
      fi

      # Create worktree
      local wt_path
      wt_path=$(create_from_pr "$pr_branch" "$pr_num")
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

  local header="${C_BOLD}Issue #$issue_num${C_RESET}  ${C_DIM}^A auto · ^L claude · ^W worktree${C_RESET}"

  local result
  result=$(fzf --height=25% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header" \
        --expect=ctrl-a,ctrl-l,ctrl-w \
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
              echo '  5. Create a $(get_pr_term)'
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

  local key=$(echo "$result" | head -1)
  local action=$(echo "$result" | tail -n +2)

  # Handle shortcuts
  case "$key" in
    ctrl-a) action="Auto-resolve (full auto)" ;;
    ctrl-l) action="Launch Claude" ;;
    ctrl-w) action="Just create worktree" ;;
  esac

  echo "$action"
}

menu_from_issue() {
  if ! has_cli; then
    setup_cli_auth
    if ! has_cli; then
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
  local header="${C_BOLD}Open Issues${C_RESET}  ${C_DIM}Enter select · ^O browser${C_RESET}"
  while true; do
    local result=$(echo "$issues" | \
      fzf --height=70% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
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
      cli_open_issue_in_browser "$issue_num"
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
    local pr_term=$(get_pr_term)
    local pr_term_lower=$(echo "$pr_term" | tr '[:upper:]' '[:lower:]')
    local header="${C_BOLD}Create a worktree${C_RESET}  ${C_DIM}^N new · ^B branch · ^C current · ^I issue · ^P $pr_term_lower${C_RESET}"

    local result=$(printf "%s\n" \
      "New branch" \
      "From existing branch" \
      "From current (quick copy)" \
      "From an issue" \
      "Review a $pr_term" \
      "Back" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
          --expect=ctrl-n,ctrl-b,ctrl-c,ctrl-i,ctrl-p)

    local key=$(echo "$result" | head -1)
    local choice=$(echo "$result" | tail -n +2)

    # Handle shortcuts
    case "$key" in
      ctrl-n) choice="New branch" ;;
      ctrl-b) choice="From existing branch" ;;
      ctrl-c) choice="From current (quick copy)" ;;
      ctrl-i) choice="From an issue" ;;
      ctrl-p) choice="Review a PR" ;;
    esac

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
      *"PR"*|*"MR"*)
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
  local header="${C_BOLD}Delete worktree(s)${C_RESET}  ${C_DIM}Space select · ^A all · Enter confirm${C_RESET}"
  local selected
  selected=$(fzf --height=60% \
        --layout=reverse \
        --border \
        --ansi \
        --multi \
        --marker='x ' \
        --bind 'space:toggle+down' \
        --bind 'ctrl-a:select-all' \
        --header="$header" \
        --preview="
          path=\$(echo {} | /usr/bin/awk '{print \$2}' | /usr/bin/sed \"s|^~|\$HOME|\")
          if [[ -d \"\$path\" ]]; then
            branch=\$(/usr/bin/git -C \"\$path\" branch --show-current 2>/dev/null || echo 'detached')
            default_branch=\$(/usr/bin/git -C \"$MAIN_REPO\" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | /usr/bin/sed 's@^refs/remotes/origin/@@')
            [[ -z \"\$default_branch\" ]] && default_branch=\"main\"

            # Header with merge status
            printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
            if [[ \"\$branch\" != \"\$default_branch\" && \"\$branch\" != \"detached\" ]]; then
              if /usr/bin/git -C \"$MAIN_REPO\" branch --merged \"\$default_branch\" 2>/dev/null | /usr/bin/grep -qE \"^[[:space:]*+]*\$branch\$\"; then
                printf '  Branch: %s  \033[32m✓ merged\033[0m\n' \"\$branch\"
              else
                printf '  Branch: %s  \033[33m○ not merged\033[0m\n' \"\$branch\"
              fi
            else
              printf '  Branch: %s\n' \"\$branch\"
            fi
            printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'

            # Uncommitted changes
            changes=\$(/usr/bin/git -C \"\$path\" status --porcelain 2>/dev/null)
            if [[ -n \"\$changes\" ]]; then
              printf '  \033[33mUncommitted changes:\033[0m\n'
              echo \"\$changes\" | /usr/bin/head -8
              echo ''
            fi

            # Recent commits
            printf '  Recent commits:\n'
            /usr/bin/git -C \"\$path\" log --oneline -5 2>/dev/null
            echo ''

            # PR/MR status (at the end)
            if [[ \"\$branch\" != \"\$default_branch\" && \"\$branch\" != \"detached\" ]]; then
              bash \"$SCRIPT_PATH\" --pr-status-preview \"\$branch\"
            fi
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
    local path=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")
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
      local to_remove=$(echo "$line" | awk '{print $2}' | sed "s|^~|$HOME|")
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
# First-time Preferences Wizard
# =============================================================================

run_preferences_wizard() {
  msg ""
  msg "  ${C_BOLD}Let's configure wt${C_RESET} in 2 quick steps."
  msg "  ${C_DIM}(Press ^S to skip any step)${C_RESET}"
  msg ""

  # Detect available editors
  local available_editors=()
  command -v cursor &>/dev/null && available_editors+=("cursor")
  command -v code &>/dev/null && available_editors+=("code")
  command -v nvim &>/dev/null && available_editors+=("nvim")
  command -v vim &>/dev/null && available_editors+=("vim")
  # Always offer custom
  available_editors+=("custom...")

  # Step 1: IDE
  local header_step1="${C_BOLD}Step 1/2 — Preferred editor${C_RESET}  ${C_DIM}^S skip${C_RESET}"
  local ide_result
  ide_result=$(printf '%s\n' "${available_editors[@]}" | \
    fzf --height=40% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header_step1" \
        --expect=ctrl-s \
        --preview='
          case {} in
            cursor*) echo "Cursor AI Editor"
                     echo ""
                     echo "AI-powered fork of VS Code"
                     echo "from Cursor.sh"
                     ;;
            code*)   echo "Visual Studio Code"
                     echo ""
                     echo "Microsoft'"'"'s open-source editor"
                     ;;
            nvim*)   echo "Neovim"
                     echo ""
                     echo "Hyperextensible Vim-based editor"
                     ;;
            vim*)    echo "Vim"
                     echo ""
                     echo "Classic terminal editor"
                     ;;
            custom*) echo "Custom editor"
                     echo ""
                     echo "Enter your editor command"
                     echo "(e.g. emacs, nano, subl)"
                     ;;
          esac
          echo ""
          echo "Used when pressing Ctrl+E"
          echo "in the worktree menu."
        ' \
        --preview-window=right:40%)

  local ide_key ide_choice
  ide_key=$(echo "$ide_result" | head -1)
  ide_choice=$(echo "$ide_result" | tail -n +2)
  # Strip ANSI codes and take first word
  ide_choice=$(echo "$ide_choice" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

  local selected_editor=""
  if [[ "$ide_key" != "ctrl-s" && -n "$ide_choice" ]]; then
    if [[ "$ide_choice" == "custom..." ]]; then
      msg ""
      msg "Enter your editor command (e.g. emacs, nano, subl):"
      read -r selected_editor </dev/tty
    else
      selected_editor="$ide_choice"
    fi
  fi

  # Step 2: Platform
  local header_step2="${C_BOLD}Step 2/2 — Git platform${C_RESET}  ${C_DIM}^S skip${C_RESET}"
  local current_remote_guess="github"
  local remote_url
  remote_url=$(git -C "${MAIN_REPO:-$PWD}" remote get-url origin 2>/dev/null || echo "")
  [[ "$remote_url" == *gitlab* ]] && current_remote_guess="gitlab"

  local platform_result
  platform_result=$(printf '%s\n' \
    "auto" \
    "github" \
    "gitlab" | \
    fzf --height=30% \
        --layout=reverse \
        --border \
        --ansi \
        --header="$header_step2" \
        --expect=ctrl-s \
        --preview="
          case {} in
            auto*)
              echo 'auto (recommended)'
              echo ''
              echo 'Reads your git remote URL'
              echo 'to detect GitHub vs GitLab.'
              echo ''
              echo \"Detected for this repo: $current_remote_guess\"
              ;;
            github*)
              echo 'GitHub'
              echo ''
              echo 'Forces GitHub mode.'
              echo 'Uses: gh CLI'
              ;;
            gitlab*)
              echo 'GitLab'
              echo ''
              echo 'Forces GitLab mode.'
              echo 'Uses: glab CLI'
              ;;
          esac
        " \
        --preview-window=right:40%)

  local platform_key platform_choice
  platform_key=$(echo "$platform_result" | head -1)
  platform_choice=$(echo "$platform_result" | tail -n +2 | awk '{print $1}')

  local selected_platform="auto"
  if [[ "$platform_key" != "ctrl-s" && -n "$platform_choice" ]]; then
    selected_platform="$platform_choice"
  fi

  # Write config file
  mkdir -p "$(dirname "$WT_CONFIG_FILE")"
  cat > "$WT_CONFIG_FILE" << WTEOF
# wt — user configuration
# Edit manually or via: wt > ⚙ Settings

WT_EDITOR=${selected_editor}
WT_PLATFORM=${selected_platform}
WT_WORKTREE_DIR=
WT_AUTO_CD=true
WT_FEATURE_PREFIX=feature/
WT_AUTO_FETCH=true
WT_CLAUDE_MODE=
WT_LIST_LIMIT=20
WTEOF

  # Source the new config
  load_config

  # Success screen
  local editor_display="${selected_editor:-auto-detect}"
  local editor_pad=$(( 17 - ${#editor_display} ))
  local platform_pad=$(( 19 - ${#selected_platform} ))
  [[ $editor_pad -lt 0 ]] && editor_pad=0
  [[ $platform_pad -lt 0 ]] && platform_pad=0

  msg ""
  msg "  ╔══════════════════════════════════════╗"
  msg "  ║  ${C_GREEN}✓${C_RESET}  wt is configured                ║"
  msg "  ╠══════════════════════════════════════╣"
  msg "  ║                                      ║"
  msg "  ║  IDE         ${editor_display}$(printf '%*s' $editor_pad '')║"
  msg "  ║  Platform    ${selected_platform}$(printf '%*s' $platform_pad '')║"
  msg "  ║                                      ║"
  msg "  ║  Config → ~/.config/wt/config        ║"
  msg "  ║                                      ║"
  msg "  ║  Tip: wt > ⚙ Settings to change      ║"
  msg "  ║                                      ║"
  msg "  ╚══════════════════════════════════════╝"
  msg ""
  msg "  Launching wt..."
  msg ""
  sleep 1
}

# =============================================================================
# First-time Install Wizard
# =============================================================================

run_install_wizard() {
  print_logo

  # Detect what needs to be installed
  local needs_symlink=false
  local needs_rc=false
  local install_dir="/usr/local/bin"
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if ! command -v wt-core &>/dev/null; then
    needs_symlink=true
    if [[ ! -d "/usr/local/bin" || ! -w "/usr/local/bin" ]]; then
      install_dir="${HOME}/.local/bin"
    fi
  fi

  local shell_name rc_file
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)    rc_file="$HOME/.profile" ;;
  esac

  local init_line='command -v wt-core &>/dev/null && eval "$(wt-core --shell-init)"'
  if ! grep -q "wt-core --shell-init" "$rc_file" 2>/dev/null; then
    needs_rc=true
  fi

  # If nothing to install, skip to preferences
  if [[ "$needs_symlink" == "false" && "$needs_rc" == "false" ]]; then
    run_preferences_wizard
    return
  fi

  # Build what-will-happen list
  msg "  ${C_BOLD}wt${C_RESET} needs a quick one-time setup."
  msg "  This will:"
  msg ""
  [[ "$needs_symlink" == "true" ]] && msg "    ${C_DIM}→${C_RESET} Create symlink  ${C_CYAN}${install_dir}/wt-core${C_RESET}"
  [[ "$needs_rc" == "true" ]]      && msg "    ${C_DIM}→${C_RESET} Add init line   ${C_CYAN}${rc_file}${C_RESET}"
  msg ""

  local confirm_result
  confirm_result=$(printf '%s\n' \
    "Yes, set it up" \
    "No, skip for now" | \
    fzf --height=15% \
        --layout=reverse \
        --border \
        --ansi \
        --no-sort \
        --header="${C_BOLD}Install now?${C_RESET}")

  if [[ "$confirm_result" != "Yes"* ]]; then
    msg ""
    msg "  Skipping install. Run: ${C_CYAN}./wt.sh --setup${C_RESET} to install later."
    msg ""
    return 1
  fi

  # Perform installation
  if [[ "$needs_symlink" == "true" ]]; then
    mkdir -p "$install_dir"
    ln -sf "$script_path" "${install_dir}/wt-core"
    msg "  ${C_GREEN}✓${C_RESET} Created: ${install_dir}/wt-core"
  fi

  if [[ "$needs_rc" == "true" ]]; then
    echo "" >> "$rc_file"
    echo "# wt - Git Worktree Manager" >> "$rc_file"
    echo "$init_line" >> "$rc_file"
    msg "  ${C_GREEN}✓${C_RESET} Added init line to ${rc_file}"
  fi

  msg ""
  msg "  ${C_BOLD}Installation complete!${C_RESET}"
  msg "  Run ${C_CYAN}source ${rc_file}${C_RESET} to activate (or restart your terminal)."
  msg ""
  sleep 1

  # Continue to preferences
  run_preferences_wizard
}

# =============================================================================
# Settings Menu
# =============================================================================

menu_settings() {
  while true; do
    # Read current values (live from variables, which were loaded from config)
    local cur_editor="${WT_EDITOR:-$(get_editor) (auto)}"
    local cur_platform="${WT_PLATFORM:-auto}"
    local cur_worktree_dir="${WT_WORKTREE_DIR:-default}"
    local cur_auto_cd="${WT_AUTO_CD:-true}"
    local cur_feature_prefix="${WT_FEATURE_PREFIX:-feature/}"
    local cur_auto_fetch="${WT_AUTO_FETCH:-true}"
    local cur_claude_mode="${WT_CLAUDE_MODE:-prompt each time}"
    local cur_list_limit="${WT_LIST_LIMIT:-20}"

    local header="${C_BOLD}⚙ Settings${C_RESET}  ${C_DIM}Enter to edit · ^R reset${C_RESET}"

    local options
    options=$(printf '%s\n' \
      "IDE              ${C_CYAN}${cur_editor}${C_RESET}" \
      "Platform         ${C_CYAN}${cur_platform}${C_RESET}" \
      "Worktree dir     ${C_CYAN}${cur_worktree_dir}${C_RESET}" \
      "Auto-CD          ${C_CYAN}${cur_auto_cd}${C_RESET}" \
      "Feature prefix   ${C_CYAN}${cur_feature_prefix}${C_RESET}" \
      "Auto-fetch       ${C_CYAN}${cur_auto_fetch}${C_RESET}" \
      "Claude mode      ${C_CYAN}${cur_claude_mode}${C_RESET}" \
      "PR/Issue limit   ${C_CYAN}${cur_list_limit}${C_RESET}" \
      "──────────────────────────────────────" \
      "↺ Reset to defaults")

    local result
    result=$(echo "$options" | \
      fzf --height=60% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$header" \
          --expect=ctrl-r \
          --preview='
            case {} in
              IDE*)
                echo "Preferred code editor"
                echo ""
                echo "Used when pressing Ctrl+E"
                echo "in the main worktree menu."
                echo ""
                echo "auto = detect cursor > code > $EDITOR > vim"
                ;;
              Platform*)
                echo "Git hosting platform"
                echo ""
                echo "auto   = detect from remote URL"
                echo "github = force GitHub (gh CLI)"
                echo "gitlab = force GitLab (glab CLI)"
                ;;
              Worktree*)
                echo "Base directory for new worktrees"
                echo ""
                echo "default = created next to main repo"
                echo "custom  = any absolute path, e.g. ~/worktrees"
                ;;
              Auto-CD*)
                echo "Auto-navigate after worktree selection"
                echo ""
                echo "true  = cd to worktree on selection"
                echo "false = no automatic cd"
                ;;
              Feature*)
                echo "Branch prefix for issue worktrees"
                echo ""
                echo "Used when creating a worktree"
                echo "from a GitHub/GitLab issue."
                echo ""
                echo "Examples: feature/ feat/ task/"
                ;;
              Auto-fetch*)
                echo "Fetch before branch operations"
                echo ""
                echo "true  = git fetch --all before listing branches"
                echo "false = use cached branch list (faster offline)"
                ;;
              Claude*)
                echo "Default Claude launch mode"
                echo ""
                echo "prompt each time = show picker (default)"
                echo "forced  = --dangerously-skip-permissions"
                echo "ask     = interactive mode"
                echo "plan    = --permission-mode=plan"
                ;;
              PR*)
                echo "Max items in PR and issue lists"
                echo ""
                echo "Higher = more results, slower API call"
                echo "Lower  = fewer results, faster"
                ;;
              *Reset*)
                echo "Reset all settings to defaults"
                echo ""
                echo "Overwrites ~/.config/wt/config"
                echo "with default values and runs wizard."
                ;;
            esac
          ' \
          --preview-window=right:45%)

    local key selected
    key=$(echo "$result" | head -1)
    selected=$(echo "$result" | tail -n +2)
    # Strip ANSI and take first word to get the setting name
    selected=$(echo "$selected" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

    # Ctrl+R or ↺ Reset to defaults
    if [[ "$key" == "ctrl-r" ]] || [[ "$selected" == "↺" ]]; then
      local confirm
      confirm=$(printf '%s\n' "Yes, reset everything" "No, cancel" | \
        fzf --height=15% --layout=reverse --border --ansi \
            --header="${C_BOLD}Reset all settings to defaults?${C_RESET}")
      if [[ "$confirm" == "Yes"* ]]; then
        rm -f "$WT_CONFIG_FILE"
        run_preferences_wizard
        load_config
        msg_success "Settings reset to defaults"
      fi
      continue
    fi

    # Exit on empty selection (Escape)
    [[ -z "$selected" ]] && return 0

    # Edit each setting based on first word of selection
    case "$selected" in
      IDE)
        local editors=()
        command -v cursor &>/dev/null && editors+=("cursor")
        command -v code &>/dev/null && editors+=("code")
        command -v nvim &>/dev/null && editors+=("nvim")
        command -v vim &>/dev/null && editors+=("vim")
        editors+=("custom...")
        local choice
        choice=$(printf '%s\n' "${editors[@]}" | \
          fzf --height=30% --layout=reverse --border --ansi \
              --header="${C_BOLD}Select IDE${C_RESET}")
        if [[ -n "$choice" ]]; then
          if [[ "$choice" == "custom..." ]]; then
            msg "Enter editor command:"
            read -r choice </dev/tty
          fi
          if [[ -n "$choice" ]]; then
            save_config_value "WT_EDITOR" "$choice"
            export WT_EDITOR="$choice"
          fi
        fi
        ;;
      Platform)
        local choice
        choice=$(printf '%s\n' "auto" "github" "gitlab" | \
          fzf --height=20% --layout=reverse --border --ansi \
              --header="${C_BOLD}Select platform${C_RESET}")
        if [[ -n "$choice" ]]; then
          save_config_value "WT_PLATFORM" "$choice"
          export WT_PLATFORM="$choice"
          _WT_PLATFORM="$choice"
        fi
        ;;
      Worktree)
        msg "Enter base directory for new worktrees (empty = default):"
        local dir
        read -r dir </dev/tty
        save_config_value "WT_WORKTREE_DIR" "$dir"
        export WT_WORKTREE_DIR="$dir"
        ;;
      Auto-CD)
        local choice
        choice=$(printf '%s\n' "true" "false" | \
          fzf --height=15% --layout=reverse --border --ansi \
              --header="${C_BOLD}Auto-CD${C_RESET}")
        if [[ -n "$choice" ]]; then
          save_config_value "WT_AUTO_CD" "$choice"
          export WT_AUTO_CD="$choice"
        fi
        ;;
      Feature)
        msg "Enter feature branch prefix (e.g. feature/, feat/, task/):"
        local prefix
        read -r prefix </dev/tty
        if [[ -n "$prefix" ]]; then
          save_config_value "WT_FEATURE_PREFIX" "$prefix"
          export WT_FEATURE_PREFIX="$prefix"
        fi
        ;;
      Auto-fetch)
        local choice
        choice=$(printf '%s\n' "true" "false" | \
          fzf --height=15% --layout=reverse --border --ansi \
              --header="${C_BOLD}Auto-fetch${C_RESET}")
        if [[ -n "$choice" ]]; then
          save_config_value "WT_AUTO_FETCH" "$choice"
          export WT_AUTO_FETCH="$choice"
        fi
        ;;
      Claude)
        local choice
        choice=$(printf '%s\n' \
          "prompt each time" \
          "forced" \
          "ask" \
          "plan" | \
          fzf --height=25% --layout=reverse --border --ansi \
              --header="${C_BOLD}Claude mode${C_RESET}")
        if [[ -n "$choice" ]]; then
          local mode_val=""
          case "$choice" in
            "forced"*) mode_val="forced" ;;
            "ask"*)    mode_val="ask" ;;
            "plan"*)   mode_val="plan" ;;
          esac
          save_config_value "WT_CLAUDE_MODE" "$mode_val"
          export WT_CLAUDE_MODE="$mode_val"
        fi
        ;;
      PR/Issue)
        msg "Enter max items in lists (default: 20):"
        local limit
        read -r limit </dev/tty
        if [[ "$limit" =~ ^[0-9]+$ ]]; then
          save_config_value "WT_LIST_LIMIT" "$limit"
          export WT_LIST_LIMIT="$limit"
        fi
        ;;
      "──────────────────────────────────────")
        continue
        ;;
    esac
  done
}
