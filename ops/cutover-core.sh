#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_ROOT="${AMG_PLATFORM_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OLD_ROOT="${SAASMINI_ROOT:-$HOME/projects/saas-mini}"
OLD_ENV="$OLD_ROOT/.env"
NEW_ENV="$NEW_ROOT/.env"
OLD_CONTAINER="${SAASMINI_CORE_CONTAINER:-saasmini-landing}"
NEW_CONTAINER="${AMG_PLATFORM_CONTAINER:-amg-platform}"
NEW_VOLUME="${AMG_PLATFORM_CORE_VOLUME:-amg-platform_amg_platform_data_core}"
PUBLIC_URL="${AMG_PLATFORM_PUBLIC_URL:-https://amgdeveloper.cl}"
RETURN_HOSTS="${AMG_RETURN_URL_HOSTS:-amgdeveloper.cl,www.amgdeveloper.cl,localhost}"
HEALTH="${AMG_PLATFORM_HEALTH:-http://127.0.0.1:3108/health}"
BACKUPS="${AMG_PLATFORM_BACKUPS:-$HOME/backups/amg-platform}"
AUDIT="$SCRIPT_DIR/sqlite-audit.mjs"
SNAPSHOT="$SCRIPT_DIR/sqlite-snapshot.mjs"
ALLOW='^(CORE_SESSION_DAYS|CORE_SESSION_COOKIE|CORE_SESSION_PRUNE_MINUTES|CORE_SESSION_RETENTION_DAYS|CORE_SSO_CODE_TTL|CORE_SSO_TOKEN_TTL|CORE_PASSWORD_RESET_TTL_MIN|CORE_EMAIL_VERIFY_TTL_MIN|SMTP_HOST|SMTP_PORT|SMTP_USER|SMTP_PASS|MAIL_FROM|CONTACT_EMAIL|MERCADOPAGO_ACCESS_TOKEN|MERCADOPAGO_WEBHOOK_SECRET|MERCADOPAGO_MODE|LOG_LEVEL|CORE_DIAGNOSTICO_KEY)='

FORCE=0
FORCE_ENV=0
REQUIRE_SSO=0
STRICT=0
AUDIT_FLAGS=()
OLD_IMAGE="${SAASMINI_IMAGE:-}"
OLD_VOLUME="${SAASMINI_CORE_VOLUME:-}"
BACKUP_DIR=""
OLD_STOPPED=0
CUTOVER_OK=0

PUBLIC_URL="${PUBLIC_URL%/}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
warn() { log "AVISO: $*"; }
fail() { log "FALLO: $*"; exit 1; }

uso() {
  cat <<'TEXTO'
uso: ops/cutover-core.sh <check|prepare|cutover|rollback> [opciones]

  check      audita el Core antiguo y el estado del destino; no modifica nada
  prepare    snapshot en caliente, auditoria y creacion del .env central
  cutover    detiene el Core antiguo, copia la DB al volumen nuevo y arranca el central
  rollback   detiene el central y vuelve a arrancar el Core antiguo

opciones:
  --force         reemplaza un core.sqlite existente en el volumen nuevo (lo respalda)
  --force-env     reemplaza el .env central existente (lo respalda)
  --require-sso   falla si los AMG_SSO_*_SECRET no coinciden con sso_clients.secret
  --strict        falla si faltan claves AMG_SSO_*_SECRET para algun cliente

variables:
  SAASMINI_ROOT, SAASMINI_CORE_CONTAINER, SAASMINI_CORE_VOLUME, SAASMINI_IMAGE
  AMG_PLATFORM_ROOT, AMG_PLATFORM_CONTAINER, AMG_PLATFORM_CORE_VOLUME
  AMG_PLATFORM_PUBLIC_URL, AMG_PLATFORM_HEALTH, AMG_PLATFORM_BACKUPS
  AMG_RETURN_URL_HOSTS, APP_NAME

No imprime secretos. El .env del Core antiguo se respalda con permisos 600.
TEXTO
}

