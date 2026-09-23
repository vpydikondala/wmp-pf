# State layout — multiple accounts

DEV, UAT and PROD each use their own AWS account and state bucket/KMS key.

Inside each environment account:

```text
legacy/...                         # preserve any existing Phase-1 key
phase2/infrastructure/terraform.tfstate
phase2/application/terraform.tfstate
```

The GitHub `dev`, `uat` and `prod` Environments select different account IDs, state buckets,
KMS keys and OIDC role ARNs. Application deployment reads the infrastructure state in the
same target account and writes only the application state.
