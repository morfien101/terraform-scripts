# VPC
variable "vpc_cidr" {}
variable "vpc_region" {}
variable "vpc_az" {}

#EC2 Hosts
variable "ami_id" {}
variable "aws_ssh_key_name" {}
variable "ssh_ips_cidrs" {}

# Tags
variable "tag_owner" {}

# Create the VPC START
provider "aws" {
    region = "${var.vpc_region}"
}

resource "aws_vpc" "vpc1" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags {
        Owner = "${var.tag_owner}"
        Name = "Randy Test VPC"
    }
}

resource "aws_subnet" "public" {
    count = 1
    availability_zone = "${var.vpc_region}${element(split(",",var.vpc_az),count.index)}"
    vpc_id = "${aws_vpc.vpc1.id}"
    cidr_block = "${cidrsubnet(var.vpc_cidr,8,count.index + 51)}"
    tags {
        Name = "Public Subnet ${count.index}"
    }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.vpc1.id}"
    tags {
        Owner = "${var.tag_owner}"
    }
}

resource "aws_route_table" "public_routes" {
    vpc_id = "${aws_vpc.vpc1.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }
    tags {
        Name = "Public subnets"
    }
}

resource "aws_route_table_association" "public" {
    count = 3
    subnet_id = "${element(aws_subnet.public.*.id,count.index)}"
    route_table_id ="${element(aws_route_table.public_routes.*.id,count.index)}"
}
# Create the VPC END

# Create the Web Server START
resource "aws_security_group" "web_server" {
    name="WS_hosts"
    description="Allows access to Web hosts"
    vpc_id="${aws_vpc.vpc1.id}"
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
        cidr_blocks=["${split(",",var.ssh_ips_cidrs)}"]
    }
    ingress {
        from_port=8000
        to_port=8000
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
    ingress {
        from_port=8080
        to_port=8080
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
}


resource "aws_instance" "blaster" {
    count = 1
    ami = "${var.ami_id}"
    instance_type = "c4.xlarge"
    subnet_id="${element(aws_subnet.public.*.id, 1)}"
    vpc_security_group_ids=["${aws_security_group.web_server.id}"]
    key_name = "${var.aws_ssh_key_name}"
    tags = {
        Name="Blaster-Demo"
        Owner = "${var.tag_owner}"
    }
    associate_public_ip_address=true
}

resource "aws_instance" "web_server" {
    count = 1
    ami = "${var.ami_id}"
    instance_type = "m4.xlarge"
    subnet_id="${element(aws_subnet.public.*.id, 1)}"
    vpc_security_group_ids=["${aws_security_group.web_server.id}"]
    key_name = "${var.aws_ssh_key_name}"
    tags = {
        Name="WS-Demo"
        Owner = "${var.tag_owner}"
    }
    associate_public_ip_address=true
}
# Create the Web Server END

output "aws_instance_web_server" {
	value = "${aws_instance.web_server.public_ip}"
}

output "aws_instance_blaster_server" {
	value = "${aws_instance.blaster.public_ip}"
}
