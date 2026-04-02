# Rapport exercice 2 — Étape 4 (Application Angular)

## Objectif
Mettre en place un stage `release` dans le pipeline GitLab CI/CD pour générer automatiquement les versions, les releases GitLab et les images Docker versionnées, à partir des commits Conventional Commits.

## Concepts fondamentaux

### Conventional Commits
Les messages de commit suivent ce format :

```
<type>(<scope>): <subject>
```

Types et impact sur la version :
- `feat:` → version mineure (MINOR)
- `fix:` → version patch (PATCH)
- `BREAKING CHANGE:` → version majeure (MAJOR)
- `docs:`, `chore:`, `refactor:`, etc. → aucun impact

### Semantic Versioning (SemVer)
Format `X.Y.Z` : X = majeur, Y = mineur, Z = patch.

---

## Ce qui a été mis en place

### 1) Plugins semantic-release

Les dépendances sont installées dans le job CI (pas dans `package.json`) :

```bash
npm install --no-save \
  semantic-release@24.2.3 \
  @semantic-release/npm@13.1.5 \
  @semantic-release/exec@7.1.0 \
  @semantic-release/gitlab@13.3.2 \
  @semantic-release/changelog@6.0.3 \
  @semantic-release/commit-analyzer@13.0.1 \
  @semantic-release/release-notes-generator@14.1.0 \
  @semantic-release/git@10.0.1
```

Rôles des plugins :
| Plugin | Rôle |
|---|---|
| `commit-analyzer` | Détermine le type de version |
| `release-notes-generator` | Génère les notes de release |
| `changelog` | Met à jour `CHANGELOG.md` |
| `npm` | Met à jour la version dans `package.json` |
| `exec` | Lance le script de retag Docker |
| `git` | Commite et pousse les fichiers mis à jour |
| `gitlab` | Crée la release GitLab |

### 2) Configuration `.releaserc.json`

- **branches** : `main` (production), `dev/test_ci` (prerelease `rc`)
- **assets commités** : `package.json`, `package-lock.json`, `CHANGELOG.md`
- **message de commit** : `chore(release): X.Y.Z [skip ci]`
- **publishCmd** : appelle `.release-docker-tag.sh` pour retagger l'image Docker

### 3) Script de retag Docker `.release-docker-tag.sh`

Appelé automatiquement par semantic-release après chaque release. Il :
1. Récupère l'image buildée au SHA courant (`CI_COMMIT_SHORT_SHA`)
2. La retague avec la version sémantique et `latest`
3. Pousse les deux tags dans le Container Registry GitLab

```
registry.gitlab.com/groupe/app:abc123f   → entrée (build_image)
registry.gitlab.com/groupe/app:2.1.0     → sortie (release)
registry.gitlab.com/groupe/app:latest    → sortie (release)
```

### 4) Job `release_angular` dans le pipeline

Ajouté dans `.gitlab-ci.yml`, stage `release` :
- **Déclenchement** : manuel sur `main`, uniquement si `RELEASE_ENABLED == "true"`
- **Anti-boucle** : le job est sauté si le message de commit commence par `chore(release):`
- **Image** : `node:22-bullseye` + service `docker:27.5.1-dind`
- `docker.io` installé en `before_script` pour le retag
- `GIT_DEPTH: "0"` pour que semantic-release lise tout l'historique

### 5) Déroulement d'une release

1. Analyse des commits depuis le dernier tag
2. Génération des notes et du changelog
3. Mise à jour de `package.json` et `package-lock.json`
4. Retag de l'image Docker avec la version et `latest`
5. Commit des fichiers mis à jour + push sur `main`
6. Création de la release et du tag dans GitLab

---

## Variables CI/CD requises

| Variable | Valeur | Options |
|---|---|---|
| `GITLAB_TOKEN` | Personal Access Token | Masked, Protected, scopes : `api` + `read_repository` + `write_repository` |
| `RELEASE_ENABLED` | `true` / `false` | Interrupteur manuel |

---

## Déclencher une release

```bash
# 1. Vérifier que les commits sont en Conventional Commits
git log --oneline -n 10

# 2. Pousser sur main
git push gitlab main

# 3. Dans GitLab → CI/CD → Pipelines → cliquer Play sur release_angular
```

Le CI Lint GitLab (`CI/CD > Pipelines > Validate`) permet de valider la syntaxe du `.gitlab-ci.yml` avant de lancer une vraie pipeline.

---

## Synchronisation de version

