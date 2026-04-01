# Rapport exercice 2 — Étape 3 (Application Angular)

## Objectif
Ajouter un stage `build` au pipeline GitLab CI/CD afin de construire l'image Docker de l'application et de la publier dans le GitLab Container Registry avec des tags lisibles.

## Ce qui a été mis en place

### 1) Nouveau stage `build`
Le fichier `.gitlab-ci.yml` contient maintenant trois stages :
- `test`
- `quality`
- `build`

Le stage `build` s'exécute après les vérifications de tests et de qualité.

### 2) Construction Docker dans GitLab CI
Un job `build_image` a été ajouté.

Ce job utilise :
- l'image `docker:27.5.1-cli`
- le service `docker:27.5.1-dind`
- une connexion au démon Docker via `DOCKER_HOST=tcp://docker:2375`

Le job construit l'image à partir du `Dockerfile` du repository puis la pousse dans le registre de conteneur GitLab.

### 3) Utilisation des variables CI/CD
Le pipeline s'appuie sur les variables GitLab fournies automatiquement :
- `CI_REGISTRY`
- `CI_REGISTRY_USER`
- `CI_REGISTRY_PASSWORD`
- `CI_REGISTRY_IMAGE`
- `CI_COMMIT_SHORT_SHA`
- `CI_COMMIT_REF_SLUG`

Variables de confort ajoutées dans le pipeline :
- `IMAGE_TAG_SHA` = image taguée avec le SHA court du commit
- `IMAGE_TAG_REF_SHA` = image taguée avec le nom de branche + SHA court

### 4) Tags des images publiées
Deux tags sont poussés dans le GitLab Container Registry :
- `${CI_COMMIT_SHORT_SHA}`
- `${CI_COMMIT_REF_SLUG}-${CI_COMMIT_SHORT_SHA}`

Exemple de tag lisible :
- `dev-test-ci-a1b2c3d4`

Ce format permet d'identifier rapidement :
- la branche source
- le commit à l'origine de l'image

### 5) Artefact du stage build
Le job `build_image` publie un artefact `archive.zip` contenant :
- `build-metadata/pushed-images.txt`

Ce fichier liste les tags effectivement poussés vers le registre GitLab.

## Différences de configuration avec le projet Java
Dans le projet Angular :
- l'image Docker embarque une application front statique servie par Nginx ;
- la validation fonctionnelle de l'image est plus simple à faire ensuite avec un test HTTP sur le conteneur ;
- le `Dockerfile` repose sur une construction Node puis un runtime Nginx minimal.

## Points de vigilance appliqués
- Les identifiants du registre GitLab ne sont pas écrits en dur dans le pipeline.
- La connexion au registre passe par les variables CI/CD fournies par GitLab.
- Le push des images est limité aux pipelines déclenchés par `push`.
- La branche de test `dev/test_ci` peut être conservée pour valider ce stage avant merge sur `main`.

## Gestion des differences d'environnement entre local et CI
Le fonctionnement local et le fonctionnement dans GitLab CI ne sont pas strictement identiques. En local, le developpeur dispose de Docker Desktop, d'un navigateur, d'eventuels fichiers `.env` et de ports choisis librement. En CI, le job s'execute dans un environnement ephemere pilote par les images declarees dans le pipeline, sans acces aux fichiers locaux du poste. Pour l'application Angular, cela implique notamment de distinguer le port de developpement habituel (`4200`) du port reel expose par l'image Docker (`8080` dans le conteneur, puis mappe localement). La configuration doit donc rester portable entre poste local, image Docker et pipeline CI, en s'appuyant sur les variables GitLab, les ports explicitement publies et des commandes de validation reproductibles.

## Limite actuelle
Le stage `build` construit et publie l'image, mais il ne réalise pas encore de smoke test automatique du conteneur. Cette vérification pourra être ajoutée ensuite pour confirmer que l'image produite démarre correctement dans l'environnement CI.

## Validation locale de l'image Angular (branche dev)
La validation locale permet de confirmer que l'image publiee depuis la branche `dev/test_ci` demarre correctement avant merge sur `main`.

### Prerequis
- Docker Desktop demarre en local.
- Un compte GitLab avec acces au projet.
- Un token GitLab (PAT) avec au minimum le scope `read_registry`.

### Commandes de validation
1. Se connecter au GitLab Container Registry :

```bash
docker login registry.gitlab.com
```

Renseigner :
- Username : utilisateur GitLab
- Password : token PAT

2. Recuperer l'image de la branche de dev :

```bash
docker pull registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationangular:dev-test-ci-1b070137
```

3. Lancer le conteneur en local :

```bash
docker run -d --name test-angular-local -p 4200:8080 registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationangular:dev-test-ci-1b070137
```

Note importante : le mapping est `4200:8080` car l'image Angular expose le port `8080` dans le conteneur.

4. Verifier l'etat du conteneur :

```bash
docker ps --filter name=test-angular-local
docker logs --tail 100 test-angular-local
```

5. Verifier la reponse HTTP de l'application :

```bash
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4200/
```

Code attendu : `200`

6. Validation visuelle dans le navigateur :

- Ouvrir `http://127.0.0.1:4200`
- Verifier que l'interface Angular se charge

7. Nettoyage local :

```bash
docker rm -f test-angular-local
```

### Critere de succes
L'image de la branche de dev est validee si :
- le conteneur demarre sans erreur bloquante ;
- l'application repond en HTTP `200` ;
- l'interface est accessible dans le navigateur.

## Résultat attendu atteint
- Le pipeline construit une image Docker.
- L'image est poussée dans le GitLab Container Registry.
- Les tags contiennent le SHA du commit et le nom de la branche.
- Le pipeline reste configurable via les variables GitLab CI/CD.

## Prochaine étape
Étape 4 : automatiser la release et la gestion de version, puis éventuellement compléter le pipeline avec un smoke test d'image ou un scan Trivy après build.
