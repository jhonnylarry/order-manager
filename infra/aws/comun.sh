#!/usr/bin/env bash
# Valores compartidos por los scripts de AWS (laboratorio de AWS Academy).
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_PAGER=""

PROYECTO="order-manager"
FILTRO="Name=tag:Proyecto,Values=${PROYECTO}"

etiquetas() { echo "ResourceType=$1,Tags=[{Key=Proyecto,Value=${PROYECTO}},{Key=Name,Value=$2}]"; }

instancia_por_nombre() {
  aws ec2 describe-instances \
    --filters "$FILTRO" "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[0].InstanceId' --output text
}

ip_publica() {
  aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}
