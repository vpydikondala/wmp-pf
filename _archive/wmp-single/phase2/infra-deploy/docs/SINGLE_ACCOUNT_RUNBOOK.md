# Single AWS account runbook

## State layout in existing `wmp-tfstate`
- `bootstrap/terraform.tfstate`
- `infrastructure/dev/terraform.tfstate`
- `application/dev/terraform.tfstate`
- `infrastructure/uat/terraform.tfstate`
- `application/uat/terraform.tfstate`
- `infrastructure/prod/terraform.tfstate`
- `application/prod/terraform.tfstate`

All states use the existing KMS key and native S3 lock files.

## GitHub
Create two repositories:
1. `workplace-management-infrastructure`
2. `workplace-management-application`

Create GitHub Environments `dev`, `uat`, `prod` in both. Protect `prod` with required reviewers and
deployment-branch restrictions. Configure environment variables:
`AWS_REGION`, `AWS_ACCOUNT_ID`, `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ARN` plus the relevant OIDC role ARNs.

Deploy infrastructure first. The application repository reads only the matching environment's
infrastructure state and writes only its own application state.
