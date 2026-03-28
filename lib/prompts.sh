#!/usr/bin/env bash
# lib/prompts.sh — Claude prompt generation

generate_prompt() {
  local type="$1"
  local num="$2"
  local platform=$(detect_platform)
  local pr_term=$(get_pr_term)
  local pr_term_long=$(get_pr_term_long)
  local platform_name=$(get_platform_name)
  local pr_prefix; if [[ "$platform" == "gitlab" ]]; then pr_prefix="!"; else pr_prefix="#"; fi

  case "$type" in
    "issue-auto")
      cat <<PROMPT
You are auto-resolving $platform_name Issue #$num.

MISSION: Fully resolve this issue autonomously and create a $pr_term_long.

PHASE 1 - UNDERSTAND:
1. Run '$(cli_cmd_issue_view "$num")' to read the issue details
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
16. Create a $pr_term with '$(cli_cmd_pr_create)' that:
    - References the issue (Closes #$num)
    - Describes what was changed and why
    - Lists any considerations or trade-offs

Be thorough but efficient. Ship working code.
PROMPT
      ;;

    "ci-fix")
      if [[ "$platform" == "gitlab" ]]; then
        cat <<PROMPT
You are fixing CI failures for $pr_term_long $pr_prefix$num.

MISSION: Analyze the CI failure logs, fix the issues, and push the fix.

PHASE 1 - GET CI LOGS:
1. Run 'glab ci list' to find recent pipelines
2. Run 'glab ci view' to see failed jobs and their logs
3. Identify which jobs failed and read their output

PHASE 2 - ANALYZE:
4. Identify the root cause of the failure
5. Understand what needs to be fixed (tests, lint, build, types, etc.)

PHASE 3 - FIX:
6. Make the necessary code changes to fix the CI errors
7. Detect package manager (check for pnpm-lock.yaml, yarn.lock, or package-lock.json)
8. Run the same checks locally to verify the fix (lint, test, build, typecheck)
9. Make sure all checks pass before proceeding

PHASE 4 - PUSH:
10. Commit with a clear message like 'fix: resolve CI failures'
11. Push to the branch (git push)

IMPORTANT:
- Focus ONLY on fixing the CI errors, don't refactor unrelated code
- If multiple issues, fix them all
- Verify locally before pushing
PROMPT
      else
        cat <<PROMPT
You are fixing CI failures for $pr_term_long #$num.

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
- Verify locally before pushing
PROMPT
      fi
      ;;

    "pr-review")
      cat <<PROMPT
You are reviewing $pr_term_long $pr_prefix$num.

FIRST STEPS:
1. Run '$(cli_cmd_pr_view "$num")' to get $pr_term title, description, and metadata
2. Run '$(cli_cmd_pr_diff "$num")' to see all code changes

CODE REVIEW CHECKLIST:
- Logic & Correctness: Does it work? Edge cases handled?
- Security: Injection, auth issues, data exposure?
- Performance: N+1 queries, memory leaks, blocking ops?
- Error Handling: Proper error messages?
- Code Quality: Readable, DRY, good abstractions?
- Testing: Tests present and meaningful?
- Breaking Changes: Could this break existing code?

OUTPUT:
- Summary of the $pr_term
- [OK] What looks good
- [~] Concerns (with file:line references)
- [!!] Blocking issues
- [?] Optional improvements
- Recommendation: Approve / Request Changes / Discuss
PROMPT
      ;;

    "pr-work")
      cat <<PROMPT
You are working on $pr_term_long $pr_prefix$num.

FIRST STEPS:
1. Run '$(cli_cmd_pr_view "$num")' to understand the $pr_term context
2. Run '$(cli_cmd_pr_diff "$num")' to see current changes

You are now in the $pr_term branch. Help the user with whatever they need:
- Understanding the code
- Making additional changes
- Fixing issues
- Responding to review comments

Ask what they'd like to do.
PROMPT
      ;;

    "issue-work")
      cat <<PROMPT
You are working on $platform_name Issue #$num.

FIRST STEPS:
1. Run '$(cli_cmd_issue_view "$num")' to read the full issue
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
- Questions if any
PROMPT
      ;;
  esac
}
