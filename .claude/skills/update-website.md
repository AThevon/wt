# update-website

Met à jour le site officiel wt-site suite aux changements du package wt.

## Instructions

Tu dois effectuer les étapes suivantes :

### 1. Analyser les changements récents sur wt

- Lire les commits récents avec `git log --oneline -10`
- Identifier les changements importants (nouvelles features, corrections de bugs, modifications de comportement)
- Lire le fichier `wt.sh` pour comprendre les fonctionnalités actuelles
- Lire le `README.md` pour voir la documentation actuelle du package

### 2. Naviguer vers le projet wt-site

- Aller dans le dossier `../wt-site` (par rapport au projet wt actuel)
- Vérifier que tu es sur la branche main et que le repo est à jour avec `git pull`

### 3. Créer une branche pour les modifications

- Créer une nouvelle branche avec un nom descriptif basé sur les changements, par exemple : `update-docs-v1.x.x` ou `sync-website-[feature]`

### 4. Mettre à jour le site web

Analyser et mettre à jour les fichiers suivants selon les changements détectés :

**Homepage** (`src/app/page.tsx` ou similaire) :
- Mettre à jour les features mises en avant
- Actualiser les exemples si nécessaire
- Vérifier que les badges de version sont corrects

**Documentation** (`docs/` ou `src/app/docs/`) :
- Mettre à jour la documentation des commandes
- Ajouter/modifier les exemples d'utilisation
- Documenter les nouvelles options ou flags
- Mettre à jour les instructions d'installation si nécessaire

### 5. Commit et Push

- Faire un commit avec un message clair décrivant les mises à jour
- Pousser la branche sur le remote

### 6. Créer la Pull Request

- Utiliser `gh pr create` pour créer une PR
- Le titre doit être descriptif (ex: "docs: sync website with wt v1.4.0 changes")
- Le body doit lister les changements effectués sur le site

## Notes importantes

- Toujours vérifier que le site compile correctement avant de créer la PR
- Ne pas modifier le style ou le design sauf si c'est explicitement demandé
- Se concentrer sur le contenu et la documentation
- Retourner l'URL de la PR à la fin
