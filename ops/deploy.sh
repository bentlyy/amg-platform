#!/usr/bin/env bash
# Despliegue idempotente del Core en el servidor.
#
# Uso:  AMG_REF=<sha|origin/main> ops/deploy.sh
# Env:  AMG_PLATFORM_ROOT, AMG_REF, AMG_PLATFORM_HEALTH, AMG_PLATFORM_CONTAINER,
#       AMG_SKIP_BACKUP, AMG_NGINX_CONF
set -euo pipefail

RAIZ="${AMG_PLATFORM_ROOT:-$HOME/projects/amg-platform}"
REF="${AMG_REF:-origin/main}"
SALUD="${AMG_PLATFORM_HEALTH:-http://127.0.0.1:3108/health}"
CONTENEDOR="${AMG_PLATFORM_CONTAINER:-amg-platform}"
NGINX_CONF="${AMG_NGINX_CONF:-$RAIZ/ops/nginx/amgdeveloper.conf}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fallar() { log "FALLO: $*"; exit 1; }

cd "$RAIZ"

log "fetch"
git fetch --prune origin

log "checkout $REF"
git checkout -f "$REF"

if [ "${AMG_SKIP_BACKUP:-0}" = "1" ]; then
  log "backup pre-deploy: omitido (AMG_SKIP_BACKUP=1)"
elif docker inspect "$CONTENEDOR" >/dev/null 2>&1; then
  log "backup pre-deploy"
  AMG_PLATFORM_ROOT="$RAIZ" bash "$RAIZ/ops/backup.sh"
else
  log "backup pre-deploy: omitido (no existe $CONTENEDOR)"
fi

if ! command -v nginx >/dev/null 2>&1; then
  log "nginx no instalado; se omite"
elif [ ! -f "$NGINX_CONF" ]; then
  log "AVISO: no existe $NGINX_CONF; no se instala nginx"
elif ! sudo -n true >/dev/null 2>&1; then
  log "AVISO: sudo sin contrasena no disponible; no se instala nginx"
else
  destino=/etc/nginx/conf.d/amgdeveloper.conf
  if sudo -n diff -q "$NGINX_CONF" "$destino" >/dev/null 2>&1; then
    log "nginx: sin cambios"
  else
    respaldo="$(mktemp)"
    publicado="$(mktemp)"
    existia=0
    if sudo -n test -f "$destino"; then
      existia=1
      sudo -n cp "$destino" "$respaldo"
    fi
    sudo -n cp "$NGINX_CONF" "$publicado"
    sudo -n cp "$publicado" "$destino"
    sudo -n chmod 0644 "$destino"
    if sudo -n nginx -t >/dev/null 2>&1; then
      sudo -n systemctl reload nginx
      log "nginx: config actualizada y recargada"
    else
      if [ "$existia" -eq 1 ]; then
        sudo -n cp "$respaldo" "$destino"
      else
        sudo -n rm -f "$destino"
      fi
      log "AVISO: nginx -t fallo con la config nueva; se restauro la anterior"
    fi
    rm -f "$respaldo" "$publicado"
  fi
fi

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
