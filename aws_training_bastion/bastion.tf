variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "ami_id" {}
variable "aws_ssh_key_name" {}

terraform {
  backend "s3"{
  }
}

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

data "aws_subnet_ids" "public_subnets" {
  vpc_id = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  tags {
    Tier = "Public"
  }
}

resource "aws_security_group" "bastion" {
    name="bastion_hosts"
    description="Allows ssh to bastion hosts"
    vpc_id="${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
    egress {
        from_port=0
        to_port=0
        protocol="-1"
        cidr_blocks=["0.0.0.0/0"]
    }
    ingress {
        from_port=22
        to_port=22
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
}


resource "aws_instance" "bastion_host" {
    ami = "${var.ami_id}"
    instance_type = "t2.micro"
    subnet_id="${data.aws_subnet_ids.public_subnets.ids[1]}"
    vpc_security_group_ids=["${aws_security_group.bastion.id}"]
    key_name = "${var.aws_ssh_key_name}"
    tags = {
        Name="Randy-Bastion"
    }
    associate_public_ip_address=true
}

output "aws_instance_bastion_host_public_ip" {
	value = "${aws_instance.bastion_host.public_ip}"
}
output "aws_instance_bastion_host_public_dns" {
    value = "${aws_instance.bastion_host.public_dns}"
}
output "aws_security_group_bastion_id" {
    value = "${aws_security_group.bastion.id}"
}
