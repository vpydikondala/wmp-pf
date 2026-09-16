# Application and Testing

The durable environments are DEV, UAT and PROD. DEV is the first integration environment; UAT is the release-qualification environment; PROD is the protected production-style lab environment.

The ALB-facing inbound/API service runs in APP subnets without a NAT/default Internet route. Processor runs in the Processor subnet tier and is the only ECS workload intended to initiate public Internet communication to Meraki through NAT. The historical standalone `outbound` service is disabled by default in all three environment tfvars.

Recommended validation flow is: local/unit/container tests -> DEV integration and smoke tests -> UAT functional/contract/performance validation -> PROD deployment health/alarm validation. Production inbound/API releases use native ECS blue/green; Processor revision changes require active/passive polling ownership to avoid duplicate Meraki polling.

Local Docker Compose files are development/test utilities and do not create an additional AWS environment.
