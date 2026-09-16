# ECS Blue/Green Deployment — PROD

The repository has DEV, UAT and PROD. UAT is the release-qualification environment. Only PROD enables native ECS blue/green for the ALB-facing inbound/API service.

Production uses one ECS service, one cluster, one internal ALB and two reusable target groups. During a deployment ECS creates a replacement service revision, registers it in the alternate target group, waits for target health, shifts production traffic, retains the previous revision for the configured bake period, then completes and terminates the old revision if healthy. Configured deployment alarms can cause rollback.

TG-A is not permanently Blue and TG-B is not permanently Green; the roles alternate across releases.

Processor is not deployed with ALB blue/green. Polling ownership must be active/passive so two Processor revisions do not simultaneously poll Meraki.

See `IAM_BOOTSTRAP_AND_DEPLOYMENT_RUNBOOK.md` for the complete bootstrap/IAM/GitHub sequence.
