variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "occupancy-platform"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "state_kms_key_arn" {
  description = "ARN of the existing KMS key used for Terraform remote state."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket used by bootstrap.tfstate and all three logical environment states."
  type        = string
}

variable "existing_github_oidc_provider_arn" {
  description = "If this AWS account already has the GitHub Actions OIDC provider, supply its ARN; otherwise leave null and this stack creates it."
  type        = string
  default     = null
  nullable    = true
}

variable "github_oidc_subjects" {
  description = "Exact GitHub OIDC sub claims used by plan/apply roles for each logical environment."
  type = object({
    dev_plan   = string
    dev_apply  = string
    uat_plan   = string
    uat_apply  = string
    prod_plan  = string
    prod_apply = string
  })
}
