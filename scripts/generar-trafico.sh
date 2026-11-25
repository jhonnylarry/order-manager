#!/usr/bin/env bash
# Genera peticiones correctas y erróneas para observarlas en el dashboard.
# Uso: scripts/generar-trafico.sh [url-base] [repeticiones]
set -euo pipefail

BASE="${1:-http://localhost:8098}"
VECES="${2:-30}"

pedir() { curl -s -o /dev/null -w '%{http_code}\n' "$@" || echo 000; }

for i in $(seq 1 "$VECES"); do
  pedir -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
    -d "{\"customerName\":\"Cliente $i\",\"items\":[{\"productName\":\"Mouse\",\"quantity\":2,\"unitPrice\":10.50}]}"
  pedir "$BASE/api/orders"
  # Errores del cliente: pedido inexistente y datos inválidos
  pedir "$BASE/api/orders/999999"
  pedir -X POST "$BASE/api/orders" -H 'Content-Type: application/json' -d '{"customerName":""}'
  # Error del servidor: cuerpo mal formado
  if [ $(( i % 5 )) -eq 0 ]; then
    pedir -X POST "$BASE/api/orders" -H 'Content-Type: application/json' -d '{esto-no-es-json'
  fi
  sleep 1
done | sort | uniq -c
