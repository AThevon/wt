# wt - Git Worktree Manager

CLI bash interactif (~3700 lignes, fichier unique `wt.sh`) pour gérer les git worktrees avec intégration GitHub/GitLab et Claude.

## Architecture

**Single-file CLI** : tout le code est dans `wt.sh`. Pas de framework, pas de build — du bash pur avec `fzf` pour les menus interactifs.

**Convention stdout/stderr** : le script retourne UNIQUEMENT le path du worktree sélectionné sur stdout. Tous les messages UI vont sur stderr (`msg()`, `msg_warn()`, etc.) pour ne pas polluer le résultat.

### Sections principales de `wt.sh`

| Section | Description |
|---------|-------------|
| Options CLI & shell-init | Parsing des flags (`--version`, `--setup`, `--wizard`, `--dev`, `--shell-init`) |
| Colors & Style | Variables ANSI (`C_RED`, `C_GREEN`, `C_ORANGE`, `C_MAGENTA`, etc.) |
| Config | Lecture/écriture `~/.config/wt/config` |
| Platform Detection | Auto-détection GitHub vs GitLab |
| CLI Abstraction | `cli_pr_list()`, `cli_pr_view()`, etc. — abstraction `gh`/`glab` |
| Prompt Generation | Génération de prompts Claude pour review, CI fix, issues |
| Worktrees | `format_worktree_line()`, `is_branch_merged()`, `get_worktrees()` |
| PRs / Issues | Formatage et preview des PRs et issues |
| Actions de création | `create_worktree()`, `create_from_pr()`, `create_from_issue()` |
| Menus | `menu_review_pr()`, `menu_from_issue()`, `menu_create_worktree()`, `menu_stash()` |
| Main Menu | `main_menu()` — point d'entrée interactif avec fzf |

### Conventions de nommage des worktrees

- Feature : `{repo}-{prefix}{branch}` (ex: `myapp-feature/auth`)
- Review : `{repo}-reviewing-{branch}` (ex: `myapp-reviewing-fix-bug`)
- Le préfixe `-reviewing-` identifie un worktree de type review

### Icônes worktree (dans `format_worktree_line()`)

| Icône | Couleur | Signification |
|-------|---------|---------------|
| `●` | dim | Branche principale (main/master) |
| `✓` | vert | Branche mergée (squash merge supporté) |
| `◎` | magenta | Worktree de review |
| `★` | jaune | Nouvelle branche locale (jamais pushée) |
| `○` | orange | En cours (pushée, non mergée) |
| `*` | — | Dirty (changements non committés) |

### Indicateurs PR (dans `cli_pr_list()`)

| CI | Review | Signification |
|----|--------|---------------|
| `[ok]` | `✓` vert | CI ok / Approved |
| `[fail]` | `✗` rouge | CI fail / Changes requested |
| `[..]` | `◀` magenta | CI en cours / Needs MY review |
| `[draft]` | ` ` | Draft / Pas de review pending |

## Tests

Framework : [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

```bash
./tests/run.sh          # Lancer tous les tests
bats tests/01-config.bats  # Un fichier spécifique
```

Fichiers dans `tests/` :
- `01-config.bats` — gestion de la config
- `02-editor.bats` — détection d'éditeur
- `03-platform.bats` — détection de plateforme
- `04-worktree-dir.bats` — répertoire des worktrees
- `05-claude-mode.bats` — modes Claude
- `06-cli-flags.bats` — flags CLI

## Dépendances

- **fzf** (requis) — menus interactifs
- **gh** / **glab** (optionnel) — intégration GitHub/GitLab
- **jq** (optionnel) — parsing JSON pour les PRs/issues
- **claude** (optionnel) — fonctionnalités IA

## Config

Fichier : `~/.config/wt/config` (clés `WT_EDITOR`, `WT_PLATFORM`, `WT_WORKTREE_DIR`, `WT_AUTO_CD`, `WT_FEATURE_PREFIX`, `WT_AUTO_FETCH`, `WT_CLAUDE_MODE`, `WT_LIST_LIMIT`).

## Commandes utiles pour dev

```bash
# Mode dev (utilise le script local au lieu de wt-core installé)
eval "$(./wt.sh --dev)"

# Revenir au mode release
wt --release
```
