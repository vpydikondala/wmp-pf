# Security
Do not commit credentials, Meraki tokens, database credentials or AWS keys.
Runtime secrets are referenced from AWS Secrets Manager. Production releases require protected-branch
review, successful security gates and GitHub Environment approval.
