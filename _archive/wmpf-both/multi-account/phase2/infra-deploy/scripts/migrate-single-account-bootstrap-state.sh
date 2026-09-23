#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE_NAME="${1:?Usage: $0 <aws-profile>}"
DIR="bootstrap/single-account-lab"

export AWS_PROFILE="$AWS_PROFILE_NAME"
export AWS_REGION="${AWS_REGION:-eu-west-2}"

BUCKET="$(terraform -chdir="$DIR" output -raw state_bucket_name)"
KMS_ARN="$(terraform -chdir="$DIR" output -raw state_kms_key_arn)"

cat > "$DIR/backend.tf" <<'HCL'
terraform {
  backend "s3" {}
}
HCL

echo "Migrating single-account lab bootstrap state to s3://${BUCKET}/bootstrap/terraform.tfstate"
terraform -chdir="$DIR" init \
  -force-copy \
  -backend-config=backend.hcl \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="kms_key_id=${KMS_ARN}"

terraform -chdir="$DIR" state list >/dev/null
echo "Bootstrap state migrated successfully."
echo "TF_STATE_BUCKET=${BUCKET}"
echo "TF_STATE_KMS_KEY_ARN=${KMS_ARN}"
