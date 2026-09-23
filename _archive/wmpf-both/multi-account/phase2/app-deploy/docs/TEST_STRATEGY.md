# Test strategy

## Pull request gates
Unit tests, linting, SAST (Bandit), dependency/SCA audit (pip-audit), secret scanning
(Gitleaks), deployment-IaC scanning (Checkov/Trivy), Docker build, image vulnerability
scan (Trivy) and SBOM generation.

## DEV
Automated smoke and integration tests. Verify Scan Ingress -> S3 -> Processing SQS ->
Processor -> RDS/S3 -> Data Lake SQS. Verify Management CRUD and private AWS service access.

## UAT
Repeat DEV tests plus contract, functional, performance, resilience and negative-security tests.
Test queue backlog/recovery, Data Lake consumer outage, Processor restart/idempotency, Meraki
API 429/backoff, RDS failover/recovery assumptions and PROD-like blue/green before production.

## PROD
Deploy approved immutable images only. Run non-destructive smoke checks, ALB/ECS health,
CloudWatch alarms and blue/green bake/rollback controls. Do not run destructive integration/NFR tests.

## Scheduled
Dependency/image rescans, backup restore tests, RDS recovery exercise, IAM/access review,
secret rotation exercise and disaster-recovery runbook rehearsal.
