#!/usr/bin/env bash
# Backup consistente de core.sqlite + configuracion del Core.
#
# Uso:  ops/backup.sh
# Env:  AMG_PLATFORM_ROOT, AMG_PLATFORM_BACKUPS, AMG_PLATFORM_BACKUP_RETENTION,
#       AMG_PLATFORM_SERVICE, AMG_PLATFORM_IMAGE
set -euo pipefail

RAIZ="${AMG_PLATFORM_ROOT:-$HOME/projects/amg-platform}"
DESTINO_RAIZ="${AMG_PLATFORM_BACKUPS:-$HOME/backups/amg-platform}"
RETENCION="${AMG_PLATFORM_BACKUP_RETENTION:-14}"
CONTENEDOR="${AMG_PLATFORM_CONTAINER:-amg-platform}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fallar() { log "FALLO: $*"; exit 1; }

[ -d "$RAIZ" ] || fallar "no existe $RAIZ"
[ -f "$RAIZ/ops/sqlite-snapshot.mjs" ] || fallar "falta ops/sqlite-snapshot.mjs"
docker inspect "$CONTENEDOR" >/dev/null 2>&1 || fallar "no existe el contenedor $CONTENEDOR"

IMAGEN="${AMG_PLATFORM_IMAGE:-$(docker inspect -f '{{.Config.Image}}' "$CONTENEDOR")}"
VOLUMEN="${AMG_PLATFORM_VOLUME:-$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/data/core"}}{{.Name}}{{end}}{{end}}' "$CONTENEDOR")}"
[ -n "$IMAGEN" ] || fallar "no se pudo deducir la imagen de $CONTENEDOR"
[ -n "$VOLUMEN" ] || fallar "no se pudo deducir el volumen de $CONTENEDOR"
docker volume inspect "$VOLUMEN" >/dev/null 2>&1 || fallar "no existe el volumen $VOLUMEN"

SELLO="$(date -u '+%Y%m%d-%H%M%S')"
DEST="$DESTINO_RAIZ/$SELLO"
mkdir -p "$DEST/sqlite" "$DEST/config"
chmod 700 "$DEST" "$DEST/sqlite" "$DEST/config"

log "destino : $DEST"
log "imagen  : $IMAGEN"
log "volumen : $VOLUMEN"

if [ -f "$RAIZ/.env" ]; then
  cp -p "$RAIZ/.env" "$DEST/config/.env"
  chmod 600 "$DEST/config/.env"
  log "config  : .env"
else
  log "AVISO   : no existe $RAIZ/.env (no se respalda)"
fi

{
  echo "amg-platform backup $SELLO"
  echo "commit  : $(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo desconocido)"
  echo "host    : $(hostname)"
  echo "generado: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
} > "$DEST/manifest.txt"

if salida=$(docker run --rm \
    -v "$VOLUMEN:/origen" \
    -v "$DEST/sqlite:/fuera" \
    -v "$RAIZ/ops/sqlite-snapshot.mjs:/app/snap.mjs:ro" \
    "$IMAGEN" node /app/snap.mjs "/origen/core.sqlite" "/fuera/core.db" 2>&1); then
  log "OK      : core $salida"
  echo "core $salida" >> "$DEST/manifest.txt"
else
  log "FALLO   : core -> $salida"
  echo "core SIN_INTEGRIDAD" >> "$DEST/manifest.txt"
  touch "$DEST/FAILED"
  exit 1
fi

( cd "$DEST" && find sqlite config -type f -exec sha256sum {} + > SHA256SUMS )
log "sha256  : $(wc -l < "$DEST/SHA256SUMS") archivos"

mapfile -t todos < <(
  find "$DESTINO_RAIZ" -mindepth 1 -maxdepth 1 -type d -name '20*' \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
)

mapfile -t healthy < <(
  for d in ${todos[@]+"${todos[@]}"}; do
    if [ ! -e "$d/FAILED" ]; then printf '%s\n' "$d"; fi
  done
)
if [ "${#healthy[@]}" -gt "$RETENCION" ]; then
  for d in "${healthy[@]:RETENCION}"; do
    [ "$d" = "$DEST" ] && continue
    log "purgando: $d"
    rm -rf "$d"
  done
fi

mapfile -t malos < <(
  for d in ${todos[@]+"${todos[@]}"}; do
    if [ -e "$d/FAILED" ]; then printf '%s\n' "$d"; fi
  done
)
if [ "${#malos[@]}" -gt 3 ]; then
  for d in "${malos[@]:3}"; do
    [ "$d" = "$DEST" ] && continue
    log "purgando backup fallido: $d"
    rm -rf "$d"
  done
fi

ln -sfn "$DEST" "$DESTINO_RAIZ/latest"
log "RESULTADO: OK. $SELLO"
