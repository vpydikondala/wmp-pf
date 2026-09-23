# Multi-account runbook

Use one AWS account per environment: DEV account, UAT account and PROD account.

Each target account contains:
- its own Terraform state bucket/KMS key;
- GitHub OIDC provider;
- environment-scoped infrastructure and application roles;
- the complete environment stack.

Recommended state keys in each account:
- `bootstrap/terraform.tfstate`
- `infrastructure/terraform.tfstate`
- `application/terraform.tfstate`

The GitHub `dev`, `uat` and `prod` Environments contain different account IDs, state buckets,
KMS keys and role ARNs. The same workflow code is reused; GitHub Environment variables select
the target account.

Deploy infrastructure first in each account. Application deployment reads the infrastructure state
from the same target account and writes only `application/terraform.tfstate`.

For centralised state in a tooling account, add explicit cross-account read/write roles and bucket/KMS
policies. The supplied baseline intentionally uses per-account state to minimise cross-account trust.
