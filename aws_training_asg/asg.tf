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
		bucket = "${tfstate_bucket}"
		key = "aws_training/vpc/terraform.tfstate"
	}
}

resource "terraform_remote_state" "sns" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "${tfstate_bucket}"
		key = "aws_training/sns/terraform.tfstate"
	}
}

resource "aws_security_group" "webserver_elb" {
	name="webserver_elb"
	description="traffic from the internet to the webservers"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_block="0.0.0.0"
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		cidr_block="0.0.0.0"
	}
}

resource "aws_elb" "webservers_elb" {
	name="webserver_elb"
	subnets="${split(",",terraform_remote_state.vpc.public_subnets})"
	cross_zone_load_balacing = true
	idle_timeout = 60
	security_groups="${aws_security_group.webserver_elb}"
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
		Name="${self.name}"
		Owner="Randy"
	}
	
}

resource "aws_security_group" "webserver_elb" {
	name="webserver_allow_from_elb"
	description="Allow traffic from the ELBs to the web servers"
	egress {
		from_port=0
		to_port=0
		protocol="-1"
		cidr_block="0.0.0.0"
	}
	ingress {
		from_port=80
		to_port=80
		protocol="tcp"
		security_groups="${aws_security_group.webserver_elb.id}"
	}
}

resource "aws_launch_configuration" "web_servers" {
	name_prefix="webserver_launch_config-"
	image_id="${var.ami_id}"
	instance_type="t2.micro"
	key_name="${var.aws_ssh_key_name}"
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
	heatlh_check_grace=300
	launch_configuration="${aws_launch_configuration.web_servers.name}"
	vpc_zone_identifier="${split(",",terraform_remote_state.vpc.public_subnets})"
	load_balancers=["${var.aws_elb.webserver_elb.id}"]
}

resource "aws_autoscaling_notification" "webservers" {
	group_names = ["${aws_autoscaling_group.webservers.name}"]
	notifications  = [
    	"autoscaling:EC2_INSTANCE_LAUNCH", 
    	"autoscaling:EC2_INSTANCE_TERMINATE",
    	"autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  	]
  	topic_arn = "${terraform_remote_state.sns.aws_sns_topic_autoscale_notifications_arn}"
}