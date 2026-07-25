resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    var.github_oidc_audience
  ]

  tags = merge(var.additional_tags, {
    Name = "token.actions.githubusercontent.com"
  })
}

data "aws_iam_policy_document" "github_deploy_assume_role" {
  statement {
    sid     = "GitHubOidcAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = [var.github_oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/${var.github_protected_branch}"
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${var.project_name}-${var.environment}-github-deploy"
  description          = "Temporary GitHub OIDC deployment access for the static website"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume_role.json
  max_session_duration = 3600

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-${var.environment}-github-deploy"
  })
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid    = "ListDeploymentBucket"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    sid    = "ManageDeploymentObjects"
    effect = "Allow"

    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    sid    = "InvalidateDistribution"
    effect = "Allow"

    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation"
    ]

    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.project_name}-${var.environment}-deployment"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

