# Préparation image Docker App Angular

## 1) Exécuter le build local

```bash
npm run build
```

Output attendu : `dist/olympic-games-starter`

## 2) Préparer un Dockerfile multi-stage

- Stage 1 avec Node (build Angular via `npm ci --cache .npm --prefer-offline` puis `npm run build`)
- Stage 2 avec Nginx pour servir le front

Dans le stage Nginx, copier uniquement les artefacts statiques générés (pas de sources, pas de `node_modules`) et utiliser la config Nginx du projet pour le fallback SPA (`try_files ... /index.html`).

- Stage build (`node:22.22.0-alpine`) :
	- `WORKDIR /app`
	- copier `package*.json`
	- lancer `npm ci --cache .npm --prefer-offline`
	- copier le reste du code
	- lancer `npm run build`

- Stage runtime (`nginx:1.27-alpine`) :
	- copier la conf Nginx vers `/etc/nginx/nginx.conf`
	- copier `dist/olympic-games-starter/browser` vers `/app`
	- exposer le port 80
	- démarrer Nginx en foreground (`daemon off;`)

Utilisation d'Alpine pour avoir des images réduites, idéal pour Nginx.

### Résultat Dockerfile

- Multi-stage OK (`node:22.22.0-alpine` pour build, `nginx:1.27-alpine` pour runtime)
- Build Angular avec `npm ci --cache .npm --prefer-offline` puis `npm run build`
- Image finale avec Nginx + artefacts `dist`
- Démarrage Nginx en foreground (`daemon off;`)

Tests :

```bash
docker build -t olympic-tracker:test .
docker run --rm -p 8080:80 olympic-tracker:test
```

Validation : `http://localhost:8080` OK

## 3) Préparer `.dockerignore`

- Exclut `node_modules`, `dist`, `.git`, `.angular`, logs, rapports…
- Réduit le build context Docker, accélère `docker build`, évite d’embarquer des fichiers inutiles.

## 4) Préparer `docker-compose.yml`

- Définit un service unique `olympic-tracker`
- Build depuis `.` avec le Dockerfile
- Publie le port `80:80`
- Redémarre automatiquement (`unless-stopped`)

Validation de cohérence :

```bash
docker compose config
```

Extrait validé :

```yaml
name: devops_proj4_applicationangular
services:
	olympic-tracker:
		build:
			context: C:\perso\formation\projet_4\exercice\DevOps_proj4_ApplicationAngular
			dockerfile: Dockerfile
		image: olympic-tracker:local
		networks:
			olympic-tracker-net: null
		ports:
			- mode: ingress
				target: 80
				published: "80"
				protocol: tcp
		restart: unless-stopped
networks:
	olympic-tracker-net:
		name: olympic-tracker-net
```

Test :

```bash
docker compose up -d --build
docker compose ps
```

Exemple de statut :

```text
devops_proj4_applicationangular-olympic-tracker-1   olympic-tracker:local   Up   0.0.0.0:80->80/tcp
```

Validation : `http://localhost` OK

## Vérifications avec `curl`

```bash
# Test HTTP + en-têtes
curl -i http://localhost

# Test statut uniquement
curl -o /dev/null -s -w "%{http_code}\n" http://localhost

# Vérifier que la page contient du HTML Angular
curl -s http://localhost | head -n 20
```

## Arrêt

```bash
docker compose stop
docker compose start
docker compose down
```

## Rappel ports

| Mode      | Outil      | Port |
|-----------|------------|------|
| Dev local | `ng serve` | 4200 |
| Docker    | `Nginx`    | 80   |

## 5) Scan Trivy sur image locale

olympic-tracker:local (alpine 3.21.3)
=====================================
Total: 66 (UNKNOWN: 0, LOW: 9, MEDIUM: 37, HIGH: 15, CRITICAL: 5)

