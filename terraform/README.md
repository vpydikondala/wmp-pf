# Occupancy Platform Terraform

This replacement baseline implements the reviewed HLD model:

- Cisco Meraki ingress: CloudFront + WAF -> CloudFront VPC Origin -> internal ALB -> inbound ECS.
- Application services: inbound and processor on ECS Fargate. The historical outbound service is disabled by default.
- Meraki API outbound access: Processor subnets -> NAT Gateway/EIP. APP/inbound subnets have no default Internet route.
- Data: S3 data bucket, processing SQS/DLQ, RDS PostgreSQL, data-lake delivery SQS/DLQ.
- Notifications: SNS topic for the approved ServiceNow integration path.
- Logs: CloudWatch log groups for ECS plus a central S3 log bucket. ALB and WAF logging are wired to the log bucket. ECS-to-S3 log archival should be implemented with the enterprise-standard delivery mechanism (for example Firehose/subscription) once that mechanism is approved.
- Security: separate ECS security groups and IAM task roles, private endpoints, KMS option, RDS-managed Secrets Manager master password.

## CIDR model

Every environment receives the same parent /16 input. Terraform derives the first four /21s:

- dev: index 0 -> 10.0.0.0/21
- reserved: index 1 -> 10.0.8.0/21
- uat: index 2 -> 10.0.16.0/21
- prod: index 3 -> 10.0.24.0/21

Each /21 is divided into eight /24 allocation blocks:

0. ALB
1. APP
2. VPCE
3. RDS
4. NAT
5. PROCESSOR (NAT-routed)
6-7. Reserved

Each active functional /24 is split into /25s by AZ.

## Validate a deployment profile

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev.tfvars
```

Before enabling ECS services, push immutable images to the generated inbound/processor ECR repositories and set `container_image_tag` to the immutable tag/SHA.

For CI/CD, do not set an AWS provider profile. Use GitHub OIDC to assume environment-specific AWS roles and initialize a remote encrypted Terraform backend.


## Route53 and CloudFront custom-domain behavior

Route53 is intentionally safe to enable before DNS values are known.

- `deployment.route53 = false`: no Route53 resources are created.
- `deployment.route53 = true` with both `route53_zone_id = null` and `route53_zone_name = null`: no hosted zone or DNS records are created; CloudFront continues to work on its generated `*.cloudfront.net` hostname when aliases are empty.
- Set `route53_zone_id` to use an existing public hosted zone.
- Or set `route53_zone_name` and leave `route53_zone_id = null` to create a public hosted zone in Terraform. Creating a hosted zone does not register the domain; delegate the domain/subdomain to the `route53_created_name_servers` output.
- If `cloudfront_aliases` is non-empty and `cloudfront_acm_certificate_arn` is null, Terraform automatically creates the required ACM certificate in `us-east-1` and DNS-validates it through the effective Route53 zone.
- If DNS is managed outside Route53, supply an existing `cloudfront_acm_certificate_arn` and keep `deployment.route53 = false`.
