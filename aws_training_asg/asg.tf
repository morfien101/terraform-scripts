variable "vpc_region" {}
variable "tfstate_bucket" {}
variable "ami_id" {}
variable "aws_ssh_key_name" {}

provider "aws" {
    region = "${var.vpc_region}"
}

resource "terraform_remote_state" "vpc" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/vpc/terraform.tfstate"
	}
}

resource "terraform_remote_state" "sns" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/sns/terraform.tfstate"
	}
}

resource "aws_security_group" "webserver-elb" {
	name="webserver_elb"
	description="traffic from the internet to the webservers"
	vpc_id="${terraform_remote_state.vpc.output.aws_vpc_vpc1_id}"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_blocks=["0.0.0.0/0"]
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		cidr_blocks=["0.0.0.0/0"]
	}
}

resource "aws_elb" "webserver-elb" {
	name="webserver-elb"
	subnets=["${split(",",terraform_remote_state.vpc.output.public_subnets)}"]
	cross_zone_load_balancing = true
	idle_timeout = 60
	security_groups=["${aws_security_group.webserver-elb.id}"]
	listener {
		instance_port=80
		instance_protocol="http"
		lb_port=80
		lb_protocol="http"
	}
	health_check {
		healthy_threshold = 2
		unhealthy_threshold = 2
		timeout = 2
		target="HTTP:80/"
		interval=10
	}
	tags {
		Name="webserver_elb"
		Owner="Randy"
	}
	
}

resource "aws_security_group" "webservers-sg" {
	name="webserver_allow_from_elb"
	description="Allow traffic from the ELBs to the web servers"
	vpc_id="${terraform_remote_state.vpc.output.aws_vpc_vpc1_id}"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_blocks=["0.0.0.0/0"]
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		security_groups=["${aws_security_group.webserver-elb.id}"]
	}
}

resource "aws_launch_configuration" "web-servers" {
	name_prefix="webserver_launch_config-"
	image_id="${var.ami_id}"
	instance_type="t2.micro"
	key_name="${var.aws_ssh_key_name}"
	security_groups=["${aws_security_group.webservers-sg.id}"]
	user_data=<<EOF
#!/bin/bash
yum install httpd -y
echo $(hostname) >> /var/www/html/index.html
service httpd start
chkconfig httpd on
EOF
	lifecycle {
		create_before_destroy = true
	}

}

resource "aws_autoscaling_group" "webservers" {
	min_size=3
	max_size=9
	desired_capacity=6
	health_check_grace_period=300
	launch_configuration="${aws_launch_configuration.web-servers.name}"
	vpc_zone_identifier=["${split(",",terraform_remote_state.vpc.output.public_subnets)}"]
	load_balancers=["${aws_elb.webserver-elb.id}"]
}

resource "aws_autoscaling_notification" "webservers" {
	group_names = ["${aws_autoscaling_group.webservers.name}"]
	notifications  = [
    	"autoscaling:EC2_INSTANCE_LAUNCH", 
    	"autoscaling:EC2_INSTANCE_TERMINATE",
    	"autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  	]
  	topic_arn = "${terraform_remote_state.sns.output.aws_sns_topic_autoscale_notifications_arn}"
}