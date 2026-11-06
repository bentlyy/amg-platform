#!/usr/bin/env bash
# Despliegue idempotente del Core en el servidor.
#
# Uso:  AMG_REF=<sha|origin/main> ops/deploy.sh
# Env:  AMG_PLATFORM_ROOT, AMG_REF, AMG_PLATFORM_HEALTH
set -euo pipefail

RAIZ="${AMG_PLATFORM_ROOT:-$HOME/projects/amg-platform}"
REF="${AMG_REF:-origin/main}"
SALUD="${AMG_PLATFORM_HEALTH:-http://127.0.0.1:3108/health}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fallar() { log "FALLO: $*"; exit 1; }

cd "$RAIZ"

log "fetch"
git fetch --prune origin

log "checkout $REF"
git checkout -f "$REF"

log "build"
docker compose build platform

log "up"
docker compose up -d --no-deps platform

log "health $SALUD"
for _ in $(seq 1 30); do
  if curl -fsS "$SALUD" >/dev/null 2>&1; then
    log "RESULTADO: OK ($(git rev-parse --short HEAD))"
    exit 0
  fi
  sleep 2
done

docker compose logs --tail=80 platform || true
fallar "el Core no respondio en $SALUD"
