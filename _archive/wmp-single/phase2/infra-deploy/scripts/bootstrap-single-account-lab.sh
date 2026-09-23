#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE_NAME="${1:?Usage: $0 <aws-profile>}"
DIR="bootstrap/single-account-lab"
TFVARS="${DIR}/terraform.tfvars"
[[ -f "$TFVARS" ]] || { echo "Create $TFVARS from terraform.tfvars.example first."; exit 1; }

export AWS_PROFILE="$AWS_PROFILE_NAME"
export AWS_REGION="${AWS_REGION:-eu-west-2}"

echo "AWS identity used for the single-account lab bootstrap:"
aws sts get-caller-identity

terraform -chdir="$DIR" init
terraform -chdir="$DIR" fmt -check -recursive
terraform -chdir="$DIR" validate
terraform -chdir="$DIR" plan -var-file=terraform.tfvars -out=bootstrap.plan
terraform -chdir="$DIR" apply bootstrap.plan

echo
terraform -chdir="$DIR" output
