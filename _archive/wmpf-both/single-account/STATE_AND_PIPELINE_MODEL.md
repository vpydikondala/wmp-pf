# State layout — single account

Existing bucket: `wmp-tfstate`

```text
legacy/...                                      # keep current Phase-1 keys unchanged

phase2/infrastructure/dev/terraform.tfstate
phase2/infrastructure/uat/terraform.tfstate
phase2/infrastructure/prod/terraform.tfstate

phase2/application/dev/terraform.tfstate
phase2/application/uat/terraform.tfstate
phase2/application/prod/terraform.tfstate
```

Infrastructure and application pipelines use different IAM roles. Application roles get
read-only access to the matching infrastructure state object and read/write access only to
the matching application state object.
