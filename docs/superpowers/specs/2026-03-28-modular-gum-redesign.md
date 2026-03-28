# wt — Refactoring modulaire + intégration gum

## Résumé

Découper `wt.sh` (fichier unique ~3800 lignes) en modules `lib/*.sh` pour faciliter la navigation IA et la maintenance. Intégrer `gum` (Charmbracelet) comme dépendance requise pour upgrader toute l'UI : spinners, confirmations, inputs, headers, résumés d'action. Remplacer le logo ASCII tigre par le nouveau WT ANSI Shadow + bande regard tigre.

## Architecture des fichiers

### Avant

```
wt.sh    # ~3800 lignes, tout dedans
```

### Après

```
wt.sh                     # Point d'entrée (~200 lignes)
lib/
  core.sh                 # Colors, msg helpers, config, platform detection, has_*()
  ui.sh                   # Wrappers gum (spinners, confirm, input, style, log)
  git.sh                  # Worktree ops, format_worktree_line, is_branch_merged,
                          # create_worktree, create_from_pr, create_from_issue
  cli.sh                  # Abstraction gh/glab (cli_pr_list, cli_pr_view, cli_issue_view)
  prompts.sh              # generate_prompt() + 5 templates Claude
  menus.sh                # Menus PR, issues, création, settings, wizards, delete
  stash.sh                # menu_stash() et toute la gestion stash (~750 lignes)
```

### Point d'entrée `wt.sh`

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/git.sh"
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/prompts.sh"
source "$LIB_DIR/menus.sh"
source "$LIB_DIR/stash.sh"

# CLI flags (--version, --update, --shell-init, --dev, --setup, --wizard)
# main_menu() call
```

L'ordre de source est important : `core.sh` et `ui.sh` en premier car tous les autres modules en dépendent.

## Dépendances

### Requises (auto-installées)

| Dépendance | Rôle |
|---|---|
| **fzf** | Menus interactifs avec preview |
| **gum** | UI : spinners, confirmations, inputs, headers, style |
| **jq** | Parsing JSON pour PR/issues via gh/glab |

### Optionnelles (check seulement)

| Dépendance | Rôle |
|---|---|
| **gh** | Intégration GitHub (PR, issues, CI) |
| **glab** | Intégration GitLab (PR, issues, CI) |
| **claude** | Fonctionnalités IA (prompts, review, fix) |

### Packaging

- **`install.sh`** : auto-installe fzf, gum et jq via le package manager détecté (apt/dnf/pacman/brew). Même logique que l'auto-install fzf actuelle, étendue aux 3.
- **`default.nix`** : ajoute `gum` aux inputs et au `wrapProgram --prefix PATH`. Met à jour la version.
- **Brew formula** (repo `homebrew-wt`) : ajoute `depends_on "gum"` et `depends_on "jq"`.
- **`wt.sh --setup`** : check les 3 dépendances requises au démarrage.

## Module `ui.sh` — Wrappers gum

Toutes les fonctions UI passent par `ui.sh`. gum est requis, pas de fallback.

### Fonctions

| Fonction | Implémentation gum | Remplace |
|---|---|---|
| `ui_success "msg"` | `gum log --level info` avec ✓ vert | `msg "[ok] ..."` |
| `ui_warn "msg"` | `gum log --level warn` avec ⚠ orange | `msg_warn "[!!] ..."` |
| `ui_error "msg"` | `gum log --level error` avec ✗ rouge | `msg "[err] ..."` |
| `ui_spin "title" cmd...` | `gum spin --spinner dot --title "title" -- cmd...` | `loader_start/stop` |
| `ui_confirm "msg"` | `gum confirm "msg"` | `read -p "... [y/N]"` |
| `ui_input "prompt" "placeholder"` | `gum input --prompt "prompt" --placeholder "placeholder"` | `read -p` |
| `ui_header "title"` | `gum style --border rounded --foreground 208 "title"` | `echo "--- title ---"` |
| `ui_box "lines..."` | `gum style --border rounded --padding "0 1" "lines..."` | `echo` brut |

### Remplacement des messages

Les 9 améliorations UI validées :

1. **Messages de statut** — icônes ✓/⚠/✗ via `ui_success`/`ui_warn`/`ui_error`
2. **Spinners** — `gum spin` animé pour fetch, CI check, prompt generation
3. **Confirmations** — `gum confirm` avec boutons Yes/No pour delete, stash drop
4. **Inputs texte** — `gum input` avec placeholder pour nom de branche, feature prefix
5. **Headers de section** — `gum style --border` pour préférences, wizards, settings
6. **Résumés d'action** — `ui_box` après création de worktree (branch, path, editor, claude mode)
7. **Wizard d'installation** — dots colorés ● installed / ○ optional
8. **Menu fzf header** — séparateurs pipes `│` entre raccourcis, `wt` en bold
9. **Transitions séquentielles** — spinner → ✓ pour les opérations multi-étapes

## Logo

### Avant

```
                                   __,,,,_
                    _ __..-;''`--/'/ /.',-`-.
    ...
 |__/|__/ /_/
