# Workplace Management / Occupancy Platform

Single-account AWS lab baseline with exactly three durable environments: **DEV, UAT and PROD**. Production uses native ECS blue/green for the ALB-facing inbound/API service.

Start with `README-START-HERE.md`, then follow `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` from the first administrator bootstrap through local foundation deployment and normal GitHub OIDC deployment.

Core controls: one shared S3 Terraform-state bucket, one shared state KMS key, one GitHub OIDC provider, separate DEV/UAT/PROD plan/apply roles, separate state keys, environment tags/names, APP/no-NAT networking, Processor-only NAT egress, and protected PROD blue/green deployment.

## Management service (RDS-backed)

The former local `spatial` application is integrated as `services/management`. Spatial configuration is a Management domain, not a separate ECS service. Management owns CRUD for buildings, floors, zones, access points and desks in PostgreSQL RDS. It runs in APP private subnets behind the existing internal ALB (`/management/*` and `/api/v1/management/*`) and has no NAT route. SQL migrations under `services/management/migrations` provide an out-of-the-box schema on first startup. See `docs/MANAGEMENT_DEMO.md`.
