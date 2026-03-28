#!/usr/bin/env bash
# lib/stash.sh — Stash management

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

  local partial_header="${C_BOLD}Partial stash${C_RESET}  ${C_DIM}Space select · ^A all · Enter confirm${C_RESET}"

  local selected=$(echo "$all_files" | \
    fzf --height=60% \
        --layout=reverse \
        --border \
        --ansi \
        --multi \
        --marker='+ ' \
        --bind 'space:toggle+down' \
        --bind 'ctrl-a:select-all' \
        --header="$partial_header" \
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
      local empty_header="${C_BOLD}No stashes${C_RESET}  ${C_DIM}^N create · ^E partial${C_RESET}"
      local empty_result=$(printf "%s\n" \
        "Create stash (all changes)" \
        "Create partial stash (select files)" \
        "Back" | \
        fzf --height=30% \
            --layout=reverse \
            --border \
            --ansi \
            --header="$empty_header" \
            --expect=ctrl-n,ctrl-e)

      local empty_key=$(echo "$empty_result" | head -1)
      local choice=$(echo "$empty_result" | tail -n +2)

      # Handle shortcuts
      case "$empty_key" in
        ctrl-n) choice="Create stash (all changes)" ;;
        ctrl-e) choice="Create partial stash (select files)" ;;
      esac

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

    # Header avec titre stylé
    local header="${C_BOLD}Stashes${C_RESET}  ${C_DIM}Enter actions · Space select · ? help${C_RESET}
ref         │ age  │ files │ branch       │ message
────────────┴──────┴───────┴──────────────┴─────────────────────────────"

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
          less <(git stash show -p "$stash_ref") </dev/tty
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
    local stash_header="${C_BOLD}$stash_ref${C_RESET}  ${C_DIM}^A apply · ^P pop · ^D drop · ^W wt · ^B branch · ^S show${C_RESET}"
    local action_result=$(echo "$menu_options" | \
      fzf --height=40% \
          --layout=reverse \
          --border \
          --ansi \
          --header="$stash_header" \
          --expect=ctrl-a,ctrl-p,ctrl-d,ctrl-w,ctrl-b,ctrl-s,ctrl-x,ctrl-r \
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

    local action_key=$(echo "$action_result" | head -1)
    local action=$(echo "$action_result" | tail -n +2)

    # Handle shortcuts
    case "$action_key" in
      ctrl-a) action="Apply (keep)" ;;
      ctrl-p) action="Pop (apply + remove)" ;;
      ctrl-d) action="Drop (delete)" ;;
      ctrl-w) action="Create worktree from stash" ;;
      ctrl-b) action="Create branch from stash" ;;
      ctrl-s) action="Show full diff" ;;
      ctrl-x) action="Export as patch" ;;
      ctrl-r) action="Rename stash" ;;
    esac

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
        less <(git stash show -p "$stash_ref") </dev/tty
        continue
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
