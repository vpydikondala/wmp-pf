# Terraform state ownership

Infrastructure and application deployment use **separate state files** because they have different
ownership, permissions, blast radius and release cadence.

The application state never manages VPC/NAT/RDS/SQS/ALB foundation resources. It reads the
infrastructure state as read-only data through `terraform_remote_state`.

Git is the source of truth for desired configuration; S3 state is the source of truth for Terraform's
resource bindings. State must never be committed to Git.

Use S3 backend encryption, versioning and native S3 lock files (`use_lockfile=true`). Restrict IAM
permissions by state object prefix so application roles cannot write infrastructure state.
