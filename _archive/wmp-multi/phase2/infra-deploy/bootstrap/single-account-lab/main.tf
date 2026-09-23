data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  environments = toset(["dev", "uat", "prod"])

  state_keys = {
    dev  = "dev/terraform.tfstate"
    uat  = "uat/terraform.tfstate"
    prod = "prod/terraform.tfstate"
  }

  plan_subjects = {
    dev  = var.github_oidc_subjects.dev_plan
    uat  = var.github_oidc_subjects.uat_plan
    prod = var.github_oidc_subjects.prod_plan
  }

  apply_subjects = {
    dev  = var.github_oidc_subjects.dev_apply
    uat  = var.github_oidc_subjects.uat_apply
    prod = var.github_oidc_subjects.prod_apply
  }

  created_github_oidc_provider_arn = try(aws_iam_openid_connect_provider.github[0].arn, null)
  github_oidc_provider_arn         = coalesce(var.existing_github_oidc_provider_arn, local.created_github_oidc_provider_arn)
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_github_oidc_provider_arn == null ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.plan_subjects[each.key]]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.apply_subjects[each.key]]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  for_each           = local.environments
  name               = "${var.project_name}-${each.key}-github-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust[each.key].json
}

resource "aws_iam_role" "github_apply" {
  for_each           = local.environments
  name               = "${var.project_name}-${each.key}-github-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_trust[each.key].json
}

data "aws_iam_policy_document" "state_access" {
  for_each = local.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid     = "ReadWriteEnvironmentState"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}/${local.state_keys[each.key]}"
    ]
  }

  statement {
    sid     = "ManageEnvironmentStateLock"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}/${local.state_keys[each.key]}.tflock"
    ]
  }

  statement {
    sid = "UseStateKmsKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [var.state_kms_key_arn]
  }
}

resource "aws_iam_policy" "state_access" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-terraform-state-access"
  policy   = data.aws_iam_policy_document.state_access[each.key].json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  for_each   = local.environments
  role       = aws_iam_role.github_plan[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  for_each   = local.environments
  role       = aws_iam_role.github_plan[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "terraform_iam_management" {
  for_each = local.environments

  statement {
    sid = "ManageApplicationRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"
    ]
  }

  statement {
    sid     = "PassApplicationRolesToEcs"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-*"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateRequiredServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "terraform_iam_management" {
  for_each = local.environments
  name     = "${var.project_name}-${each.key}-terraform-iam-management"
  policy   = data.aws_iam_policy_document.terraform_iam_management[each.key].json
}

resource "aws_iam_role_policy_attachment" "apply_iam" {
  for_each   = local.environments
  role       = aws_iam_role.github_apply[each.key].name
  policy_arn = aws_iam_policy.terraform_iam_management[each.key].arn
}