| Fichier | Mécanisme |
|---|---|
| `package.json` | Plugin `@semantic-release/npm` (automatique) |
| `CHANGELOG.md` | Plugin `@semantic-release/changelog` (automatique) |

---

## Images Docker versionnées

| Tag | Créé quand | Exemple |
|---|---|---|
| `<SHA>` | Chaque push | `registry.../app:abc123f` |
| `<branche>-<SHA>` | Chaque push | `registry.../app:main-abc123f` |
| `<version>` | Chaque release | `registry.../app:2.1.0` |
| `latest` | Chaque release | `registry.../app:latest` |

### Récupérer une image versionnée

```bash
# Tirer la dernière image de production
docker pull registry.gitlab.com/<namespace>/<projet>:latest

# Tirer une version spécifique
docker pull registry.gitlab.com/<namespace>/<projet>:2.1.0
```

### Retagger manuellement une release passée

Si une release a été créée avant la mise en place du retag automatique, les tags versionnés n'existent pas. Les créer manuellement :

```bash
export REGISTRY=registry.gitlab.com/<namespace>/<projet>
export SHA=<sha_court_du_commit_build>
export VERSION=2.0.1

docker pull $REGISTRY:$SHA
docker tag $REGISTRY:$SHA $REGISTRY:$VERSION
docker tag $REGISTRY:$SHA $REGISTRY:latest
docker push $REGISTRY:$VERSION
docker push $REGISTRY:latest
```

Le SHA du commit se trouve dans GitLab → Repository → Commits, ou via :
```bash
git log --oneline | grep -B1 "chore(release): 2.0.1"
```

---

## Erreurs rencontrées et corrections

**YAML invalide dans le script CI.** La syntaxe `test -n "$VAR" || (echo ... && exit 1)` n'est pas acceptée dans un bloc YAML multi-lignes. Corrigé en utilisant un bloc `if/fi` standard.

**`@semantic-release/gitlab@^14` n'existe pas.** La version 14 n'a jamais été publiée sur npm. Corrigé en utilisant `^13.3.2`.

**Les tests Angular échouaient à cause des deps semantic-release dans `package.json`.** Les plugins étaient détectés et installés lors du `npm ci` de test. Corrigé en les retirant du `package.json` et en les installant uniquement dans le job `release_angular`.

**Détection Angular incorrecte basée sur `package.json`.** Les scripts de test utilisaient la présence de `package.json` pour détecter un projet Angular. Corrigé en utilisant `angular.json` comme critère.

**Deux pipelines "Skipped" après une release.** Comportement normal : semantic-release pousse un commit et un tag, chacun peut déclencher une pipeline GitLab. Les deux ont `[skip ci]` donc sont automatiquement sautés.

---

## Résultat

- ✅ semantic-release installé et configuré pour GitLab
- ✅ Stage `release` présent dans le pipeline
- ✅ Convention Conventional Commits adoptée
- ✅ Releases GitLab générées automatiquement avec changelog
- ✅ Images Docker taguées avec la version sémantique et `latest`
- ✅ Déclenchement manuel via `RELEASE_ENABLED`
- ✅ Version synchronisée dans `package.json`


### Conventional Commits
La convention Conventional Commits structure les messages de commit selon un format standard :

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types acceptés (utilisés pour la versioning) :
- `feat:` → version mineure (MINOR)
- `fix:` → version patch (PATCH)
- `BREAKING CHANGE:` → version majeure (MAJOR)
- `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:` → aucun impact de version

Exemple :
- `fix(api): corriger la connexion Postgres` → version 1.0.1 (patch)
- `feat(ui): ajouter pagination` → version 1.1.0 (minor)
- `BREAKING CHANGE: suppression endpoint /v1` → version 2.0.0 (major)

### Semantic Versioning (SemVer)
Le format X.Y.Z représente :
- X = version majeure (breaking changes)
- Y = version mineure (features)
- Z = version patch (fixes)

## Ce qui a été mis en place

### 1) Installation de semantic-release

Les dépendances sont installées **à la volée dans le job CI** (pas dans `package.json`) pour ne pas interférer avec les tests Angular :

```bash
npm install --no-save semantic-release@24.2.3 \
  @semantic-release/npm@13.1.5 \
  @semantic-release/exec@7.1.0 \
  @semantic-release/gitlab@13.3.2 \
  @semantic-release/changelog@6.0.3 \
  @semantic-release/commit-analyzer@13.0.1 \
  @semantic-release/release-notes-generator@14.1.0 \
  @semantic-release/git@10.0.1
```

