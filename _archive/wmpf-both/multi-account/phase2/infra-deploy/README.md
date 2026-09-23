# Workplace Management Infrastructure

Deploy this repository **first**. It provisions the durable AWS platform for DEV, UAT and PROD.

## Ownership boundary

This repository owns VPC/subnets/routes, IGW/NAT, VPC endpoints, CloudFront/WAF/internal ALB,
target groups/listeners, ECS cluster, ECR repositories, IAM roles, security groups, CloudWatch
log groups, S3, two SQS queues + DLQs, RDS PostgreSQL, KMS/Secrets Manager and optional DNS.

It deliberately does **not** create ECS task definitions or ECS services. Those are released by
the separate `workplace-management-application` repository after container images are built.

## Network model

* APP: Scan Ingress + Management; no 0.0.0.0/0 route.
* Interface VPC endpoint ENIs: deployed in APP subnets.
* S3: gateway endpoint.
* Processor: Telemetry Processor + Dashboard Sync placement.
* Processor route table: NAT default route because Dashboard Sync requires Meraki Dashboard API egress.
* NAT public subnets: default route to IGW.
* CloudFront/VPC Origin inbound and NAT/IGW outbound are independent paths.
* Processing SQS and Data Lake SQS are separate regional queues and share the SQS interface endpoint.

## Deployment order

1. Bootstrap Terraform state/OIDC roles as required.
2. `terraform init -reconfigure -backend-config=backends/<env>.hcl -backend-config="kms_key_id=..."`
3. `terraform validate`
4. `terraform plan -var-file=environments/<env>.tfvars`
5. `terraform apply -var-file=environments/<env>.tfvars`
6. Export `terraform output -json` for the application team.

State keys remain `dev/terraform.tfstate`, `uat/terraform.tfstate`, `prod/terraform.tfstate`.
