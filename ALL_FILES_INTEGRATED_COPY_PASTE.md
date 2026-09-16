# ALL FILES - INTEGRATED COPY/PASTE

## `.env.example`
```
# LOCAL ONLY - copy to .env.<environment>; do not commit real values.
AWS_PROFILE=wmp-dev
AWS_REGION=eu-west-2
TF_STATE_BUCKET=REPLACE-COMPANY-wmp-dev-tfstate
TF_STATE_KMS_KEY_ARN=arn:aws:kms:eu-west-2:REPLACE:key/REPLACE

```

## `.github/CODEOWNERS`
```
* @REPLACE_ORG/platform-team
/terraform/ @REPLACE_ORG/cloud-platform @REPLACE_ORG/security
/bootstrap/ @REPLACE_ORG/cloud-platform @REPLACE_ORG/security
/.github/workflows/ @REPLACE_ORG/platform-team @REPLACE_ORG/security
/terraform/environments/prod.tfvars @REPLACE_ORG/cloud-platform @REPLACE_ORG/security

```

## `.github/security-requirements.txt`
```
checkov
bandit
pip-audit
pytest

```

## `.github/workflows/ci.yml`
```
name: CI

on:
  workflow_dispatch:
  push:
    branches: [main, "feature/**"]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    uses: ./.github/workflows/reusable-ci.yml

```

## `.github/workflows/deploy-dev.yml`
```
name: Deploy DEV
on:
  push:
    branches: [main]
  workflow_dispatch:
jobs:
  plan:
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: dev
      terraform_environment: dev
      mode: plan
      artifact_name: dev-tfplan
  apply:
    needs: plan
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: dev
      terraform_environment: dev
      mode: apply
      plan_source_artifact: dev-tfplan

```

## `.github/workflows/deploy-prod.yml`
```
name: Deploy PROD Blue Green
on:
  workflow_dispatch:
jobs:
  plan:
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: prod
      terraform_environment: prod
      mode: plan
      artifact_name: prod-tfplan
  apply:
    needs: plan
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: prod
      terraform_environment: prod
      mode: apply
      plan_source_artifact: prod-tfplan

```

## `.github/workflows/deploy-uat.yml`
```
name: Deploy UAT
on:
  workflow_dispatch:
jobs:
  plan:
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: uat
      terraform_environment: uat
      mode: plan
      artifact_name: uat-tfplan
  apply:
    needs: plan
    uses: ./.github/workflows/reusable-terraform.yml
    with:
      environment: uat
      terraform_environment: uat
      mode: apply
      plan_source_artifact: uat-tfplan

```

## `.github/workflows/reusable-build-push.yml`
```
name: Reusable Build and Push Images

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      terraform_environment:
        required: true
        type: string

permissions:
  contents: read
  id-token: write

jobs:
  build-push:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v6.1.0
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6.2.3
        with:
          role-to-assume: ${{ vars.AWS_APPLY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
          role-session-name: gha-${{ inputs.terraform_environment }}-images
      - name: Verify AWS account
        run: |
          ACTUAL="$(aws sts get-caller-identity --query Account --output text)"
          test "$ACTUAL" = "${{ vars.AWS_ACCOUNT_ID }}"
      - name: Build and push immutable service images
        env:
          AWS_REGION: ${{ vars.AWS_REGION }}
          PROJECT_NAME: occupancy-platform
        run: ./scripts/build-push-images.sh "${{ inputs.terraform_environment }}" "${GITHUB_SHA}"

```

## `.github/workflows/reusable-ci.yml`
```
name: Reusable CI

on:
  workflow_call:

permissions:
  contents: read

jobs:
  terraform-quality-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6.1.0
      - uses: hashicorp/setup-terraform@v4.0.1
        with:
          terraform_version: ${{ vars.TERRAFORM_VERSION || '1.16.2' }}
      - name: Terraform fmt
        run: terraform -chdir=terraform fmt -check -recursive
      - name: Terraform init without backend
        run: terraform -chdir=terraform init -backend=false
      - name: Terraform validate
        run: terraform -chdir=terraform validate
      - name: TFLint setup
        uses: terraform-linters/setup-tflint@v5
        with:
          tflint_version: v0.59.1
      - name: TFLint init
        run: tflint --init
      - name: TFLint
        run: tflint --chdir=terraform --recursive
      - name: Checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: terraform
          framework: terraform
          quiet: true
          soft_fail: false

  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6.1.0
        with:
          fetch-depth: 0
      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  python-security-unit:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        service: [inbound, outbound, processor, management]
    steps:
      - uses: actions/checkout@v6.1.0
      - uses: actions/setup-python@v6
        with:
          python-version: ${{ vars.PYTHON_VERSION || '3.12' }}
          cache: pip
      - name: Install service and security tools
        run: |
          python -m pip install --upgrade pip
          pip install -e services/common
          pip install -r services/${{ matrix.service }}/requirements.txt
          pip install bandit pip-audit pytest
      - name: Bandit SAST
        run: bandit -r services/${{ matrix.service }}/src --severity-level medium --confidence-level medium
      - name: Dependency audit
        run: pip-audit -r services/${{ matrix.service }}/requirements.txt
      - name: Unit tests
        env:
          PYTHONPATH: services/${{ matrix.service }}/src
        run: pytest -q services/${{ matrix.service }}/tests

  workflow-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6.1.0
      - name: actionlint
        uses: raven-actions/actionlint@v2

  container-security:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        service: [inbound, outbound, processor, management]
    steps:
      - uses: actions/checkout@v6.1.0
      - name: Build container
        run: docker build -f services/${{ matrix.service }}/Dockerfile -t occupancy-${{ matrix.service }}:${GITHUB_SHA} .
      - name: Trivy HIGH/CRITICAL gate
        run: |
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:0.74.0 image \
            --exit-code 1 \
            --severity HIGH,CRITICAL \
            --ignore-unfixed \
            occupancy-${{ matrix.service }}:${GITHUB_SHA}

  integration:
    runs-on: ubuntu-latest
    needs: [python-security-unit]
    steps:
      - uses: actions/checkout@v6.1.0
      - uses: actions/setup-python@v6
        with:
          python-version: ${{ vars.PYTHON_VERSION || '3.12' }}
      - name: Local end-to-end integration tests
        run: ./scripts/integration/run.sh

```

## `.github/workflows/reusable-deployed-tests.yml`
```
name: Reusable Deployed Tests

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      terraform_environment:
        required: true
        type: string
      run_performance:
        required: false
        type: boolean
        default: false

permissions:
  contents: read
  id-token: write

jobs:
  deployed-tests:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v6.1.0
      - uses: hashicorp/setup-terraform@v4.0.1
        with:
          terraform_version: ${{ vars.TERRAFORM_VERSION || '1.16.2' }}
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6.2.3
        with:
          role-to-assume: ${{ vars.AWS_PLAN_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
          role-session-name: gha-${{ inputs.terraform_environment }}-verify
      - name: Terraform init and resolve endpoint
        id: endpoint
        shell: bash
        run: |
          terraform init -reconfigure \
            -backend-config="backends/${{ inputs.terraform_environment }}.hcl" \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="kms_key_id=${{ vars.TF_STATE_KMS_KEY_ARN }}"
          DOMAIN=$(terraform output -raw cloudfront_domain_name)
          test -n "$DOMAIN"
          echo "base_url=https://${DOMAIN}" >> "$GITHUB_OUTPUT"
      - name: Health smoke test
        working-directory: .
        env:
          SMOKE_BASE_URL: ${{ steps.endpoint.outputs.base_url }}
        run: ./scripts/smoke-test.sh "${{ inputs.terraform_environment }}"
      - name: Functional webhook smoke test
        if: vars.RUN_FUNCTIONAL_SMOKE == 'true'
        working-directory: .
        env:
          SMOKE_BASE_URL: ${{ steps.endpoint.outputs.base_url }}
          WEBHOOK_SECRET: ${{ secrets.WEBHOOK_TEST_SECRET }}
        run: ./scripts/functional-smoke-test.sh
      - name: Performance gate
        if: inputs.run_performance
        working-directory: .
        env:
          WEBHOOK_SECRET: ${{ secrets.WEBHOOK_TEST_SECRET }}
          PERF_USERS: ${{ vars.PERF_USERS || '10' }}
          PERF_SPAWN_RATE: ${{ vars.PERF_SPAWN_RATE || '2' }}
          PERF_DURATION: ${{ vars.PERF_DURATION || '30s' }}
          PERF_FAIL_RATIO: ${{ vars.PERF_FAIL_RATIO || '0.01' }}
          PERF_P95_LIMIT_MS: ${{ vars.PERF_P95_LIMIT_MS || '1500' }}
          PERF_MIN_RPS: ${{ vars.PERF_MIN_RPS || '1' }}
        run: ./scripts/performance-test.sh "${{ steps.endpoint.outputs.base_url }}"

```

## `.github/workflows/reusable-terraform.yml`
```
name: Reusable Terraform

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      terraform_environment:
        required: true
        type: string
      mode:
        required: true
        type: string
      artifact_name:
        required: false
        type: string
        default: tfplan
      plan_source_artifact:
        required: false
        type: string
        default: ""

permissions:
  contents: read
  id-token: write

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    concurrency:
      group: terraform-${{ inputs.environment }}
      cancel-in-progress: false
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v6.1.0
      - uses: hashicorp/setup-terraform@v4.0.1
        with:
          terraform_version: ${{ vars.TERRAFORM_VERSION || '1.16.2' }}
      - name: Configure AWS credentials - plan
        if: inputs.mode == 'plan'
        uses: aws-actions/configure-aws-credentials@v6.2.3
        with:
          role-to-assume: ${{ vars.AWS_PLAN_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
          role-session-name: gha-${{ inputs.environment }}-plan
      - name: Configure AWS credentials - apply
        if: inputs.mode == 'apply'
        uses: aws-actions/configure-aws-credentials@v6.2.3
        with:
          role-to-assume: ${{ vars.AWS_APPLY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
          role-session-name: gha-${{ inputs.environment }}-apply
      - name: Verify AWS account
        run: |
          set -euo pipefail
          ACTUAL="$(aws sts get-caller-identity --query Account --output text)"
          echo "Target account: $ACTUAL"
          test "$ACTUAL" = "${{ vars.AWS_ACCOUNT_ID }}"
      - name: Terraform init
        run: |
          terraform init -reconfigure \
            -backend-config="backends/${{ inputs.terraform_environment }}.hcl" \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="kms_key_id=${{ vars.TF_STATE_KMS_KEY_ARN }}"
      - name: Terraform validate
        run: terraform validate
      - name: Terraform plan
        if: inputs.mode == 'plan'
        run: |
          terraform plan \
            -var-file="environments/${{ inputs.terraform_environment }}.tfvars" \
            -var="container_image_tag=${GITHUB_SHA}" \
            -out=tfplan
          terraform show -no-color tfplan > tfplan.txt
          terraform show -json tfplan > tfplan.json
      - name: Upload plan
        if: inputs.mode == 'plan'
        uses: actions/upload-artifact@v7
        with:
          name: ${{ inputs.artifact_name }}
          path: |
            terraform/tfplan
            terraform/tfplan.txt
            terraform/tfplan.json
          retention-days: 5
      - name: Download approved plan
        if: inputs.mode == 'apply'
        uses: actions/download-artifact@v8
        with:
          name: ${{ inputs.plan_source_artifact }}
          path: terraform
      - name: Build and push immutable service images
        if: inputs.mode == 'apply'
        working-directory: .
        env:
          AWS_REGION: ${{ vars.AWS_REGION }}
          PROJECT_NAME: occupancy-platform
        run: ./scripts/build-push-images.sh "${{ inputs.terraform_environment }}" "${GITHUB_SHA}"
      - name: Apply exact plan
        if: inputs.mode == 'apply'
        run: terraform apply -auto-approve tfplan

```

## `.gitignore`
```
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
*.plan
crash.log
crash.*.log
.terraformrc
terraform.rc
bootstrap/environments/*/terraform.tfvars
bootstrap/environments/*/backend.tf
.env
.env.*
!.env.example
__pycache__/
.pytest_cache/
.venv/
venv/
coverage.xml
htmlcov/
.DS_Store
.integration.env
*-meraki-secret.json
locust*.csv

```

## `.tflint.hcl`
```
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.42.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

```

## `APPLICATION_AND_TESTING.md`
```
# Application and Testing

The durable environments are DEV, UAT and PROD. DEV is the first integration environment; UAT is the release-qualification environment; PROD is the protected production-style lab environment.

The ALB-facing inbound/API service runs in APP subnets without a NAT/default Internet route. Processor runs in the Processor subnet tier and is the only ECS workload intended to initiate public Internet communication to Meraki through NAT. The historical standalone `outbound` service is disabled by default in all three environment tfvars.

Recommended validation flow is: local/unit/container tests -> DEV integration and smoke tests -> UAT functional/contract/performance validation -> PROD deployment health/alarm validation. Production inbound/API releases use native ECS blue/green; Processor revision changes require active/passive polling ownership to avoid duplicate Meraki polling.

Local Docker Compose files are development/test utilities and do not create an additional AWS environment.

```

## `DEPLOYMENT_MODES.md`
```
# Deployment Modes

This repository supports one target lab topology: **one AWS account with DEV, UAT and PROD**. There is no Test/Preprod/four-account deployment mode in this baseline.

## Local administrator mode

Used for the one-time bootstrap and first environment foundation creation. Authenticate with an administrator/SSO profile, run `scripts/bootstrap-single-account-lab.sh`, migrate bootstrap state, then use `scripts/tf-local-single-account.sh` for controlled local plan/apply.

## Remote GitHub OIDC mode

Used for normal deployments. GitHub Environments `dev`, `uat`, and `prod` assume separate plan/apply roles through the single AWS GitHub OIDC provider. No static AWS keys are stored in GitHub.

## Production deployment mode

Only PROD enables native ECS blue/green for the ALB-facing inbound/API service. Processor uses controlled active/passive revision ownership rather than ALB traffic switching.

```

## `GITHUB_SETUP.md`
```
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

```

## `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md`
```
# IAM, Bootstrap and Deployment Runbook

## 1. What is created manually vs by Terraform

Use an existing AWS administrator/SSO role only for the **first bootstrap**. Do not manually create the GitHub deployment roles or ECS blue/green role in the console; Terraform creates them.

Bootstrap Terraform creates once in the single AWS account:
- S3 state bucket (`wmp-tfstate` by default), versioning, Block Public Access and TLS-only bucket policy.
- One customer-managed KMS key and alias for Terraform state.
- One GitHub OIDC provider for `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com` (unless one already exists and its ARN is supplied).
- DEV/UAT/PROD GitHub plan roles.
- DEV/UAT/PROD GitHub apply roles.
- Environment-scoped state policies and IAM-management/PassRole policy.

Application Terraform later creates the VPCs, ECS/ECR, ALB, RDS, queues, application IAM roles and the PROD ECS blue/green infrastructure role.

## 2. Prerequisites on your workstation

Install/configure: AWS CLI, Terraform, Git, and optionally GitHub CLI (`gh`) plus `jq`. Configure one administrator/SSO profile for the lab account and verify it:

```bash
aws sso login --profile wmp-lab        # if using IAM Identity Center
aws sts get-caller-identity --profile wmp-lab
terraform version
```

The account returned by STS is the only AWS account used by DEV/UAT/PROD.

## 3. Configure bootstrap variables

From repository root:

```bash
cp bootstrap/single-account-lab/terraform.tfvars.example \
   bootstrap/single-account-lab/terraform.tfvars
```

Edit `bootstrap/single-account-lab/terraform.tfvars`:

```hcl
aws_region        = "eu-west-2"
project_name      = "occupancy-platform"
owner             = "platform-team"
state_bucket_name = "wmp-tfstate"
existing_github_oidc_provider_arn = null

github_oidc_subjects = {
  dev_plan   = "repo:YOUR-ORG/YOUR-REPO:environment:dev"
  dev_apply  = "repo:YOUR-ORG/YOUR-REPO:environment:dev"
  uat_plan   = "repo:YOUR-ORG/YOUR-REPO:environment:uat"
  uat_apply  = "repo:YOUR-ORG/YOUR-REPO:environment:uat"
  prod_plan  = "repo:YOUR-ORG/YOUR-REPO:environment:prod"
  prod_apply = "repo:YOUR-ORG/YOUR-REPO:environment:prod"
}
```

Replace `YOUR-ORG/YOUR-REPO`. If `wmp-tfstate` is unavailable, choose another globally unique bucket name. Do not add an account number unless you choose to.

If the AWS account already has the GitHub Actions OIDC provider, set `existing_github_oidc_provider_arn` to that provider ARN instead of trying to create it again.

## 4. Run bootstrap locally with administrator credentials

From repository root:

```bash
./scripts/bootstrap-single-account-lab.sh wmp-lab
```

The script runs `terraform init`, format check, validate, plan and apply against `bootstrap/single-account-lab` and prints outputs.

Expected IAM roles:

```text
occupancy-platform-dev-github-plan
occupancy-platform-dev-github-apply
occupancy-platform-uat-github-plan
occupancy-platform-uat-github-apply
occupancy-platform-prod-github-plan
occupancy-platform-prod-github-apply
```

### Bootstrap role permissions

Plan roles receive:
- environment state S3/KMS access;
- AWS managed `ReadOnlyAccess` for Terraform planning.

Apply roles receive:
- environment state S3/KMS access;
- AWS managed `PowerUserAccess` for this lab;
- an additional scoped IAM policy allowing creation/management of application roles named `occupancy-platform-<env>-*`;
- scoped `iam:PassRole` for those roles when passed to `ecs-tasks.amazonaws.com` or `ecs.amazonaws.com`;
- constrained `iam:CreateServiceLinkedRole` for ECS, ELB and RDS.

`PowerUserAccess` is a lab bootstrap choice. Replace it with organisation-approved least-privilege deployment policies in the real project.

## 5. What the OIDC trust does

There is **one** AWS IAM OIDC provider. Environment separation is implemented by six role trust policies. Each role requires:

```text
aud = sts.amazonaws.com
sub = repo:YOUR-ORG/YOUR-REPO:environment:<dev|uat|prod>
```

Therefore a job using GitHub Environment `dev` can assume the DEV role but not the UAT/PROD roles. The GitHub workflow must have `permissions: id-token: write`; `reusable-terraform.yml` already has it.

## 6. Migrate bootstrap state to the shared S3 backend

After bootstrap succeeds:

```bash
./scripts/migrate-single-account-bootstrap-state.sh wmp-lab
```

Bootstrap state becomes:

```text
s3://wmp-tfstate/bootstrap/terraform.tfstate
```

Workload state uses the same bucket/KMS key but independent keys:

```text
dev/terraform.tfstate
uat/terraform.tfstate
prod/terraform.tfstate
```

Native S3 lock files are enabled with `use_lockfile = true`.

## 7. Create/configure GitHub Environments

In GitHub: **Repository → Settings → Environments**. Create exactly:

```text
dev
uat
prod
```

Recommended lab protection:
- `dev`: no approval.
- `uat`: optional reviewer if you want a promotion gate.
- `prod`: required reviewer and restrict deployment to `main` as appropriate.

If `gh` and `jq` are installed and authenticated, populate the environment variables automatically:

```bash
gh auth login
./scripts/configure-github-single-account.sh YOUR-ORG/YOUR-REPO
```

For every GitHub Environment the script sets:
- `AWS_REGION=eu-west-2`
- `AWS_ACCOUNT_ID=<same lab account for all three>` (safety check only)
- `TF_STATE_BUCKET=<shared bucket>`
- `TF_STATE_KMS_KEY_ARN=<shared key>`
- environment-specific `AWS_PLAN_ROLE_ARN`
- environment-specific `AWS_APPLY_ROLE_ARN`

No long-lived AWS access key or secret key is stored in GitHub.

## 8. Verify workload environment configuration

Files:

```text
terraform/environments/dev.tfvars
terraform/environments/uat.tfvars
terraform/environments/prod.tfvars
```

Required VPC results:
- DEV: `10.0.0.0/21`
- `10.0.8.0/21`: reserved
- UAT: `10.0.16.0/21`
- PROD: `10.0.24.0/21`

Every deployed environment uses functional allocations: ALB #0, APP #1 (no NAT), VPCE #2, RDS #3, NAT #4, Processor #5 (NAT), reserved #6/#7. Each deployed `/24` is split across AZs as `/25`s.

Only PROD sets:

```hcl
inbound_blue_green_enabled           = true
inbound_blue_green_bake_time_minutes = 10
```

DEV/UAT keep blue/green disabled.

## 9. First workload deployment: create foundation before images/services

The committed tfvars enable inbound and Processor services. On a brand-new account the ECR repositories do not yet exist, so first create the foundation with ECS services disabled.

For the first DEV apply, temporarily set in `terraform/environments/dev.tfvars`:

```hcl
inbound_service   = false
outbound_service  = false
processor_service = false
    management_service = false
