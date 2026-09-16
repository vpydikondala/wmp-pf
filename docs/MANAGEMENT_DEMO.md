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
