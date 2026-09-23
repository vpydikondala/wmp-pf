# Legacy Phase 1 application and infrastructure

This folder represents the existing Lambda-based implementation already present in the real
`existing-repo`. Do not replace your current legacy source with this placeholder.

When adopting this package, merge `phase2/` and the Phase-2 workflow files from
`legacy/.github/workflows/` into the existing repository while preserving the real legacy code,
workflows and Terraform state unchanged.

Phase 1 and Phase 2 may coexist during migration, but do not leave the Lambda Processor and ECS
Processor consuming the same Processing SQS workload concurrently, and do not run the legacy
Dashboard poller concurrently with Phase-2 Dashboard Sync.