```

Get the shared KMS ARN:

```bash
export AWS_PROFILE=wmp-lab
export TF_STATE_KMS_KEY_ARN="$(terraform -chdir=bootstrap/single-account-lab output -raw state_kms_key_arn)"
```

Then:

```bash
./scripts/tf-local-single-account.sh plan  dev wmp-lab
./scripts/tf-local-single-account.sh apply dev wmp-lab
```

This establishes the environment foundation/ECR without asking ECS to pull images that do not yet exist.

Repeat the same foundation procedure for UAT and PROD when you first create those environments.

## 10. Build/push first immutable images

After the environment ECR repositories exist:

```bash
./scripts/build-push-images.sh dev bootstrap-001
```

Restore DEV tfvars to:

```hcl
inbound_service   = true
outbound_service  = false
processor_service = true
```

The historical `outbound` service remains disabled. Processor owns Internet-initiated Meraki polling/outbound behaviour and is the workload placed in NAT-routed Processor subnets.

Apply DEV again locally if desired:

```bash
./scripts/tf-local-single-account.sh plan  dev wmp-lab
./scripts/tf-local-single-account.sh apply dev wmp-lab
```

For normal GitHub releases, the reusable workflow uses the Git commit SHA as the immutable image tag.

## 11. Validate local Terraform before remote deployment

Run:

```bash
cd terraform
terraform fmt -recursive -check
terraform init -reconfigure \
  -backend-config=backends/dev.hcl \
  -backend-config="kms_key_id=${TF_STATE_KMS_KEY_ARN}"
terraform validate
terraform plan -var-file=environments/dev.tfvars
```

Repeat with `uat` and `prod` backend/tfvars when appropriate. Never reuse a DEV initialized working directory for PROD without `terraform init -reconfigure`.

## 12. Push repository to GitHub

Commit only source/configuration. Do not commit `terraform.tfvars` containing local bootstrap customisation, `.terraform`, state files, plan files, secrets or AWS credentials.

```bash
git add .
git commit -m "Configure single-account DEV UAT PROD ECS blue-green"
git push origin main
```

## 13. Remote GitHub deployment order

### DEV
`deploy-dev.yml` runs on `main` push or manually:

```text
GitHub dev Environment
 -> OIDC -> DEV plan role
 -> init dev/terraform.tfstate
 -> Terraform plan
 -> upload exact plan
 -> OIDC -> DEV apply role
 -> build/push immutable images
 -> apply exact plan
```

### UAT
Run **Actions → Deploy UAT → Run workflow** after DEV validation. It uses UAT roles, `uat/terraform.tfstate` and `uat.tfvars`.

### PROD
After UAT validation run **Actions → Deploy PROD Blue Green → Run workflow**. The `prod` GitHub Environment approval gate protects the apply job. It uses PROD roles, `prod/terraform.tfstate` and `prod.tfvars`.

## 14. Production native ECS blue/green IAM chain

Application Terraform creates an ECS infrastructure role trusted by:

```text
ecs.amazonaws.com
```

and attaches `AmazonECSInfrastructureRolePolicyForLoadBalancers`. The PROD GitHub apply role does not assume this role; it has scoped `iam:PassRole` so Terraform can pass it to ECS. ECS then uses it for load-balancer blue/green operations.

Separate ECS task/execution roles are trusted by:

```text
ecs-tasks.amazonaws.com
```

The PROD GitHub apply role can pass those roles only to the appropriate ECS service principals through `iam:PassedToService`.

## 15. Production blue/green release sequence

```text
GitHub PROD approval
 -> OIDC assumes PROD apply role
 -> publish/register new task revision
 -> ECS creates GREEN replacement tasks
 -> GREEN registers in alternate target group
 -> ALB health checks GREEN
 -> ECS moves production traffic BLUE -> GREEN
 -> configured bake period runs with old BLUE retained
 -> healthy: deployment completes and old BLUE is terminated
 -> alarm/failure: ECS rolls back toward the previous revision
```

Target groups are reusable slots; TG-A is not permanently Blue and TG-B is not permanently Green.

Processor is not treated as an ALB blue/green service. If polling ownership changes between Processor revisions, use an active/passive ownership control so two revisions do not poll Meraki simultaneously.

## 16. Day-to-day deployment

After initial foundation bootstrap, administrators should not run normal releases with AWS admin credentials. Normal flow is:

```text
code -> PR/CI -> merge main -> DEV -> validate -> UAT -> validate -> PROD approval -> ECS blue/green
```

Use the administrator profile only for bootstrap recovery or explicitly approved platform administration.

## 17. Troubleshooting checkpoints

- `AccessDenied` reading state: verify role has the correct environment state object and shared KMS permissions.
- `Not authorized to perform sts:AssumeRoleWithWebIdentity`: check GitHub Environment name and OIDC `sub` exactly match the trust policy.
- `iam:PassRole` denied: verify target role name begins `occupancy-platform-<env>-` and `iam:PassedToService` is `ecs-tasks.amazonaws.com` or `ecs.amazonaws.com`.
- First deployment cannot push image: create ECR/foundation with ECS services disabled first.
- APP task cannot reach public Internet: expected by design. Only Processor has NAT-routed Internet egress.
- Blue/green not created in DEV/UAT: expected. It is enabled only in PROD.

```

## `IMPLEMENTATION_RUNBOOK.md`
```
# Implementation Runbook

This repository is now DEV/UAT/PROD only in a single AWS account. Follow `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` as the authoritative ordered procedure.

High-level sequence:

```text
1 Administrator/SSO AWS access
2 Configure bootstrap terraform.tfvars
3 Local bootstrap: shared S3 + KMS + one GitHub OIDC provider + six IAM roles
4 Migrate bootstrap state to S3
5 Create/configure GitHub Environments dev/uat/prod
6 First DEV foundation apply with ECS services disabled
7 Build/push first immutable images
8 Enable DEV inbound + Processor services and validate
9 Create/validate UAT
10 Create PROD foundation
11 Enable PROD services
12 Normal releases: GitHub DEV -> UAT -> protected PROD
13 PROD inbound/API uses ECS native blue/green
```

Do not use obsolete Test, Preprod or four-account procedures.

```

## `README-START-HERE.md`
```
# START HERE — WMP Single-Account DEV/UAT/PROD

This repository has exactly three durable environments in one AWS lab account: **DEV, UAT and PROD**. `10.0.8.0/21` is reserved and is not a fourth environment. Production uses native Amazon ECS blue/green for the ALB-facing inbound/API service.

## Read in this order

1. `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` — authoritative end-to-end instructions: administrator bootstrap, S3/KMS, GitHub OIDC, IAM permissions, GitHub Environments, local Terraform and remote GitHub deployment.
2. `SINGLE_ACCOUNT_3ENV_BLUE_GREEN_RUNBOOK.md` — architecture and blue/green operational detail.
3. `terraform/README.md` — Terraform/network specifics.
4. `GITHUB_SETUP.md` — GitHub settings and variables.
5. `APPLICATION_AND_TESTING.md` — application/testing notes.

## Fixed lab model

- One AWS account.
- One shared S3 Terraform-state bucket (`wmp-tfstate` by default; S3 names are globally unique).
- One shared KMS key for Terraform state.
- One GitHub Actions OIDC provider in the AWS account.
- Six GitHub IAM roles: plan/apply for DEV, UAT and PROD.
- Separate state objects: `dev/terraform.tfstate`, `uat/terraform.tfstate`, `prod/terraform.tfstate`.
- DEV VPC `10.0.0.0/21`; UAT VPC `10.0.16.0/21`; PROD VPC `10.0.24.0/21`.
- APP ECS has no NAT/default Internet route. Processor ECS uses the Processor subnet tier with NAT.
- Historical `outbound` service is disabled by default; Meraki polling/outbound ownership belongs to Processor in the target design.

Do not use old Test/Preprod/four-account instructions from earlier repository versions.

```

