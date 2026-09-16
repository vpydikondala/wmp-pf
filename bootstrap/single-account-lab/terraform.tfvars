aws_region   = "eu-west-2"
project_name = "occupancy-platform"
owner        = "platform-team"

# EXISTING S3 bucket
state_bucket_name = "wmp-tfstate"

# EXISTING KMS key
state_kms_key_arn = "arn:aws:kms:eu-west-2:414860507448:key/6d4362ed-54f0-438b-8dfa-56d460019348"

# Leave null if GitHub OIDC does not already exist.
existing_github_oidc_provider_arn = null

github_oidc_subjects = {
  dev_plan  = "repo:vpydikondala/wmp-pf:environment:dev"
  dev_apply = "repo:vpydikondala/wmp-pf:environment:dev"

  uat_plan   = "repo:vpydikondala/wmp-pf:environment:uat"
  uat_apply  = "repo:vpydikondala/wmp-pf:environment:uat"
  prod_plan  = "repo:vpydikondala/wmp-pf:environment:prod"
  prod_apply = "repo:vpydikondala/wmp-pf:environment:prod"
}