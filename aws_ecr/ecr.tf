#variable "aws_region" {}
provider "aws" {
  region = "us-west-1"
}

provider "aws" {
  alias = "us-west-1"
  region = "us-west-1"
}

provider "aws" {
  alias = "us-east-1"
  region = "us-east-1"
}

resource "aws_ecr_repository" "ruby_app-uswest1" {
  provider = "aws.us-west-1"
  name = "ruby_app"
}

resource "aws_ecr_repository" "ruby_app-useast1" {
  provider = "aws.us-east-1"
  name = "ruby_app"
}

output "aws_ecr_repository_ruby_app-useast1_url" {
	value = "${aws_ecr_repository.ruby_app-useast1.repository_url}"
}

output "aws_ecr_repository_ruby_app-uswest1_url" {
	value = "${aws_ecr_repository.ruby_app-uswest1.repository_url}"
}
