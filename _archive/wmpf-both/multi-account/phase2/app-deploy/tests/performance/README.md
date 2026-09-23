# Performance Tests

Run performance/load testing against DEV or UAT as appropriate for the lab. UAT is the primary release-qualification environment before PROD. Production should default to non-destructive smoke/health validation unless an approved production load-test procedure exists.

Use the deployed CloudFront URL as the target for AWS-environment testing. Do not treat local Docker Compose as an additional AWS environment.
