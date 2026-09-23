\
param([Parameter(Mandatory=$true)][ValidateSet("dev","uat","prod")][string]$Environment,
      [Parameter(Mandatory=$true)][string]$Tag)
$ErrorActionPreference = "Stop"
Push-Location deploy
terraform init -reconfigure `
  -backend-config="backends/$Environment.hcl" `
  -backend-config="kms_key_id=$env:TF_STATE_KMS_KEY_ARN"
terraform validate
terraform plan `
  -var-file="environments/$Environment.tfvars" `
  -var="container_image_tag=$Tag" `
  -var="infra_state_kms_key_arn=$env:TF_STATE_KMS_KEY_ARN" `
  -out=tfplan
terraform apply tfplan
Pop-Location
