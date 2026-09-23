# Final deployment runbook — multi-account

## 1. Merge into the real existing repository
Preserve all existing Phase-1 files and state. Add the supplied `phase2/` tree. Merge the supplied
Phase-2 workflow YAML files with the repository-root `.github/workflows/` directory using
`scripts/install-phase2-workflows.ps1` or `.sh`.

## 2. GitHub Environments
Create `dev`, `uat`, `prod`. Protect PROD with required reviewers and deployment branch rules.

Configure environment variables:
- `AWS_REGION=eu-west-2`
- `AWS_ACCOUNT_ID`
- `TF_STATE_BUCKET`
- `TF_STATE_KMS_KEY_ARN`
- `AWS_INFRA_PLAN_ROLE_ARN`
- `AWS_INFRA_APPLY_ROLE_ARN`
- `AWS_APP_BUILD_ROLE_ARN`
- `AWS_APP_DEPLOY_ROLE_ARN`
- `AWS_APP_TEST_ROLE_ARN`
- `APPLICATION_BASE_URL` when applicable.

## 3. OIDC
Use GitHub OIDC; do not configure long-lived AWS keys. Scope trust to:
`repo:YOUR-ORG/existing-repo:environment:dev|uat|prod`.
Keep infrastructure and application permission policies separate.

## 4. Deploy Phase-2 infrastructure first
Run `phase2-infra-pr`, then `phase2-infra-deploy` for DEV. Inspect plan before apply.
Repeat for UAT and PROD only after environment acceptance.

## 5. Build/deploy applications
`phase2-app-ci` performs unit/SAST/SCA/secret/container/IaC checks.
`phase2-app-deploy` builds immutable images, scans them, creates SBOMs, pushes ECR and deploys
application Terraform onto the Phase-2 infrastructure.

## 6. Migration controls
Keep Phase 1 running until Phase 2 passes acceptance. Before activating ECS Processor, disable the
legacy Lambda SQS event-source mapping. Before activating Dashboard Sync, disable the legacy
Meraki Dashboard polling schedule. Do not run duplicate active consumers/pollers.

## 7. Promotion
DEV -> UAT -> PROD. Promote the same approved source/release identifier; do not make unreviewed
environment-specific source changes. PROD Scan Ingress uses the configured ECS blue/green path.

## 8. Verification
Run smoke tests after every deployment. DEV/UAT additionally run integration/functional tests;
UAT runs security, resilience and NFR/performance tests. PROD receives non-destructive smoke and
health/bake validation.