env_get() {
  awk -v k="$2" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2); sub(/\r$/, "", v); print v; exit }' "$1"
}

env_require() {
  local valor
  valor="$(env_get "$1" "$2")"
  [ -n "$valor" ] || fail "falta $2 en $1"
}

contenedor_existe() {
  docker inspect "$1" >/dev/null 2>&1
}

contenedor_corriendo() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true
}

volumen_existe() {
  docker volume inspect "$1" >/dev/null 2>&1
}

volumen_tiene_core() {
  local volumen="$1"
  volumen_existe "$volumen" || return 1
  docker run --rm -v "$volumen:/vol:ro" "$OLD_IMAGE" test -f /vol/core.sqlite >/dev/null 2>&1
}

deducir_origen() {
  if [ -z "$OLD_IMAGE" ]; then
    contenedor_existe "$OLD_CONTAINER" || fail "no existe $OLD_CONTAINER; define SAASMINI_IMAGE"
    OLD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$OLD_CONTAINER")"
  fi
  [ -n "$OLD_IMAGE" ] || fail "no se pudo deducir la imagen del Core antiguo"

  if [ -z "$OLD_VOLUME" ] && contenedor_existe "$OLD_CONTAINER"; then
    OLD_VOLUME="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/data/core"}}{{.Name}}{{end}}{{end}}' "$OLD_CONTAINER")"
  fi
  OLD_VOLUME="${OLD_VOLUME:-saas-mini_saasmini_data_core}"
}

preflight() {
  local requerido
  for requerido in docker curl sha256sum awk mktemp id; do
    command -v "$requerido" >/dev/null 2>&1 || fail "falta el comando $requerido"
  done
  docker info >/dev/null 2>&1 || fail "Docker no responde"
  docker compose version >/dev/null 2>&1 || fail "falta docker compose"

  [ -d "$NEW_ROOT" ] || fail "no existe AMG_PLATFORM_ROOT=$NEW_ROOT"
  [ -f "$NEW_ROOT/docker-compose.yml" ] || fail "falta $NEW_ROOT/docker-compose.yml"
  [ -f "$AUDIT" ] || fail "falta $AUDIT"
  [ -f "$SNAPSHOT" ] || fail "falta $SNAPSHOT"
  [ -f "$OLD_ENV" ] || fail "no existe $OLD_ENV"

  env_require "$OLD_ENV" AMG_SESSION_SECRET
  env_require "$OLD_ENV" AMG_SSO_ROOT_SECRET
  env_require "$OLD_ENV" CORE_URL

  deducir_origen
  volumen_existe "$OLD_VOLUME" || fail "no existe el volumen antiguo $OLD_VOLUME"
  volumen_tiene_core "$OLD_VOLUME" || fail "el volumen $OLD_VOLUME no tiene core.sqlite"
}

audit_volume() {
  docker run --rm \
    -v "$1:/db" \
    -v "$2:/config/.env:ro" \
    -v "$AUDIT:/app/audit.mjs:ro" \
    "$OLD_IMAGE" node /app/audit.mjs /db/core.sqlite /config/.env "${AUDIT_FLAGS[@]}"
}

audit_snapshot() {
  docker run --rm --user root \
    -v "$1:/db" \
    -v "$OLD_ENV:/config/.env:ro" \
    -v "$AUDIT:/app/audit.mjs:ro" \
    "$OLD_IMAGE" node /app/audit.mjs "/db/$2" /config/.env "${AUDIT_FLAGS[@]}"
}

auditar_volumen() {
  local volumen="$1" archivo_env="$2" salida_json="$3" etiqueta="$4" salida
  if salida="$(audit_volume "$volumen" "$archivo_env")"; then
    printf '%s\n' "$salida" > "$salida_json"
    log "auditoria OK: $etiqueta"
  else
    printf '%s\n' "$salida" > "$salida_json"
    printf '%s\n' "$salida"
    fail "auditoria fallo: $etiqueta"
  fi
}

