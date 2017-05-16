variable "aws_region" {}
provider "aws" {
  region = "${var.aws_region}"
}

data "aws_iam_policy_document" "containter_admin" {
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecr:*"
        ],
        "Resource": "*"
      }
    ]
  }
}

data "aws_iam_policy_document" "container_readonly" {
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage"
        ],
        "Resource": "*"
      }
    ]
  }
}

resource "aws_ecr_repository" "randy" {
  name = "randy"
}

output "aws_ecr_repository_randy_url" {
	value = "${aws_ecr_repository.randy.repository_url}"
}