Plugins utilisés :
- `semantic-release` — moteur principal
- `@semantic-release/npm` — mise à jour de `package.json` (non publié sur npm)
- `@semantic-release/exec` — exécution de scripts custom (retag Docker)
- `@semantic-release/git` — commit + push auto des mises à jour
- `@semantic-release/changelog` — génération CHANGELOG.md
- `@semantic-release/gitlab` — création de releases GitLab

### 2) Fichier de configuration `.releaserc.json`

Le fichier `.releaserc.json` définit :
- **branches** : `main` en produit, `dev/test_ci` en prerelease (version rc)
- **plugins** : l'ordre et config de chaque étape (analyze, generate, changelog, npm, git, gitlab)
- **assets** : fichiers à commiter (package.json, package-lock.json, CHANGELOG.md)
- **message** : format du commit auto généré

### 3) Script de retag Docker `.release-docker-tag.sh`

Le fichier `.release-docker-tag.sh` est appelé par semantic-release via `@semantic-release/exec publishCmd` :
- Reçoit la version en paramètre : `${nextRelease.version}`
- Se connecte au GitLab Container Registry (`docker login`)
- Récupère l'image taguée SHA du commit courant
- La retague avec le numéro de version sémantique (ex: `2.0.2`) et `latest`
- Pousse les deux tags dans le registry

Exemple :
```bash
# Source (créée par build_image)
registry.gitlab.com/groupe/app:abc123f

# Tags créés après release
registry.gitlab.com/groupe/app:2.0.2
registry.gitlab.com/groupe/app:latest
```

### 4) Stage `release` au pipeline

Un job `release_angular` a été ajouté au `.gitlab-ci.yml` :
- Déclenché **manuellement** sur la branche `main` (sécurité)
- Règle spéciale : n'exécute pas si commit commence par `chore(release):` (évite boucles)
- Utilise l'image `node:22-bullseye` avec un service **Docker-in-Docker** (`docker:27.5.1-dind`)
- Installe `docker.io` en `before_script` pour pouvoir appeler Docker CLI
- Variables `DOCKER_HOST` et `DOCKER_TLS_CERTDIR` configurées pour le dind
- Injecte `GITLAB_TOKEN` pour authentifier les push vers GitLab

### 5) Comportement du release

Quand le job `release_angular` s'exécute :
1. **Analyzer** : lit les commits depuis la dernière version, détecte type (major/minor/patch)
2. **Release Notes** : génère la liste des changements
3. **Changelog** : ajoute/met à jour CHANGELOG.md
4. **NPM** : met à jour `package.json` + `package-lock.json`
5. **Exec** (`publishCmd`) : `.release-docker-tag.sh X.Y.Z` — retag Docker avec la version
6. **Git** : commit + push les fichiers mis à jour sur main
7. **GitLab** : crée une release GitLab avec tags et notes

## Variables CI/CD requises

### Token GitLab (GITLAB_TOKEN)

À créer dans GitLab > Project > Settings > CI/CD > Variables :

**Propriétés** :
- Clé : `GITLAB_TOKEN`
- Valeur : Personal Access Token (PAT)
- Visibilité : **Masked and hidden**
- Protection : Checked (main seulement)
- Scopes recommandés : `api` + `read_repository` + `write_repository`

Alternative locale en développement :
- Utiliser `CI_JOB_TOKEN` automatique (fourni par GitLab CI)
- Valable seulement dans le contexte du pipeline

### Configuration supplémentaire

`CI_JOB_TOKEN` est injecté automatiquement par GitLab CI et permet l'accès restreint au dépôt pendant l'exécution du job. C'est plus sûr qu'un PAT exposé.

## Comment utiliser le release en CI

### Avant de déclencher

Vérifier que les commits récents respectent Conventional Commits :
```bash
git log --oneline -n 10
# Attendu : des lignes comme "fix(...):", "feat(...):)", etc.
```

### Déclencher manuellement un release

Dans GitLab UI :
1. Aller à CI/CD > Pipelines
2. Créer une nouvelle pipeline (ou attendre un push) sur `main`
3. Le job `release_angular` apparaît avec un bouton **Play** (manual job)
4. Cliquer pour lancer le release

Avant l'execution, il est possible de verifier la syntaxe du pipeline avec l'outil integre GitLab **Validate your GitLab CI configuration** (CI Lint). Cet ecran permet de valider le fichier `.gitlab-ci.yml` et de detecter rapidement les erreurs YAML ou de structure des jobs avant de lancer une pipeline reelle.

