#!/usr/bin/env bash
# Restaura core.sqlite desde un backup de ops/backup.sh.
#
#   bash ops/restore.sh <backup-dir> [--force]
#   bash ops/restore.sh latest
#
# Sin --force no toca un contenedor que este corriendo. Con --force lo detiene,
# restaura, lo vuelve a arrancar y verifica /health. Antes de reemplazar la BD
# deja una copia consistente en core.sqlite.pre-restore; si el Core no vuelve a
# responder, intenta recuperar esa copia automaticamente.
set -euo pipefail

RAIZ="${AMG_PLATFORM_ROOT:-$HOME/projects/amg-platform}"
BACKUPS="${AMG_PLATFORM_BACKUPS:-$HOME/backups/amg-platform}"
CONTENEDOR="${AMG_PLATFORM_CONTAINER:-amg-platform}"
SALUD="${AMG_PLATFORM_HEALTH:-http://127.0.0.1:3108/health}"
FUERZA=0

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || { echo "uso: $0 <backup-dir|latest> [--force]" >&2; exit 2; }
case "${2:-}" in
  --force) FUERZA=1 ;;
  "") ;;
  *) echo "argumento desconocido: $2" >&2; exit 2 ;;
esac

BACKUP="$1"
if [ "$BACKUP" = "latest" ]; then
  BACKUP="$BACKUPS/latest"
fi
[ -d "$BACKUP" ] || die "no existe el backup: $BACKUP"
BACKUP="$(cd "$BACKUP" && pwd -P)"
SNAP="$BACKUP/sqlite/core.db"
[ -f "$SNAP" ] || die "el backup no tiene sqlite/core.db"

if [ -f "$BACKUP/FAILED" ] && [ "$FUERZA" -ne 1 ]; then
  die "el backup esta marcado como fallido; repite con --force si de verdad quieres restaurarlo"
fi

for requerido in docker curl sha256sum mktemp awk; do
  command -v "$requerido" >/dev/null 2>&1 || die "falta el comando $requerido"
done
docker info >/dev/null 2>&1 || die "Docker no responde"
docker inspect "$CONTENEDOR" >/dev/null 2>&1 || die "no existe el contenedor $CONTENEDOR"
[ -f "$RAIZ/ops/sqlite-snapshot.mjs" ] || die "falta $RAIZ/ops/sqlite-snapshot.mjs"

IMAGEN="${AMG_PLATFORM_IMAGE:-$(docker inspect -f '{{.Config.Image}}' "$CONTENEDOR")}"
VOLUMEN="${AMG_PLATFORM_VOLUME:-$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/data/core"}}{{.Name}}{{end}}{{end}}' "$CONTENEDOR")}"
[ -n "$IMAGEN" ] || die "no se pudo deducir la imagen de $CONTENEDOR"
[ -n "$VOLUMEN" ] || die "no se pudo deducir el volumen de $CONTENEDOR"
docker volume inspect "$VOLUMEN" >/dev/null 2>&1 || die "no existe el volumen $VOLUMEN"

log "origen : $BACKUP"
log "imagen : $IMAGEN"
log "volumen: $VOLUMEN"

if [ -f "$BACKUP/SHA256SUMS" ]; then
  ( cd "$BACKUP" && sha256sum -c --quiet SHA256SUMS ) \
    && log "SHA256SUMS del backup: OK" \
    || die "el backup esta corrupto; no se restaura"
else
  log "AVISO: el backup no tiene SHA256SUMS"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$SNAP" "$TMP/inspeccion.db"
docker run --rm -v "$TMP:/d" "$IMAGEN" node -e '
  const D = require("better-sqlite3");
  const db = new D("/d/inspeccion.db", { readonly: true, fileMustExist: true });
  const ok = db.pragma("integrity_check", { simple: true });
  if (ok !== "ok") { console.error("integridad: " + ok); process.exit(1); }

  const requeridas = ["users", "organizations", "memberships", "sso_clients"];
  const tablas = new Set(db.prepare("select name from sqlite_master where type = ?")
    .all("table").map(r => r.name));
  const faltan = requeridas.filter(t => !tablas.has(t));
  if (faltan.length) {
    console.error("la copia no parece un core.sqlite central; faltan tablas: " + faltan.join(", "));
    process.exit(1);
  }

  const n = (t) => db.prepare(`select count(*) as n from ${t}`).get().n;
  console.log(`  integridad: OK (${n("users")} usuarios, ${n("organizations")} organizaciones, ${n("sso_clients")} clientes SSO)`);
  db.close();'

