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
