## TERRAFORM REMOTE STATE FILE
terraform {
  backend "s3"{
  }
}

# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
}

## EC2 RESOURCES
data terraform_remote_state "vpc" {
  backend = "s3"
  config {
		region = "${var.tfregion}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/vpc/terraform.tfstate"
	}
}

data "aws_ami" "ecs" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }
}


data "terraform_remote_state" "sns" {
	backend = "s3"
	config {
		region = "${var.aws_region}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/sns/terraform.tfstate"
	}
}

## BASTION HOST
data terraform_remote_state "bastion" {
  backend = "s3"
  config {
		region = "${var.tfregion}"
		bucket = "${var.tfstate_bucket}"
		key = "aws_training/bastion/terraform.tfstate"
	}
}

### Network
data "aws_subnet_ids" "private_subnets" {
  vpc_id = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  tags {
    Tier = "Private"
  }
}

data "aws_subnet_ids" "public_subnets" {
  vpc_id = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  tags {
    Tier = "Public"
  }
}

### Compute

resource "aws_autoscaling_group" "app" {
  name                 = "tf-test-asg"
  vpc_zone_identifier  = ["${data.aws_subnet_ids.private_subnets.ids}"]
  min_size             = "${var.asg_min}"
  max_size             = "${var.asg_max}"
# This is breaking the runs because terraform is stateful and the autoscaling
# policies are change the numbers outside of the scope of terraform.
#  desired_capacity     = "${var.asg_desired}"
  launch_configuration = "${aws_launch_configuration.app.name}"
}

resource "aws_launch_configuration" "app" {
  security_groups = [
    "${aws_security_group.ecs_asg_sg.id}",
  ]

  key_name                    = "${var.ec2_key_name}"
  image_id                    = "${data.aws_ami.ecs.image_id}"
  instance_type               = "${var.ecs_instance_type}"
  spot_price                  = "${var.ecs_spot_price}"
  associate_public_ip_address = false
  iam_instance_profile        = "${aws_iam_instance_profile.app.name}"
  lifecycle {
    create_before_destroy = true
  }
  user_data                   = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
EOF
}

resource "aws_autoscaling_policy" "scaleup-1" {
  name = "scaleup-1"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"
}

resource "aws_autoscaling_policy" "scaledown-1" {
  name = "scaledown-1"
  scaling_adjustment = "-1"
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"
}

resource "aws_cloudwatch_metric_alarm" "1-high-cpu" {
    alarm_name = "ECS-CPU-HIGH-Alarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "120"
    statistic = "Average"
    threshold = "70"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
    }
    alarm_description = "Scale up if CPU > 80% for 2 minutes"
    alarm_actions = ["${aws_autoscaling_policy.scaleup-1.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "1-down-cpu" {
    alarm_name = "ECS-CPU-LOW-Alarm"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "300"
    statistic = "Average"
    threshold = "30"
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
    }
    alarm_description = "Scale down if CPU < 30% for 5 minutes"
    alarm_actions = ["${aws_autoscaling_policy.scaledown-1.arn}"]
}

