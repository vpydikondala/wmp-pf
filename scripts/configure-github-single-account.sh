#!/usr/bin/env bash
set -euo pipefail
# Requires gh + jq. Run after bootstrap and after creating GitHub environments dev/uat/prod.
REPO="${1:?Usage: $0 ORG/REPO}"
BOOTSTRAP_DIR="$(cd "$(dirname "$0")/../bootstrap/single-account-lab" && pwd)"
cd "$BOOTSTRAP_DIR"
ACCOUNT_ID="$(terraform output -raw aws_account_id)"
BUCKET="$(terraform output -raw state_bucket_name)"
KMS_ARN="$(terraform output -raw state_kms_key_arn)"
PLAN_JSON="$(terraform output -json github_plan_role_arns)"
APPLY_JSON="$(terraform output -json github_apply_role_arns)"
for env in dev uat prod; do
  gh api --method PUT "repos/${REPO}/environments/${env}" >/dev/null
  gh variable set AWS_REGION --repo "$REPO" --env "$env" --body "eu-west-2"
  gh variable set AWS_ACCOUNT_ID --repo "$REPO" --env "$env" --body "$ACCOUNT_ID"
  gh variable set TF_STATE_BUCKET --repo "$REPO" --env "$env" --body "$BUCKET"
  gh variable set TF_STATE_KMS_KEY_ARN --repo "$REPO" --env "$env" --body "$KMS_ARN"
  gh variable set AWS_PLAN_ROLE_ARN --repo "$REPO" --env "$env" --body "$(jq -r --arg e "$env" '.[$e]' <<<"$PLAN_JSON")"
  gh variable set AWS_APPLY_ROLE_ARN --repo "$REPO" --env "$env" --body "$(jq -r --arg e "$env" '.[$e]' <<<"$APPLY_JSON")"
done
echo "Configured dev/uat/prod GitHub environment variables. Configure PROD required reviewers in GitHub UI."
