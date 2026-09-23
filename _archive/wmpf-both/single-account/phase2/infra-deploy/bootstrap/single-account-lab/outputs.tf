output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "state_bucket_name" {
  value = var.state_bucket_name
}

output "state_kms_key_arn" {
  value = var.state_kms_key_arn
}

output "github_oidc_provider_arn" {
  value = local.github_oidc_provider_arn
}

output "github_plan_role_arns" {
  value = { for env, role in aws_iam_role.github_plan : env => role.arn }
}

output "github_apply_role_arns" {
  value = { for env, role in aws_iam_role.github_apply : env => role.arn }
}

output "state_keys" {
  value = local.state_keys
}
