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
