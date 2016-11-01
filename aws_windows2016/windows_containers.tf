variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "bastion_ami_id" {}
variable "aws_ssh_key_name" {}

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

resource "aws_security_group" "windows_bastion" {
    name="Windows_Bastion"
    description="Allows RDP to bastion hosts"
    vpc_id="${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
    egress {
        from_port=0
        to_port=0
        protocol="-1"
        cidr_blocks=["0.0.0.0/0"]
    }
    ingress {
        from_port=3389
        to_port=3389
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
}


resource "aws_instance" "windows_bastion" {
    ami = "${var.bastion_ami_id}"
    instance_type = "t2.micro"
    subnet_id="${element(split(",",data.terraform_remote_state.vpc.public_subnets), 1)}"
    vpc_security_group_ids=["${aws_security_group.windows_bastion.id}"]
    key_name = "${var.aws_ssh_key_name}"
    tags = {
        Name="Randy-Bastion"
    }
    associate_public_ip_address=true
}

output "aws_instance_windows_bastion_public_ip" {
	value = "${aws_instance.windows_bastion.public_ip}"
}
output "aws_instance_windows_bastion_public_dns" {
    value = "${aws_instance.windows_bastion.public_dns}"
}
output "aws_security_group_windows_bastion_id" {
    value = "${aws_security_group.windows_bastion.id}"
}
