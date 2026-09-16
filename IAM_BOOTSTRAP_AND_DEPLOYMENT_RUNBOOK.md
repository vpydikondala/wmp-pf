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
