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