auditar_snapshot() {
  local archivo_db="$1" salida_json="$2" etiqueta="$3" salida
  if salida="$(audit_snapshot "$(dirname "$archivo_db")" "$(basename "$archivo_db")")"; then
    printf '%s\n' "$salida" > "$salida_json"
    log "auditoria OK: $etiqueta"
  else
    printf '%s\n' "$salida" > "$salida_json"
    printf '%s\n' "$salida"
    fail "auditoria fallo: $etiqueta"
  fi
}

snapshot_volume() {
  local volumen="$1" destino_dir="$2" destino_nombre="$3" uid gid
  uid="$(id -u)"
  gid="$(id -g)"
  docker run --rm --user root \
    -v "$volumen:/origen" \
    -v "$destino_dir:/fuera" \
    -v "$SNAPSHOT:/app/snap.mjs:ro" \
    "$OLD_IMAGE" sh -c "node /app/snap.mjs /origen/core.sqlite '/fuera/$destino_nombre' && chown $uid:$gid '/fuera/$destino_nombre'"
}

limpiar_volumen() {
  docker run --rm --user root -v "$1:/db" "$OLD_IMAGE" sh -c 'rm -f /db/core.sqlite-wal /db/core.sqlite-shm'
}

restaurar_volumen() {
  local destino_dir="$1" destino_nombre="$2"
  docker run --rm --user root \
    -v "$NEW_VOLUME:/destino" \
    -v "$destino_dir:/origen:ro" \
    "$OLD_IMAGE" sh -c "cp /origen/$destino_nombre /destino/core.sqlite && rm -f /destino/core.sqlite-wal /destino/core.sqlite-shm && chown 1000:1000 /destino/core.sqlite && chmod 600 /destino/core.sqlite"
}

comparar_copias() {
  local destino_dir="$1" destino_nombre="$2"
  docker run --rm --user root \
    -v "$NEW_VOLUME:/nuevo:ro" \
    -v "$destino_dir:/viejo:ro" \
    "$OLD_IMAGE" cmp -s /nuevo/core.sqlite "/viejo/$destino_nombre"
}

nuevo_backup() {
  local sello
  sello="$(date -u '+%Y%m%d-%H%M%S')"
  mkdir -p "$BACKUPS"
  chmod 700 "$BACKUPS"
  BACKUP_DIR="$(mktemp -d "$BACKUPS/cutover-$sello-XXXXXX")"
  chmod 700 "$BACKUP_DIR"
  mkdir -p "$BACKUP_DIR/sqlite" "$BACKUP_DIR/config"
  chmod 700 "$BACKUP_DIR/sqlite" "$BACKUP_DIR/config"
  cp -p "$OLD_ENV" "$BACKUP_DIR/config/saas-mini.env"
  chmod 600 "$BACKUP_DIR/config/saas-mini.env"
  {
    echo "amg-platform cutover $sello"
    echo "host    : $(hostname)"
    echo "origen  : $OLD_ROOT"
    echo "destino : $NEW_ROOT"
    echo "imagen  : $OLD_IMAGE"
    echo "volumen : $OLD_VOLUME"
    echo "nuevo   : $NEW_VOLUME"
    echo "generado: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$BACKUP_DIR/manifest.txt"
  chmod 600 "$BACKUP_DIR/manifest.txt"
  log "respaldo: $BACKUP_DIR"
}

construir_env() {
  local tmp
  tmp="$(mktemp "$NEW_ENV.XXXXXX")"
  chmod 600 "$tmp"
  awk -v re="$ALLOW" '$0 ~ re { sub(/\r$/, ""); print }' "$OLD_ENV" > "$tmp"
  {
    printf 'CORE_URL=%s\n' "$PUBLIC_URL"
    printf 'AMG_SESSION_SECRET=%s\n' "$(env_get "$OLD_ENV" AMG_SESSION_SECRET)"
    printf 'AMG_SSO_ROOT_SECRET=%s\n' "$(env_get "$OLD_ENV" AMG_SSO_ROOT_SECRET)"
    printf 'CORE_RETURN_URL_HOSTS=%s\n' "$RETURN_HOSTS"
    printf 'APP_NAME=%s\n' "$APP_NAME"
  } >> "$tmp"
  mv "$tmp" "$NEW_ENV"
  chmod 600 "$NEW_ENV"
}

validar_env_nuevo() {
  local clave
  for clave in CORE_URL AMG_SESSION_SECRET AMG_SSO_ROOT_SECRET; do
    [ -n "$(env_get "$NEW_ENV" "$clave")" ] || fail "falta $clave en $NEW_ENV"
  done
  [ "$(env_get "$NEW_ENV" CORE_URL)" = "$PUBLIC_URL" ] || warn "CORE_URL de $NEW_ENV no es $PUBLIC_URL"
  case ",$(env_get "$NEW_ENV" CORE_RETURN_URL_HOSTS)," in
    *",www.amgdeveloper.cl,"*) ;;
    *) warn "CORE_RETURN_URL_HOSTS de $NEW_ENV no incluye www.amgdeveloper.cl" ;;
  esac
}

