# Network Segmentation — Final DEV/UAT/PROD Model

All three environments are in one AWS account but have independent VPCs and state.

| Environment | VPC | ALB /24 | APP /24 | VPCE /24 | RDS /24 | NAT /24 | Processor /24 | Reserved |
|---|---|---|---|---|---|---|---|---|
| DEV | 10.0.0.0/21 | 10.0.0.0/24 | 10.0.1.0/24 | 10.0.2.0/24 | 10.0.3.0/24 | 10.0.4.0/24 | 10.0.5.0/24 | 10.0.6.0/23 |
| UAT | 10.0.16.0/21 | 10.0.16.0/24 | 10.0.17.0/24 | 10.0.18.0/24 | 10.0.19.0/24 | 10.0.20.0/24 | 10.0.21.0/24 | 10.0.22.0/23 |
| PROD | 10.0.24.0/21 | 10.0.24.0/24 | 10.0.25.0/24 | 10.0.26.0/24 | 10.0.27.0/24 | 10.0.28.0/24 | 10.0.29.0/24 | 10.0.30.0/23 |

`10.0.8.0/21` is reserved and is not deployed as a durable environment.

Each deployed functional `/24` is split into two `/25` AWS subnets across the active AZs. APP has no `0.0.0.0/0` NAT route. Processor has the NAT-routed default route and owns Internet-initiated Meraki communication. The historical standalone outbound service is disabled by default.

Validate with only:

```bash
terraform plan -var-file=environments/dev.tfvars
terraform plan -var-file=environments/uat.tfvars
terraform plan -var-file=environments/prod.tfvars
```
