# Secret containers only. Secret values are populated/rotated outside Terraform
# so credentials do not enter tfvars or Terraform state.
resource "aws_secretsmanager_secret" "meraki" {
  count = var.deployment.secrets_manager ? 1 : 0

  name                    = "${local.name_prefix}/meraki/oauth"
  description             = "Cisco Meraki OAuth/API credentials for ${local.name_prefix}"
  kms_key_id              = var.deployment.kms ? aws_kms_key.application[0].arn : null
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.name_prefix}-meraki-oauth"
  }
}
