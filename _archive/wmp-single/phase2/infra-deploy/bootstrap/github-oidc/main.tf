variable "github_org" { type = string }
variable "infra_repo" { type = string }
variable "app_repo" { type = string }
variable "environments" { type = set(string) default = ["dev","uat","prod"] }

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  roles = merge(
    { for x in setproduct(var.environments, ["plan","apply"]) :
      "infra-${x[0]}-${x[1]}" => { repo=var.infra_repo, env=x[0], kind="infra-${x[1]}" } },
    { for x in setproduct(var.environments, ["build","deploy","test"]) :
      "app-${x[0]}-${x[1]}" => { repo=var.app_repo, env=x[0], kind="app-${x[1]}" } }
  )
}
resource "aws_iam_role" "github" {
  for_each = local.roles
  name = "wmp-${each.key}"
  assume_role_policy = jsonencode({
    Version="2012-10-17"
    Statement=[{
      Effect="Allow", Action="sts:AssumeRoleWithWebIdentity",
      Principal={Federated=data.aws_iam_openid_connect_provider.github.arn},
      Condition={
        StringEquals={
          "token.actions.githubusercontent.com:aud"="sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub"="repo:${var.github_org}/${each.value.repo}:environment:${each.value.env}"
        }
      }
    }]
  })
}
# Attach organisation-approved least-privilege policies to these roles.
# This bootstrap intentionally creates trust roles; permission policies must be reviewed against
# the exact AWS resources/account IDs before production enablement.
output "role_arns" { value = { for k,r in aws_iam_role.github : k => r.arn } }