comparar_secretos() {
  if [ "$(env_get "$OLD_ENV" AMG_SESSION_SECRET)" = "$(env_get "$NEW_ENV" AMG_SESSION_SECRET)" ]; then
    log "session secret: coincide"
  else
    warn "AMG_SESSION_SECRET difiere entre el Core antiguo y el nuevo"
  fi
  if [ "$(env_get "$OLD_ENV" AMG_SSO_ROOT_SECRET)" = "$(env_get "$NEW_ENV" AMG_SSO_ROOT_SECRET)" ]; then
    log "root SSO: coincide"
  else
    warn "AMG_SSO_ROOT_SECRET difiere entre el Core antiguo y el nuevo"
  fi
}

ensure_new_env() {
  APP_NAME="${APP_NAME:-$(env_get "$OLD_ENV" APP_NAME)}"
  APP_NAME="${APP_NAME:-AMG}"

  if [ -f "$NEW_ENV" ]; then
    if [ "$FORCE_ENV" -eq 1 ]; then
      cp -p "$NEW_ENV" "$BACKUP_DIR/config/amg-platform.env.antes"
      chmod 600 "$BACKUP_DIR/config/amg-platform.env.antes"
      construir_env
      log "reemplazado .env central"
    else
      validar_env_nuevo
      chmod 600 "$NEW_ENV"
      log "se conserva .env central"
    fi
  else
    construir_env
    log "creado .env central"
  fi

  validar_env_nuevo
  comparar_secretos
}

compose_config() {
  ( cd "$NEW_ROOT" && docker compose config --quiet )
}