resource "aws_autoscaling_notification" "ECS_servers" {
	group_names = ["${aws_autoscaling_group.app.name}"]
	notifications  = [
    	"autoscaling:EC2_INSTANCE_LAUNCH",
    	"autoscaling:EC2_INSTANCE_TERMINATE",
    	"autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  	]
  	topic_arn = "${data.terraform_remote_state.sns.aws_sns_topic_autoscale_notifications_arn}"
}
### Security

resource "aws_security_group" "alb_sg" {
  description = "controls access to the application ALB"
  vpc_id = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  name   = "tf-ecs-lbsg"
  tags {
    Name = "RandyAlbSg"
  }
}

resource "aws_security_group_rule" "alb_allow_80_in"{
  security_group_id = "${aws_security_group.alb_sg.id}"
  type = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_allow_all_out" {
  security_group_id = "${aws_security_group.alb_sg.id}"
  type = "egress"
  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks = [
    "0.0.0.0/0",
  ]
}

resource "aws_security_group" "ecs_asg_sg" {
  description = "controls direct access to application instances"
  vpc_id      = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  name        = "tf-ecs-instsg"
  tags {
    Name = "RandyEcsAsgSg"
  }
}

resource "aws_security_group_rule" "ecs_cluster_allow_22_in_from_bastion" {
  security_group_id = "${aws_security_group.ecs_asg_sg.id}"
  type = "ingress"
  protocol  = "tcp"
  from_port = 22
  to_port   = 22

  source_security_group_id = "${data.terraform_remote_state.bastion.aws_security_group_bastion_id}"
}

resource "aws_security_group_rule" "ecs_cluster_allow_49153_65535_in_from_bastion" {
  security_group_id = "${aws_security_group.ecs_asg_sg.id}"
  type = "ingress"
  protocol  = "tcp"
  from_port = 32000
  to_port   = 65535

  source_security_group_id = "${data.terraform_remote_state.bastion.aws_security_group_bastion_id}"
}

resource "aws_security_group_rule" "ecs_cluster_allow_all_in_from_alb" {
  security_group_id = "${aws_security_group.ecs_asg_sg.id}"
  type = "ingress"
  protocol  = "tcp"
  from_port = 0
  to_port   = 65535
  source_security_group_id = "${aws_security_group.alb_sg.id}"
}

resource "aws_security_group_rule" "ecs_cluster_allow_all_out" {
  security_group_id = "${aws_security_group.ecs_asg_sg.id}"
  type = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

## ECS
resource "aws_ecs_cluster" "main" {
  name = "terraform_example_ecs_cluster"
}

data "template_file" "go_rage_online_task_file" {
  template = "${file("${path.module}/task-go_rage_online.json")}"

  vars {
    image_url        = "${format("%s:%s", var.task_template_image_url, var.task_template_image_version)}"
    container_name   = "go_rage_online"
    log_group_region = "${var.aws_region}"
    log_group_name   = "${aws_cloudwatch_log_group.app.name}"
  }
}

resource "aws_ecs_task_definition" "go_rage_online_task" {
  family                = "tf_go_rage_online_td"
  container_definitions = "${data.template_file.go_rage_online_task_file.rendered}"
}

resource "aws_ecs_service" "go_rage_online_service" {
  name            = "tf-ecs-go_rage_online"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.go_rage_online_task.arn}"
  desired_count   = "${var.go_rage_online_desired_count}"
  iam_role        = "${aws_iam_role.ecs_service.name}"

  load_balancer {
    target_group_arn = "${aws_alb_target_group.go_rage_online.id}"
    container_name   = "go_rage_online"
    container_port   = "8001"
  }

  depends_on = [
    "aws_iam_role_policy.ecs_service",
    "aws_alb_listener.front_end",
  ]
}

## IAM

resource "aws_iam_role" "ecs_service" {
  name = "tf_example_ecs_role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_service" {
  name = "tf_example_ecs_policy"
  role = "${aws_iam_role.ecs_service.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "app" {
  name  = "tf-ecs-instprofile"
  role = "${aws_iam_role.app_instance.name}"
}

resource "aws_iam_role" "app_instance" {
  name = "tf-ecs-example-instance-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

data "template_file" "instance_profile" {
  template = "${file("${path.module}/instance-profile-policy.json")}"

  vars {
    app_log_group_arn = "${aws_cloudwatch_log_group.app.arn}"
    ecs_log_group_arn = "${aws_cloudwatch_log_group.ecs.arn}"
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "TfEcsExampleInstanceRole"
  role   = "${aws_iam_role.app_instance.name}"
  policy = "${data.template_file.instance_profile.rendered}"
}

## ALB

resource "aws_alb_target_group" "go_rage_online" {
  name     = "tf-ecs-go-rage-online"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${data.terraform_remote_state.vpc.aws_vpc_vpc1_id}"
  deregistration_delay = "${var.go_rage_online_deregistration_delay}"
  health_check {
    path = "/healthcheck"
    timeout = 2
    interval = 5
  }
}

resource "aws_alb" "ecs_alb" {
  name            = "tf-example-alb-ecs"
  subnets         = ["${data.aws_subnet_ids.public_subnets.ids}"]
  security_groups = ["${aws_security_group.alb_sg.id}"]
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.ecs_alb.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.go_rage_online.id}"
    type             = "forward"
  }
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "ecs" {
  name = "tf-ecs-group/ecs-agent"
}

resource "aws_cloudwatch_log_group" "app" {
  name = "tf-ecs-group/go-rage-online"
}
