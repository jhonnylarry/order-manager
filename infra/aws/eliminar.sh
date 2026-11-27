#!/usr/bin/env bash
# Elimina todos los recursos con la etiqueta Proyecto=order-manager.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=comun.sh
source ./comun.sh

ids() { aws ec2 "$1" --filters "$FILTRO" --query "$2" --output text; }

INSTANCIAS=$(aws ec2 describe-instances --filters "$FILTRO" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCIAS" ]; then
  echo "Eliminando instancias: $INSTANCIAS"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $INSTANCIAS >/dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $INSTANCIAS
fi

for sg in $(ids describe-security-groups 'SecurityGroups[].GroupId'); do
  aws ec2 delete-security-group --group-id "$sg" >/dev/null
done
for subred in $(ids describe-subnets 'Subnets[].SubnetId'); do
  aws ec2 delete-subnet --subnet-id "$subred"
done
for rutas in $(ids describe-route-tables 'RouteTables[].RouteTableId'); do
  aws ec2 delete-route-table --route-table-id "$rutas"
done
VPC=$(ids describe-vpcs 'Vpcs[].VpcId')
for igw in $(ids describe-internet-gateways 'InternetGateways[].InternetGatewayId'); do
  aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC"
  aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
done
for vpc in $VPC; do aws ec2 delete-vpc --vpc-id "$vpc"; done

rm -f "${HOME}/.aws/${PROYECTO}-grafana.txt"
echo "Infraestructura eliminada"
