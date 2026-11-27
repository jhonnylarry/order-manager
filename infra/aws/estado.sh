#!/usr/bin/env bash
# Muestra instancias, direcciones y, si es posible, el estado del clúster.
# Uso: infra/aws/estado.sh ["comando a ejecutar en el servidor"]
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=comun.sh
source ./comun.sh

# Las comillas invertidas son sintaxis de la consulta (JMESPath), no de la shell
# shellcheck disable=SC2016
aws ec2 describe-instances --filters "$FILTRO" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Nombre:Tags[?Key==`Name`]|[0].Value,Estado:State.Name,Tipo:InstanceType,Subred:SubnetId,IP:PublicIpAddress}' \
  --output table

SERVIDOR=$(instancia_por_nombre "${PROYECTO}-servidor")
[ -z "$SERVIDOR" ] && exit 0

COMANDO="${1:-k3s kubectl get nodes -o wide; k3s kubectl get pods -A; tail -5 /var/log/despliegue.log}"
PARAMETROS=$(python3 -c 'import json,sys; print(json.dumps({"commands":[sys.argv[1]]}))' "$COMANDO")
ID=$(aws ssm send-command --instance-ids "$SERVIDOR" --document-name AWS-RunShellScript \
  --parameters "$PARAMETROS" --query Command.CommandId --output text)
aws ssm wait command-executed --command-id "$ID" --instance-id "$SERVIDOR" || true
aws ssm get-command-invocation --command-id "$ID" --instance-id "$SERVIDOR" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text
