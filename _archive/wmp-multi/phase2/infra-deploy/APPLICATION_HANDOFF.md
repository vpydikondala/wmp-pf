# Infrastructure → Application handoff

The application pipeline reads the infrastructure remote state. Required outputs include:

- ECS cluster name/ARN
- APP and Processor subnet IDs
- per-service security group IDs
- ECS execution/task role ARNs
- ECR repository URLs
- inbound primary/alternate and Management target group ARNs
- Processing SQS and Data Lake SQS URLs
- S3 data bucket
- RDS endpoint/database and RDS managed secret ARN

No static AWS credentials are passed between repositories. CI/CD uses GitHub OIDC roles.
The application repository must not create or modify VPC, route tables, NAT, IGW, VPC endpoints,
RDS, S3, SQS, KMS, CloudFront, WAF or ALB infrastructure.
