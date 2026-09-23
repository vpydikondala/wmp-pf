# Management service

RDS PostgreSQL-backed Workplace Management service. It owns configuration/master data for buildings, floors, zones, access points and desks. It runs in APP private subnets behind the existing internal ALB and has no NAT/default Internet route.

On startup it retrieves the RDS-managed master credential from Secrets Manager and applies versioned SQL files in `migrations/`. This is an out-of-the-box lab implementation. For governed production, use a dedicated migration identity/job and a lower-privilege runtime database user rather than the RDS master credential.

UI: `/management/`
API: `/api/v1/management/*`
Health: `/health` (ALB target-group health check)
