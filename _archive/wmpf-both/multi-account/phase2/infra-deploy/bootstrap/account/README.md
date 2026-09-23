# Per-account bootstrap

Run this bootstrap once in DEV, UAT and PROD accounts using an authorised administrator.

1. Create/reference the account's state S3 bucket and KMS key.
2. Enable S3 versioning and block public access.
3. Create/reference the GitHub OIDC provider.
4. Create repo/environment-scoped plan/apply/build/deploy/test roles.
5. Put the resulting ARNs into the corresponding GitHub Environment variables.

Do not store AWS access keys in GitHub.
