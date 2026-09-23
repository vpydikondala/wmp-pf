# Workplace Management Application

Use this repository **after** `workplace-management-infrastructure` has been applied.

## Services

- `inbound`: Meraki Scan Ingress; APP subnets; behind internal ALB; writes raw S3 and Processing SQS.
- `management`: Management UI/API; APP subnets; behind internal ALB; RDS CRUD; no NAT.
- `processor`: long-running SQS worker; Processor subnets; consumes Processing SQS, enriches/writes RDS/S3, publishes Data Lake SQS.
- `dashboard_sync`: scheduled ECS RunTask; Processor subnets; the workload requiring NAT/IGW egress to the public Meraki Dashboard API.

Processing SQS and Data Lake SQS are separate queues. They are infrastructure resources and are
passed to containers through environment configuration. The application repository does not create them.

## Build/deploy order

1. Infrastructure team applies the infrastructure repo for the target environment.
2. Developer runs unit/integration tests.
3. Build the four container images.
4. Push immutable image tags to the pre-created ECR repositories.
5. Application Terraform reads infrastructure remote-state outputs.
6. Application Terraform creates/updates ECS task definitions and services and schedules Dashboard Sync.
7. Promote the same tested image tag/digest DEV → UAT → PROD; do not rebuild per environment.

For Windows:
`./scripts/build-push-images.ps1 dev <git-sha>`
then
`./scripts/deploy.ps1 dev <git-sha>`

PROD inbound uses ECS native blue/green; Management and Processor use controlled rolling deployments.
