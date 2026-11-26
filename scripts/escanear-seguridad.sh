#!/usr/bin/env bash
# Política de seguridad: el pipeline se detiene ante cualquiera de estos hallazgos.
#   1. Vulnerabilidades críticas en la imagen (sistema operativo y librerías Java)
#   2. Secretos escritos en el repositorio
#   3. Configuraciones críticas en el Dockerfile y los manifiestos de Kubernetes
# Uso: scripts/escanear-seguridad.sh [imagen]
set -uo pipefail
cd "$(dirname "$0")/.."

IMAGEN="${1:-order-manager:1.0.0}"
RESUMEN=evidencias/seguridad-resumen.txt
mkdir -p evidencias
: > "$RESUMEN"
fallos=0

# controlar <nombre> <reporte> <argumentos de trivy...>
controlar() {
  local nombre="$1" reporte="$2"
  shift 2
  if trivy "$@" --exit-code 1 --output "$reporte"; then
    echo "APROBADO   $nombre" | tee -a "$RESUMEN"
  else
    cat "$reporte" 2>/dev/null
    echo "BLOQUEADO  $nombre" | tee -a "$RESUMEN"
    fallos=$((fallos + 1))
  fi
}

controlar "Vulnerabilidades críticas en la imagen" evidencias/vulnerabilidades-criticas.txt \
  image --scanners vuln --severity CRITICAL "$IMAGEN"

controlar "Secretos en el repositorio" evidencias/secretos.txt \
  fs --scanners secret --skip-dirs target .

controlar "Configuraciones críticas" evidencias/configuracion.txt \
  config --severity CRITICAL --skip-dirs target .

# Reporte informativo: las vulnerabilidades altas se registran, pero no bloquean
trivy image --scanners vuln --severity HIGH,CRITICAL --quiet \
  --output evidencias/vulnerabilidades-altas-y-criticas.txt "$IMAGEN" || true

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Control de seguridad"
    echo '```'
    cat "$RESUMEN"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$fallos" -gt 0 ]; then
  echo "Pipeline detenido: $fallos control(es) de seguridad no aprobado(s)."
  exit 1
fi
echo "Todos los controles de seguridad aprobados."