CORRIENDO="$(docker inspect -f '{{.State.Running}}' "$CONTENEDOR")"
if [ "$CORRIENDO" = "true" ]; then
  [ "$FUERZA" -eq 1 ] || die "$CONTENEDOR esta corriendo; usa --force para restaurar encima"
  log "deteniendo $CONTENEDOR"
  docker stop --time 30 "$CONTENEDOR" >/dev/null
fi

HABIA_ACTUAL=0
if docker run --rm -v "$VOLUMEN:/d" "$IMAGEN" test -f /d/core.sqlite; then
  HABIA_ACTUAL=1
  log "respaldando la BD actual como core.sqlite.pre-restore"
  if ! docker run --rm \
    -v "$VOLUMEN:/d" \
    -v "$RAIZ/ops/sqlite-snapshot.mjs:/app/snap.mjs:ro" \
    "$IMAGEN" node /app/snap.mjs /d/core.sqlite /d/core.sqlite.pre-restore >/dev/null; then
    if [ "$CORRIENDO" = "true" ]; then docker start "$CONTENEDOR" >/dev/null; fi
    die "no se pudo respaldar la BD actual; no se restauro nada"
  fi
else
  log "AVISO: el volumen no tiene una BD actual; no hay core.sqlite.pre-restore"
fi

volver_a_previa() {
  if [ "$HABIA_ACTUAL" -ne 1 ]; then
    return 0
  fi
  log "ROLLBACK: restaurando core.sqlite.pre-restore"
  docker run --rm --user root \
    -v "$VOLUMEN:/destino" \
    "$IMAGEN" sh -c 'cp /destino/core.sqlite.pre-restore /destino/core.sqlite && rm -f /destino/core.sqlite-wal /destino/core.sqlite-shm && chown 1000:1000 /destino/core.sqlite && chmod 600 /destino/core.sqlite'
}

log "restaurando $(basename "$BACKUP")"
if ! docker run --rm --user root \
  -v "$VOLUMEN:/destino" \
  -v "$SNAP:/origen/core.db:ro" \
  "$IMAGEN" sh -c 'cp /origen/core.db /destino/core.sqlite && rm -f /destino/core.sqlite-wal /destino/core.sqlite-shm && chown 1000:1000 /destino/core.sqlite && chmod 600 /destino/core.sqlite'; then
  volver_a_previa || true
  if [ "$CORRIENDO" = "true" ]; then docker start "$CONTENEDOR" >/dev/null || true; fi
  die "no se pudo copiar el backup al volumen"
fi

SHA_ORIGEN="$(sha256sum "$SNAP" | awk '{print $1}')"
SHA_DESTINO="$(docker run --rm --user root -v "$VOLUMEN:/d" "$IMAGEN" sha256sum /d/core.sqlite | awk '{print $1}')"
if [ "$SHA_ORIGEN" != "$SHA_DESTINO" ]; then
  volver_a_previa || true
  if [ "$CORRIENDO" = "true" ]; then docker start "$CONTENEDOR" >/dev/null || true; fi
  die "la copia restaurada no coincide con el backup"
fi

arrancar_y_esperar() {
  local intento
  docker start "$CONTENEDOR" >/dev/null
  for intento in $(seq 1 30); do
    if curl -fsS --max-time 5 "$SALUD" >/dev/null 2>&1; then
      log "health: OK tras ${intento} intento(s)"
      return 0
    fi
    sleep 2
  done
  return 1
}

if arrancar_y_esperar; then
  log "RESULTADO: OK. Restaurado desde $BACKUP"
  if [ "$HABIA_ACTUAL" -eq 1 ]; then
    log "la BD anterior queda en $VOLUMEN:core.sqlite.pre-restore"
  fi
  exit 0
fi

docker logs --tail=80 "$CONTENEDOR" || true
if [ "$HABIA_ACTUAL" -eq 1 ]; then
  docker stop --time 30 "$CONTENEDOR" >/dev/null 2>&1 || true
  volver_a_previa
  if arrancar_y_esperar; then
    log "el Core volvio a responder con la BD anterior"
  else
    log "FALLO: el Core no respondio ni con la BD anterior; revisa docker logs $CONTENEDOR"
  fi
fi
die "el Core no respondio en $SALUD tras restaurar"