Via CLI (si accès):
```bash
git push origin main
# Attendre la pipeline GitLab
# Puis declarer manuellement depuis l'interface GitLab
```

### Logs et résultat

Le job `release_angular` affiche :
- Analyse des commits : `Found X commits since last release`
- Version générée : `Publishing version X.Y.Z`
- URL de la release : lien GitLab Releases

### Résultat visible dans GitLab

Dans GitLab UI :
- Project > Releases : nouvelle entry avec tag versionné, changelog, assets
- Project > Tags : nouveau tag de version
- Commits : commit auto généré `chore(release): X.Y.Z`

## Synchronisation de version

### Angular

La version dans `package.json` est mise à jour automatiquement par le plugin `@semantic-release/npm` du projet Angular. Aucune action manuelle nécessaire.

Il n'y a donc pas de script `.release-prepare.sh` côté Angular : la mise à jour de version est gérée nativement par les plugins semantic-release (`@semantic-release/npm` puis `@semantic-release/git`).

### Images Docker

Les images publiées dans le stage `build` reçoivent deux tags basés sur le SHA : `<sha>` et `<branche>-<sha>`.  
**À chaque release**, le script `.release-docker-tag.sh` retaggue automatiquement l'image avec la version sémantique et `latest` :

| Tag | Quand | Exemple |
|---|---|---|
| `<SHA>` | À chaque push | `registry.../app:abc123f` |
| `<branche>-<SHA>` | À chaque push | `registry.../app:main-abc123f` |
| `<version>` | À chaque release | `registry.../app:2.0.2` |
| `latest` | À chaque release | `registry.../app:latest` |

### Récupération manuelle des images d'une release passée

Si une release a été effectuée **avant** la mise en place du retag automatique (ex: v2.0.1), les images versionnées n'ont pas été créées. Pour les retrouver ou les créer manuellement :

**Étape 1** — Identifier le SHA du commit de build correspondant :
```bash
# Dans la pipeline GitLab : colonne "SHA" ou via
git log --oneline | grep -B5 "chore(release): 2.0.1"
```

**Étape 2** — Retagger manuellement depuis votre poste :
```bash
export REGISTRY=registry.gitlab.com/<namespace>/<projet>
export SHA=<sha_court_du_commit>

docker pull $REGISTRY:$SHA
docker tag $REGISTRY:$SHA $REGISTRY:2.0.1
docker tag $REGISTRY:$SHA $REGISTRY:latest
docker push $REGISTRY:2.0.1
docker push $REGISTRY:latest
```

Ou directement dans **GitLab UI** : Container Registry > sélectionner le tag SHA > copier l'image > retagger via API GitLab.

## Points de vigilance appliqués

- Le token GitLab n'est pas exprimé en dur dans le pipeline.
- L'authentification passe via `GITLAB_TOKEN` (variable de projet maskée).
- Le job `release_angular` ne se déclenche **que manuellement** pour éviter les releases accidentelles.
- Les commits auto-générés par semantic-release commencent par `chore(release):` pour éviter une loop.
- Le `publishCmd` de `@semantic-release/exec` n'est exécuté que si une release est réellement générée (pas de retag inutile si aucun commit releasable).
- La branche `dev/test_ci` peut produire des prerelease (version rc) sans interférer avec les releases main.
- Le validateur intégré GitLab CI Lint est utile pour contrôler le `.gitlab-ci.yml` avant exécution.

## Résultat attendu atteint

- ✅ semantic-release est installé et configuré pour GitLab.
- ✅ Un stage `release` est présent au pipeline avec un job `release_angular` manuel.
- ✅ La convention Conventional Commits est documentée et adoptée.
- ✅ Les releases GitLab sont générées automatiquement avec changelog.
- ✅ Les images Docker sont taguées avec la version sémantique (ex: `2.0.2`, `latest`).
- ✅ Le job de release se déclenche manuellement sur `main` (gate `RELEASE_ENABLED`).
- ✅ La version est synchronisée dans `package.json` via `@semantic-release/npm`.

## Prochaines étapes

1. Vérifier la génération de la release GitLab, du changelog et des images versionnées.
2. Retagger manuellement les images de la release v2.0.1 si nécessaire (voir commandes ci-dessus).
3. Mettre en place le Conventional Commits pour tous les futurs commits.
