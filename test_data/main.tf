variable "vpc_region" {}
variable "tfstate_bucket" {}

provider "aws" {
    region = "${var.vpc_region}"
}

data "terraform_remote_state" "vpc" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/vpc/terraform.tfstate"
	}
}

data "aws_subnet_ids" "subnets" {
  vpc_id = "vpc-cd788eb4"
}

data "aws_subnet_ids" "remote_subnets" {
  vpc_id = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
}

output "subnets" {
  value = ["${data.aws_subnet_ids.subnets.ids}"]
}

output "remote_subnets" {
  value = ["${data.aws_subnet_ids.remote_subnets.ids}"]
}