## `README.md`
```
# Workplace Management / Occupancy Platform

Single-account AWS lab baseline with exactly three durable environments: **DEV, UAT and PROD**. Production uses native ECS blue/green for the ALB-facing inbound/API service.

Start with `README-START-HERE.md`, then follow `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` from the first administrator bootstrap through local foundation deployment and normal GitHub OIDC deployment.

Core controls: one shared S3 Terraform-state bucket, one shared state KMS key, one GitHub OIDC provider, separate DEV/UAT/PROD plan/apply roles, separate state keys, environment tags/names, APP/no-NAT networking, Processor-only NAT egress, and protected PROD blue/green deployment.

## Management service (RDS-backed)

The former local `spatial` application is integrated as `services/management`. Spatial configuration is a Management domain, not a separate ECS service. Management owns CRUD for buildings, floors, zones, access points and desks in PostgreSQL RDS. It runs in APP private subnets behind the existing internal ALB (`/management/*` and `/api/v1/management/*`) and has no NAT route. SQL migrations under `services/management/migrations` provide an out-of-the-box schema on first startup. See `docs/MANAGEMENT_DEMO.md`.

```

## `SINGLE_ACCOUNT_3ENV_BLUE_GREEN_RUNBOOK.md`
```
# Workplace Management — Single AWS Account / DEV-UAT-PROD / ECS Blue-Green Runbook

## 1. Target model
One AWS lab account contains three isolated Terraform environments: DEV, UAT and PROD. One shared bootstrap creates one S3 Terraform-state bucket, one KMS key, one GitHub Actions OIDC provider, and separate plan/apply IAM roles for each environment. PROD alone enables native ECS blue/green for the ALB-facing inbound service. Processor is the only Internet-initiating ECS workload and uses Processor/NAT subnets. The historical outbound service is disabled by default.

State layout:
- `s3://wmp-tfstate/bootstrap/terraform.tfstate`
- `s3://wmp-tfstate/dev/terraform.tfstate`
- `s3://wmp-tfstate/uat/terraform.tfstate`
- `s3://wmp-tfstate/prod/terraform.tfstate`

Network allocations:
- DEV `10.0.0.0/21`
- `10.0.8.0/21` reserved
- UAT `10.0.16.0/21`
- PROD `10.0.24.0/21`

Each `/21` uses `/24` functional blocks: ALB #0, APP #1 (no NAT), VPCE #2, RDS #3, NAT #4, Processor #5 (NAT-routed), #6/#7 reserved. Deployed `/24`s split into two `/25`s across AZs.

## 2. Prerequisites
Install AWS CLI, Terraform >=1.10, Git, Docker, GitHub CLI (`gh`) and `jq`. Configure an AWS CLI profile with AdministratorAccess for the one-time lab bootstrap. Do not create permanent AWS keys for GitHub.

Verify the target account before bootstrap:
```bash
aws sts get-caller-identity --profile <lab-admin-profile>
```

## 3. Prepare bootstrap variables
```bash
cp bootstrap/single-account-lab/terraform.tfvars.example bootstrap/single-account-lab/terraform.tfvars
```
Edit `terraform.tfvars`:
- choose a globally unique S3 bucket name; requested default is `wmp-tfstate`, but S3 names are global
- replace `YOUR-ORG/YOUR-REPO`
- leave `existing_github_oidc_provider_arn = null` unless this account already has the GitHub OIDC provider

There is ONE OIDC provider in the AWS account and six roles:
- `occupancy-platform-dev-github-plan/apply`
- `occupancy-platform-uat-github-plan/apply`
- `occupancy-platform-prod-github-plan/apply`

The trust policies separate environments through the GitHub OIDC `sub` claim. The apply roles have state access, PowerUserAccess for this lab, scoped IAM role management, and scoped `iam:PassRole` for `ecs-tasks.amazonaws.com` and `ecs.amazonaws.com`. Tighten PowerUserAccess for the real project.

## 4. Run the one-time bootstrap locally
From repository root:
```bash
./scripts/bootstrap-single-account-lab.sh <lab-admin-profile>
```
This creates the KMS state key, S3 bucket with versioning/SSE-KMS/public-access block, GitHub OIDC provider, environment plan/apply roles and environment-specific state policies.

Save the outputs. Then migrate bootstrap's local state into the shared S3 bucket:
```bash
./scripts/migrate-single-account-bootstrap-state.sh <lab-admin-profile>
```
After verifying remote state, protect/remove local bootstrap state according to your normal secure process.

## 5. GitHub Environments
In GitHub repository Settings -> Environments create exactly:
- `dev`
- `uat`
- `prod`

Recommended controls: DEV automatic; UAT controlled promotion; PROD required reviewers + protected main branch. The workflow `environment:` value is important because it is part of the OIDC subject.

You can populate variables from bootstrap outputs with:
```bash
./scripts/configure-github-single-account.sh YOUR-ORG/YOUR-REPO
```
This sets per environment: `AWS_REGION`, `AWS_ACCOUNT_ID` (safety check only), `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ARN`, `AWS_PLAN_ROLE_ARN`, and `AWS_APPLY_ROLE_ARN`.

`AWS_ACCOUNT_ID` is not used in the state bucket or key; it only prevents accidental execution against the wrong AWS account.

## 6. Terraform environment files
The repository now contains only:
```text
terraform/environments/dev.tfvars
terraform/environments/uat.tfvars
terraform/environments/prod.tfvars
terraform/backends/dev.hcl
terraform/backends/uat.hcl
terraform/backends/prod.hcl
```
DEV and UAT have `inbound_blue_green_enabled = false`. PROD has `inbound_blue_green_enabled = true` and a 10-minute bake period. All environments have `outbound_service = false` so the legacy public-Meraki poller is not accidentally placed in APP/no-NAT. Polling belongs in Processor/NAT.

## 7. First infrastructure deployment / ECR chicken-and-egg
For the very first deployment of each environment, if container images do not exist, set `service_deployment_enabled = false` (or keep individual ECS service flags disabled) and apply foundational infrastructure/ECR first. Then build and push immutable images, enable service deployment and apply again.

Local plan example:
```bash
export TF_STATE_KMS_KEY_ARN='<bootstrap output ARN>'
./scripts/tf-local-single-account.sh plan dev <lab-admin-profile>
```
CI/CD should be the normal path after OIDC is configured.

## 8. DEV deployment
Run `.github/workflows/deploy-dev.yml`. GitHub obtains a short-lived OIDC token and assumes the DEV role. Terraform initializes `dev/terraform.tfstate`, plans/applies `dev.tfvars`, and creates resources tagged `Environment=dev`. Validate health, webhook/SQS/S3/RDS processing and Processor egress.

## 9. UAT deployment
Run `.github/workflows/deploy-uat.yml` after DEV passes. It assumes only the UAT role and uses `uat/terraform.tfstate`. Promote the same immutable application revision/digest rather than rebuilding different source. Perform integration, Meraki contract, queue/database, functional and acceptance testing.

## 10. PROD blue-green deployment
Protect the GitHub `prod` environment with approval. Run `.github/workflows/deploy-prod.yml`. The PROD role applies `prod.tfvars`. Native ECS blue/green is enabled only for the inbound/ALB-facing ECS service.

Normal release sequence:
1. CI tests/scans source and Terraform.
2. Build/push immutable container image.
3. Deploy/validate DEV.
4. Promote/validate UAT.
5. Approve PROD.
6. Register/update PROD task definition/service with the approved image.
7. ECS starts the GREEN service revision in the same ECS cluster and APP subnets.
8. GREEN registers in the alternate ALB target group and must pass target health checks.
9. ECS switches production traffic from current BLUE to GREEN.
10. During the configured 10-minute bake period both revisions exist; GREEN serves production and BLUE remains available for rollback.
11. If deployment alarms/failure criteria trigger, ECS rolls back to BLUE when configured for rollback.
12. If bake completes successfully, ECS completes deployment and terminates the old BLUE tasks.
13. On the next deployment the target groups/revision roles alternate; there are not permanent Blue and Green environments.

## 11. Required ECS IAM roles
Terraform creates application roles with environment-prefixed names. Keep role purposes separate:
- ECS task execution role: ECR image pull/logging/required startup secret access; trust `ecs-tasks.amazonaws.com`.
- Inbound task role: only inbound application's AWS permissions.
- Processor task role: S3/SQS/secrets/KMS/DB-related permissions needed by Processor.
- ECS blue-green infrastructure role (PROD only): trust `ecs.amazonaws.com`; attach `AmazonECSInfrastructureRolePolicyForLoadBalancers`.
- GitHub PROD apply role must be able to `iam:PassRole` environment-prefixed ECS roles to `ecs-tasks.amazonaws.com` and the blue-green infrastructure role to `ecs.amazonaws.com`.

## 12. Processor deployment rule
Do not use ALB blue/green semantics blindly for a Meraki poller. Never allow two revisions to become independent active pollers unless application-level locking guarantees single ownership. Use active/passive ownership: old Processor active -> deploy new revision -> validate -> transfer polling ownership -> observe -> terminate old revision. SQS consumers must remain idempotent.

## 13. Tagging
The AWS provider uses common/default tags including `Project`, `Environment`, `ManagedBy`, and `Owner`. Resource names also include the environment prefix (`occupancy-platform-dev-*`, `-uat-*`, `-prod-*`). Use AWS Cost Explorer/Tag Editor with `Environment` to distinguish lab spend. Activate the `Environment` cost-allocation tag in Billing if you want cost reporting by environment.

## 14. Validation before PROD
Run locally or in CI:
```bash
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
```
Then create environment-specific plans. Inspect that DEV/UAT do not create blue-green alternate target-group infrastructure and PROD does. Confirm APP route tables have no Internet default route and Processor route tables have `0.0.0.0/0 -> NAT`.

## 15. Important lab limitations
All three environments share one AWS account and one state KMS key, so the account boundary does not protect PROD from an overly broad IAM policy. State objects and GitHub roles are separated, but `PowerUserAccess` remains intentionally broad for the lab. For the real project, replace it with scoped deployment permissions and follow the enterprise landing-zone/account model.

```

## `SINGLE_ACCOUNT_LAB_RUNBOOK.md`
```
# Single-Account Lab Runbook

The lab contains exactly DEV, UAT and PROD in one AWS account. This file is retained as a compatibility entry point; use `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` for the full ordered instructions and `SINGLE_ACCOUNT_3ENV_BLUE_GREEN_RUNBOOK.md` for blue/green architecture detail.

```

## `VALIDATION_NOTES.md`
```
# Validation notes

Repository-generation validation completed in the build workspace:

- Python `compileall`: PASS
- Bash syntax (`bash -n`) for all scripts: PASS
- GitHub Actions YAML parse: PASS
- Docker Compose YAML parse: PASS
- Terraform/application IAM consistency check: outbound now has S3 and processing-SQS permissions matching its implemented behavior

Dependency-backed pytest, Docker Compose and Terraform CLI execution could not be run in the artifact-generation workspace because outbound package/network access and the Terraform/Docker CLIs are not available there. The repository CI and local run scripts perform these checks in the target developer/GitHub environment.

```

## `bootstrap/single-account-lab/backend.hcl`
```
bucket       = "wmp-tfstate"
key          = "bootstrap/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true

```

## `bootstrap/single-account-lab/main.tf`
```
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  environments = toset(["dev", "uat", "prod"])

  state_keys = {
    dev  = "dev/terraform.tfstate"
    uat  = "uat/terraform.tfstate"
    prod = "prod/terraform.tfstate"
  }

  plan_subjects = {
    dev  = var.github_oidc_subjects.dev_plan
    uat  = var.github_oidc_subjects.uat_plan
    prod = var.github_oidc_subjects.prod_plan
  }

  apply_subjects = {
    dev  = var.github_oidc_subjects.dev_apply
    uat  = var.github_oidc_subjects.uat_apply
    prod = var.github_oidc_subjects.prod_apply
  }

  created_github_oidc_provider_arn = try(aws_iam_openid_connect_provider.github[0].arn, null)
  github_oidc_provider_arn         = coalesce(var.existing_github_oidc_provider_arn, local.created_github_oidc_provider_arn)
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_github_oidc_provider_arn == null ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.plan_subjects[each.key]]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.apply_subjects[each.key]]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  for_each           = local.environments
  name               = "${var.project_name}-${each.key}-github-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust[each.key].json
}

resource "aws_iam_role" "github_apply" {
  for_each           = local.environments
  name               = "${var.project_name}-${each.key}-github-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_trust[each.key].json
}

data "aws_iam_policy_document" "state_access" {
  for_each = local.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid     = "ReadWriteEnvironmentState"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}/${local.state_keys[each.key]}"
    ]
  }

  statement {
    sid     = "ManageEnvironmentStateLock"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}/${local.state_keys[each.key]}.tflock"
    ]
  }

  statement {
    sid = "UseStateKmsKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [var.state_kms_key_arn]
  }
}

resource "aws_iam_policy" "state_access" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-terraform-state-access"
  policy   = data.aws_iam_policy_document.state_access[each.key].json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  for_each   = local.environments
  role       = aws_iam_role.github_plan[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  for_each   = local.environments
  role       = aws_iam_role.github_plan[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "terraform_iam_management" {
  for_each = local.environments

  statement {
    sid = "ManageApplicationRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"
    ]
  }

  statement {
    sid     = "PassApplicationRolesToEcs"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateRequiredServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "terraform_iam_management" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-terraform-iam-management"
  policy   = data.aws_iam_policy_document.terraform_iam_management[each.key].json
}

resource "aws_iam_role_policy_attachment" "apply_iam" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = aws_iam_policy.terraform_iam_management[each.key].arn
}

```

## `bootstrap/single-account-lab/outputs.tf`
```
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "state_bucket_name" {
  value = var.state_bucket_name
}

output "state_kms_key_arn" {
  value = var.state_kms_key_arn
}

output "github_oidc_provider_arn" {
  value = local.github_oidc_provider_arn
}

output "github_plan_role_arns" {
  value = { for env, role in aws_iam_role.github_plan : env => role.arn }
}

output "github_apply_role_arns" {
  value = { for env, role in aws_iam_role.github_apply : env => role.arn }
}

output "state_keys" {
  value = local.state_keys
}

```

## `bootstrap/single-account-lab/providers.tf`
```
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform-Bootstrap"
      Purpose   = "single-account-lab"
      Owner     = var.owner
    }
  }
}

```

## `bootstrap/single-account-lab/terraform.tfvars.example`
```
aws_region        = "eu-west-2"
project_name      = "occupancy-platform"
owner             = "platform-team"
state_bucket_name = "wmp-tfstate"
state_kms_key_arn = "arn:aws:kms:eu-west-2:REPLACE_ACCOUNT:key/REPLACE_KEY_ID"

# Leave null when this stack should create the single GitHub Actions OIDC provider.
existing_github_oidc_provider_arn = null

# Replace YOUR-ORG/YOUR-REPO with the real GitHub repository.
# One OIDC provider is shared; environment-specific roles are separated by sub claim.
github_oidc_subjects = {
  dev_plan   = "repo:YOUR-ORG/YOUR-REPO:environment:dev"
  dev_apply  = "repo:YOUR-ORG/YOUR-REPO:environment:dev"
  uat_plan   = "repo:YOUR-ORG/YOUR-REPO:environment:uat"
  uat_apply  = "repo:YOUR-ORG/YOUR-REPO:environment:uat"
  prod_plan  = "repo:YOUR-ORG/YOUR-REPO:environment:prod"
  prod_apply = "repo:YOUR-ORG/YOUR-REPO:environment:prod"
}

```

## `bootstrap/single-account-lab/variables.tf`
```
variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "occupancy-platform"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "state_kms_key_arn" {
  description = "ARN of the existing KMS key used for Terraform remote state."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket used by bootstrap.tfstate and all three logical environment states."
  type        = string
}

variable "existing_github_oidc_provider_arn" {
  description = "If this AWS account already has the GitHub Actions OIDC provider, supply its ARN; otherwise leave null and this stack creates it."
  type        = string
  default     = null
  nullable    = true
}

variable "github_oidc_subjects" {
  description = "Exact GitHub OIDC sub claims used by plan/apply roles for each logical environment."
  type = object({
    dev_plan   = string
    dev_apply  = string
    uat_plan   = string
    uat_apply  = string
    prod_plan  = string
    prod_apply = string
  })
}

```

## `bootstrap/single-account-lab/versions.tf`
```
terraform {
  backend "s3" {}

  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }
}

```

## `docker-compose.integration.yml`
```
services:
  localstack:
    image: localstack/localstack:4.8
    ports:
      - "4566:4566"
    environment:
      SERVICES: s3,sqs,secretsmanager
      AWS_DEFAULT_REGION: eu-west-2
      DEBUG: "0"
      SQS_ENDPOINT_STRATEGY: path
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:4566/_localstack/health"]
      interval: 2s
      timeout: 2s
      retries: 30

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: occupancy
      POSTGRES_USER: platform_admin
      POSTGRES_PASSWORD: integration-password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U platform_admin -d occupancy"]
      interval: 2s
      timeout: 2s
      retries: 30

  mock-meraki:
    build:
      context: .
      dockerfile: services/mock-meraki/Dockerfile
    ports:
      - "8081:8081"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8081/health')"]
      interval: 2s
      timeout: 2s
      retries: 30

  inbound:
    build:
      context: .
      dockerfile: services/inbound/Dockerfile
    ports:
      - "8080:8080"
    environment:
      ENVIRONMENT: integration
      SERVICE_NAME: inbound
      AWS_REGION: eu-west-2
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_ENDPOINT_URL: http://localstack:4566
      DATA_BUCKET: integration-data
      PROCESSING_QUEUE_URL: ${PROCESSING_QUEUE_URL}
      MERAKI_SECRET_ARN: integration-meraki
      WEBHOOK_AUTH_REQUIRED: "true"
    depends_on:
      localstack:
        condition: service_healthy

  processor:
    build:
      context: .
      dockerfile: services/processor/Dockerfile
    environment:
      ENVIRONMENT: integration
      SERVICE_NAME: processor
      AWS_REGION: eu-west-2
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_ENDPOINT_URL: http://localstack:4566
      PROCESSING_QUEUE_URL: ${PROCESSING_QUEUE_URL}
      DATALAKE_QUEUE_URL: ${DATALAKE_QUEUE_URL}
      RDS_ENDPOINT: postgres
      RDS_PORT: "5432"
      RDS_DATABASE: occupancy
      RDS_SECRET_ARN: integration-rds
      PROCESSOR_POLL_WAIT_SECONDS: "1"
      PROCESSOR_FAILURE_BACKOFF_SECONDS: "1"
    depends_on:
      localstack:
        condition: service_healthy
      postgres:
        condition: service_healthy

  outbound:
    build:
      context: .
      dockerfile: services/outbound/Dockerfile
    environment:
      ENVIRONMENT: integration
      SERVICE_NAME: outbound
      AWS_REGION: eu-west-2
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_ENDPOINT_URL: http://localstack:4566
      DATA_BUCKET: integration-data
      PROCESSING_QUEUE_URL: ${PROCESSING_QUEUE_URL}
      MERAKI_SECRET_ARN: integration-meraki
      MERAKI_BASE_URL: http://mock-meraki:8081/api/v1
      MERAKI_POLL_PATHS: /organizations
      MERAKI_POLL_INTERVAL_SECONDS: "5"
      MERAKI_FAILURE_BACKOFF_SECONDS: "1"
    depends_on:
      localstack:
        condition: service_healthy
      mock-meraki:
        condition: service_healthy

```

## `docs/ECS_BLUE_GREEN_DEPLOYMENT.md`
```
# ECS Blue/Green Deployment — PROD

The repository has DEV, UAT and PROD. UAT is the release-qualification environment. Only PROD enables native ECS blue/green for the ALB-facing inbound/API service.

Production uses one ECS service, one cluster, one internal ALB and two reusable target groups. During a deployment ECS creates a replacement service revision, registers it in the alternate target group, waits for target health, shifts production traffic, retains the previous revision for the configured bake period, then completes and terminates the old revision if healthy. Configured deployment alarms can cause rollback.

TG-A is not permanently Blue and TG-B is not permanently Green; the roles alternate across releases.

Processor is not deployed with ALB blue/green. Polling ownership must be active/passive so two Processor revisions do not simultaneously poll Meraki.

See `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` for the complete bootstrap/IAM/GitHub sequence.

```

## `docs/MANAGEMENT_DEMO.md`
```
# Management ECS + RDS

`services/management` is the productionized successor to the earlier local Spatial demo. Spatial configuration is now a feature of the Management service, not a separate ECS service.

The service manages Buildings, Floors, Zones, Access Points and Desks in the environment RDS PostgreSQL database. It runs in APP private subnets, receives external administrator traffic only through CloudFront -> WAF -> VPC Origin -> internal ALB, and has no NAT/default Internet route. Processor remains the only NAT-routed ECS workload.

## Database bootstrap

On first task startup the service retrieves the RDS-managed credential from Secrets Manager and applies versioned SQL migrations from `services/management/migrations`. The initial migration creates `buildings`, `floors`, `zones`, `access_points`, `desks`, `observations`, indexes and `schema_migrations`. Repeated starts are idempotent because applied migration filenames are recorded.

This startup migration model is intended as an out-of-the-box lab/development solution. For governed production, move DDL execution to a dedicated migration task/job and give the long-running Management task a lower-privilege CRUD database identity.

## Routes

- UI: `/management/`
- API: `/api/v1/management/buildings`, `/floors`, `/zones`, `/access-points`, `/desks`
- Floor layout read model: `/api/v1/management/floors/{floor_id}/layout`
- ALB health: `/health`

## Terraform

Set `deployment.management_service = true`. Terraform creates the Management ECR repository, task definition, ECS service, CloudWatch log group, security group, ALB target group/rule and RDS connectivity rules. `management_port` defaults to `8090` and `ecs_desired_count.management` defaults to `1`.

```

## `docs/NETWORK_SEGMENTATION_UPDATE.md`
```
# Network Segmentation — Final DEV/UAT/PROD Model

All three environments are in one AWS account but have independent VPCs and state.

| Environment | VPC | ALB /24 | APP /24 | VPCE /24 | RDS /24 | NAT /24 | Processor /24 | Reserved |
|---|---|---|---|---|---|---|---|---|
| DEV | 10.0.0.0/21 | 10.0.0.0/24 | 10.0.1.0/24 | 10.0.2.0/24 | 10.0.3.0/24 | 10.0.4.0/24 | 10.0.5.0/24 | 10.0.6.0/23 |
| UAT | 10.0.16.0/21 | 10.0.16.0/24 | 10.0.17.0/24 | 10.0.18.0/24 | 10.0.19.0/24 | 10.0.20.0/24 | 10.0.21.0/24 | 10.0.22.0/23 |
| PROD | 10.0.24.0/21 | 10.0.24.0/24 | 10.0.25.0/24 | 10.0.26.0/24 | 10.0.27.0/24 | 10.0.28.0/24 | 10.0.29.0/24 | 10.0.30.0/23 |

`10.0.8.0/21` is reserved and is not deployed as a durable environment.

Each deployed functional `/24` is split into two `/25` AWS subnets across the active AZs. APP has no `0.0.0.0/0` NAT route. Processor has the NAT-routed default route and owns Internet-initiated Meraki communication. The historical standalone outbound service is disabled by default.

Validate with only:

```bash
terraform plan -var-file=environments/dev.tfvars
terraform plan -var-file=environments/uat.tfvars
terraform plan -var-file=environments/prod.tfvars
```

```

## `scripts/bootstrap-single-account-lab.sh`
```
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

```

## `scripts/build-push-images.ps1`
```
param(
  [Parameter(Mandatory=$true)][ValidateSet("dev","uat","prod")][string]$Environment,
  [string]$Tag = "local",
  [string]$ProjectName = "occupancy-platform",
  [string]$AwsRegion = "eu-west-2"
)
$ErrorActionPreference = "Stop"
$AccountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "Unable to determine AWS account" }
$Registry = "$AccountId.dkr.ecr.$AwsRegion.amazonaws.com"
aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }
foreach ($Service in @("inbound","outbound","processor","management")) {
  $Repo = "$ProjectName-$Environment-$Service"
  $Image = "$Registry/${Repo}:$Tag"
  aws ecr describe-repositories --repository-names $Repo | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ECR repository not found: $Repo" }
  docker build -f "services/$Service/Dockerfile" -t $Image .
  if ($LASTEXITCODE -ne 0) { throw "Docker build failed: $Service" }
  docker push $Image
  if ($LASTEXITCODE -ne 0) { throw "Docker push failed: $Service" }
  Write-Host "$Service=$Image"
}

```

## `scripts/build-push-images.sh`
```
#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT=${1:?environment required}
TAG=${2:-${GITHUB_SHA:-local}}
PROJECT_NAME=${PROJECT_NAME:-occupancy-platform}
AWS_REGION=${AWS_REGION:-eu-west-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for service in inbound outbound processor management; do
  repo="${PROJECT_NAME}-${ENVIRONMENT}-${service}"
  image="${REGISTRY}/${repo}:${TAG}"
  aws ecr describe-repositories --repository-names "$repo" >/dev/null
  docker build -f "services/${service}/Dockerfile" -t "$image" .
  docker push "$image"
  echo "$service=$image"
done

```

## `scripts/configure-github-single-account.sh`
```
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

```

## `scripts/functional-smoke-test.sh`
```
#!/usr/bin/env bash
set -euo pipefail
BASE_URL=${SMOKE_BASE_URL:?SMOKE_BASE_URL required}
SECRET=${WEBHOOK_SECRET:?WEBHOOK_SECRET required}
EVENT_ID="smoke-$(date +%s)-${RANDOM}"
BODY=$(cat <<JSON
{"event_id":"${EVENT_ID}","organizationId":"smoke-org","type":"occupancy","deviceSerial":"SMOKE-DEVICE","value":1}
JSON
)
STATUS=$(curl -sS -o /tmp/smoke-response.json -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -H "X-Meraki-Secret: ${SECRET}" \
  -d "$BODY" \
  "${BASE_URL%/}/api/v1/meraki/webhook")
test "$STATUS" = "202"
grep -q "$EVENT_ID" /tmp/smoke-response.json
cat /tmp/smoke-response.json

```

## `scripts/integration/init-localstack.sh`
```
#!/usr/bin/env bash
set -euo pipefail

AWS=(aws --endpoint-url http://localhost:4566 --region eu-west-2)
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2

"${AWS[@]}" s3api head-bucket --bucket integration-data >/dev/null 2>&1 || \
  "${AWS[@]}" s3api create-bucket --bucket integration-data \
    --create-bucket-configuration LocationConstraint=eu-west-2 >/dev/null

for queue in integration-processing integration-datalake; do
  "${AWS[@]}" sqs create-queue --queue-name "$queue" >/dev/null
done

"${AWS[@]}" secretsmanager create-secret \
  --name integration-meraki \
  --secret-string '{"api_key":"integration-api-key","webhook_secret":"integration-webhook-secret"}' \
  >/dev/null 2>&1 || \
"${AWS[@]}" secretsmanager put-secret-value \
  --secret-id integration-meraki \
  --secret-string '{"api_key":"integration-api-key","webhook_secret":"integration-webhook-secret"}' >/dev/null

"${AWS[@]}" secretsmanager create-secret \
  --name integration-rds \
  --secret-string '{"username":"platform_admin","password":"integration-password"}' \
  >/dev/null 2>&1 || \
"${AWS[@]}" secretsmanager put-secret-value \
  --secret-id integration-rds \
  --secret-string '{"username":"platform_admin","password":"integration-password"}' >/dev/null

PROCESSING_QUEUE_URL=$("${AWS[@]}" sqs get-queue-url --queue-name integration-processing --query QueueUrl --output text)
DATALAKE_QUEUE_URL=$("${AWS[@]}" sqs get-queue-url --queue-name integration-datalake --query QueueUrl --output text)

cat > .integration.env <<ENV
PROCESSING_QUEUE_URL=${PROCESSING_QUEUE_URL/localhost/localstack}
DATALAKE_QUEUE_URL=${DATALAKE_QUEUE_URL/localhost/localstack}
ENV

cat .integration.env

```

## `scripts/integration/run.sh`
```
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

cleanup() {
  docker compose -f docker-compose.integration.yml --env-file .integration.env down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

touch .integration.env
docker compose -f docker-compose.integration.yml --env-file .integration.env up -d --build localstack postgres mock-meraki

for _ in $(seq 1 60); do
  if curl -fsS http://localhost:4566/_localstack/health >/dev/null \
     && curl -fsS http://localhost:8081/health >/dev/null \
     && docker compose -f docker-compose.integration.yml exec -T postgres pg_isready -U platform_admin -d occupancy >/dev/null; then
    break
  fi
  sleep 2
done

./scripts/integration/init-localstack.sh

docker compose -f docker-compose.integration.yml --env-file .integration.env up -d --build inbound processor outbound

for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/health >/dev/null; then break; fi
  sleep 2
done

python -m pip install -r tests/integration/requirements.txt
AWS_ENDPOINT_URL=http://localhost:4566 pytest -q tests/integration

```

## `scripts/migrate-single-account-bootstrap-state.sh`
```
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

```

## `scripts/performance-test.sh`
```
#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-${PERF_BASE_URL:-http://localhost:8080}}
USERS=${PERF_USERS:-25}
SPAWN_RATE=${PERF_SPAWN_RATE:-5}
DURATION=${PERF_DURATION:-60s}
FAIL_RATIO=${PERF_FAIL_RATIO:-0.01}
export PERF_FAIL_RATIO="$FAIL_RATIO"

python -m pip install -r tests/performance/requirements.txt
locust -f tests/performance/locustfile.py --headless \
  --host "$HOST" \
  -u "$USERS" \
  -r "$SPAWN_RATE" \
  -t "$DURATION" \
  --only-summary

```

## `scripts/smoke-test.sh`
```
#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:?environment required}"
BASE_URL=${SMOKE_BASE_URL:?SMOKE_BASE_URL must be supplied}
echo "Smoke testing ${ENVIRONMENT}: ${BASE_URL}"
for _ in $(seq 1 20); do
  if curl -fsS "${BASE_URL%/}/health" | grep -q '"status":"ok"'; then
    echo "Health check passed"
    exit 0
  fi
  sleep 5
done
echo "Health check failed" >&2
exit 1

```

## `scripts/tf-local-single-account.sh`
```
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

```

## `services/common/occupancy_common/__init__.py`
```
"""Shared helpers for the occupancy platform services."""

```

## `services/common/occupancy_common/aws.py`
```
from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any

import boto3
from botocore.config import Config


def _client(service: str):
    endpoint = os.getenv("AWS_ENDPOINT_URL")
    kwargs: dict[str, Any] = {
        "region_name": os.getenv("AWS_REGION", "eu-west-2"),
    }
    if endpoint:
        kwargs["endpoint_url"] = endpoint
    if service == "s3":
        kwargs["config"] = Config(s3={"addressing_style": "path"})
    return boto3.client(service, **kwargs)


@lru_cache(maxsize=None)
def s3_client():
    return _client("s3")


@lru_cache(maxsize=None)
def sqs_client():
    return _client("sqs")


@lru_cache(maxsize=None)
def secrets_client():
    return _client("secretsmanager")


@lru_cache(maxsize=64)
def get_json_secret(secret_arn: str) -> dict[str, Any]:
    response = secrets_client().get_secret_value(SecretId=secret_arn)
    value = response.get("SecretString")
    if not value:
        raise RuntimeError(f"Secret {secret_arn} does not contain SecretString")
    data = json.loads(value)
    if not isinstance(data, dict):
        raise RuntimeError(f"Secret {secret_arn} must contain a JSON object")
    return data

```

## `services/common/occupancy_common/events.py`
```
from __future__ import annotations

import hashlib
import json
import uuid
from datetime import UTC, datetime
from typing import Any


def utc_now() -> datetime:
    return datetime.now(UTC)


def iso_now() -> str:
    return utc_now().isoformat()


def stable_event_id(payload: dict[str, Any], supplied: str | None = None) -> str:
    if supplied:
        return supplied[:128]
    for key in ("event_id", "eventId", "id", "messageId"):
        value = payload.get(key)
        if value:
            return str(value)[:128]
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str).encode()
    return hashlib.sha256(encoded).hexdigest()


def tenant_id(payload: dict[str, Any], supplied: str | None = None) -> str:
    if supplied:
        return supplied[:128]
    for key in ("tenant_id", "tenantId", "organizationId", "organization_id"):
        value = payload.get(key)
        if value:
            return str(value)[:128]
    return "default"


def raw_key(source: str, tenant: str, event_id: str, when: datetime | None = None) -> str:
    dt = when or utc_now()
    safe_tenant = tenant.replace("/", "_")
    safe_event = event_id.replace("/", "_")
    return f"raw/{source}/{safe_tenant}/{dt:%Y/%m/%d}/{safe_event}.json"


def processing_message(*, bucket: str, key: str, source: str, tenant: str, event_id: str) -> dict[str, str]:
    return {
        "schema_version": "1",
        "bucket": bucket,
        "key": key,
        "source": source,
        "tenant_id": tenant,
        "event_id": event_id,
        "enqueued_at": iso_now(),
        "message_id": str(uuid.uuid4()),
    }

```

## `services/common/occupancy_common/logging.py`
```
import json
import logging
import os
import sys
from datetime import UTC, datetime


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "service": os.getenv("SERVICE_NAME", "unknown"),
            "environment": os.getenv("ENVIRONMENT", "local"),
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

```

## `services/common/pyproject.toml`
```
[build-system]
requires = ["setuptools>=75"]
build-backend = "setuptools.build_meta"

[project]
name = "occupancy-common"
version = "0.1.0"
description = "Shared runtime helpers for the Workplace Management telemetry services"
requires-python = ">=3.12"
dependencies = [
  "boto3>=1.35,<2",
  "botocore>=1.35,<2",
]

[tool.setuptools.packages.find]
where = ["."]
include = ["occupancy_common*"]

```

## `services/inbound/Dockerfile`
```
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/inbound/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/inbound/requirements.txt /app/services/inbound/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/inbound/requirements.txt
COPY services/inbound/src /app/services/inbound/src

USER 65532:65532
EXPOSE 8080
CMD ["uvicorn", "inbound_service.app:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]

```

## `services/inbound/README.md`
```
# Inbound service

FastAPI service exposed through CloudFront -> WAF -> VPC Origin -> internal ALB.

`POST /api/v1/meraki/webhook` validates the optional Meraki webhook secret, stores the raw JSON in S3 and publishes an S3 pointer to the processing SQS queue. `GET /health` is used by the ALB target group.

Required runtime variables: `DATA_BUCKET`, `PROCESSING_QUEUE_URL`. When webhook authentication is enabled, also set `MERAKI_SECRET_ARN`; the secret JSON must contain `webhook_secret`.

```

## `services/inbound/requirements.txt`
```
fastapi>=0.115,<1
uvicorn[standard]>=0.32,<1
pydantic>=2.10,<3

```

## `services/inbound/src/inbound_service/__init__.py`
```

```

## `services/inbound/src/inbound_service/app.py`
```
from __future__ import annotations

import json
import logging
import os
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request, status

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.events import processing_message, raw_key, stable_event_id, tenant_id
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)

app = FastAPI(title="Occupancy Inbound Service", version="1.0.0")


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _authorise(secret_header: str | None) -> None:
    if os.getenv("WEBHOOK_AUTH_REQUIRED", "true").lower() not in {"1", "true", "yes"}:
        return
    secret_arn = os.getenv("MERAKI_SECRET_ARN")
    if not secret_arn:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Webhook secret is not configured")
    expected = get_json_secret(secret_arn).get("webhook_secret")
    if not expected or secret_header != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook secret")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "inbound"}


@app.post("/api/v1/meraki/webhook", status_code=status.HTTP_202_ACCEPTED)
async def meraki_webhook(
    request: Request,
    x_meraki_secret: str | None = Header(default=None),
    x_tenant_id: str | None = Header(default=None),
    x_event_id: str | None = Header(default=None),
) -> dict[str, str]:
    _authorise(x_meraki_secret)
    try:
        payload: Any = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Body must be valid JSON") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Webhook body must be a JSON object")

    bucket = _required("DATA_BUCKET")
    queue_url = _required("PROCESSING_QUEUE_URL")
    event_id = stable_event_id(payload, x_event_id)
    tenant = tenant_id(payload, x_tenant_id)
    key = raw_key("inbound", tenant, event_id)
    body = json.dumps(payload, separators=(",", ":"), default=str).encode()

    s3_client().put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/json",
        Metadata={"source": "inbound", "tenant-id": tenant, "event-id": event_id},
    )
    message = processing_message(bucket=bucket, key=key, source="inbound", tenant=tenant, event_id=event_id)
    sqs_client().send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
    logger.info("accepted webhook event_id=%s tenant=%s key=%s", event_id, tenant, key)
    return {"status": "accepted", "event_id": event_id, "tenant_id": tenant, "s3_key": key}

```

## `services/inbound/tests/test_app.py`
```
import json

from fastapi.testclient import TestClient

from inbound_service import app as app_module


class FakeS3:
    def __init__(self):
        self.objects = []

    def put_object(self, **kwargs):
        self.objects.append(kwargs)
        return {}


class FakeSQS:
    def __init__(self):
        self.messages = []

    def send_message(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "1"}


def test_health():
    client = TestClient(app_module.app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_webhook_lands_s3_and_enqueues(monkeypatch):
    fake_s3 = FakeS3()
    fake_sqs = FakeSQS()
    monkeypatch.setenv("DATA_BUCKET", "data-bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue-url")
    monkeypatch.setenv("MERAKI_SECRET_ARN", "secret")
    monkeypatch.setenv("WEBHOOK_AUTH_REQUIRED", "true")
    monkeypatch.setattr(app_module, "s3_client", lambda: fake_s3)
    monkeypatch.setattr(app_module, "sqs_client", lambda: fake_sqs)
    monkeypatch.setattr(app_module, "get_json_secret", lambda _: {"webhook_secret": "expected"})

    client = TestClient(app_module.app)
    payload = {"event_id": "evt-1", "organizationId": "org-1", "type": "occupancy", "value": 1}
    response = client.post(
        "/api/v1/meraki/webhook",
        json=payload,
        headers={"X-Meraki-Secret": "expected"},
    )
    assert response.status_code == 202
    assert len(fake_s3.objects) == 1
    assert json.loads(fake_s3.objects[0]["Body"])["event_id"] == "evt-1"
    assert len(fake_sqs.messages) == 1
    queued = json.loads(fake_sqs.messages[0]["MessageBody"])
    assert queued["event_id"] == "evt-1"
    assert queued["source"] == "inbound"


def test_webhook_rejects_bad_secret(monkeypatch):
    monkeypatch.setenv("MERAKI_SECRET_ARN", "secret")
    monkeypatch.setenv("WEBHOOK_AUTH_REQUIRED", "true")
    monkeypatch.setattr(app_module, "get_json_secret", lambda _: {"webhook_secret": "expected"})
    client = TestClient(app_module.app)
    response = client.post("/api/v1/meraki/webhook", json={}, headers={"X-Meraki-Secret": "wrong"})
    assert response.status_code == 401

```

## `services/management/Dockerfile`
```
FROM python:3.12-slim
WORKDIR /app
COPY services/management/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY services/management/src /app/src
COPY services/management/migrations /app/migrations
ENV PYTHONPATH=/app/src
ENV MANAGEMENT_MIGRATIONS_PATH=/app/migrations
EXPOSE 8090
CMD ["uvicorn", "management_service.app:app", "--host", "0.0.0.0", "--port", "8090"]

```

## `services/management/README.md`
```
# Management service

RDS PostgreSQL-backed Workplace Management service. It owns configuration/master data for buildings, floors, zones, access points and desks. It runs in APP private subnets behind the existing internal ALB and has no NAT/default Internet route.

On startup it retrieves the RDS-managed master credential from Secrets Manager and applies versioned SQL files in `migrations/`. This is an out-of-the-box lab implementation. For governed production, use a dedicated migration identity/job and a lower-privilege runtime database user rather than the RDS master credential.

UI: `/management/`
API: `/api/v1/management/*`
Health: `/health` (ALB target-group health check)

```

## `services/management/data/default_layout.json`
```
{
  "site": {"id": "london-hq", "name": "London HQ"},
  "floor": {"id": "floor-03", "name": "Floor 3", "width": 100, "height": 100},
  "zones": [
    {"id": "zone-a", "name": "Product & Engineering", "polygon": [{"x": 4,"y": 5},{"x": 49,"y": 5},{"x": 49,"y": 70},{"x": 4,"y": 70}]},
    {"id": "zone-b", "name": "Sales & Operations", "polygon": [{"x": 51,"y": 5},{"x": 96,"y": 5},{"x": 96,"y": 70},{"x": 51,"y": 70}]},
    {"id": "zone-c", "name": "Collaboration", "polygon": [{"x": 4,"y": 73},{"x": 96,"y": 73},{"x": 96,"y": 96},{"x": 4,"y": 96}]}
  ],
  "desks": [
    {"id":"A-01","name":"A-01","zone_id":"zone-a","x":12,"y":18,"radius":4},
    {"id":"A-02","name":"A-02","zone_id":"zone-a","x":25,"y":18,"radius":4},
    {"id":"A-03","name":"A-03","zone_id":"zone-a","x":38,"y":18,"radius":4},
    {"id":"A-04","name":"A-04","zone_id":"zone-a","x":12,"y":38,"radius":4},
    {"id":"A-05","name":"A-05","zone_id":"zone-a","x":25,"y":38,"radius":4},
    {"id":"A-06","name":"A-06","zone_id":"zone-a","x":38,"y":38,"radius":4},
    {"id":"B-01","name":"B-01","zone_id":"zone-b","x":62,"y":18,"radius":4},
    {"id":"B-02","name":"B-02","zone_id":"zone-b","x":75,"y":18,"radius":4},
    {"id":"B-03","name":"B-03","zone_id":"zone-b","x":88,"y":18,"radius":4},
    {"id":"B-04","name":"B-04","zone_id":"zone-b","x":62,"y":38,"radius":4},
    {"id":"B-05","name":"B-05","zone_id":"zone-b","x":75,"y":38,"radius":4},
    {"id":"B-06","name":"B-06","zone_id":"zone-b","x":88,"y":38,"radius":4}
  ],
  "access_points": [
    {"id":"AP-01","serial":"Q2XX-LAB-0001","x":25,"y":55},
    {"id":"AP-02","serial":"Q2XX-LAB-0002","x":75,"y":55}
  ]
}

```

## `services/management/migrations/001_management_schema.sql`
```
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS buildings (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT UNIQUE,
    address TEXT,
    timezone TEXT NOT NULL DEFAULT 'Europe/London',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS floors (
    id UUID PRIMARY KEY,
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    floor_number INTEGER,
    map_width DOUBLE PRECISION NOT NULL DEFAULT 100,
    map_height DOUBLE PRECISION NOT NULL DEFAULT 100,
    floor_plan_s3_key TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(building_id, name)
);

CREATE TABLE IF NOT EXISTS zones (
    id UUID PRIMARY KEY,
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    zone_type TEXT,
    polygon JSONB NOT NULL DEFAULT '[]'::jsonb,
    capacity INTEGER,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(floor_id, name)
);

CREATE TABLE IF NOT EXISTS access_points (
    id UUID PRIMARY KEY,
    floor_id UUID REFERENCES floors(id) ON DELETE SET NULL,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    serial TEXT NOT NULL UNIQUE,
    name TEXT,
    mac_address TEXT,
    x DOUBLE PRECISION,
    y DOUBLE PRECISION,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS desks (
    id UUID PRIMARY KEY,
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(floor_id, name)
);

CREATE TABLE IF NOT EXISTS observations (
    id BIGSERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    desk_id UUID REFERENCES desks(id) ON DELETE SET NULL,
    confidence DOUBLE PRECISION NOT NULL DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS ix_observations_device_ts ON observations(device_id, ts DESC);
CREATE INDEX IF NOT EXISTS ix_floors_building ON floors(building_id);
CREATE INDEX IF NOT EXISTS ix_zones_floor ON zones(floor_id);
CREATE INDEX IF NOT EXISTS ix_access_points_floor ON access_points(floor_id);
CREATE INDEX IF NOT EXISTS ix_access_points_zone ON access_points(zone_id);
CREATE INDEX IF NOT EXISTS ix_desks_floor ON desks(floor_id);

```

## `services/management/requirements.txt`
```
fastapi==0.116.1
uvicorn[standard]==0.35.0
pydantic==2.11.7
psycopg[binary]>=3.3,<4
boto3>=1.35,<2
httpx==0.28.1

```

## `services/management/src/management_service/__init__.py`
```
"""Workplace Management service."""

```

## `services/management/src/management_service/app.py`
```
from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, Response, status
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .store import apply_migrations, connection

STATIC_DIR = Path(__file__).parent / "static"


@asynccontextmanager
async def lifespan(_: FastAPI):
    apply_migrations()
    yield


app = FastAPI(title="Workplace Management", version="2.0.0", lifespan=lifespan)
app.mount("/management/static", StaticFiles(directory=STATIC_DIR), name="static")


class BuildingIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    code: str | None = Field(default=None, max_length=100)
    address: str | None = None
    timezone: str = "Europe/London"
    active: bool = True


class FloorIn(BaseModel):
    building_id: UUID
    name: str = Field(min_length=1, max_length=200)
    floor_number: int | None = None
    map_width: float = Field(default=100, gt=0)
    map_height: float = Field(default=100, gt=0)
    floor_plan_s3_key: str | None = None
    active: bool = True


class ZoneIn(BaseModel):
    floor_id: UUID
    name: str = Field(min_length=1, max_length=200)
    zone_type: str | None = None
    polygon: list[dict[str, float]] = Field(default_factory=list)
    capacity: int | None = Field(default=None, ge=0)
    active: bool = True


class AccessPointIn(BaseModel):
    floor_id: UUID | None = None
    zone_id: UUID | None = None
    serial: str = Field(min_length=1, max_length=128)
    name: str | None = None
    mac_address: str | None = None
    x: float | None = None
    y: float | None = None
    active: bool = True


class DeskIn(BaseModel):
    floor_id: UUID
    zone_id: UUID | None = None
    name: str = Field(min_length=1, max_length=200)
    x: float
    y: float
    active: bool = True


def _rows(sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with connection() as conn:
        return list(conn.execute(sql, params).fetchall())


def _one(sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any]:
    with connection() as conn:
        row = conn.execute(sql, params).fetchone()
    if row is None:
        raise HTTPException(404, "record not found")
    return dict(row)


def _delete(table: str, item_id: UUID) -> Response:
    allowed = {"buildings", "floors", "zones", "access_points", "desks"}
    if table not in allowed:
        raise HTTPException(400, "invalid resource")
    with connection() as conn:
        row = conn.execute(f"DELETE FROM {table} WHERE id=%s RETURNING id", (item_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "record not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/")
@app.get("/management")
@app.get("/management/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health")
def health():
    try:
        with connection() as conn:
            conn.execute("SELECT 1").fetchone()
        return {"status": "ok", "service": "management", "database": "ok"}
    except Exception as exc:
        raise HTTPException(503, f"database unavailable: {type(exc).__name__}") from exc


@app.get("/api/v1/management/buildings")
def list_buildings():
    return _rows("SELECT * FROM buildings ORDER BY name")


@app.post("/api/v1/management/buildings", status_code=201)
def create_building(item: BuildingIn):
    item_id = uuid4()
    return _one("""INSERT INTO buildings(id,name,code,address,timezone,active) VALUES(%s,%s,%s,%s,%s,%s) RETURNING *""",
                (item_id,item.name,item.code,item.address,item.timezone,item.active))


@app.put("/api/v1/management/buildings/{item_id}")
def update_building(item_id: UUID, item: BuildingIn):
    return _one("""UPDATE buildings SET name=%s,code=%s,address=%s,timezone=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.name,item.code,item.address,item.timezone,item.active,item_id))


@app.delete("/api/v1/management/buildings/{item_id}", status_code=204)
def delete_building(item_id: UUID): return _delete("buildings", item_id)


@app.get("/api/v1/management/floors")
def list_floors(building_id: UUID | None = None):
    return _rows("SELECT * FROM floors WHERE (%s::uuid IS NULL OR building_id=%s) ORDER BY floor_number NULLS LAST,name", (building_id, building_id))


@app.post("/api/v1/management/floors", status_code=201)
def create_floor(item: FloorIn):
    return _one("""INSERT INTO floors(id,building_id,name,floor_number,map_width,map_height,floor_plan_s3_key,active) VALUES(%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.building_id,item.name,item.floor_number,item.map_width,item.map_height,item.floor_plan_s3_key,item.active))


@app.put("/api/v1/management/floors/{item_id}")
def update_floor(item_id: UUID, item: FloorIn):
    return _one("""UPDATE floors SET building_id=%s,name=%s,floor_number=%s,map_width=%s,map_height=%s,floor_plan_s3_key=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.building_id,item.name,item.floor_number,item.map_width,item.map_height,item.floor_plan_s3_key,item.active,item_id))


@app.delete("/api/v1/management/floors/{item_id}", status_code=204)
def delete_floor(item_id: UUID): return _delete("floors", item_id)


@app.get("/api/v1/management/zones")
def list_zones(floor_id: UUID | None = None):
    return _rows("SELECT * FROM zones WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name", (floor_id, floor_id))


@app.post("/api/v1/management/zones", status_code=201)
def create_zone(item: ZoneIn):
    import json
    return _one("""INSERT INTO zones(id,floor_id,name,zone_type,polygon,capacity,active) VALUES(%s,%s,%s,%s,%s::jsonb,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.name,item.zone_type,json.dumps(item.polygon),item.capacity,item.active))


@app.put("/api/v1/management/zones/{item_id}")
def update_zone(item_id: UUID, item: ZoneIn):
    import json
    return _one("""UPDATE zones SET floor_id=%s,name=%s,zone_type=%s,polygon=%s::jsonb,capacity=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.name,item.zone_type,json.dumps(item.polygon),item.capacity,item.active,item_id))


@app.delete("/api/v1/management/zones/{item_id}", status_code=204)
def delete_zone(item_id: UUID): return _delete("zones", item_id)


@app.get("/api/v1/management/access-points")
def list_access_points(floor_id: UUID | None = None):
    return _rows("SELECT * FROM access_points WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name NULLS LAST,serial", (floor_id, floor_id))


@app.post("/api/v1/management/access-points", status_code=201)
def create_access_point(item: AccessPointIn):
    return _one("""INSERT INTO access_points(id,floor_id,zone_id,serial,name,mac_address,x,y,active) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.zone_id,item.serial,item.name,item.mac_address,item.x,item.y,item.active))


@app.put("/api/v1/management/access-points/{item_id}")
def update_access_point(item_id: UUID, item: AccessPointIn):
    return _one("""UPDATE access_points SET floor_id=%s,zone_id=%s,serial=%s,name=%s,mac_address=%s,x=%s,y=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.zone_id,item.serial,item.name,item.mac_address,item.x,item.y,item.active,item_id))


@app.delete("/api/v1/management/access-points/{item_id}", status_code=204)
def delete_access_point(item_id: UUID): return _delete("access_points", item_id)


@app.get("/api/v1/management/desks")
def list_desks(floor_id: UUID | None = None):
    return _rows("SELECT * FROM desks WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name", (floor_id, floor_id))


@app.post("/api/v1/management/desks", status_code=201)
def create_desk(item: DeskIn):
    return _one("""INSERT INTO desks(id,floor_id,zone_id,name,x,y,active) VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.zone_id,item.name,item.x,item.y,item.active))


@app.put("/api/v1/management/desks/{item_id}")
def update_desk(item_id: UUID, item: DeskIn):
    return _one("""UPDATE desks SET floor_id=%s,zone_id=%s,name=%s,x=%s,y=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.zone_id,item.name,item.x,item.y,item.active,item_id))


@app.delete("/api/v1/management/desks/{item_id}", status_code=204)
def delete_desk(item_id: UUID): return _delete("desks", item_id)


@app.get("/api/v1/management/floors/{floor_id}/layout")
def floor_layout(floor_id: UUID):
    floor = _one("SELECT * FROM floors WHERE id=%s", (floor_id,))
    zones = _rows("SELECT * FROM zones WHERE floor_id=%s ORDER BY name", (floor_id,))
    desks = _rows("SELECT * FROM desks WHERE floor_id=%s ORDER BY name", (floor_id,))
    aps = _rows("SELECT * FROM access_points WHERE floor_id=%s ORDER BY name NULLS LAST,serial", (floor_id,))
    return {"floor": floor, "zones": zones, "desks": desks, "access_points": aps, "generated_at": datetime.now(timezone.utc)}

```

## `services/management/src/management_service/domain.py`
```
from __future__ import annotations

from dataclasses import dataclass
from math import hypot
from typing import Iterable


@dataclass(frozen=True)
class Point:
    x: float
    y: float


def point_in_polygon(point: Point, polygon: Iterable[Point]) -> bool:
    """Ray-casting point-in-polygon test for simple floor-plan polygons."""
    pts = list(polygon)
    if len(pts) < 3:
        return False
    inside = False
    j = len(pts) - 1
    for i, pi in enumerate(pts):
        pj = pts[j]
        crosses = ((pi.y > point.y) != (pj.y > point.y)) and (
            point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) or 1e-12) + pi.x
        )
        if crosses:
            inside = not inside
        j = i
    return inside


def nearest_desk(point: Point, desks: list[dict], zone_id: str | None) -> tuple[dict | None, float | None]:
    candidates = [d for d in desks if zone_id is None or d.get("zone_id") == zone_id]
    if not candidates:
        return None, None
    ranked = sorted((hypot(point.x - d["x"], point.y - d["y"]), d) for d in candidates)
    distance, desk = ranked[0]
    radius = float(desk.get("radius", 4.0))
    return (desk, distance) if distance <= radius else (None, distance)


def locate(point: Point, layout: dict) -> dict:
    zone = None
    for candidate in layout.get("zones", []):
        polygon = [Point(**p) for p in candidate.get("polygon", [])]
        if point_in_polygon(point, polygon):
            zone = candidate
            break
    desk, distance = nearest_desk(point, layout.get("desks", []), zone["id"] if zone else None)
    return {
        "zone_id": zone["id"] if zone else None,
        "zone_name": zone["name"] if zone else None,
        "desk_id": desk["id"] if desk else None,
        "desk_name": desk["name"] if desk else None,
        "desk_distance": round(distance, 2) if distance is not None else None,
    }

```

## `services/management/src/management_service/static/index.html`
```
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Workplace Management</title><style>body{font-family:system-ui;margin:2rem;max-width:1200px}nav button{margin:.25rem}section{margin-top:1.5rem}input,select,textarea,button{padding:.55rem;margin:.2rem}table{border-collapse:collapse;width:100%;margin-top:1rem}th,td{border:1px solid #ddd;padding:.5rem;text-align:left}pre{background:#f5f5f5;padding:1rem;overflow:auto}.row{display:flex;flex-wrap:wrap;gap:.4rem}.muted{color:#666}</style></head><body>
<h1>Workplace Management</h1><p class="muted">RDS-backed administration for buildings, floors, zones, access points and desks.</p>
<nav><button onclick="show('buildings')">Buildings</button><button onclick="show('floors')">Floors</button><button onclick="show('zones')">Zones</button><button onclick="show('access-points')">Access Points</button><button onclick="show('desks')">Desks</button></nav>
<section><h2 id="title"></h2><div id="form" class="row"></div><button onclick="createItem()">Add</button><table><thead id="head"></thead><tbody id="body"></tbody></table></section>
<script>
const base='/api/v1/management'; let resource='buildings'; let cache={};
const fields={
'buildings':['name','code','address','timezone'],
'floors':['building_id','name','floor_number','map_width','map_height'],
'zones':['floor_id','name','zone_type','capacity'],
'access-points':['floor_id','zone_id','serial','name','mac_address','x','y'],
'desks':['floor_id','zone_id','name','x','y']};
async function show(r){resource=r; document.querySelector('#title').textContent=r.replace('-',' '); const f=document.querySelector('#form'); f.innerHTML=''; fields[r].forEach(x=>{const i=document.createElement('input');i.id='f_'+x;i.placeholder=x;f.appendChild(i)}); await load()}
async function load(){const rows=await fetch(`${base}/${resource}`).then(r=>r.json());cache[resource]=rows; const cols=['id',...fields[resource]];document.querySelector('#head').innerHTML='<tr>'+cols.map(c=>`<th>${c}</th>`).join('')+'<th>action</th></tr>';document.querySelector('#body').innerHTML=rows.map(x=>'<tr>'+cols.map(c=>`<td>${x[c]??''}</td>`).join('')+`<td><button onclick="del('${x.id}')">Delete</button></td></tr>`).join('')}
function payload(){const o={active:true};for(const f of fields[resource]){let v=document.querySelector('#f_'+f).value;if(v==='')v=null;if(['floor_number','capacity'].includes(f)&&v!==null)v=Number(v);if(['map_width','map_height','x','y'].includes(f)&&v!==null)v=Number(v);o[f]=v}if(resource==='buildings'&&!o.timezone)o.timezone='Europe/London';if(resource==='zones')o.polygon=[];return o}
async function createItem(){const r=await fetch(`${base}/${resource}`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload())});if(!r.ok){alert(await r.text());return}await load()}
async function del(id){if(!confirm('Delete this record?'))return;const r=await fetch(`${base}/${resource}/${id}`,{method:'DELETE'});if(!r.ok){alert(await r.text());return}await load()}
show('buildings');
</script></body></html>

```

## `services/management/src/management_service/store.py`
```
from __future__ import annotations

import json
import os
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import boto3
import psycopg
from psycopg.rows import dict_row


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _secret() -> dict[str, Any]:
    arn = _required("RDS_SECRET_ARN")
    region = os.getenv("AWS_REGION")
    response = boto3.client("secretsmanager", region_name=region).get_secret_value(SecretId=arn)
    return json.loads(response["SecretString"])


def database_dsn() -> str:
    secret = _secret()
    return (
        f"host={_required('RDS_ENDPOINT')} port={os.getenv('RDS_PORT', '5432')} "
        f"dbname={os.getenv('RDS_DATABASE', 'occupancy')} "
        f"user={secret['username']} password={secret['password']} connect_timeout=10"
    )


@contextmanager
def connection():
    with psycopg.connect(database_dsn(), row_factory=dict_row) as conn:
        yield conn
        conn.commit()


def apply_migrations() -> None:
    migration_dir = Path(os.getenv("MANAGEMENT_MIGRATIONS_PATH", "/app/migrations"))
    with connection() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())")
        applied = {row["version"] for row in conn.execute("SELECT version FROM schema_migrations").fetchall()}
        for path in sorted(migration_dir.glob("*.sql")):
            if path.name in applied:
                continue
            for statement in path.read_text(encoding="utf-8").split(";"):
                if statement.strip():
                    conn.execute(statement)
            conn.execute("INSERT INTO schema_migrations(version) VALUES (%s)", (path.name,))

```

## `services/management/tests/test_api.py`
```
from management_service.app import app, BuildingIn, AccessPointIn


def test_management_routes_registered():
    paths = {route.path for route in app.routes}
    assert "/health" in paths
    assert "/management/" in paths
    assert "/api/v1/management/buildings" in paths
    assert "/api/v1/management/floors" in paths
    assert "/api/v1/management/zones" in paths
    assert "/api/v1/management/access-points" in paths
    assert "/api/v1/management/desks" in paths


def test_models():
    b = BuildingIn(name="HQ")
    assert b.timezone == "Europe/London"
    ap = AccessPointIn(serial="Q2XX-1234")
    assert ap.active is True

```

## `services/management/tests/test_domain.py`
```
from pathlib import Path


def test_initial_migration_contains_management_tables():
    sql = Path("services/management/migrations/001_management_schema.sql").read_text()
    for table in ["buildings", "floors", "zones", "access_points", "desks"]:
        assert f"CREATE TABLE IF NOT EXISTS {table}" in sql

```

## `services/mock-meraki/Dockerfile`
```
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app/src
WORKDIR /app
COPY services/mock-meraki/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY services/mock-meraki/src /app/src
EXPOSE 8081
CMD ["uvicorn", "mock_meraki.app:app", "--host", "0.0.0.0", "--port", "8081", "--no-access-log"]

```

## `services/mock-meraki/requirements.txt`
```
fastapi>=0.115,<1
uvicorn[standard]>=0.32,<1

```

## `services/mock-meraki/src/mock_meraki/__init__.py`
```

```

## `services/mock-meraki/src/mock_meraki/app.py`
```
from __future__ import annotations

from fastapi import FastAPI, Header, HTTPException, Response

app = FastAPI(title="Mock Meraki API", version="1.0.0")
_state = {"status": 200}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/control/status/{code}")
def set_status(code: int):
    _state["status"] = code
    return {"status": code}


def _check(auth: str | None):
    if auth != "Bearer integration-api-key":
        raise HTTPException(status_code=401, detail="unauthorised")
    if _state["status"] == 429:
        return Response(status_code=429, headers={"Retry-After": "1"})
    if _state["status"] >= 400:
        return Response(status_code=_state["status"])
    return None


@app.get("/api/v1/organizations")
def organizations(authorization: str | None = Header(default=None)):
    error = _check(authorization)
    if error:
        return error
    return [{"id": "org-1", "name": "Integration Organisation", "organizationId": "org-1"}]


@app.get("/api/v1/organizations/{org_id}/networks")
def networks(org_id: str, authorization: str | None = Header(default=None)):
    error = _check(authorization)
    if error:
        return error
    return [{"id": "net-1", "name": "Integration Network", "organizationId": org_id}]

```

## `services/outbound/Dockerfile`
```
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/outbound/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/outbound/requirements.txt /app/services/outbound/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/outbound/requirements.txt
COPY services/outbound/src /app/services/outbound/src

USER 65532:65532
CMD ["python", "-m", "outbound_service.worker"]

```

## `services/outbound/README.md`
```
# Outbound service

Long-running worker that calls configured Cisco Meraki REST paths through the private APP subnet/NAT path. Each successful API response is wrapped in a telemetry envelope, stored durably in S3, and a pointer is published to the processing queue.

Required: `DATA_BUCKET`, `PROCESSING_QUEUE_URL`, `MERAKI_SECRET_ARN`.
Optional: `MERAKI_BASE_URL`, `MERAKI_POLL_PATHS`, `MERAKI_POLL_INTERVAL_SECONDS`, `MERAKI_HTTP_TIMEOUT_SECONDS`, `MERAKI_FAILURE_BACKOFF_SECONDS`.

Run one polling cycle with `python -m outbound_service.worker --once`.

```

## `services/outbound/requirements.txt`
```
httpx>=0.28,<1

```

## `services/outbound/src/outbound_service/__init__.py`
```

```

## `services/outbound/src/outbound_service/worker.py`
```
from __future__ import annotations

import argparse
import json
import logging
import os
import time
from datetime import UTC, datetime
from typing import Any

import httpx

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.events import processing_message, raw_key, stable_event_id, tenant_id
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _paths() -> list[str]:
    raw = os.getenv("MERAKI_POLL_PATHS", "/organizations")
    return [part.strip() for part in raw.split(",") if part.strip()]


def _credentials() -> dict[str, Any]:
    return get_json_secret(_required("MERAKI_SECRET_ARN"))


def _headers() -> dict[str, str]:
    secret = _credentials()
    token = secret.get("api_key") or secret.get("access_token")
    if not token:
        raise RuntimeError("Meraki secret must contain api_key or access_token")
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "workplace-management-outbound/1.0",
    }


def poll_once(client: httpx.Client | None = None) -> int:
    bucket = _required("DATA_BUCKET")
    queue_url = _required("PROCESSING_QUEUE_URL")
    base_url = os.getenv("MERAKI_BASE_URL", "https://api.meraki.com/api/v1").rstrip("/")
    timeout = float(os.getenv("MERAKI_HTTP_TIMEOUT_SECONDS", "20"))
    own_client = client is None
    client = client or httpx.Client(timeout=timeout, headers=_headers())
    count = 0
    try:
        for path in _paths():
            url = f"{base_url}/{path.lstrip('/')}"
            response = client.get(url)
            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", "1"))
                raise RuntimeError(f"Meraki rate limited request; retry_after={retry_after}")
            response.raise_for_status()
            payload: Any = response.json()
            envelope = {
                "event_id": stable_event_id({"path": path, "payload": payload, "at": datetime.now(UTC).isoformat()}),
                "tenant_id": tenant_id(payload if isinstance(payload, dict) else {}),
                "event_type": "meraki_poll",
                "api_path": path,
                "observed_at": datetime.now(UTC).isoformat(),
                "payload": payload,
            }
            event_id = envelope["event_id"]
            tenant = envelope["tenant_id"]
            key = raw_key("outbound", tenant, event_id)
            s3_client().put_object(
                Bucket=bucket,
                Key=key,
                Body=json.dumps(envelope, separators=(",", ":"), default=str).encode(),
                ContentType="application/json",
                Metadata={"source": "outbound", "tenant-id": tenant, "event-id": event_id},
            )
            sqs_client().send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(processing_message(
                    bucket=bucket,
                    key=key,
                    source="outbound",
                    tenant=tenant,
                    event_id=event_id,
                )),
            )
            count += 1
            logger.info("polled Meraki path=%s event_id=%s", path, event_id)
    finally:
        if own_client:
            client.close()
    return count


def run_forever() -> None:
    interval = int(os.getenv("MERAKI_POLL_INTERVAL_SECONDS", "300"))
    failure_sleep = int(os.getenv("MERAKI_FAILURE_BACKOFF_SECONDS", "30"))
    while True:
        try:
            poll_once()
            time.sleep(interval)
        except Exception:
            logger.exception("outbound poll failed")
            time.sleep(failure_sleep)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="Poll configured paths once and exit")
    args = parser.parse_args()
    if args.once:
        poll_once()
    else:
        run_forever()


if __name__ == "__main__":
    main()

```

## `services/outbound/tests/test_worker.py`
```
import json

import httpx

from outbound_service import worker


class FakeS3:
    def __init__(self):
        self.objects = []
    def put_object(self, **kwargs):
        self.objects.append(kwargs)


class FakeSQS:
    def __init__(self):
        self.messages = []
    def send_message(self, **kwargs):
        self.messages.append(kwargs)


def test_poll_once_lands_and_enqueues(monkeypatch):
    fake_s3 = FakeS3()
    fake_sqs = FakeSQS()
    monkeypatch.setenv("DATA_BUCKET", "bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue")
    monkeypatch.setenv("MERAKI_BASE_URL", "https://example.test/api/v1")
    monkeypatch.setenv("MERAKI_POLL_PATHS", "/organizations")
    monkeypatch.setattr(worker, "s3_client", lambda: fake_s3)
    monkeypatch.setattr(worker, "sqs_client", lambda: fake_sqs)

    def handler(request: httpx.Request):
        assert request.url.path == "/api/v1/organizations"
        return httpx.Response(200, json=[{"id": "org-1", "name": "Example"}])

    client = httpx.Client(transport=httpx.MockTransport(handler))
    assert worker.poll_once(client) == 1
    assert len(fake_s3.objects) == 1
    body = json.loads(fake_s3.objects[0]["Body"])
    assert body["event_type"] == "meraki_poll"
    assert len(fake_sqs.messages) == 1


def test_poll_once_raises_on_rate_limit(monkeypatch):
    monkeypatch.setenv("DATA_BUCKET", "bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue")
    monkeypatch.setenv("MERAKI_BASE_URL", "https://example.test/api/v1")
    monkeypatch.setenv("MERAKI_POLL_PATHS", "/organizations")
    client = httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(429, headers={"Retry-After": "2"})))
    try:
        worker.poll_once(client)
        assert False, "expected rate limit failure"
    except RuntimeError as exc:
        assert "rate limited" in str(exc)

```

## `services/processor/Dockerfile`
```
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/processor/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/processor/requirements.txt /app/services/processor/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/processor/requirements.txt
COPY services/processor/src /app/services/processor/src

USER 65532:65532
CMD ["python", "-m", "processor_service.worker"]

```

## `services/processor/README.md`
```
# Processor service

Long-running SQS consumer. It reads the durable S3 raw object referenced by each processing message, normalises common occupancy fields, upserts the event into PostgreSQL, then publishes a compact analytical record to the data-lake delivery queue.

The processing SQS message is deleted only after S3 read, database commit and data-lake queue publish all succeed; otherwise it remains for retry and eventual DLQ redrive.

```

## `services/processor/requirements.txt`
```
psycopg[binary]>=3.3,<4

```

## `services/processor/src/processor_service/__init__.py`
```

```

## `services/processor/src/processor_service/worker.py`
```
from __future__ import annotations

import argparse
import json
import logging
import os
import time
from datetime import UTC, datetime
from typing import Any

import psycopg

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS occupancy_events (
    event_id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    source TEXT NOT NULL,
    event_type TEXT,
    observed_at TIMESTAMPTZ,
    device_serial TEXT,
    client_mac TEXT,
    occupancy_value DOUBLE PRECISION,
    raw_s3_key TEXT NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
"""

UPSERT = """
INSERT INTO occupancy_events (
    event_id, tenant_id, source, event_type, observed_at,
    device_serial, client_mac, occupancy_value, raw_s3_key, payload, processed_at
) VALUES (
    %(event_id)s, %(tenant_id)s, %(source)s, %(event_type)s, %(observed_at)s,
    %(device_serial)s, %(client_mac)s, %(occupancy_value)s, %(raw_s3_key)s,
    %(payload)s::jsonb, NOW()
)
ON CONFLICT (event_id) DO UPDATE SET
    tenant_id = EXCLUDED.tenant_id,
    source = EXCLUDED.source,
    event_type = EXCLUDED.event_type,
    observed_at = EXCLUDED.observed_at,
    device_serial = EXCLUDED.device_serial,
    client_mac = EXCLUDED.client_mac,
    occupancy_value = EXCLUDED.occupancy_value,
    raw_s3_key = EXCLUDED.raw_s3_key,
    payload = EXCLUDED.payload,
    processed_at = NOW()
"""


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def database_dsn() -> str:
    secret = get_json_secret(_required("RDS_SECRET_ARN"))
    username = secret.get("username")
    password = secret.get("password")
    if not username or not password:
        raise RuntimeError("RDS secret must contain username and password")
    host = _required("RDS_ENDPOINT")
    port = os.getenv("RDS_PORT", "5432")
    dbname = os.getenv("RDS_DATABASE", "occupancy")
    return f"host={host} port={port} dbname={dbname} user={username} password={password} connect_timeout=10"


def normalize(payload: dict[str, Any], message: dict[str, Any]) -> dict[str, Any]:
    inner = payload.get("payload") if isinstance(payload.get("payload"), dict) else payload
    event_type = payload.get("event_type") or payload.get("type") or inner.get("type") or inner.get("eventType")
    observed_at = payload.get("observed_at") or payload.get("occurredAt") or payload.get("timestamp") or inner.get("timestamp")
    device_serial = payload.get("device_serial") or payload.get("deviceSerial") or inner.get("serial") or inner.get("deviceSerial")
    client_mac = payload.get("client_mac") or payload.get("clientMac") or inner.get("clientMac") or inner.get("client_mac")
    occupancy = payload.get("occupancy_value")
    if occupancy is None:
        occupancy = payload.get("value")
    if occupancy is None and isinstance(inner, dict):
        occupancy = inner.get("occupancy") or inner.get("value")
    try:
        occupancy_value = float(occupancy) if occupancy is not None else None
    except (TypeError, ValueError):
        occupancy_value = None
    return {
        "event_id": str(message["event_id"]),
        "tenant_id": str(message.get("tenant_id", "default")),
        "source": str(message.get("source", "unknown")),
        "event_type": str(event_type) if event_type is not None else None,
        "observed_at": observed_at,
        "device_serial": str(device_serial) if device_serial is not None else None,
        "client_mac": str(client_mac) if client_mac is not None else None,
        "occupancy_value": occupancy_value,
        "raw_s3_key": str(message["key"]),
        "payload": json.dumps(payload, separators=(",", ":"), default=str),
    }


def process_message(message_body: str, connection: psycopg.Connection[Any]) -> dict[str, Any]:
    message = json.loads(message_body)
    obj = s3_client().get_object(Bucket=message["bucket"], Key=message["key"])
    payload = json.loads(obj["Body"].read())
    if not isinstance(payload, dict):
        raise ValueError("Raw telemetry object must be a JSON object")
    record = normalize(payload, message)
    with connection.cursor() as cur:
        cur.execute(DDL)
        cur.execute(UPSERT, record)
    connection.commit()

    datalake_message = {
        "schema_version": "1",
        "event_id": record["event_id"],
        "tenant_id": record["tenant_id"],
        "source": record["source"],
        "event_type": record["event_type"],
        "observed_at": record["observed_at"],
        "device_serial": record["device_serial"],
        "client_mac": record["client_mac"],
        "occupancy_value": record["occupancy_value"],
        "raw_s3_key": record["raw_s3_key"],
        "processed_at": datetime.now(UTC).isoformat(),
    }
    sqs_client().send_message(
        QueueUrl=_required("DATALAKE_QUEUE_URL"),
        MessageBody=json.dumps(datalake_message, separators=(",", ":"), default=str),
    )
    logger.info("processed event_id=%s source=%s", record["event_id"], record["source"])
    return datalake_message


def receive_once(connection: psycopg.Connection[Any]) -> int:
    queue_url = _required("PROCESSING_QUEUE_URL")
    wait = int(os.getenv("PROCESSOR_POLL_WAIT_SECONDS", "20"))
    response = sqs_client().receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=wait,
        AttributeNames=["ApproximateReceiveCount"],
    )
    messages = response.get("Messages", [])
    processed = 0
    for message in messages:
        process_message(message["Body"], connection)
        sqs_client().delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
        processed += 1
    return processed


def run_forever() -> None:
    reconnect_delay = int(os.getenv("PROCESSOR_FAILURE_BACKOFF_SECONDS", "5"))
    while True:
        try:
            with psycopg.connect(database_dsn()) as connection:
                while True:
                    receive_once(connection)
        except Exception:
            logger.exception("processor loop failed; message remains on queue for retry/DLQ")
            time.sleep(reconnect_delay)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="Receive one SQS batch and exit")
    args = parser.parse_args()
    if args.once:
        with psycopg.connect(database_dsn()) as connection:
            receive_once(connection)
    else:
        run_forever()


if __name__ == "__main__":
    main()

```

## `services/processor/tests/test_worker.py`
```
import io
import json

from processor_service import worker


class FakeBody:
    def __init__(self, payload):
        self.payload = payload
    def read(self):
        return json.dumps(self.payload).encode()


class FakeS3:
    def get_object(self, **kwargs):
        return {"Body": FakeBody({"type": "occupancy", "value": 1, "deviceSerial": "Q2XX-1234"})}


class FakeSQS:
    def __init__(self):
        self.messages = []
    def send_message(self, **kwargs):
        self.messages.append(kwargs)


class FakeCursor:
    def __init__(self):
        self.executions = []
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def execute(self, sql, params=None):
        self.executions.append((sql, params))


class FakeConnection:
    def __init__(self):
        self.cursor_obj = FakeCursor()
        self.committed = False
    def cursor(self):
        return self.cursor_obj
    def commit(self):
        self.committed = True


def test_normalize_extracts_occupancy():
    record = worker.normalize(
        {"type": "occupancy", "value": "1", "deviceSerial": "Q2XX"},
        {"event_id": "evt-1", "tenant_id": "org-1", "source": "inbound", "key": "raw.json"},
    )
    assert record["occupancy_value"] == 1.0
    assert record["device_serial"] == "Q2XX"


def test_process_message_writes_db_and_datalake(monkeypatch):
    sqs = FakeSQS()
    monkeypatch.setenv("DATALAKE_QUEUE_URL", "datalake")
    monkeypatch.setattr(worker, "s3_client", lambda: FakeS3())
    monkeypatch.setattr(worker, "sqs_client", lambda: sqs)
    connection = FakeConnection()
    message = json.dumps({
        "bucket": "bucket",
        "key": "raw.json",
        "source": "inbound",
        "tenant_id": "org-1",
        "event_id": "evt-1",
    })
    result = worker.process_message(message, connection)
    assert connection.committed
    assert len(connection.cursor_obj.executions) == 2
    assert result["event_id"] == "evt-1"
    assert len(sqs.messages) == 1

```

## `terraform/.gitignore`
```
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.plan
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc

# Keep .terraform.lock.hcl committed after terraform init.

```

## `terraform/README.md`
```
# Occupancy Platform Terraform

This replacement baseline implements the reviewed HLD model:

- Cisco Meraki ingress: CloudFront + WAF -> CloudFront VPC Origin -> internal ALB -> inbound ECS.
- Application services: inbound and processor on ECS Fargate. The historical outbound service is disabled by default.
- Meraki API outbound access: Processor subnets -> NAT Gateway/EIP. APP/inbound subnets have no default Internet route.
- Data: S3 data bucket, processing SQS/DLQ, RDS PostgreSQL, data-lake delivery SQS/DLQ.
- Notifications: SNS topic for the approved ServiceNow integration path.
- Logs: CloudWatch log groups for ECS plus a central S3 log bucket. ALB and WAF logging are wired to the log bucket. ECS-to-S3 log archival should be implemented with the enterprise-standard delivery mechanism (for example Firehose/subscription) once that mechanism is approved.
- Security: separate ECS security groups and IAM task roles, private endpoints, KMS option, RDS-managed Secrets Manager master password.

## CIDR model

Every environment receives the same parent /16 input. Terraform derives the first four /21s:

- dev: index 0 -> 10.0.0.0/21
- reserved: index 1 -> 10.0.8.0/21
- uat: index 2 -> 10.0.16.0/21
- prod: index 3 -> 10.0.24.0/21

Each /21 is divided into eight /24 allocation blocks:

0. ALB
1. APP
2. VPCE
3. RDS
4. NAT
5. PROCESSOR (NAT-routed)
6-7. Reserved

Each active functional /24 is split into /25s by AZ.

## Validate a deployment profile

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev.tfvars
```

Before enabling ECS services, push immutable images to the generated inbound/processor ECR repositories and set `container_image_tag` to the immutable tag/SHA.

For CI/CD, do not set an AWS provider profile. Use GitHub OIDC to assume environment-specific AWS roles and initialize a remote encrypted Terraform backend.


## Route53 and CloudFront custom-domain behavior

Route53 is intentionally safe to enable before DNS values are known.

- `deployment.route53 = false`: no Route53 resources are created.
- `deployment.route53 = true` with both `route53_zone_id = null` and `route53_zone_name = null`: no hosted zone or DNS records are created; CloudFront continues to work on its generated `*.cloudfront.net` hostname when aliases are empty.
- Set `route53_zone_id` to use an existing public hosted zone.
- Or set `route53_zone_name` and leave `route53_zone_id = null` to create a public hosted zone in Terraform. Creating a hosted zone does not register the domain; delegate the domain/subdomain to the `route53_created_name_servers` output.
- If `cloudfront_aliases` is non-empty and `cloudfront_acm_certificate_arn` is null, Terraform automatically creates the required ACM certificate in `us-east-1` and DNS-validates it through the effective Route53 zone.
- If DNS is managed outside Route53, supply an existing `cloudfront_acm_certificate_arn` and keep `deployment.route53 = false`.

```

## `terraform/acm.tf`
```
# CloudFront custom-domain certificates must be created in us-east-1.
# If an existing ARN is supplied, Terraform uses it. Otherwise, when aliases and
# a Route53 hosted zone are available, Terraform creates and DNS-validates one.

locals {
  create_cloudfront_certificate = (
    var.deployment.cloudfront &&
    length(var.cloudfront_aliases) > 0 &&
    var.cloudfront_acm_certificate_arn == null &&
    var.deployment.route53 &&
    local.route53_effective_zone_id != null
  )
}

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1
  count    = local.create_cloudfront_certificate ? 1 : 0

  domain_name               = var.cloudfront_aliases[0]
  subject_alternative_names = slice(var.cloudfront_aliases, 1, length(var.cloudfront_aliases))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront-certificate"
  }
}

resource "aws_route53_record" "cloudfront_certificate_validation" {
  for_each = local.create_cloudfront_certificate ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.route53_effective_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1
  count    = local.create_cloudfront_certificate ? 1 : 0

  certificate_arn = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [
    for record in aws_route53_record.cloudfront_certificate_validation : record.fqdn
  ]
}

locals {
  cloudfront_certificate_arn = (
    var.cloudfront_acm_certificate_arn != null
    ? var.cloudfront_acm_certificate_arn
    : try(aws_acm_certificate_validation.cloudfront[0].certificate_arn, null)
  )
}

```

## `terraform/alb.tf`
```
resource "aws_lb" "internal" {
  count = var.deployment.alb ? 1 : 0

  name               = substr("${local.name_prefix}-alb", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = [for az in local.two_azs : aws_subnet.alb[az].id]

  enable_deletion_protection = var.environment == "prod"
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.deployment.log_bucket ? [1] : []
    content {
      bucket  = aws_s3_bucket.logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "inbound" {
  count = var.deployment.alb ? 1 : 0

  # Primary target group. With native ECS blue/green, ECS alternates traffic
  # between this target group and aws_lb_target_group.inbound_alternate.
  name        = substr("${local.name_prefix}-inbound", 0, 32)
  port        = var.inbound_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = var.alb_health_check_path
    protocol            = "HTTP"
  }

  tags = {
    Service = "inbound"
  }
}


resource "aws_lb_target_group" "inbound_alternate" {
  count = var.deployment.alb && var.inbound_blue_green_enabled ? 1 : 0

  name        = trimsuffix(substr("${local.name_prefix}-inbound-alt", 0, 32), "-")
  port        = var.inbound_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = var.alb_health_check_path
    protocol            = "HTTP"
  }

  tags = {
    Service    = "inbound"
    Deployment = "alternate"
  }
}

resource "aws_lb_listener" "http" {
  count = var.deployment.alb && var.alb_certificate_arn == null ? 1 : 0

  load_balancer_arn = aws_lb.internal[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inbound[0].arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.deployment.alb && var.alb_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.internal[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inbound[0].arn
  }
}


# Native ECS blue/green requires an ALB listener *rule* ARN, not the listener ARN.
# The rule must reference both target groups and start with exactly one non-zero weight.
# ECS owns the target-group weights during deployments; Terraform therefore ignores
# subsequent action changes made by ECS.
resource "aws_lb_listener_rule" "inbound_blue_green" {
  count = var.deployment.alb && var.inbound_blue_green_enabled ? 1 : 0

  listener_arn = var.alb_certificate_arn == null ? aws_lb_listener.http[0].arn : aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.inbound[0].arn
        weight = 1
      }

      target_group {
        arn    = aws_lb_target_group.inbound_alternate[0].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_target_group" "management" {
  count = var.deployment.alb && var.deployment.management_service ? 1 : 0

  name        = trimsuffix(substr("${local.name_prefix}-mgmt", 0, 32), "-")
  port        = var.management_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = "/health"
    protocol            = "HTTP"
  }

  tags = { Service = "management" }
}

resource "aws_lb_listener_rule" "management" {
  count = var.deployment.alb && var.deployment.management_service ? 1 : 0

  listener_arn = var.alb_certificate_arn == null ? aws_lb_listener.http[0].arn : aws_lb_listener.https[0].arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.management[0].arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/management/*", "/management/*"]
    }
  }
}

```

## `terraform/backend.tf`
```
terraform {
  backend "s3" {}
}

```

## `terraform/backends/dev.hcl`
```
bucket       = "wmp-tfstate"
key          = "dev/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true

```

## `terraform/backends/prod.hcl`
```
bucket       = "wmp-tfstate"
key          = "prod/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true

```

## `terraform/backends/uat.hcl`
```
bucket       = "wmp-tfstate"
key          = "uat/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true

```

## `terraform/cloudfront.tf`
```
data "aws_cloudfront_cache_policy" "caching_disabled" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "Managed-AllViewer"
}

resource "aws_cloudfront_vpc_origin" "alb" {
  count = var.deployment.cloudfront ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${local.name_prefix}-alb-vpc-origin"
    arn                    = aws_lb.internal[0].arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = local.alb_origin_policy

    origin_ssl_protocols {
      quantity = 1
      items    = ["TLSv1.2"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront-vpc-origin"
  }
}

resource "aws_cloudfront_distribution" "api" {
  count = var.deployment.cloudfront ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} REST API"
  aliases         = var.cloudfront_aliases
  price_class     = "PriceClass_100"

  origin {
    domain_name = aws_lb.internal[0].dns_name
    origin_id   = "${local.name_prefix}-internal-alb"

    vpc_origin_config {
      vpc_origin_id           = aws_cloudfront_vpc_origin.alb[0].id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    target_origin_id       = "${local.name_prefix}-internal-alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled[0].id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer[0].id
  }

  viewer_certificate {
    cloudfront_default_certificate = local.cloudfront_certificate_arn == null
    acm_certificate_arn            = local.cloudfront_certificate_arn
    ssl_support_method             = local.cloudfront_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = local.cloudfront_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  web_acl_id = var.deployment.waf ? aws_wafv2_web_acl.cloudfront[0].arn : null

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}

```

## `terraform/ecr.tf`
```
resource "aws_ecr_repository" "application" {
  for_each = var.deployment.ecr ? local.ecr_repository_names : toset([])

  name                 = "${local.name_prefix}-${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.deployment.kms ? "KMS" : "AES256"
    kms_key          = var.deployment.kms ? aws_kms_key.application[0].arn : null
  }

  tags = {
    Name    = "${local.name_prefix}-${each.value}"
    Service = each.value
  }
}

resource "aws_ecr_lifecycle_policy" "application" {
  for_each = aws_ecr_repository.application

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain the most recent 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

```

## `terraform/ecs.tf`
```
resource "aws_ecs_cluster" "main" {
  count = var.deployment.ecs_cluster ? 1 : 0

  name = "${local.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ecs"
  }
}

resource "aws_ecs_task_definition" "service" {
  for_each = local.enabled_ecs_services

  family                   = "${local.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_cpu)
  memory                   = tostring(var.ecs_memory)
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${aws_ecr_repository.application[each.key].repository_url}:${var.container_image_tag}"
      essential = true

      portMappings = contains(["inbound", "management"], each.key) ? [
        {
          containerPort = each.key == "inbound" ? var.inbound_port : var.management_port
          hostPort      = each.key == "inbound" ? var.inbound_port : var.management_port
          protocol      = "tcp"
        }
      ] : []

      environment = concat(
        [
          { name = "ENVIRONMENT", value = var.environment },
          { name = "SERVICE_NAME", value = each.key },
          { name = "AWS_REGION", value = var.aws_region },
          { name = "MERAKI_BASE_URL", value = var.meraki_base_url },
          { name = "MERAKI_POLL_PATHS", value = var.meraki_poll_paths },
          { name = "MERAKI_POLL_INTERVAL_SECONDS", value = tostring(var.meraki_poll_interval_seconds) },
          { name = "WEBHOOK_AUTH_REQUIRED", value = tostring(var.webhook_auth_required) },
          { name = "PROCESSOR_POLL_WAIT_SECONDS", value = tostring(var.processor_poll_wait_seconds) }
        ],
        var.deployment.data_bucket ? [
          { name = "DATA_BUCKET", value = aws_s3_bucket.data[0].bucket }
        ] : [],
        var.deployment.processing_queue ? [
          { name = "PROCESSING_QUEUE_URL", value = aws_sqs_queue.processing[0].url }
        ] : [],
        var.deployment.datalake_queue ? [
          { name = "DATALAKE_QUEUE_URL", value = aws_sqs_queue.datalake[0].url }
        ] : [],
        var.deployment.rds ? [
          { name = "RDS_ENDPOINT", value = aws_db_instance.platform[0].address },
          { name = "RDS_PORT", value = tostring(aws_db_instance.platform[0].port) },
          { name = "RDS_DATABASE", value = var.rds_database_name },
          { name = "RDS_SECRET_ARN", value = aws_db_instance.platform[0].master_user_secret[0].secret_arn }
        ] : [],
        var.deployment.sns ? [
          { name = "SERVICENOW_SNS_TOPIC_ARN", value = aws_sns_topic.servicenow[0].arn }
        ] : [],
        var.deployment.secrets_manager ? [
          { name = "MERAKI_SECRET_ARN", value = aws_secretsmanager_secret.meraki[0].arn }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }
    }
  ])

  tags = {
    Service = each.key
  }
}

resource "aws_ecs_service" "inbound" {
  count = var.deployment.inbound_service ? 1 : 0

  name            = "${local.name_prefix}-inbound"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["inbound"].arn
  desired_count   = var.ecs_desired_count.inbound
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true
  wait_for_steady_state              = true

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = var.inbound_blue_green_enabled ? "BLUE_GREEN" : "ROLLING"
    bake_time_in_minutes = var.inbound_blue_green_enabled ? var.inbound_blue_green_bake_time_minutes : null
  }

  # The ECS deployment circuit breaker is for ROLLING deployments. Native
  # BLUE_GREEN uses its own deployment stages/health checks and may optionally
  # add CloudWatch deployment alarms or lifecycle hooks for richer rollback gates.
  dynamic "deployment_circuit_breaker" {
    for_each = var.inbound_blue_green_enabled ? [] : [1]
    content {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["inbound"].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.inbound[0].arn
    container_name   = "inbound"
    container_port   = var.inbound_port

    dynamic "advanced_configuration" {
      for_each = var.inbound_blue_green_enabled ? [1] : []
      content {
        alternate_target_group_arn = aws_lb_target_group.inbound_alternate[0].arn
        production_listener_rule   = aws_lb_listener_rule.inbound_blue_green[0].arn
        role_arn                   = aws_iam_role.ecs_blue_green_infrastructure[0].arn
      }
    }
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https,
    aws_lb_listener_rule.inbound_blue_green,
    aws_iam_role_policy_attachment.ecs_blue_green_infrastructure
  ]

  timeouts {
    create = "60m"
    update = "60m"
  }
}

resource "aws_ecs_service" "outbound" {
  count = var.deployment.outbound_service ? 1 : 0

  name            = "${local.name_prefix}-outbound"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["outbound"].arn
  desired_count   = var.ecs_desired_count.outbound
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["outbound"].id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "processor" {
  count = var.deployment.processor_service ? 1 : 0

  name            = "${local.name_prefix}-processor"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["processor"].arn
  desired_count   = var.ecs_desired_count.processor
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.processor[az].id]
    security_groups  = [aws_security_group.ecs["processor"].id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "management" {
  count = var.deployment.management_service ? 1 : 0

  name            = "${local.name_prefix}-management"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["management"].arn
  desired_count   = var.ecs_desired_count.management
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true
  wait_for_steady_state              = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["management"].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.management[0].arn
    container_name   = "management"
    container_port   = var.management_port
  }

  depends_on = [aws_lb_listener_rule.management]
}

```

## `terraform/environments/dev.tfvars`
```
aws_region   = "eu-west-2"
environment  = "dev"
project_name = "occupancy-platform"
owner        = "platform-team"

# Same parent /16 for every environment.
# Terraform derives Dev as 10.0.0.0/21.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

  nat_gateway  = true
  nat_az_count = 1

  alb        = true
  cloudfront = true
  waf        = true
  route53    = false

  ecr             = true
  kms             = true
  secrets_manager = true

  data_bucket = true
  log_bucket  = true

  processing_queue = true
  datalake_queue   = true
  sns               = true

  rds = true

  ecs_cluster       = true
  inbound_service   = true
  outbound_service  = false
  processor_service = true
  management_service = true

  vpc_endpoints = {
    s3   = true
    ecr  = true
    sqs  = true
    kms  = true
    logs            = true
    sts             = true
    secrets_manager = true
  }
}

alb_certificate_arn = null
alb_ingress_cidrs   = []

cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                 = null
route53_zone_name               = null

rds_multi_az = false

# In CI/CD replace with the immutable image tag/SHA built for this release.
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url                  = "https://api.meraki.com/api/v1"
meraki_poll_paths                = "/organizations"
meraki_poll_interval_seconds     = 300
webhook_auth_required            = true
processor_poll_wait_seconds      = 20

```

## `terraform/environments/prod.tfvars`
```
aws_region   = "eu-west-2"
environment  = "prod"
project_name = "occupancy-platform"
owner        = "platform-team"

# Terraform derives Prod as 10.0.24.0/21.
# NAT allocation inside Prod is therefore 10.0.28.0/24,
# split to 10.0.28.0/25 and 10.0.28.128/25.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

  nat_gateway  = true
  nat_az_count = 2

  alb        = true
  cloudfront = true
  waf        = true
  route53    = false

  ecr             = true
  kms             = true
  secrets_manager = true

  data_bucket = true
  log_bucket  = true

  processing_queue = true
  datalake_queue   = true
  sns               = true

  rds = true

  ecs_cluster       = true

  # Turn these on after the corresponding immutable container images exist.
  inbound_service   = true
  outbound_service  = false
  processor_service = true
  management_service = true

  vpc_endpoints = {
    s3   = true
    ecr  = true
    sqs  = true
    kms  = true
    logs            = true
    sts             = true
    secrets_manager = true
  }
}

# For production, set this to the regional ACM ARN before enabling traffic.
alb_certificate_arn = null
alb_ingress_cidrs   = []

# Example after certificate/DNS approval:
# cloudfront_aliases             = ["api.example.com"]
# cloudfront_acm_certificate_arn = "arn:aws:acm:us-east-1:..."
# route53_zone_id                = "Z..."
cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                 = null
route53_zone_name               = null

# Production uses native ECS blue/green for the ALB-facing inbound service.
# Blue and green revisions share the same cluster, APP subnets, ALB, CloudFront and WAF.
inbound_blue_green_enabled           = true
inbound_blue_green_bake_time_minutes = 10

rds_multi_az      = true
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url                  = "https://api.meraki.com/api/v1"
meraki_poll_paths                = "/organizations"
meraki_poll_interval_seconds     = 300
webhook_auth_required            = true
processor_poll_wait_seconds      = 20

```

## `terraform/environments/uat.tfvars`
```
aws_region   = "eu-west-2"
environment  = "uat"
project_name = "occupancy-platform"
owner        = "platform-team"

# Terraform derives UAT as 10.0.16.0/21.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

  # Production-like topology. Set nat_az_count=1 only if TDA explicitly accepts
  # lower-cost cross-AZ NAT for UAT.
  nat_gateway  = true
  nat_az_count = 2

  alb        = true
  cloudfront = true
  waf        = true
  route53    = false

  ecr             = true
  kms             = true
  secrets_manager = true

  data_bucket = true
  log_bucket  = true

  processing_queue = true
  datalake_queue   = true
  sns               = true

  rds = true

  ecs_cluster       = true
  inbound_service   = true
  outbound_service  = false
  processor_service = true
  management_service = true

  vpc_endpoints = {
    s3   = true
    ecr  = true
    sqs  = true
    kms  = true
    logs            = true
    sts             = true
    secrets_manager = true
  }
}

# Replace before using HTTPS on the internal ALB.
# When null, CloudFront -> ALB uses HTTP inside the VPC origin.
alb_certificate_arn = null
alb_ingress_cidrs   = []

# Add aliases only after setting a valid us-east-1 ACM certificate.
cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                 = null
route53_zone_name               = null

rds_multi_az      = true
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url                  = "https://api.meraki.com/api/v1"
meraki_poll_paths                = "/organizations"
meraki_poll_interval_seconds     = 300
webhook_auth_required            = true
processor_poll_wait_seconds      = 20

```

## `terraform/iam.tf`
```
data "aws_iam_policy_document" "ecs_task_execution_assume" {
  count = var.deployment.ecs_cluster ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  count = var.deployment.ecs_cluster ? 1 : 0

  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume[0].json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count = var.deployment.ecs_cluster ? 1 : 0

  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_assume" {
  for_each = local.enabled_ecs_services

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  for_each = local.enabled_ecs_services

  name               = "${local.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume[each.key].json

  tags = {
    Service = each.key
  }
}

data "aws_iam_policy_document" "ecs_task" {
  for_each = local.enabled_ecs_services

  dynamic "statement" {
    for_each = var.deployment.data_bucket && contains(["inbound", "outbound", "processor"], each.key) ? [1] : []
    content {
      sid = "DataBucket"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      resources = [
        aws_s3_bucket.data[0].arn,
        "${aws_s3_bucket.data[0].arn}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.processing_queue && contains(["inbound", "outbound", "processor"], each.key) ? [1] : []
    content {
      sid = "ProcessingQueue"
      actions = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      resources = [aws_sqs_queue.processing[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.datalake_queue && each.key == "processor" ? [1] : []
    content {
      sid = "DataLakeQueue"
      actions = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      resources = [aws_sqs_queue.datalake[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.sns ? [1] : []
    content {
      sid       = "ServiceNowNotifications"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.servicenow[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.rds && contains(["processor", "management"], each.key) ? [1] : []
    content {
      sid       = "RDSMasterSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_db_instance.platform[0].master_user_secret[0].secret_arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.secrets_manager && contains(["inbound", "outbound"], each.key) ? [1] : []
    content {
      sid       = "MerakiSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.meraki[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.kms ? [1] : []
    content {
      sid = "ApplicationKMS"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      resources = [aws_kms_key.application[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  for_each = local.enabled_ecs_services

  name   = "${local.name_prefix}-${each.key}-task-policy"
  role   = aws_iam_role.ecs_task[each.key].id
  policy = data.aws_iam_policy_document.ecs_task[each.key].json
}


# Amazon ECS native blue/green needs an infrastructure role that ECS itself can
# assume to update ALB listener rules and target-group registrations.
data "aws_iam_policy_document" "ecs_blue_green_infrastructure_assume" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_blue_green_infrastructure" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  name               = "${local.name_prefix}-ecs-blue-green-lb"
  assume_role_policy = data.aws_iam_policy_document.ecs_blue_green_infrastructure_assume[0].json

  tags = {
    Purpose = "ecs-native-blue-green-load-balancer-management"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_blue_green_infrastructure" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  role       = aws_iam_role.ecs_blue_green_infrastructure[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

```

## `terraform/kms.tf`
```
data "aws_iam_policy_document" "application_kms" {
  count = var.deployment.kms ? 1 : 0

  statement {
    sid    = "EnableAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "application" {
  count = var.deployment.kms ? 1 : 0

  description             = "KMS key for ${local.name_prefix}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.application_kms[0].json

  tags = {
    Name = "${local.name_prefix}-kms"
  }
}

resource "aws_kms_alias" "application" {
  count         = var.deployment.kms ? 1 : 0
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.application[0].key_id
}

```

## `terraform/locals.tf`
```
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  # ----------------------------------------------------------
  # Parent /16 -> first four /21 environment allocations.
  # dev=0, uat=2, prod=3; index 1 (10.0.8.0/21) remains reserved
  # ----------------------------------------------------------
  environment_index = {
    dev  = 0
    uat  = 2
    prod = 3
  }[var.environment]

  environment_cidr = cidrsubnet(var.vpc_cidr, 5, local.environment_index)

  # /21 -> 8 x /24 functional allocation blocks.
  # APP remains the shared private tier for all ALB-facing ECS services.
  # Processor receives the only additional ECS subnet tier because it alone
  # initiates Internet-bound traffic through NAT. Blocks #6 and #7 remain reserved.
  allocation_cidrs = {
    alb       = cidrsubnet(local.environment_cidr, 3, 0)
    app       = cidrsubnet(local.environment_cidr, 3, 1)
    vpce      = cidrsubnet(local.environment_cidr, 3, 2)
    rds       = cidrsubnet(local.environment_cidr, 3, 3)
    nat       = cidrsubnet(local.environment_cidr, 3, 4)
    processor = cidrsubnet(local.environment_cidr, 3, 5)
    reserved = [
      cidrsubnet(local.environment_cidr, 3, 6),
      cidrsubnet(local.environment_cidr, 3, 7)
    ]
  }

  subnet_cidrs = {
    alb = [
      cidrsubnet(local.allocation_cidrs.alb, 1, 0),
      cidrsubnet(local.allocation_cidrs.alb, 1, 1)
    ]
    app = [
      cidrsubnet(local.allocation_cidrs.app, 1, 0),
      cidrsubnet(local.allocation_cidrs.app, 1, 1)
    ]
    vpce = [
      cidrsubnet(local.allocation_cidrs.vpce, 1, 0),
      cidrsubnet(local.allocation_cidrs.vpce, 1, 1)
    ]
    rds = [
      cidrsubnet(local.allocation_cidrs.rds, 1, 0),
      cidrsubnet(local.allocation_cidrs.rds, 1, 1)
    ]
    nat = [
      cidrsubnet(local.allocation_cidrs.nat, 1, 0),
      cidrsubnet(local.allocation_cidrs.nat, 1, 1)
    ]
    processor = [
      cidrsubnet(local.allocation_cidrs.processor, 1, 0),
      cidrsubnet(local.allocation_cidrs.processor, 1, 1)
    ]
  }

  active_azs = slice(var.azs, 0, var.deployment.app_az_count)
  active_az_map = {
    for index, az in local.active_azs : az => index
  }

  two_azs = slice(var.azs, 0, 2)
  two_az_map = {
    for index, az in local.two_azs : az => index
  }

  nat_azs = var.deployment.nat_gateway ? slice(var.azs, 0, var.deployment.nat_az_count) : []
  nat_az_map = {
    for index, az in local.nat_azs : az => index
  }

  interface_endpoints_enabled = anytrue([
    var.deployment.vpc_endpoints.ecr,
    var.deployment.vpc_endpoints.sqs,
    var.deployment.vpc_endpoints.kms,
    var.deployment.vpc_endpoints.logs,
    var.deployment.vpc_endpoints.sts,
    var.deployment.vpc_endpoints.secrets_manager
  ])

  ecs_service_flags = {
    inbound   = var.service_deployment_enabled && var.deployment.inbound_service
    outbound  = var.service_deployment_enabled && var.deployment.outbound_service
    processor  = var.service_deployment_enabled && var.deployment.processor_service
    management = var.service_deployment_enabled && var.deployment.management_service
  }

  enabled_ecs_services = {
    for name, enabled in local.ecs_service_flags : name => enabled if enabled
  }

  ecr_repository_names = toset(["inbound", "outbound", "processor", "management"])

  # For NAT-routed workload AZs without a same-AZ NAT, route to the first
  # enabled NAT. This intentionally permits lower environments to use one NAT
  # for cost while production can remain AZ-local with two NAT gateways.
  workload_nat_target_az = var.deployment.nat_gateway && length(local.nat_azs) > 0 ? {
    for az in local.active_azs : az => (
      contains(local.nat_azs, az) ? az : local.nat_azs[0]
    )
  } : {}

  data_bucket_name = "${substr(replace(lower(local.name_prefix), "_", "-"), 0, 35)}-${data.aws_caller_identity.current.account_id}-data"
  log_bucket_name  = "aws-waf-logs-${substr(replace(lower(local.name_prefix), "_", "-"), 0, 24)}-${data.aws_caller_identity.current.account_id}"

  alb_listener_port = var.alb_certificate_arn != null ? 443 : 80
  alb_origin_policy = var.alb_certificate_arn != null ? "https-only" : "http-only"
}

```

## `terraform/logs.tf`
```
resource "aws_cloudwatch_log_group" "ecs" {
  for_each = local.enabled_ecs_services

  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = var.deployment.kms ? aws_kms_key.application[0].arn : null

  tags = {
    Service = each.key
  }
}

```

## `terraform/nat.tf`
```
# One public route table/NAT/EIP per enabled NAT AZ.
resource "aws_route_table" "nat_public" {
  for_each = local.nat_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-nat-public-${each.key}"
  }
}

resource "aws_route" "nat_public_internet" {
  for_each = local.nat_az_map

  route_table_id         = aws_route_table.nat_public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "nat_public" {
  for_each = local.nat_az_map

  subnet_id      = aws_subnet.nat_public[each.key].id
  route_table_id = aws_route_table.nat_public[each.key].id
}

resource "aws_eip" "nat" {
  for_each = local.nat_az_map
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_az_map

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.nat_public[each.key].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }
}

# One isolated route table per APP application AZ.
# No 0.0.0.0/0 route is created here; AWS service access is through VPC
# endpoints and VPC-local routes only.
resource "aws_route_table" "app" {
  for_each = local.active_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-app-${each.key}"
  }
}

resource "aws_route_table_association" "app" {
  for_each = local.active_az_map

  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}

# Dedicated Processor route tables. Processor is the only ECS tier with
# an Internet default route through NAT.
resource "aws_route_table" "processor" {
  for_each = local.active_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-processor-${each.key}"
  }
}

resource "aws_route" "processor_nat" {
  for_each = var.deployment.nat_gateway ? local.active_az_map : {}

  route_table_id         = aws_route_table.processor[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.workload_nat_target_az[each.key]].id
}

resource "aws_route_table_association" "processor" {
  for_each = local.active_az_map

  subnet_id      = aws_subnet.processor[each.key].id
  route_table_id = aws_route_table.processor[each.key].id
}

```

## `terraform/network.tf`
```
resource "aws_vpc" "main" {
  cidr_block           = local.environment_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  # CloudFront VPC Origins require an IGW attached to the VPC even though
  # origin traffic itself does not route through the IGW.
  count  = (var.deployment.nat_gateway || var.deployment.cloudfront) ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# APP ECS subnets follow app_az_count and have no Internet/NAT default route.
# All ALB-facing ECS services use this tier.
resource "aws_subnet" "app" {
  for_each = local.active_az_map

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.app[each.value]

  tags = {
    Name = "${local.name_prefix}-app-${each.key}"
    Tier = "application"
  }
}

# Processor ECS subnets are isolated from Inbound and use their own route tables.
# Per the requested design these subnets receive NAT default routes.
resource "aws_subnet" "processor" {
  for_each = local.active_az_map

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.processor[each.value]

  tags = {
    Name = "${local.name_prefix}-processor-${each.key}"
    Tier = "processor-application"
  }
}

# ALB subnets exist only when ALB is enabled and always span two AZs.
resource "aws_subnet" "alb" {
  for_each = var.deployment.alb ? local.two_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.alb[each.value]

  tags = {
    Name = "${local.name_prefix}-alb-${each.key}"
    Tier = "alb"
  }
}

# Interface-endpoint subnets only exist when at least one interface endpoint is enabled.
resource "aws_subnet" "vpce" {
  for_each = local.interface_endpoints_enabled ? local.active_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.vpce[each.value]

  tags = {
    Name = "${local.name_prefix}-vpce-${each.key}"
    Tier = "vpce"
  }
}

# RDS subnet group must cover at least two AZs, even for a Single-AZ DB instance.
resource "aws_subnet" "rds" {
  for_each = var.deployment.rds ? local.two_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.rds[each.value]

  tags = {
    Name = "${local.name_prefix}-rds-${each.key}"
    Tier = "database"
  }
}

resource "aws_subnet" "nat_public" {
  for_each = local.nat_az_map

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = local.subnet_cidrs.nat[each.value]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-nat-public-${each.key}"
    Tier = "public-egress"
  }
}

# Isolated ALB route table.
resource "aws_route_table" "alb" {
  count  = var.deployment.alb ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-alb"
  }
}

resource "aws_route_table_association" "alb" {
  for_each       = aws_subnet.alb
  subnet_id      = each.value.id
  route_table_id = aws_route_table.alb[0].id
}

# Isolated interface endpoint route table.
resource "aws_route_table" "vpce" {
  count  = local.interface_endpoints_enabled ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-vpce"
  }
}

resource "aws_route_table_association" "vpce" {
  for_each       = aws_subnet.vpce
  subnet_id      = each.value.id
  route_table_id = aws_route_table.vpce[0].id
}

# Isolated RDS route table.
resource "aws_route_table" "rds" {
  count  = var.deployment.rds ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-rds"
  }
}

resource "aws_route_table_association" "rds" {
  for_each       = aws_subnet.rds
  subnet_id      = each.value.id
  route_table_id = aws_route_table.rds[0].id
}

```

## `terraform/outputs.tf`
```
output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "parent_network_cidr" {
  description = "Parent /16 network allocation supplied to Terraform."
  value       = var.vpc_cidr
}

output "vpc_cidr" {
  description = "Actual environment VPC CIDR derived from the parent /16."
  value       = local.environment_cidr
}

output "environment_cidr" {
  description = "Terraform-derived /21 for this environment."
  value       = local.environment_cidr
}

output "allocation_cidrs" {
  description = "The /24 functional allocation blocks inside the environment /21."
  value       = local.allocation_cidrs
}


output "subnet_cidrs" {
  description = "Actual /25 subnet CIDRs per functional tier and AZ index."
  value       = local.subnet_cidrs
}

output "deployed_subnet_cidrs" {
  description = "Actual subnet CIDRs deployed in this environment, keyed by tier and AZ."
  value = {
    alb  = { for az, subnet in aws_subnet.alb : az => subnet.cidr_block }
    app  = { for az, subnet in aws_subnet.app : az => subnet.cidr_block }
    vpce = { for az, subnet in aws_subnet.vpce : az => subnet.cidr_block }
    rds  = { for az, subnet in aws_subnet.rds : az => subnet.cidr_block }
    nat       = { for az, subnet in aws_subnet.nat_public : az => subnet.cidr_block }
    processor = { for az, subnet in aws_subnet.processor : az => subnet.cidr_block }
  }
}

# APP subnet tier is shared by all ALB-facing ECS services and has no NAT default route.
output "app_subnet_ids" {
  value = { for az, subnet in aws_subnet.app : az => subnet.id }
}

output "inbound_subnet_ids" {
  description = "ALB-facing ECS subnet IDs. These are the APP subnets and have no NAT default route."
  value       = { for az, subnet in aws_subnet.app : az => subnet.id }
}

output "processor_subnet_ids" {
  value = { for az, subnet in aws_subnet.processor : az => subnet.id }
}


output "alb_subnet_ids" {
  value = { for az, subnet in aws_subnet.alb : az => subnet.id }
}

output "vpce_subnet_ids" {
  value = { for az, subnet in aws_subnet.vpce : az => subnet.id }
}

output "rds_subnet_ids" {
  value = { for az, subnet in aws_subnet.rds : az => subnet.id }
}

output "nat_gateway_ids" {
  value = { for az, nat in aws_nat_gateway.this : az => nat.id }
}

output "nat_eip_public_ips" {
  value = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

output "internal_alb_dns_name" {
  value = try(aws_lb.internal[0].dns_name, null)
}

output "cloudfront_domain_name" {
  value = try(aws_cloudfront_distribution.api[0].domain_name, null)
}

output "data_bucket_name" {
  value = try(aws_s3_bucket.data[0].bucket, null)
}

output "log_bucket_name" {
  value = try(aws_s3_bucket.logs[0].bucket, null)
}

output "processing_queue_url" {
  value = try(aws_sqs_queue.processing[0].url, null)
}

output "datalake_queue_url" {
  value = try(aws_sqs_queue.datalake[0].url, null)
}

output "servicenow_sns_topic_arn" {
  value = try(aws_sns_topic.servicenow[0].arn, null)
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
}

output "rds_endpoint" {
  value = try(aws_db_instance.platform[0].address, null)
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN managed by RDS."
  value       = try(aws_db_instance.platform[0].master_user_secret[0].secret_arn, null)
  sensitive   = true
}

output "route53_hosted_zone_id" {
  description = "Effective Route53 hosted zone ID when Route53 is enabled."
  value       = local.route53_effective_zone_id
}

output "route53_created_name_servers" {
  description = "Name servers when Terraform created the public hosted zone. Delegate the registered domain/subdomain to these servers."
  value       = try(aws_route53_zone.public[0].name_servers, [])
}

output "cloudfront_certificate_arn" {
  description = "Effective CloudFront ACM certificate ARN, whether supplied or created by Terraform."
  value       = local.cloudfront_certificate_arn
}


output "inbound_deployment_strategy" {
  description = "Deployment strategy used by the ALB-facing inbound ECS service."
  value       = var.inbound_blue_green_enabled ? "BLUE_GREEN" : "ROLLING"
}

output "inbound_primary_target_group_arn" {
  description = "Primary inbound ALB target group ARN."
  value       = var.deployment.alb ? aws_lb_target_group.inbound[0].arn : null
}

output "inbound_alternate_target_group_arn" {
  description = "Alternate inbound ALB target group ARN used for native ECS blue/green."
  value       = var.deployment.alb && var.inbound_blue_green_enabled ? aws_lb_target_group.inbound_alternate[0].arn : null
}

```

## `terraform/providers.tf`
```
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Required for CloudFront-scoped WAF resources.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

```

## `terraform/rds.tf`
```
resource "aws_db_subnet_group" "platform" {
  count = var.deployment.rds ? 1 : 0

  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = [for az in local.two_azs : aws_subnet.rds[az].id]

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group"
  }
}

resource "aws_db_instance" "platform" {
  count = var.deployment.rds ? 1 : 0

  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.deployment.kms ? aws_kms_key.application[0].arn : null

  db_name  = var.rds_database_name
  username = var.rds_username
  port     = 5432

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null

  db_subnet_group_name   = aws_db_subnet_group.platform[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = false
  multi_az               = var.rds_multi_az

  backup_retention_period = var.rds_backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot       = true

  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-final-snapshot" : null

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}

```

## `terraform/route53.tf`
```
# Route53 is optional. Three supported modes:
# 1. route53=false: no Route53 resources. CloudFront can use its default domain.
# 2. route53=true + route53_zone_id set: use an existing public hosted zone.
# 3. route53=true + route53_zone_id=null + route53_zone_name set: create the public hosted zone.
#
# Creating a hosted zone does NOT register a domain. If Terraform creates the zone,
# delegate the registered domain/subdomain to the output name servers.

resource "aws_route53_zone" "public" {
  count = (
    var.deployment.route53 &&
    var.route53_zone_id == null &&
    var.route53_zone_name != null
  ) ? 1 : 0

  name    = trimsuffix(var.route53_zone_name, ".")
  comment = "Public hosted zone for ${local.name_prefix}"

  tags = {
    Name = "${local.name_prefix}-public-zone"
  }
}

locals {
  route53_effective_zone_id = var.deployment.route53 ? (
    var.route53_zone_id != null
    ? var.route53_zone_id
    : try(aws_route53_zone.public[0].zone_id, null)
  ) : null
}

resource "aws_route53_record" "cloudfront_a" {
  for_each = (
    var.deployment.route53 &&
    var.deployment.cloudfront &&
    local.route53_effective_zone_id != null
  ) ? toset(var.cloudfront_aliases) : toset([])

  zone_id = local.route53_effective_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_aaaa" {
  for_each = (
    var.deployment.route53 &&
    var.deployment.cloudfront &&
    local.route53_effective_zone_id != null
  ) ? toset(var.cloudfront_aliases) : toset([])

  zone_id = local.route53_effective_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }
}

```

## `terraform/s3.tf`
```
resource "aws_s3_bucket" "data" {
  count         = var.deployment.data_bucket ? 1 : 0
  bucket        = local.data_bucket_name
  force_destroy = var.data_bucket_force_destroy

  tags = {
    Name = local.data_bucket_name
    Type = "application-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.deployment.kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null
    }

    bucket_key_enabled = var.deployment.kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    id     = "noncurrent-version-retention"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.s3_data_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.data]
}

resource "aws_s3_bucket_policy" "data_tls" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data[0].arn,
          "${aws_s3_bucket.data[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket" "logs" {
  count         = var.deployment.log_bucket ? 1 : 0
  bucket        = local.log_bucket_name
  force_destroy = var.log_bucket_force_destroy

  tags = {
    Name = local.log_bucket_name
    Type = "central-log-archive"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "log_bucket" {
  count = var.deployment.log_bucket ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs[0].arn,
      "${aws_s3_bucket.logs[0].arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.alb ? [1] : []
    content {
      sid    = "AllowALBLogDelivery"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
      }

      actions = ["s3:PutObject"]
      resources = [
        "${aws_s3_bucket.logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.waf ? [1] : []
    content {
      sid    = "AWSWAFLogDeliveryAclCheck"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      actions = [
        "s3:GetBucketAcl",
        "s3:ListBucket"
      ]
      resources = [aws_s3_bucket.logs[0].arn]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deployment.waf ? [1] : []
    content {
      sid    = "AWSWAFLogDeliveryWrite"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      actions = ["s3:PutObject"]
      resources = [
        "${aws_s3_bucket.logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      ]

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.log_bucket[0].json
}

```

## `terraform/secrets.tf`
```
# Secret containers only. Secret values are populated/rotated outside Terraform
# so credentials do not enter tfvars or Terraform state.
resource "aws_secretsmanager_secret" "meraki" {
  count = var.deployment.secrets_manager ? 1 : 0

  name                    = "${local.name_prefix}/meraki/oauth"
  description             = "Cisco Meraki OAuth/API credentials for ${local.name_prefix}"
  kms_key_id              = var.deployment.kms ? aws_kms_key.application[0].arn : null
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.name_prefix}-meraki-oauth"
  }
}

```

## `terraform/security_groups.tf`
```
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  count       = var.deployment.alb ? 1 : 0
  name        = "${local.name_prefix}-sg-alb"
  description = "Internal ALB security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_cloudfront" {
  count = var.deployment.alb && var.deployment.cloudfront ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  prefix_list_id     = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id
  from_port          = local.alb_listener_port
  to_port            = local.alb_listener_port
  ip_protocol        = "tcp"
  description        = "CloudFront VPC origin traffic"
}

resource "aws_vpc_security_group_ingress_rule" "alb_test_cidrs" {
  for_each = var.deployment.alb ? toset(var.alb_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = each.value
  from_port          = local.alb_listener_port
  to_port            = local.alb_listener_port
  ip_protocol        = "tcp"
  description        = "Explicit direct ALB test ingress"
}

resource "aws_security_group" "ecs" {
  for_each = local.enabled_ecs_services

  name        = "${local.name_prefix}-sg-${each.key}"
  description = "${each.key} ECS service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${local.name_prefix}-sg-${each.key}"
    Service = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "inbound_from_alb" {
  count = var.deployment.inbound_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["inbound"].id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.inbound_port
  to_port                      = var.inbound_port
  ip_protocol                  = "tcp"
  description                  = "Inbound API traffic from internal ALB"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_inbound" {
  count = var.deployment.inbound_service ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  referenced_security_group_id = aws_security_group.ecs["inbound"].id
  from_port                    = var.inbound_port
  to_port                      = var.inbound_port
  ip_protocol                  = "tcp"
  description                  = "ALB to inbound ECS"
}

# ECS tasks need HTTPS for AWS APIs/endpoints; outbound also uses HTTPS to Meraki.
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  for_each = local.enabled_ecs_services

  security_group_id = aws_security_group.ecs[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS egress for AWS APIs/endpoints and approved external APIs"
}

resource "aws_security_group" "rds" {
  count       = var.deployment.rds ? 1 : 0
  name        = "${local.name_prefix}-sg-rds"
  description = "PostgreSQL RDS security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_processor" {
  count = var.deployment.rds && var.deployment.processor_service ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.ecs["processor"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from processor ECS"
}

resource "aws_vpc_security_group_egress_rule" "processor_to_rds" {
  count = var.deployment.rds && var.deployment.processor_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["processor"].id
  referenced_security_group_id = aws_security_group.rds[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Processor to PostgreSQL"
}

resource "aws_security_group" "vpce" {
  count       = local.interface_endpoints_enabled ? 1 : 0
  name        = "${local.name_prefix}-sg-vpce"
  description = "Interface VPC endpoint security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-vpce"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ecs" {
  for_each = local.interface_endpoints_enabled ? local.enabled_ecs_services : {}

  security_group_id            = aws_security_group.vpce[0].id
  referenced_security_group_id = aws_security_group.ecs[each.key].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS from ${each.key} ECS to interface endpoints"
}

resource "aws_vpc_security_group_ingress_rule" "management_from_alb" {
  count = var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["management"].id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.management_port
  to_port                      = var.management_port
  ip_protocol                  = "tcp"
  description                  = "Management UI/API traffic from internal ALB"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_management" {
  count = var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  referenced_security_group_id = aws_security_group.ecs["management"].id
  from_port                    = var.management_port
  to_port                      = var.management_port
  ip_protocol                  = "tcp"
  description                  = "ALB to management ECS"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_management" {
  count = var.deployment.rds && var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.ecs["management"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from management ECS"
}

resource "aws_vpc_security_group_egress_rule" "management_to_rds" {
  count = var.deployment.rds && var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["management"].id
  referenced_security_group_id = aws_security_group.rds[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Management ECS to PostgreSQL"
}

```

## `terraform/sns.tf`
```
resource "aws_sns_topic" "servicenow" {
  count = var.deployment.sns ? 1 : 0
  name  = "${local.name_prefix}-servicenow-notifications"

  kms_master_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sns_topic_subscription" "servicenow_https" {
  for_each = var.deployment.sns ? toset(var.sns_https_endpoints) : toset([])

  topic_arn = aws_sns_topic.servicenow[0].arn
  protocol  = "https"
  endpoint  = each.value
}

```

## `terraform/sqs.tf`
```
resource "aws_sqs_queue" "processing_dlq" {
  count = var.deployment.processing_queue ? 1 : 0

  name                      = "${local.name_prefix}-processing-dlq"
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sqs_queue" "processing" {
  count = var.deployment.processing_queue ? 1 : 0

  name                       = "${local.name_prefix}-processing"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = 345600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq[0].arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "datalake_dlq" {
  count = var.deployment.datalake_queue ? 1 : 0

  name                      = "${local.name_prefix}-datalake-dlq"
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sqs_queue" "datalake" {
  count = var.deployment.datalake_queue ? 1 : 0

  name                       = "${local.name_prefix}-datalake-delivery"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = 345600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.datalake_dlq[0].arn
    maxReceiveCount     = 5
  })
}

```

## `terraform/validation.tf`
```
resource "terraform_data" "configuration_validation" {
  input = var.environment

  lifecycle {
    precondition {
      condition     = !var.deployment.nat_gateway || var.deployment.nat_az_count >= 1
      error_message = "When nat_gateway=true, nat_az_count must be at least 1."
    }

    precondition {
      condition     = var.deployment.nat_gateway || var.deployment.nat_az_count == 0
      error_message = "When nat_gateway=false, set nat_az_count=0."
    }

    precondition {
      condition     = var.deployment.nat_az_count <= var.deployment.app_az_count
      error_message = "nat_az_count cannot exceed app_az_count."
    }

    precondition {
      condition     = !var.deployment.alb || var.deployment.app_az_count == 2
      error_message = "ALB deployment requires app_az_count=2 because the ALB spans two AZs."
    }

    precondition {
      condition     = !var.deployment.cloudfront || var.deployment.alb
      error_message = "cloudfront=true requires alb=true."
    }

    precondition {
      condition     = !var.deployment.waf || var.deployment.cloudfront
      error_message = "waf=true requires cloudfront=true."
    }

    precondition {
      condition     = !var.deployment.route53 || var.deployment.cloudfront
      error_message = "route53=true requires cloudfront=true."
    }

    precondition {
      condition = (
        length(var.cloudfront_aliases) == 0 ||
        var.cloudfront_acm_certificate_arn != null ||
        (var.deployment.route53 && (var.route53_zone_id != null || var.route53_zone_name != null))
      )
      error_message = "CloudFront aliases require either an existing cloudfront_acm_certificate_arn, or Route53 management with route53_zone_id/route53_zone_name so Terraform can create and DNS-validate the certificate."
    }

    precondition {
      condition     = length(local.enabled_ecs_services) == 0 || (var.deployment.ecs_cluster && var.deployment.ecr)
      error_message = "Any ECS service deployment requires ecs_cluster=true and ecr=true."
    }

    precondition {
      condition     = !var.deployment.inbound_service || var.deployment.alb
      error_message = "inbound_service=true requires alb=true."
    }

    precondition {
      condition = !var.deployment.inbound_service || (
        var.deployment.vpc_endpoints.ecr &&
        var.deployment.vpc_endpoints.s3 &&
        var.deployment.vpc_endpoints.sqs &&
        var.deployment.vpc_endpoints.logs &&
        var.deployment.vpc_endpoints.secrets_manager
      )
      error_message = "inbound_service=true uses an isolated subnet with no NAT route and therefore requires ECR, S3, SQS, CloudWatch Logs, and Secrets Manager VPC endpoints."
    }

    precondition {
      condition = !var.deployment.inbound_service || (
        var.deployment.data_bucket &&
        var.deployment.processing_queue
      )
      error_message = "inbound_service=true requires data_bucket=true and processing_queue=true."
    }

    precondition {
      condition     = !var.deployment.outbound_service || var.deployment.secrets_manager
      error_message = "outbound_service=true requires secrets_manager=true for its configured credentials."
    }

    precondition {
      condition = !var.deployment.outbound_service || (
        var.deployment.vpc_endpoints.ecr &&
        var.deployment.vpc_endpoints.s3 &&
        var.deployment.vpc_endpoints.sqs &&
        var.deployment.vpc_endpoints.logs &&
        var.deployment.vpc_endpoints.secrets_manager
      )
      error_message = "outbound_service=true is placed on the isolated APP subnet tier and therefore requires ECR, S3, SQS, CloudWatch Logs, and Secrets Manager VPC endpoints."
    }

    precondition {
      condition     = !var.deployment.processor_service || var.deployment.nat_gateway
      error_message = "processor_service=true requires nat_gateway=true in this routed-processor design."
    }

    precondition {
      condition = !var.deployment.processor_service || (
        var.deployment.data_bucket &&
        var.deployment.processing_queue &&
        var.deployment.datalake_queue &&
        var.deployment.rds
      )
      error_message = "processor_service=true requires data_bucket, processing_queue, datalake_queue, and rds."
    }
  }
}


resource "terraform_data" "blue_green_validation" {
  lifecycle {
    precondition {
      condition     = !var.inbound_blue_green_enabled || var.environment == "prod"
      error_message = "inbound_blue_green_enabled is intended for the prod environment in this repository."
    }

    precondition {
      condition     = !var.inbound_blue_green_enabled || (var.deployment.alb && var.deployment.ecs_cluster && var.deployment.inbound_service)
      error_message = "inbound_blue_green_enabled=true requires alb, ecs_cluster, and inbound_service to be enabled."
    }
  }
}

```

## `terraform/variables.tf`
```
# ============================================================
# GENERAL
# ============================================================

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "environment must be one of: dev, uat, prod."
  }
}

variable "project_name" {
  description = "Project/application name."
  type        = string
}

variable "owner" {
  description = "Infrastructure owner/team."
  type        = string
}

# ============================================================
# NETWORK
# ============================================================

variable "vpc_cidr" {
  description = "Parent /16 CIDR supplied to every environment. Terraform derives the environment /21 from environment."
  type        = string

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 5, 0)) && tonumber(split("/", var.vpc_cidr)[1]) == 16
    error_message = "vpc_cidr must be a valid /16 CIDR."
  }
}

variable "azs" {
  description = "Ordered AZ list. Supply at least two AZs because ALB/RDS may require two even when app_az_count is 1."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Provide at least two Availability Zones."
  }
}

# ============================================================
# DEPLOYMENT FLAGS
# ============================================================

variable "deployment" {
  description = "Environment deployment profile. Individual resources can be enabled/disabled."

  type = object({
    app_az_count = number

    nat_gateway  = bool
    nat_az_count = number

    alb        = bool
    cloudfront = bool
    waf        = bool
    route53    = bool

    ecr             = bool
    kms             = bool
    secrets_manager = bool

    data_bucket = bool
    log_bucket  = bool

    processing_queue = bool
    datalake_queue   = bool
    sns               = bool

    rds = bool

    ecs_cluster       = bool
    inbound_service   = bool
    outbound_service  = bool
    processor_service = bool
    management_service = bool

    vpc_endpoints = object({
      s3   = bool
      ecr  = bool
      sqs  = bool
      kms  = bool
      logs            = bool
      sts             = bool
      secrets_manager = bool
    })
  })

  validation {
    condition     = var.deployment.app_az_count >= 1 && var.deployment.app_az_count <= 2
    error_message = "deployment.app_az_count must be 1 or 2."
  }

  validation {
    condition     = var.deployment.nat_az_count >= 0 && var.deployment.nat_az_count <= 2
    error_message = "deployment.nat_az_count must be 0, 1, or 2."
  }
}

# ============================================================
# ALB / CLOUDFRONT / DNS
# ============================================================


variable "inbound_blue_green_enabled" {
  description = "Enable native Amazon ECS blue/green deployments for the ALB-facing inbound service. Recommended for Production only."
  type        = bool
  default     = false
}

variable "inbound_blue_green_bake_time_minutes" {
  description = "Minutes to keep both inbound service revisions running after production traffic shifts to the green revision."
  type        = number
  default     = 10

  validation {
    condition     = var.inbound_blue_green_bake_time_minutes >= 0 && var.inbound_blue_green_bake_time_minutes <= 1440
    error_message = "inbound_blue_green_bake_time_minutes must be between 0 and 1440."
  }
}

variable "management_port" {
  description = "Management ECS container/target-group port."
  type        = number
  default     = 8090
}

variable "inbound_port" {
  description = "Inbound ECS container/target-group port."
  type        = number
  default     = 8080
}

variable "alb_certificate_arn" {
  description = "Regional ACM certificate ARN for HTTPS on the internal ALB. If null, ALB uses HTTP."
  type        = string
  default     = null
}

variable "alb_ingress_cidrs" {
  description = "Optional direct CIDRs allowed to reach the internal ALB when testing without CloudFront."
  type        = list(string)
  default     = []
}

variable "alb_health_check_path" {
  description = "Inbound service target-group health check path."
  type        = string
  default     = "/health"
}

variable "cloudfront_aliases" {
  description = "CloudFront aliases."
  type        = list(string)
  default     = []
}

variable "cloudfront_acm_certificate_arn" {
  description = "Optional existing ACM certificate ARN in us-east-1 for CloudFront aliases. When null and Route53 DNS is managed by this stack, Terraform can create and validate the certificate automatically."
  type        = string
  default     = null
  nullable    = true
}

variable "route53_zone_id" {
  description = "Optional existing public Route53 hosted-zone ID. When null, Terraform can create a public hosted zone if route53_zone_name is set."
  type        = string
  default     = null
  nullable    = true
}

variable "route53_zone_name" {
  description = "Optional public Route53 hosted-zone name, for example example.com. When deployment.route53=true and route53_zone_id is null, Terraform creates this hosted zone. Leave null when using only the default CloudFront domain."
  type        = string
  default     = null
  nullable    = true
}

# ============================================================
# ECS / ECR
# ============================================================

variable "container_image_tag" {
  description = "Container image tag. In CI/CD, use an immutable commit SHA or release tag."
  type        = string
  default     = "bootstrap"
}

variable "ecs_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Fargate task memory MiB."
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired count by ECS service."
  type = object({
    inbound   = number
    outbound  = number
    processor = number
    management = number
  })
  default = {
    inbound   = 1
    outbound  = 1
    processor = 1
    management = 1
  }
}


variable "service_deployment_enabled" {
  description = "Master switch for ECS services. Set false during the first infrastructure/ECR bootstrap apply; normal CI/CD leaves this true."
  type        = bool
  default     = true
}

variable "meraki_base_url" {
  description = "Cisco Meraki Dashboard API base URL, or an approved mock/DevNet endpoint in lower environments."
  type        = string
  default     = "https://api.meraki.com/api/v1"
}

variable "meraki_poll_paths" {
  description = "Comma-separated Meraki API paths polled by the outbound service."
  type        = string
  default     = "/organizations"
}

variable "meraki_poll_interval_seconds" {
  description = "Outbound polling interval."
  type        = number
  default     = 300
}

variable "webhook_auth_required" {
  description = "Require X-Meraki-Secret on inbound webhook requests."
  type        = bool
  default     = true
}

variable "processor_poll_wait_seconds" {
  description = "SQS long-poll wait used by the processor."
  type        = number
  default     = 20
}

# ============================================================
# DATA / QUEUES / SNS
# ============================================================

variable "data_bucket_force_destroy" {
  description = "Allow Terraform to destroy non-empty data bucket. Keep false outside disposable environments."
  type        = bool
  default     = false
}

variable "log_bucket_force_destroy" {
  description = "Allow Terraform to destroy non-empty log bucket."
  type        = bool
  default     = false
}

variable "s3_data_retention_days" {
  description = "Lifecycle retention for noncurrent/expired data objects where applicable."
  type        = number
  default     = 90
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout for application queues."
  type        = number
  default     = 300
}

variable "sns_https_endpoints" {
  description = "Optional HTTPS endpoints subscribed to the ServiceNow notification SNS topic."
  type        = list(string)
  default     = []
}

# ============================================================
# RDS
# ============================================================

variable "rds_instance_class" {
  description = "PostgreSQL RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16"
}

variable "rds_database_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "occupancy"
}

variable "rds_username" {
  description = "RDS master username. Password is managed by RDS/Secrets Manager."
  type        = string
  default     = "platform_admin"
}

variable "rds_multi_az" {
  description = "Whether the RDS DB instance itself is Multi-AZ. The DB subnet group still spans two AZs."
  type        = bool
  default     = false
}

variable "rds_allocated_storage" {
  description = "Initial RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "RDS storage autoscaling maximum in GiB."
  type        = number
  default     = 100
}

variable "rds_backup_retention_days" {
  description = "RDS automated backup retention."
  type        = number
  default     = 7
}

# ============================================================
# KMS / WAF
# ============================================================

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days."
  type        = number
  default     = 30
}

variable "waf_rate_limit" {
  description = "CloudFront WAF per-IP rate limit over the provider/WAF evaluation window."
  type        = number
  default     = 2000
}

```

## `terraform/versions.tf`
```
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

}

```

## `terraform/vpc_endpoints.tf`
```
resource "aws_vpc_endpoint" "s3" {
  count = var.deployment.vpc_endpoints.s3 ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for rt in aws_route_table.app : rt.id],
    [for rt in aws_route_table.processor : rt.id]
  )

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}

locals {
  interface_endpoint_services = {
    ecr_api = {
      enabled = var.deployment.vpc_endpoints.ecr
      service = "ecr.api"
    }
    ecr_dkr = {
      enabled = var.deployment.vpc_endpoints.ecr
      service = "ecr.dkr"
    }
    sqs = {
      enabled = var.deployment.vpc_endpoints.sqs
      service = "sqs"
    }
    kms = {
      enabled = var.deployment.vpc_endpoints.kms
      service = "kms"
    }
    logs = {
      enabled = var.deployment.vpc_endpoints.logs
      service = "logs"
    }
    sts = {
      enabled = var.deployment.vpc_endpoints.sts
      service = "sts"
    }
    secretsmanager = {
      enabled = var.deployment.vpc_endpoints.secrets_manager
      service = "secretsmanager"
    }
  }

  enabled_interface_endpoint_services = {
    for name, config in local.interface_endpoint_services : name => config if config.enabled
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.enabled_interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for az in local.active_azs : aws_subnet.vpce[az].id]
  security_group_ids  = [aws_security_group.vpce[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-vpce-${replace(each.key, "_", "-")}"
  }
}

```

## `terraform/waf.tf`
```
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  count    = var.deployment.waf ? 1 : 0

  name  = "${local.name_prefix}-cloudfront-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "PerIpRateLimit"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront-waf"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider = aws.us_east_1
  count    = var.deployment.waf && var.deployment.log_bucket ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.cloudfront[0].arn
  log_destination_configs = [aws_s3_bucket.logs[0].arn]
}

```

## `tests/integration/requirements.txt`
```
boto3>=1.35,<2
httpx>=0.28,<1
psycopg[binary]>=3.3,<4
pytest>=8,<10

```

## `tests/integration/test_end_to_end.py`
```
from __future__ import annotations

import json
import os
import time

import boto3
import httpx
import psycopg
from botocore.config import Config

AWS_ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localhost:4566")
REGION = os.getenv("AWS_REGION", "eu-west-2")
INBOUND_URL = os.getenv("INBOUND_URL", "http://localhost:8080")


def client(service):
    kwargs = {"endpoint_url": AWS_ENDPOINT, "region_name": REGION,
              "aws_access_key_id": "test", "aws_secret_access_key": "test"}
    if service == "s3":
        kwargs["config"] = Config(s3={"addressing_style": "path"})
    return boto3.client(service, **kwargs)


def wait_until(predicate, timeout=30, interval=1):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            value = predicate()
            if value:
                return value
            last = value
        except Exception as exc:
            last = exc
        time.sleep(interval)
    raise AssertionError(f"condition not met in {timeout}s; last={last!r}")


def test_inbound_to_processor_to_database_and_datalake():
    payload = {
        "event_id": "integration-webhook-1",
        "organizationId": "org-1",
        "type": "occupancy",
        "deviceSerial": "Q2XX-INTEGRATION",
        "clientMac": "00:11:22:33:44:55",
        "value": 1,
    }
    response = httpx.post(
        f"{INBOUND_URL}/api/v1/meraki/webhook",
        json=payload,
        headers={"X-Meraki-Secret": "integration-webhook-secret"},
        timeout=10,
    )
    assert response.status_code == 202, response.text

    s3 = client("s3")
    key = response.json()["s3_key"]
    obj = s3.get_object(Bucket="integration-data", Key=key)
    assert json.loads(obj["Body"].read())["event_id"] == "integration-webhook-1"

    def db_row():
        with psycopg.connect("host=localhost port=5432 dbname=occupancy user=platform_admin password=integration-password") as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT event_id, occupancy_value FROM occupancy_events WHERE event_id=%s", ("integration-webhook-1",))
                return cur.fetchone()

    row = wait_until(db_row)
    assert row[0] == "integration-webhook-1"
    assert row[1] == 1.0

    sqs = client("sqs")
    queue_url = sqs.get_queue_url(QueueName="integration-datalake")["QueueUrl"]

    def dl_message():
        result = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=1)
        for item in result.get("Messages", []):
            body = json.loads(item["Body"])
            if body.get("event_id") == "integration-webhook-1":
                return body
        return None

    delivered = wait_until(dl_message)
    assert delivered["tenant_id"] == "org-1"


def test_outbound_meraki_poll_reaches_processing_pipeline():
    def db_row():
        with psycopg.connect("host=localhost port=5432 dbname=occupancy user=platform_admin password=integration-password") as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT event_id, source FROM occupancy_events WHERE source='outbound' ORDER BY processed_at DESC LIMIT 1")
                return cur.fetchone()

    row = wait_until(db_row, timeout=40)
    assert row[1] == "outbound"

```

## `tests/performance/README.md`
```
# Performance Tests

Run performance/load testing against DEV or UAT as appropriate for the lab. UAT is the primary release-qualification environment before PROD. Production should default to non-destructive smoke/health validation unless an approved production load-test procedure exists.

Use the deployed CloudFront URL as the target for AWS-environment testing. Do not treat local Docker Compose as an additional AWS environment.

```

## `tests/performance/locustfile.py`
```
from __future__ import annotations

import os
import uuid

from locust import HttpUser, between, events, task

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "integration-webhook-secret")
P95_LIMIT_MS = float(os.getenv("PERF_P95_LIMIT_MS", "1500"))
MIN_RPS = float(os.getenv("PERF_MIN_RPS", "1"))


class InboundTelemetryUser(HttpUser):
    wait_time = between(0.05, 0.2)

    @task
    def publish_occupancy(self):
        event_id = str(uuid.uuid4())
        payload = {
            "event_id": event_id,
            "organizationId": "perf-org",
            "type": "occupancy",
            "deviceSerial": f"Q2XX-{event_id[:8]}",
            "clientMac": "00:11:22:33:44:55",
            "value": 1,
        }
        with self.client.post(
            "/api/v1/meraki/webhook",
            json=payload,
            headers={"X-Meraki-Secret": WEBHOOK_SECRET},
            name="POST /api/v1/meraki/webhook",
            catch_response=True,
        ) as response:
            if response.status_code != 202:
                response.failure(f"expected 202, got {response.status_code}: {response.text}")


@events.quitting.add_listener
def enforce_nfr(environment, **_kwargs):
    total = environment.stats.total
    p95 = total.get_response_time_percentile(0.95) or 0
    rps = total.total_rps or 0
    if total.fail_ratio > float(os.getenv("PERF_FAIL_RATIO", "0.01")):
        environment.process_exit_code = 20
    elif p95 > P95_LIMIT_MS:
        environment.process_exit_code = 21
    elif rps < MIN_RPS:
        environment.process_exit_code = 22

```

## `tests/performance/requirements.txt`
```
locust>=2.46,<3

```

## `tests/performance/spatial_locustfile.py`
```
import random
from locust import HttpUser, between, task


class SpatialPresenceUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task(8)
    def observation(self):
        self.client.post("/api/observe", json={
            "device_id": f"load-{random.randint(1,1000)}",
            "x": random.uniform(5,95),
            "y": random.uniform(5,95),
            "confidence": 0.85,
        })

    @task(2)
    def dashboard(self):
        self.client.get("/api/occupancy")

```
