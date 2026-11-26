#!/usr/bin/env bash
# Comprueba que métricas, logs, alertas y dashboard funcionan. Falla si algo no responde.
# Deja la evidencia en la carpeta evidencias/.
# Detiene la base de datos unos segundos: usar solo en clústeres de prueba.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p evidencias
: > evidencias/falla-controlada.txt
PIDS=()
PETICIONES=()
trap 'kill "${PIDS[@]}" 2>/dev/null || true' EXIT

reenviar() { kubectl -n "$1" port-forward "service/$2" "$3" >/dev/null & PIDS+=("$!"); }
reenviar order-manager order-manager 18098:8098
reenviar monitoring prometheus 19090:9090
reenviar monitoring loki 13100:3100
reenviar monitoring grafana 13000:3000
sleep 8

scripts/generar-trafico.sh http://localhost:18098 "${REPETICIONES:-30}" | tee evidencias/trafico.txt

# Falla controlada: sin base de datos la API responde 500 y registra el error,
# lo que permite comprobar que el monitoreo detecta una falla real del servidor
echo "Falla controlada: se detiene la base de datos"
kubectl -n order-manager scale deployment/postgres --replicas=0
kubectl -n order-manager wait --for=delete pod -l app=postgres --timeout=60s
for _ in 1 2 3; do
  curl -s -m 60 -o /dev/null -w '%{http_code}\n' http://localhost:18098/api/orders >> evidencias/falla-controlada.txt &
  PETICIONES+=("$!")
done
wait "${PETICIONES[@]}" || true
kubectl -n order-manager scale deployment/postgres --replicas=1
kubectl -n order-manager rollout status deployment/postgres --timeout=120s
kubectl -n order-manager rollout status deployment/order-manager --timeout=120s
sleep 20

consulta() { curl -fsS --get http://localhost:19090/api/v1/query --data-urlencode "query=$1"; }

comprobar() {
  local nombre="$1" expresion="$2"
  local salida
  salida=$(consulta "$expresion")
  if echo "$salida" | grep -q '"result":\[{'; then
    echo "OK    $nombre"
  else
    echo "FALLA $nombre"; echo "$salida"; return 1
  fi
}

{
  comprobar "Disponibilidad de la aplicación" 'up{job="order-manager"} == 1'
  comprobar "Peticiones HTTP"                 'http_server_requests_seconds_count{job="order-manager"} > 0'
  comprobar "Errores 5xx registrados"         'http_server_requests_seconds_count{job="order-manager",status=~"5.."} > 0'
  comprobar "Eventos de error en logs"        'logback_events_total{job="order-manager",level="error"} > 0'
  comprobar "CPU del contenedor"              'container_cpu_usage_seconds_total{namespace="order-manager",container="app"}'
  comprobar "Memoria del contenedor"          'container_memory_working_set_bytes{namespace="order-manager",container="app"}'
  comprobar "Tiempo de despliegue"            'deploy_duration_seconds'
  comprobar "Cobertura de pruebas"            'ci_coverage_percent'
} | tee evidencias/metricas.txt

curl -fsS --get http://localhost:13100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="order-manager", app="order-manager"} |= "ERROR"' \
  --data-urlencode 'limit=5' > evidencias/logs-loki.json
if ! grep -q '"values":\[\[' evidencias/logs-loki.json; then echo "FALLA Logs de errores en Loki"; exit 1; fi
echo "OK    Logs de errores en Loki" | tee -a evidencias/metricas.txt

curl -fsS http://localhost:19090/api/v1/rules > evidencias/reglas-de-alerta.json
curl -fsS http://localhost:19090/api/v1/alerts > evidencias/alertas-activas.json
if ! grep -q 'TasaDeErroresAlta' evidencias/reglas-de-alerta.json; then echo "FALLA Reglas de alerta"; exit 1; fi
echo "OK    Reglas de alerta cargadas" | tee -a evidencias/metricas.txt

CLAVE=$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d)
curl -fsS -u "admin:${CLAVE}" http://localhost:13000/api/dashboards/uid/order-manager > evidencias/dashboard.json
echo "OK    Dashboard disponible en Grafana" | tee -a evidencias/metricas.txt

kubectl get deployments,pods,services,hpa -n order-manager > evidencias/kubernetes.txt
kubectl get deployments,pods,services -n monitoring >> evidencias/kubernetes.txt
