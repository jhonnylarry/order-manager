#!/usr/bin/env bash
# Despliega la aplicación y el monitoreo en el clúster de Kubernetes activo.
# Uso: scripts/desplegar-k8s.sh [etiqueta-de-imagen]
# La imagen order-manager:<etiqueta> debe estar disponible en el clúster.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_TAG="${1:-1.0.0}"
ENTORNO="${ENTORNO:-local}"
COMMIT="${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo desconocido)}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-jhonnylarry_order-manager}"
INICIO=$(date +%s)

kubectl apply -f k8s/namespaces.yaml

# Las credenciales se generan en el clúster y nunca se guardan en el repositorio
if ! kubectl -n order-manager get secret db-credentials >/dev/null 2>&1; then
  kubectl -n order-manager create secret generic db-credentials \
    --from-literal=POSTGRES_DB=orderdb \
    --from-literal=POSTGRES_USER=orderuser \
    --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)"
fi
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=password="${GRAFANA_PASSWORD:-$(openssl rand -hex 12)}"
fi

kubectl apply -k k8s
kubectl -n order-manager set image deployment/order-manager "app=order-manager:${IMAGE_TAG}"

for despliegue in postgres order-manager; do
  kubectl -n order-manager rollout status "deployment/${despliegue}" --timeout=300s
done
DURACION=$(( $(date +%s) - INICIO ))

for despliegue in prometheus pushgateway loki alloy grafana; do
  kubectl -n monitoring rollout status "deployment/${despliegue}" --timeout=300s
done

# Métricas de calidad: las entrega el pipeline; si no, se consultan en SonarCloud
medida_sonar() {
  curl -fsS "https://sonarcloud.io/api/measures/component?component=${SONAR_PROJECT_KEY}&branch=main&metricKeys=$1" 2>/dev/null |
    sed -n 's/.*"value":"\([0-9.]*\)".*/\1/p'
}
COVERAGE="${COVERAGE:-$(medida_sonar coverage || true)}"
TESTS="${TESTS:-$(medida_sonar tests || true)}"

kubectl -n monitoring port-forward service/pushgateway 19091:9091 >/dev/null &
PF=$!
trap 'kill "$PF" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -fsS http://localhost:19091/-/ready >/dev/null 2>&1 && break; sleep 1; done

{
  echo "deploy_duration_seconds ${DURACION}"
  echo "deploy_timestamp_seconds $(date +%s)"
  echo "deploy_info{commit=\"${COMMIT}\",environment=\"${ENTORNO}\"} 1"
  [ -n "${COVERAGE}" ] && echo "ci_coverage_percent ${COVERAGE}"
  [ -n "${TESTS}" ] && echo "ci_tests_total ${TESTS}"
  true
} | curl -fsS -X PUT --data-binary @- http://localhost:19091/metrics/job/cicd

echo "Despliegue completado en ${DURACION} s (commit ${COMMIT}, entorno ${ENTORNO})"
kubectl get pods -n order-manager
kubectl get pods -n monitoring
