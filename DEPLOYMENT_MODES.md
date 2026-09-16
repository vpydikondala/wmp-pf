# Deployment Modes

This repository supports one target lab topology: **one AWS account with DEV, UAT and PROD**. There is no Test/Preprod/four-account deployment mode in this baseline.

## Local administrator mode

Used for the one-time bootstrap and first environment foundation creation. Authenticate with an administrator/SSO profile, run `scripts/bootstrap-single-account-lab.sh`, migrate bootstrap state, then use `scripts/tf-local-single-account.sh` for controlled local plan/apply.

## Remote GitHub OIDC mode

Used for normal deployments. GitHub Environments `dev`, `uat`, and `prod` assume separate plan/apply roles through the single AWS GitHub OIDC provider. No static AWS keys are stored in GitHub.

## Production deployment mode

Only PROD enables native ECS blue/green for the ALB-facing inbound/API service. Processor uses controlled active/passive revision ownership rather than ALB traffic switching.