esperar_salud() {
  local intento
  for intento in $(seq 1 30); do
    if curl -fsS --max-time 5 "$HEALTH" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

recuperar() {
  local codigo=$?
  if [ "$codigo" -eq 0 ] || [ "$CUTOVER_OK" -eq 1 ] || [ "$OLD_STOPPED" -ne 1 ]; then
    exit "$codigo"
  fi

  log "ROLLBACK automatico"
  docker stop "$NEW_CONTAINER" >/dev/null 2>&1 || true
  if contenedor_existe "$OLD_CONTAINER"; then
    if ! contenedor_corriendo "$OLD_CONTAINER"; then
      docker start "$OLD_CONTAINER" >/dev/null 2>&1 || warn "no se pudo arrancar $OLD_CONTAINER"
    fi
  fi
  if esperar_salud; then
    log "Core antiguo restaurado en $HEALTH"
  else
    log "FALLO: el Core antiguo no respondio; revisa docker logs $OLD_CONTAINER"
  fi
  exit "$codigo"
}

hacer_check() {
  preflight
  local salida
  if salida="$(audit_volume "$OLD_VOLUME" "$OLD_ENV")"; then
    printf '%s\n' "$salida"
  else
    printf '%s\n' "$salida"
    fail "auditoria del Core antiguo fallo"
  fi

  if [ -f "$NEW_ENV" ]; then
    validar_env_nuevo
    log "destino .env: existe"
  else
    warn "no existe $NEW_ENV; prepare lo crea"
  fi

  if volumen_existe "$NEW_VOLUME"; then
    if volumen_tiene_core "$NEW_VOLUME"; then
      log "destino volumen: $NEW_VOLUME contiene core.sqlite"
    else
      log "destino volumen: $NEW_VOLUME vacio"
    fi
  else
    log "destino volumen: $NEW_VOLUME no existe"
  fi

  if contenedor_corriendo "$NEW_CONTAINER"; then
    warn "$NEW_CONTAINER esta corriendo; cutover se negará a continuar"
  fi
  log "check OK"
}

hacer_prepare() {
  preflight
  nuevo_backup

  local salida
  if salida="$(snapshot_volume "$OLD_VOLUME" "$BACKUP_DIR/sqlite" old-core.db 2>&1)"; then
    printf '%s\n' "$salida" > "$BACKUP_DIR/sqlite/snapshot.json"
    log "snapshot OK: $salida"
  else
    printf '%s\n' "$salida"
    fail "no se pudo crear el snapshot"
  fi

  auditar_snapshot "$BACKUP_DIR/sqlite/old-core.db" "$BACKUP_DIR/audit-old.json" "snapshot del Core antiguo"
  ensure_new_env
  compose_config

  ( cd "$BACKUP_DIR" && find sqlite config -type f ! -name '*-wal' ! -name '*-shm' -exec sha256sum {} + > SHA256SUMS )
  log "RESULTADO: prepare OK. Snapshot en $BACKUP_DIR. No se detuvo el Core antiguo."
}

hacer_cutover() {
  preflight
  contenedor_existe "$OLD_CONTAINER" || fail "no existe $OLD_CONTAINER; no hay rollback posible"
  contenedor_corriendo "$OLD_CONTAINER" || fail "$OLD_CONTAINER no esta corriendo; arrancalo antes del cutover"
  if contenedor_corriendo "$NEW_CONTAINER"; then
    fail "$NEW_CONTAINER ya esta corriendo; detenlo antes del cutover"
  fi
  if volumen_existe "$NEW_VOLUME" && volumen_tiene_core "$NEW_VOLUME" && [ "$FORCE" -eq 0 ]; then
    fail "$NEW_VOLUME ya contiene core.sqlite; usa --force para reemplazarlo"
  fi

  nuevo_backup
  ensure_new_env
  [ "$(env_get "$NEW_ENV" CORE_URL)" = "$PUBLIC_URL" ] || fail "CORE_URL de $NEW_ENV no es $PUBLIC_URL"
  compose_config
  auditar_volumen "$OLD_VOLUME" "$OLD_ENV" "$BACKUP_DIR/audit-old-live.json" "Core antiguo en caliente"

  if [ "$FORCE" -eq 1 ] && volumen_existe "$NEW_VOLUME" && volumen_tiene_core "$NEW_VOLUME"; then
    local previo
    if previo="$(snapshot_volume "$NEW_VOLUME" "$BACKUP_DIR/sqlite" new-core-before.db 2>&1)"; then
      printf '%s\n' "$previo" > "$BACKUP_DIR/sqlite/snapshot-new-before.json"
      log "snapshot del Core nuevo previo OK"
      auditar_snapshot "$BACKUP_DIR/sqlite/new-core-before.db" "$BACKUP_DIR/audit-new-before.json" "Core nuevo previo"
    else
      printf '%s\n' "$previo"
      fail "no se pudo respaldar el Core nuevo existente"
    fi
  fi

  log "construyendo imagen central"
  ( cd "$NEW_ROOT" && docker compose build platform )

  docker volume create "$NEW_VOLUME" >/dev/null
  log "deteniendo $OLD_CONTAINER"
  docker stop --time 30 "$OLD_CONTAINER" >/dev/null
  OLD_STOPPED=1

  local salida
  if salida="$(snapshot_volume "$OLD_VOLUME" "$BACKUP_DIR/sqlite" old-core.db 2>&1)"; then
    printf '%s\n' "$salida" > "$BACKUP_DIR/sqlite/snapshot-final.json"
    log "snapshot final OK: $salida"
  else
    printf '%s\n' "$salida"
    fail "no se pudo crear el snapshot final"
  fi

  auditar_snapshot "$BACKUP_DIR/sqlite/old-core.db" "$BACKUP_DIR/audit-final.json" "snapshot final"
  restaurar_volumen "$BACKUP_DIR/sqlite" old-core.db
  comparar_copias "$BACKUP_DIR/sqlite" old-core.db || fail "la copia en $NEW_VOLUME no coincide con el snapshot"
  log "copia verificada"
  auditar_volumen "$NEW_VOLUME" "$OLD_ENV" "$BACKUP_DIR/audit-new.json" "Core nuevo"
  limpiar_volumen "$NEW_VOLUME"

  log "arrancando $NEW_CONTAINER"
  ( cd "$NEW_ROOT" && docker compose up -d --no-deps --no-build platform )
  if ! esperar_salud; then
    ( cd "$NEW_ROOT" && docker compose logs --tail=80 platform ) || true
    fail "el Core nuevo no respondio en $HEALTH"
  fi

  CUTOVER_OK=1
  if ! ( cd "$BACKUP_DIR" && find sqlite config -type f ! -name '*-wal' ! -name '*-shm' -exec sha256sum {} + > SHA256SUMS ); then
    warn "no se pudo escribir SHA256SUMS"
  fi
  log "RESULTADO: cutover OK. Rollback: ops/cutover-core.sh rollback"
}

hacer_rollback() {
  command -v docker >/dev/null 2>&1 || fail "falta docker"
  command -v curl >/dev/null 2>&1 || fail "falta curl"
  docker info >/dev/null 2>&1 || fail "Docker no responde"
  contenedor_existe "$OLD_CONTAINER" || fail "no existe $OLD_CONTAINER"

  if contenedor_corriendo "$NEW_CONTAINER"; then
    log "deteniendo $NEW_CONTAINER"
    docker stop --time 30 "$NEW_CONTAINER" >/dev/null
  fi
  if ! contenedor_corriendo "$OLD_CONTAINER"; then
    log "arrancando $OLD_CONTAINER"
    docker start "$OLD_CONTAINER" >/dev/null
  fi
  if ! esperar_salud; then
    docker logs --tail=80 "$OLD_CONTAINER" || true
    fail "el Core antiguo no respondio en $HEALTH"
  fi
  log "RESULTADO: rollback OK. Los datos escritos en $NEW_VOLUME no se copiaron al Core antiguo."
}

ACCION="${1:-}"
[ -n "$ACCION" ] || { uso; exit 2; }
shift
case "$ACCION" in
  -h|--help) uso; exit 0 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --force-env) FORCE_ENV=1 ;;
    --require-sso) REQUIRE_SSO=1 ;;
    --strict) STRICT=1 ;;
    -h|--help) uso; exit 0 ;;
    *) fail "opcion desconocida: $1" ;;
  esac
  shift
done

if [ "$REQUIRE_SSO" -eq 1 ]; then AUDIT_FLAGS+=(--require-sso); fi
if [ "$STRICT" -eq 1 ]; then AUDIT_FLAGS+=(--strict); fi

trap recuperar EXIT

case "$ACCION" in
  check) hacer_check ;;
  prepare) hacer_prepare ;;
  cutover) hacer_cutover ;;
  rollback) hacer_rollback ;;
  *) uso; exit 2 ;;
esac
