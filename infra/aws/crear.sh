#!/usr/bin/env bash
# Crea la infraestructura en AWS y despliega el proyecto en un clúster k3s:
#   VPC con dos subredes en zonas distintas, internet gateway, grupo de seguridad
#   y dos instancias EC2 (servidor de Kubernetes y nodo trabajador).
# Uso: infra/aws/crear.sh [rama-o-commit]      (por defecto: main)
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=comun.sh
source ./comun.sh

REF="${1:-main}"
REPO="${REPO:-https://github.com/jhonnylarry/order-manager.git}"
TIPO_SERVIDOR="${TIPO_SERVIDOR:-t3.large}"
TIPO_TRABAJADOR="${TIPO_TRABAJADOR:-t3.medium}"
ARCHIVO_CLAVE="${HOME}/.aws/${PROYECTO}-grafana.txt"

if [ "$(aws ec2 describe-vpcs --filters "$FILTRO" --query 'length(Vpcs)')" != "0" ]; then
  echo "Ya existe infraestructura del proyecto. Elimínela primero con infra/aws/eliminar.sh" >&2
  exit 1
fi

MI_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
AMI="$(aws ssm get-parameter --query Parameter.Value --output text \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id)"

echo "== Red"
VPC=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 \
  --tag-specifications "$(etiquetas vpc "${PROYECTO}-vpc")" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames
IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications "$(etiquetas internet-gateway "${PROYECTO}-igw")" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
RUTAS=$(aws ec2 create-route-table --vpc-id "$VPC" \
  --tag-specifications "$(etiquetas route-table "${PROYECTO}-rutas")" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RUTAS" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null

crear_subred() {
  local id
  id=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block "$1" --availability-zone "${AWS_DEFAULT_REGION}$2" \
    --tag-specifications "$(etiquetas subnet "${PROYECTO}-subred-$2")" --query Subnet.SubnetId --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch
  aws ec2 associate-route-table --subnet-id "$id" --route-table-id "$RUTAS" >/dev/null
  echo "$id"
}
SUBRED_A=$(crear_subred 10.20.1.0/24 a)
SUBRED_B=$(crear_subred 10.20.2.0/24 b)

echo "== Seguridad (acceso externo solo desde ${MI_IP})"
SG=$(aws ec2 create-security-group --group-name "${PROYECTO}-sg" --description "Order Manager" --vpc-id "$VPC" \
  --tag-specifications "$(etiquetas security-group "${PROYECTO}-sg")" --query GroupId --output text)
# Tráfico interno del clúster
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol -1 --source-group "$SG" >/dev/null
# API, Grafana y Prometheus solo desde la IP de quien despliega
for puerto in 30080 30030 30090; do
  aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port "$puerto" --cidr "${MI_IP}/32" >/dev/null
done

TOKEN_K3S="$(openssl rand -hex 24)"
(umask 077; openssl rand -hex 12 > "$ARCHIVO_CLAVE")
CLAVE_GRAFANA="$(cat "$ARCHIVO_CLAVE")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

preparar_imagen() {
  cat <<SCRIPT
#!/bin/bash
set -euxo pipefail
exec > /var/log/despliegue.log 2>&1
export HOME=/root
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io git
git clone ${REPO} /opt/${PROYECTO}
cd /opt/${PROYECTO}
git checkout ${REF}
SHA=\$(git rev-parse HEAD)
docker build --label org.opencontainers.image.revision=\$SHA -t order-manager:\$SHA .
SCRIPT
}

{
  preparar_imagen
  cat <<SCRIPT
curl -sfL https://get.k3s.io | K3S_TOKEN=${TOKEN_K3S} sh -s - server --node-label rol=principal
docker save order-manager:\$SHA | k3s ctr images import -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes | grep -q ' Ready'; do sleep 5; done
COMMIT=\${SHA:0:7} ENTORNO=aws GRAFANA_PASSWORD=${CLAVE_GRAFANA} scripts/desplegar-k8s.sh \$SHA
# La base de datos permanece en el servidor para que apagar el trabajador no la afecte
kubectl -n order-manager patch deployment postgres -p '{"spec":{"template":{"spec":{"nodeSelector":{"rol":"principal"}}}}}'
kubectl -n order-manager rollout status deployment/postgres --timeout=300s
echo DESPLIEGUE_COMPLETO
SCRIPT
} > "$TMP/servidor.sh"

lanzar() {
  aws ec2 run-instances --image-id "$AMI" --instance-type "$1" --subnet-id "$2" --security-group-ids "$SG" \
    --iam-instance-profile Name=LabInstanceProfile \
    --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1 \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=25,VolumeType=gp3,Encrypted=true}' \
    --user-data "file://$3" \
    --tag-specifications "$(etiquetas instance "$4")" \
    --query 'Instances[0].InstanceId' --output text
}

echo "== Instancias"
SERVIDOR=$(lanzar "$TIPO_SERVIDOR" "$SUBRED_A" "$TMP/servidor.sh" "${PROYECTO}-servidor")
aws ec2 wait instance-running --instance-ids "$SERVIDOR"
IP_PRIVADA=$(aws ec2 describe-instances --instance-ids "$SERVIDOR" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

{
  preparar_imagen
  cat <<SCRIPT
until curl -ks https://${IP_PRIVADA}:6443 >/dev/null; do sleep 10; done
curl -sfL https://get.k3s.io | K3S_URL=https://${IP_PRIVADA}:6443 K3S_TOKEN=${TOKEN_K3S} sh -s - agent --node-label rol=trabajador
docker save order-manager:\$SHA | k3s ctr images import -
echo DESPLIEGUE_COMPLETO
SCRIPT
} > "$TMP/trabajador.sh"
TRABAJADOR=$(lanzar "$TIPO_TRABAJADOR" "$SUBRED_B" "$TMP/trabajador.sh" "${PROYECTO}-trabajador")

IP=$(ip_publica "$SERVIDOR")
echo "== Instalando (puede tardar 8 a 12 minutos)"
for _ in $(seq 1 90); do
  if curl -fsS --max-time 5 "http://${IP}:30030/api/health" >/dev/null 2>&1 &&
     curl -fsS --max-time 5 "http://${IP}:30080/actuator/health" >/dev/null 2>&1; then
    cat <<FIN

Despliegue listo
  Servidor:    ${SERVIDOR}
  Trabajador:  ${TRABAJADOR}
  API:         http://${IP}:30080/api/orders
  Grafana:     http://${IP}:30030   (usuario admin, clave en ${ARCHIVO_CLAVE})
  Prometheus:  http://${IP}:30090

Al terminar: infra/aws/eliminar.sh
FIN
    exit 0
  fi
  sleep 10
done
echo "El despliegue no respondió a tiempo. Revise con infra/aws/estado.sh" >&2
exit 1
