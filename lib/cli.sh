#!/usr/bin/env bash
# lib/cli.sh — gh/glab CLI abstraction

# =============================================================================
# CLI Abstraction (gh / glab)
# =============================================================================

cli_pr_list() {
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab mr list --per-page "${WT_LIST_LIMIT:-20}" --output json 2>/dev/null | \
      /usr/bin/jq -r '.[] |
        (if .draft then "\u001b[2m[draft]\u001b[0m"
         elif .head_pipeline == null then "\u001b[2m[--]\u001b[0m"
         elif .head_pipeline.status == "failed" then "\u001b[31m[fail]\u001b[0m"
         elif .head_pipeline.status == "success" then "\u001b[32m[ok]\u001b[0m"
         else "\u001b[33m[..]\u001b[0m" end) as $ci |
        "#\(.iid)\t\($ci)  \t\(.title[0:50])\t\u001b[2m@\(.author.username)\u001b[0m\t\(.source_branch)"'
  else
    local gh_user
    gh_user=$(gh api user --jq .login 2>/dev/null)
    gh pr list --limit "${WT_LIST_LIMIT:-20}" --json number,title,headRefName,author,reviewDecision,statusCheckRollup,isDraft,reviewRequests 2>/dev/null | \
      /usr/bin/jq -r --arg me "$gh_user" '.[] |
        (if .isDraft then "\u001b[2m[draft]\u001b[0m"
         elif (.statusCheckRollup | length) == 0 then "\u001b[2m[--]\u001b[0m"
         elif ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length) > 0 then "\u001b[31m[fail]\u001b[0m"
         elif ([.statusCheckRollup[] | select(.status == "COMPLETED")] | length) < (.statusCheckRollup | length) then "\u001b[33m[..]\u001b[0m"
         else "\u001b[32m[ok]\u001b[0m" end) as $ci |
        (([.reviewRequests[] | select(.login == $me)] | length) > 0) as $needs_my_review |
        (if .reviewDecision == "APPROVED" then "\u001b[32m✓\u001b[0m"
         elif .reviewDecision == "CHANGES_REQUESTED" then "\u001b[31m✗\u001b[0m"
         elif $needs_my_review then "\u001b[35m◀\u001b[0m"
         else " " end) as $review |
        "#\(.number)\t\($ci) \($review)\t\(.title[0:50])\t\u001b[2m@\(.author.login)\u001b[0m\t\(.headRefName)"'
  fi
}

cli_pr_view() {
  local num="$1"
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab mr view "$num" --output json 2>/dev/null | \
      /usr/bin/jq -r '"Title: \(.title)\n\nStats: \(.changes_count // "?") changed files\n\nLabels: \(if (.labels | length) > 0 then (.labels | join(", ")) else "none" end)\n\nState: \(.state)\n\n" + (if .description then "Description:\n\(.description[0:500])" else "" end)'
  else
    gh pr view "$num" --json title,body,labels,reviewDecision,additions,deletions,changedFiles 2>/dev/null | \
      /usr/bin/jq -r '"Title: \(.title)\n\nStats: +\(.additions) -\(.deletions) (\(.changedFiles) files)\n\nLabels: \(if (.labels | length) > 0 then (.labels | map(.name) | join(", ")) else "none" end)\n\nReview: \(.reviewDecision // "Pending")\n\n" + (if .body then "Description:\n\(.body[0:500])" else "" end)'
  fi
}

cli_pr_diff_stat() {
  local num="$1"
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    local mr_json
    mr_json=$(glab mr view "$num" --output json 2>/dev/null)
    local target_branch source_branch
    target_branch=$(echo "$mr_json" | /usr/bin/jq -r '.target_branch')
    source_branch=$(echo "$mr_json" | /usr/bin/jq -r '.source_branch')
    if [[ -n "$target_branch" && -n "$source_branch" ]]; then
      git diff --stat "origin/$target_branch...origin/$source_branch" 2>/dev/null | /usr/bin/head -20
    fi
  else
    gh pr diff "$num" --stat 2>/dev/null | /usr/bin/head -20
  fi
}

cli_issue_list() {
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab issue list --per-page "${WT_LIST_LIMIT:-20}" --output json 2>/dev/null | \
      /usr/bin/jq -r '.[] |
        (if (.labels | length) > 0 then (.labels | join(","))[0:15] else "-" end) as $labels |
        "#\(.iid)\t\(.title[0:50])\t@\(.author.username)\t\($labels)"'
  else
    gh issue list --limit "${WT_LIST_LIMIT:-20}" --json number,title,author,labels,state 2>/dev/null | \
      /usr/bin/jq -r '.[] |
        (if (.labels | length) > 0 then (.labels | map(.name) | join(","))[0:15] else "-" end) as $labels |
        "#\(.number)\t\(.title[0:50])\t@\(.author.login)\t\($labels)"'
  fi
}