```

Petit tigre ASCII (~12 lignes, ~50 colonnes), orange monochrome.

### Après

```
 █████   ███   █████ ███████████
░░███   ░███  ░░███ ░█░░░███░░░█    ▓▓▒▒▒  ▒▒▒▒       ▓▓▓███▓▓▓▓▓ ▓▓▓▓▓▓▓▓▓ ▓▓▓▓▓███▓▓▓       ▒▒▒▒  ▒▒▒▓▓
 ░███   ░███   ░███ ░   ░███  ░     ▓▓▒▒▒  ▒▒▒▒▒           ▓██▓▓▓ ▓▓▓▓▓▓▓▓▓ ▓▓▓▓▓▓           ▒▒▒▒▒  ▒▒▒▓▓
 ░███   ░███   ░███     ░███        ▓▓▒▒▒  ▒▒▒▒▒▒▓   ░▒▓▓    ▒█▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ▓▓▒    ▓▒▒▒▒▒▒  ▒▒▒▓▓
 ░░███  █████  ███      ░███        ▓▓▒▒▒  ▒▒ ▒▒▒▓▓   ▒▒▓  ▓   ▒▓▓▓▓▓▓▓▓▓▓▓▓▓▒   ▓  ▓▒▒   ▓▓▒▒▒ ▒▒  ▒▒▒▓▓
  ░░░█████░█████░       ░███        ▓▓▒▒▒  ▒▒  ▒▒▒▓▓    ▒▒▒▒    ▒▒▓▓▓▓▓▓▓▓▓▒▒    ▒▒▒▒    ▓▓▒▒▒  ▒▒  ▒▒▒▓▓
    ░░███ ░░███         █████       ▓▓▒▒▒  ▒▒  ▒▒▒▒▓▓▓█         ▒▒▓▓▓▓▓▓▓▓▓▒▒         █▓▓▓▒▒▒▒  ▒▒  ▒▒▒▓▓
     ░░░   ░░░         ░░░░░
Git Worktree Manager v{VERSION}
```

WT ANSI Shadow à gauche + bande regard tigre à droite (6 lignes). Tout en orange bold (`\033[1;38;5;208m`). Version en dim, collée à gauche.

## Icônes du menu principal

Les actions du menu principal passent d'icônes dim uniformes à des icônes colorées (seule l'icône est colorée, le texte reste normal) :

| Avant | Après | Action |
|---|---|---|
| `›` dim | `+` vert | Create a worktree |
| `◇` dim | `⧉` orange | Manage stashes |
| `×` dim | `✕` rouge | Delete worktree(s) |
| `◦` dim | `⚙` dim | Settings |
| `‹` dim | `↩` dim | Quit |

Les icônes worktree (●, ✓, ◎, ★, ○, *) restent inchangées — elles sont déjà bien.

## Test en local

Le mode `--dev` existant permet de tester le script local :

```bash
eval "$(./wt.sh --dev)"   # Pointe wt vers le script local
wt                         # Utilise le code local + lib/
```

Le `SCRIPT_DIR` dans `wt.sh` résout le dossier `lib/` relativement au script, donc `--dev` fonctionne sans modification après le split.

Pour revenir au mode release : `wt --release`

## Tests

Les tests BATS existants doivent continuer à passer. Le helper `load_wt()` dans `test_helper/common.bash` sera mis à jour pour sourcer les modules dans l'ordre au lieu du fichier unique.

Pas de nouveaux tests pour gum (c'est de l'UI interactive), mais les tests unitaires existants (config, editor, platform, worktree-dir, claude-mode, cli-flags) restent valides et doivent passer.

## Ce qui ne change PAS

- Toute la logique fzf (menus, previews, raccourcis clavier) reste identique
- Les conventions de nommage des worktrees
- Les icônes worktree (●, ✓, ◎, ★, ○, *)
- Les indicateurs PR ([ok], [fail], [..], [draft])
- La convention stdout/stderr (path sur stdout, UI sur stderr)
- Le fichier de config `~/.config/wt/config` et ses clés
- Le mécanisme `--shell-init` / `--dev` / `--release`
- Les completions zsh
