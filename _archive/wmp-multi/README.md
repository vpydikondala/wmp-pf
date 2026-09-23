# existing-repo — Phase 1 + Phase 2

This is the final monorepo layout for the Lambda-to-ECS Phase-2 migration.

## Structure

- `legacy/` — existing Phase-1 Lambda application/infrastructure and the shared GitHub workflow location.
- `phase2/infra-deploy/` — Phase-2 durable AWS infrastructure.
- `phase2/app-deploy/` — Phase-2 container application source, tests and application deployment Terraform.

GitHub remains the source of truth for desired configuration and release history. Terraform state
is not committed to Git. This `multi-account` variant uses one state bucket/KMS boundary per AWS environment account, with separate infrastructure and application state objects.

## Deployment order

1. Preserve and verify the existing legacy solution.
2. Bootstrap/verify Terraform backend and GitHub OIDC roles.
3. Run `phase2-infra-pr.yml`.
4. Deploy `phase2/infra-deploy` for DEV, then UAT, then PROD as approved.
5. Run `phase2-app-ci.yml`.
6. Build, scan, generate SBOMs and push immutable application images.
7. Deploy `phase2/app-deploy` onto the existing Phase-2 infrastructure.
8. Run smoke/integration/functional/security/NFR tests at the appropriate environment.
9. Cut over Lambda consumers/pollers in a controlled sequence.
10. PROD Scan Ingress uses ECS native blue/green.

The workflow files intentionally live under `legacy/.github/workflows/` in this package, as requested.
**GitHub Actions only auto-discovers workflow files from the repository-root `.github/workflows/`
directory.** Therefore, in a real GitHub repository either keep a root `.github/workflows/` directory,
or copy/symlink-equivalent the supplied Phase-2 workflow YAML files there. GitHub does not execute
workflows solely because they are under `legacy/.github/workflows/`.
