# GitHub Setup — Single AWS Account, DEV/UAT/PROD

The authoritative end-to-end procedure is `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md`.

Create GitHub Environments `dev`, `uat`, `prod`. All three target the same AWS account but use different OIDC-trusted IAM roles and different Terraform state keys. Configure `prod` with required reviewer(s); optionally protect UAT.

Each environment requires: `AWS_REGION`, `AWS_ACCOUNT_ID`, `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ARN`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`. `AWS_ACCOUNT_ID` is only a safety assertion and is identical for all three environments.

Run after AWS bootstrap:

```bash
gh auth login
./scripts/configure-github-single-account.sh YOUR-ORG/YOUR-REPO
```

The reusable Terraform workflow requests `id-token: write`, exchanges the GitHub OIDC token for short-lived AWS credentials, verifies the target account, initializes the correct state backend, plans with the environment tfvars, and applies the exact saved plan.

Deployment workflows are only `deploy-dev.yml`, `deploy-uat.yml`, and `deploy-prod.yml`.
