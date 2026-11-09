#!/usr/bin/env bash
# create-network.sh — builds the SecureFlow network on AWS with the AWS CLI.
#
# What it creates (all FREE: no NAT Gateway, no Elastic IP, no instances):
#   VPC 10.20.0.0/16, 6 subnets in 2 AZs (public / app / db), an Internet Gateway,
#   3 route tables (public -> IGW, app and db local only) and 3 chained security groups
#   (alb: 443 from the internet -> api: 8000 from alb -> db: 5432 from api).
#
# Usage:   ./infra/aws-cli/create-network.sh            (region us-east-1 by default)
#          AWS_REGION=eu-west-1 ./infra/aws-cli/create-network.sh
# Output:  every new ID is appended to $OUT_FILE (default ~/secureflow-net.env).
#          Reload them later with:  source ~/secureflow-net.env
#
# Design and reasons: docs/network.md
# Later this script is replaced by Terraform (it does not detect drift or update things).

set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
OUT_FILE="${OUT_FILE:-$HOME/secureflow-net.env}"
AZ_A="${AWS_REGION}a"
AZ_B="${AWS_REGION}b"
TAGS="{Key=Project,Value=secureflow},{Key=Env,Value=dev},{Key=Owner,Value=islam}"

log()  { echo "==> $*" >&2; }
save() { echo "$1=$2" >> "$OUT_FILE"; echo "    $1=$2" >&2; }   # NAME=ID to the file, shown on stderr

# Each mk_* function creates one resource, saves its ID, and prints ONLY the ID on stdout,
# so the caller can write:  SOME_ID=$(mk_something ...)

# --- 0. Safety checks ---------------------------------------------------------
log "Region: $AWS_REGION | caller: $(aws sts get-caller-identity --query Arn --output text)"

existing=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=secureflow-vpc \
  --query 'Vpcs[0].VpcId' --output text)
if [[ "$existing" != "None" ]]; then
  echo "ERROR: secureflow-vpc already exists ($existing). Nothing created." >&2
  exit 1
fi

# --- 1. VPC --------------------------------------------------------------------
log "Creating the VPC"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=secureflow-vpc},$TAGS]" \
  --query Vpc.VpcId --output text)
save VPC_ID "$VPC_ID"

# --- 2. Subnets (one AZ each) ---------------------------------------------------
mk_subnet() {   # $1 = short name, $2 = CIDR, $3 = AZ
  local id
  id=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=secureflow-$1},$TAGS]" \
    --query Subnet.SubnetId --output text)
  save "SUBNET_${1//-/_}" "$id"
  echo "$id"
}
log "Creating 6 subnets"
SUBNET_public_a=$(mk_subnet public-a 10.20.1.0/24  "$AZ_A")
SUBNET_public_b=$(mk_subnet public-b 10.20.2.0/24  "$AZ_B")
SUBNET_app_a=$(mk_subnet    app-a    10.20.11.0/24 "$AZ_A")
SUBNET_app_b=$(mk_subnet    app-b    10.20.12.0/24 "$AZ_B")
SUBNET_db_a=$(mk_subnet     db-a     10.20.21.0/24 "$AZ_A")
SUBNET_db_b=$(mk_subnet     db-b     10.20.22.0/24 "$AZ_B")

# --- 3. Internet Gateway --------------------------------------------------------
log "Creating and attaching the Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=secureflow-igw},$TAGS]" \
  --query InternetGateway.InternetGatewayId --output text)
save IGW_ID "$IGW_ID"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

# --- 4. Route tables (one per tier; the main route table stays unused) ----------
mk_rtb() {      # $1 = tier name
  local id
  id=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=secureflow-rtb-$1},$TAGS]" \
    --query RouteTable.RouteTableId --output text)
  save "RTB_$1" "$id"
  echo "$id"
}
associate() {   # $1 = route table ID, $2 = subnet ID
  aws ec2 associate-route-table --route-table-id "$1" --subnet-id "$2" \
    --query AssociationState.State --output text >/dev/null
}
log "Creating route tables"
RTB_public=$(mk_rtb public)
RTB_app=$(mk_rtb app)
RTB_db=$(mk_rtb db)

aws ec2 create-route --route-table-id "$RTB_public" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null   # public = route to the IGW
associate "$RTB_public" "$SUBNET_public_a"
associate "$RTB_public" "$SUBNET_public_b"
associate "$RTB_app"    "$SUBNET_app_a"       # app: local only for now (NAT later, when deploying)
associate "$RTB_app"    "$SUBNET_app_b"
associate "$RTB_db"     "$SUBNET_db_a"        # db: local only, never a route to the internet
associate "$RTB_db"     "$SUBNET_db_b"

# --- 5. Security groups (chained: alb -> api -> db, no port 22) ------------------
mk_sg() {       # $1 = name, $2 = description
  local id
  id=$(aws ec2 create-security-group --vpc-id "$VPC_ID" --group-name "secureflow-$1" \
    --description "$2" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=secureflow-$1},$TAGS]" \
    --query GroupId --output text)
  save "SG_$1" "$id"
  echo "$id"
}
log "Creating security groups"
SG_alb=$(mk_sg alb "SecureFlow ALB - HTTPS from the internet")
SG_api=$(mk_sg api "SecureFlow API - only from the ALB")
SG_db=$(mk_sg  db  "SecureFlow DB - only from the API")

aws ec2 authorize-security-group-ingress --group-id "$SG_alb" --protocol tcp --port 443  --cidr 0.0.0.0/0         >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_api" --protocol tcp --port 8000 --source-group "$SG_alb" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_db"  --protocol tcp --port 5432 --source-group "$SG_api" >/dev/null

log "Done. IDs saved in $OUT_FILE"