cli_issue_view() {
  local num="$1"
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab issue view "$num" --output json 2>/dev/null | \
      /usr/bin/jq -r '"Title: \(.title)\n\nState: \(.state)\n\nLabels: \(if (.labels | length) > 0 then (.labels | join(", ")) else "none" end)\n\nComments: \(.user_notes_count)\n\n" + (if .description then "Description:\n\(.description[0:800])" else "No description" end)'
  else
    gh issue view "$num" --json title,body,labels,state,comments 2>/dev/null | \
      /usr/bin/jq -r '"Title: \(.title)\n\nState: \(.state)\n\nLabels: \(if (.labels | length) > 0 then (.labels | map(.name) | join(", ")) else "none" end)\n\nComments: \(.comments | length)\n\n" + (if .body then "Description:\n\(.body[0:800])" else "No description" end)'
  fi
}

cli_open_pr_in_browser() {
  local num="$1"
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab mr view "$num" --web >/dev/null 2>&1
  else
    gh pr view "$num" --web >/dev/null 2>&1
  fi
}

cli_open_issue_in_browser() {
  local num="$1"
  local platform=$(detect_platform)
  if [[ "$platform" == "gitlab" ]]; then
    glab issue view "$num" --web >/dev/null 2>&1
  else
    gh issue view "$num" --web >/dev/null 2>&1
  fi
}

cli_pr_status() {
  local branch="$1"
  local platform=$(detect_platform)
  local pr_term=$(get_pr_term)
  local pr_prefix; if [[ "$platform" == "gitlab" ]]; then pr_prefix="!"; else pr_prefix="#"; fi

  if [[ "$platform" == "gitlab" ]]; then
    if ! command -v glab &>/dev/null; then return; fi
    local mr_info
    mr_info=$(glab mr list --source-branch "$branch" --output json 2>/dev/null | /usr/bin/jq '.[0] // empty')
    if [[ -n "$mr_info" ]]; then
      local mr_state mr_number mr_title
      mr_state=$(echo "$mr_info" | /usr/bin/jq -r '.state')
      mr_number=$(echo "$mr_info" | /usr/bin/jq -r '.iid')
      mr_title=$(echo "$mr_info" | /usr/bin/jq -r '.title[0:50]')
      printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
      case "$mr_state" in
        "merged")  printf '  \033[32m✓ %s %s%s MERGED\033[0m\n' "$pr_term" "$pr_prefix" "$mr_number" ;;
        "closed")  printf '  \033[31m✗ %s %s%s CLOSED\033[0m\n' "$pr_term" "$pr_prefix" "$mr_number" ;;
        *)         printf '  \033[34m○ %s %s%s OPEN\033[0m\n' "$pr_term" "$pr_prefix" "$mr_number" ;;
      esac
      printf '  %s\n' "$mr_title"
    fi
  else
    if ! command -v gh &>/dev/null; then return; fi
    local pr_info
    pr_info=$(gh pr view "$branch" --json state,number,title 2>/dev/null)
    if [[ -n "$pr_info" ]]; then
      local pr_state pr_number pr_title
      pr_state=$(echo "$pr_info" | /usr/bin/jq -r '.state')
      pr_number=$(echo "$pr_info" | /usr/bin/jq -r '.number')
      pr_title=$(echo "$pr_info" | /usr/bin/jq -r '.title[0:50]')
      printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
      case "$pr_state" in
        "MERGED")  printf '  \033[32m✓ %s #%s MERGED\033[0m\n' "$pr_term" "$pr_number" ;;
        "CLOSED")  printf '  \033[31m✗ %s #%s CLOSED\033[0m\n' "$pr_term" "$pr_number" ;;
        *)         printf '  \033[34m○ %s #%s OPEN\033[0m\n' "$pr_term" "$pr_number" ;;
      esac
      printf '  %s\n' "$pr_title"
    fi
  fi
}

# CLI command helpers for Claude prompts
cli_cmd_issue_view() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "glab issue view $1"; else echo "gh issue view $1"; fi
}
cli_cmd_pr_create() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "glab mr create"; else echo "gh pr create"; fi
}
cli_cmd_pr_view() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "glab mr view $1"; else echo "gh pr view $1"; fi
}
cli_cmd_pr_diff() {
  if [[ "$(detect_platform)" == "gitlab" ]]; then echo "glab mr diff $1"; else echo "gh pr diff $1"; fi
}
