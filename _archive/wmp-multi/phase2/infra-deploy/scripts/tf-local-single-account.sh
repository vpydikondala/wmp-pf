#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:?Usage: $0 <plan|apply|destroy> <dev|uat|prod> <aws-profile>}"
ENVIRONMENT="${2:?Missing environment}"
AWS_PROFILE_NAME="${3:?Missing AWS profile}"
case "$ENVIRONMENT" in dev|uat|prod) ;; *) echo "Invalid environment: $ENVIRONMENT"; exit 1;; esac
export AWS_PROFILE="$AWS_PROFILE_NAME"
cd "$(dirname "$0")/../terraform"
KMS_ARN="${TF_STATE_KMS_KEY_ARN:?Set TF_STATE_KMS_KEY_ARN from bootstrap output}"
terraform init -reconfigure -backend-config="backends/${ENVIRONMENT}.hcl" -backend-config="kms_key_id=${KMS_ARN}"
case "$ACTION" in
  plan) terraform plan -var-file="environments/${ENVIRONMENT}.tfvars" ;;
  apply) terraform apply -var-file="environments/${ENVIRONMENT}.tfvars" ;;
  destroy) terraform destroy -var-file="environments/${ENVIRONMENT}.tfvars" ;;
  *) echo "Invalid action: $ACTION"; exit 1;;
esac
