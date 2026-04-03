# Rapport — Exercice 3 Étape 2 : Charts Helm

## Objectif

Transformer les manifestes Kubernetes validés en étape 1 en deux charts Helm fonctionnels :
- `olympic-tracker-chart` (application Angular)
- `workshop-api-chart` (application Java Spring Boot + PostgreSQL)

---

## Prérequis validés

| Prérequis | Statut |
|---|---|
| Déploiement Kubernetes fonctionnel (étape 1) | ✅ |
| Helm installé (`v4.1.3`) | ✅ |
| Minikube actif (contexte `minikube`, k8s v1.30.11) | ✅ |
| Images publiées dans GitLab Registry (`2.1.0`) | ✅ |

---

## Structure des charts créés

### Chart Angular — `olympic-tracker-chart`

```
DevOps_proj4_ApplicationAngular/helm/olympic-tracker-chart/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    └── service.yaml
```

### Chart Java — `workshop-api-chart`

```
DevOps_proj4_ApplicationJava/helm/workshop-api-chart/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment-app.yaml
    ├── service-app.yaml
    ├── deployment-db.yaml
    ├── service-db.yaml
    ├── pvc-db.yaml
    ├── secret-db.yaml
    └── configmap-db.yaml
```

---

## Valeurs extraites dans `values.yaml`

### Angular (`olympic-tracker-chart`)

| Clé | Valeur |
|---|---|
| `image.repository` | `registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationangular` |
| `image.tag` | `2.1.0` |
| `image.pullPolicy` | `Always` |
| `image.pullSecretName` | `gitlab-registry-secret` |
| `service.type` | `LoadBalancer` |
| `service.port` | `80` |
| `service.targetPort` | `8080` |
| `replicaCount` | `1` |

### Java (`workshop-api-chart`)

| Clé | Valeur |
|---|---|
| `image.repository` | `registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationjava` |
| `image.tag` | `2.1.0` |
| `image.pullSecretName` | `gitlab-registry-secret` |
| `service.port` | `8080` |
| `database.image` | `postgres:13` |
| `database.name` | `workshopsdb` |
| `database.storage` | `1Gi` |
| `database.secret.create` | `false` (secret externe) |
| `database.secret.existingSecretName` | `workshop-db-secret` |
| `database.secret.usernameKey` | `POSTGRES_USER` |
| `database.secret.passwordKey` | `POSTGRES_PASSWORD` |

---

## Gestion des secrets

Le chart Java utilise un **secret Kubernetes externe** (`database.secret.create: false`) pour ne jamais stocker de mot de passe dans Git.

Le secret `workshop-db-secret` est créé manuellement (local) ou via pipeline GitLab CI (staging/prod) :

```bash
kubectl -n java-app create secret generic workshop-db-secret \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Les variables `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` sont définies dans GitLab CI/CD Variables (Protected + Masked + Hidden) avec scope par environnement (`dev`, `staging`, `prod`).

---

## Versioning

| Élément | Valeur |
|---|---|
| Chart version (`Chart.yaml`) | `0.1.0` |
| App version (`appVersion`) | `2.1.0` |
| Image tag (`values.yaml`) | `2.1.0` |

Convention adoptée :
- `version` (chart) : semver, incrémenté à chaque modification du chart
- `appVersion` : aligné sur le tag CI/CD de l'image Docker

---

## Validation des charts

### `helm lint`

```
==> Linting olympic-tracker-chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

==> Linting workshop-api-chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

### `helm template` (rendu)

```
56 lignes générées  → angular-rendered.yaml
175 lignes générées → java-rendered.yaml
```

### `helm install --dry-run --debug`

```
ANGULAR_DRYRUN_OK
JAVA_DRYRUN_OK
```

---

## Déploiement réel

### Commandes exécutées

```bash
# Création du secret DB (valeurs dev depuis .env_AppJava)
kubectl -n java-app create secret generic workshop-db-secret \
  --from-literal=POSTGRES_USER="workshops_user" \
  --from-literal=POSTGRES_PASSWORD="<masked>"

# Installation Angular
helm upgrade --install olympic-tracker \
  DevOps_proj4_ApplicationAngular/helm/olympic-tracker-chart \
  --namespace angular-app --create-namespace

# Installation Java
helm upgrade --install workshop-api \
  DevOps_proj4_ApplicationJava/helm/workshop-api-chart \
  --namespace java-app --create-namespace \
  --set database.name="workshopsdb"
```

### Résultat `helm list -A`

```
NAME            NAMESPACE    REVISION  STATUS    CHART                      APP VERSION
olympic-tracker angular-app  1         deployed  olympic-tracker-chart-0.1.0  2.1.0
workshop-api    java-app     2         deployed  workshop-api-chart-0.1.0     2.1.0
```

### Résultat `kubectl get pods -A`

```
NAMESPACE    NAME                                                    READY  STATUS   RESTARTS  AGE
angular-app  olympic-tracker-olympic-tracker-chart-98dbdc8c4-zpz9b  1/1    Running  0         16m
java-app     workshop-api-workshop-api-chart-7f49445458-lmx8p       1/1    Running  0         3m24s
java-app     workshop-api-workshop-api-chart-db-84b6fd4478-zt698    1/1    Running  1         3m23s
```

---

## Points de vigilance respectés

| Point | Action |
|---|---|
| Ne pas sur-variabiliser | Seules les valeurs réellement variables sont dans `values.yaml` |
| Noms de ressources uniques | Utilisation des helpers Helm (`fullname`, `dbFullname`) |
| YAML valide | `helm lint` 0 erreur sur les deux charts |
| PostgreSQL inclus dans le chart Java | `deployment-db.yaml`, `service-db.yaml`, `pvc-db.yaml` dans `workshop-api-chart` |
| Pas de secret en clair dans Git | `database.secret.create: false`, secret K8s créé hors Git |

---

## Résultat

✅ Deux charts Helm fonctionnels créés  
✅ Manifestes Kubernetes migrés dans `templates/`  
✅ Valeurs variables extraites dans `values.yaml`  
✅ Fonctions Helm (`{{ .Values.xxx }}`, helpers `_helpers.tpl`) utilisées  
✅ `helm lint` sans erreur sur les deux charts  
✅ `helm install --dry-run --debug` réussi  
✅ Applications déployées et pods `Running` via `helm install`
