#!/usr/bin/env bash
# Auditoría de cumplimiento: comprueba que el repositorio respeta las políticas
# del proyecto. Genera un informe y termina con error si alguna no se cumple.
# Uso: scripts/auditar-cumplimiento.sh
#      REPOSITORIO=dueño/nombre para comprobar la protección de ramas con gh
set -uo pipefail
cd "$(dirname "$0")/.."

INFORME=evidencias/auditoria-cumplimiento.md
FLUJO=.github/workflows/ci-cd.yml
REPOSITORIO="${REPOSITORIO:-${GITHUB_REPOSITORY:-jhonnylarry/order-manager}}"
mkdir -p evidencias
fallos=0

{
  echo "# Auditoría de cumplimiento"
  echo
  echo "- Fecha: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "- Commit: $(git rev-parse --short HEAD)"
  echo
  echo "| Resultado | Política | Detalle |"
  echo "|---|---|---|"
} > "$INFORME"

registrar() {
  local resultado="$1" politica="$2" detalle="$3"
  echo "| $resultado | $politica | $detalle |" >> "$INFORME"
  printf '%-9s %s %s\n' "$resultado" "$politica" "$detalle"
  [ "$resultado" = "CUMPLE" ] || fallos=$((fallos + 1))
}

# evaluar <política> <hallazgos>: cumple cuando no hay hallazgos
evaluar() {
  if [ -z "$2" ]; then
    registrar "CUMPLE" "$1" "-"
  else
    registrar "NO CUMPLE" "$1" "$(echo "$2" | tr '\n|' '  ')"
  fi
}

# ---------- Secretos ----------
evaluar "No hay archivos con credenciales en el repositorio" \
  "$(git ls-files | grep -E '(^|/)(\.env|credentials)$|\.(pem|key|p12)$')"

evaluar "Las contraseñas se leen desde variables de entorno" \
  "$(grep -HnE 'password=[^$[:space:]]' src/main/resources/*.properties)"

# ---------- Contenedores ----------
usuario=$(awk '$1 == "USER" {u = $2} END {print u}' Dockerfile)
if [ -n "$usuario" ] && [ "$usuario" != "root" ] && [ "$usuario" != "0" ]; then
  registrar "CUMPLE" "La imagen no se ejecuta como root" "usuario $usuario"
else
  registrar "NO CUMPLE" "La imagen no se ejecuta como root" "falta la instrucción USER"
fi

evaluar "Las imágenes tienen una versión fija (sin latest)" \
  "$({
    awk '$1 == "FROM" {print $2}' Dockerfile
    sed -nE 's/^[[:space:]-]*image:[[:space:]]*//p' docker-compose.yml k8s/*/*.yaml
  } | grep -vE ':[^/]+$|@sha256' ; {
    awk '$1 == "FROM" {print $2}' Dockerfile
    sed -nE 's/^[[:space:]-]*image:[[:space:]]*//p' docker-compose.yml k8s/*/*.yaml
  } | grep -E ':latest$')"

# ---------- Kubernetes ----------
evaluar "Todos los contenedores tienen límites de recursos" "$(ruby -ryaml -e '
  Dir["k8s/*/*.yaml"].sort.each do |archivo|
    YAML.load_stream(File.read(archivo)).compact.each do |objeto|
      next unless objeto["kind"] == "Deployment"
      objeto.dig("spec", "template", "spec", "containers").each do |c|
        puts "#{archivo}: #{c["name"]}" unless c.dig("resources", "limits")
      end
    end
  end')"

evaluar "La aplicación corre sin root y con sondas de salud" "$(ruby -ryaml -e '
  objetos = YAML.load_stream(File.read("k8s/app/order-manager.yaml")).compact
  pod = objetos.find { |o| o["kind"] == "Deployment" }.dig("spec", "template", "spec")
  puts "falta runAsNonRoot" unless pod.dig("securityContext", "runAsNonRoot")
  pod["containers"].each do |c|
    %w[readinessProbe livenessProbe].each { |s| puts "#{c["name"]}: falta #{s}" unless c[s] }
    puts "#{c["name"]}: permite escalar privilegios" unless c.dig("securityContext", "allowPrivilegeEscalation") == false
  end')"

# ---------- Pipeline ----------
minimo=$(sed -nE 's/^[[:space:]]*MIN_COVERAGE:[[:space:]]*"?([0-9]+)"?.*/\1/p' "$FLUJO")
if [ "${minimo:-0}" -ge 70 ]; then
  registrar "CUMPLE" "Cobertura mínima exigida de al menos 70%" "configurada en ${minimo}%"
else
  registrar "NO CUMPLE" "Cobertura mínima exigida de al menos 70%" "valor actual: ${minimo:-ninguno}"
fi

evaluar "El análisis de SonarCloud bloquea si falla el quality gate" \
  "$(grep -q 'sonar.qualitygate.wait=true' "$FLUJO" || echo 'falta sonar.qualitygate.wait=true')"

evaluar "El despliegue exige el escaneo de seguridad" \
  "$(ruby -ryaml -e '
    necesita = Array(YAML.load_file(ARGV[0]).dig("jobs", "deploy", "needs"))
    puts "deploy no depende de scan" unless necesita.include?("scan")' "$FLUJO")"

evaluar "Las acciones de GitHub usan una versión fija" \
  "$(grep -hE '^[[:space:]-]*uses:' .github/workflows/*.yml | grep -E '@(main|master|latest)[[:space:]]*$|uses:[^@]*$')"

# ---------- Protección de ramas ----------
for rama in main develop; do
  politica="La rama $rama está protegida"
  if ! reglas=$(gh api "repos/$REPOSITORIO/rules/branches/$rama" --jq '.[].type' 2>&1); then
    registrar "NO CUMPLE" "$politica" "no se pudo consultar GitHub"
    continue
  fi
  faltan=""
  for regla in pull_request required_status_checks non_fast_forward deletion; do
    echo "$reglas" | grep -qx "$regla" || faltan="$faltan $regla"
  done
  if [ -z "$faltan" ]; then
    registrar "CUMPLE" "$politica" "pull request, controles obligatorios, sin force push ni borrado"
  else
    registrar "NO CUMPLE" "$politica" "faltan reglas:$faltan"
  fi
done

{
  echo
  echo "Políticas no cumplidas: $fallos"
} >> "$INFORME"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$INFORME" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$fallos" -gt 0 ]; then
  echo "Auditoría no aprobada: $fallos política(s) sin cumplir."
  exit 1
fi
echo "Auditoría aprobada."
