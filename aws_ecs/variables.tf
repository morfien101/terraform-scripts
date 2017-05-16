variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-west-2"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

variable "ec2_key_name" {
  description = "Name of AWS key pair"
}

variable "ecs_instance_type" {
  default     = "t2.small"
  description = "AWS instance type"
}

variable "ecs_spot_price" {
  description = "The price that we are willing to pay for the spot instances"
}

variable "asg_min" {
  description = "Min numbers of servers in ASG"
  default     = "1"
}

variable "asg_max" {
  description = "Max numbers of servers in ASG"
  default     = "2"
}

variable "asg_desired" {
  description = "Desired numbers of servers in ASG"
  default     = "1"
}

variable "tfregion" {
  description = "location to collect terraform state files"
  default = ""
}

variable "tfstate_bucket" {
  description = "Bucket name that holds terraform state files"
}

variable "task_template_image_url" {
  description = "Where to pull the task container from"
}
variable "task_template_image_version" {
  description = "What version of the container to pull"
}

variable "go_rage_online_deregistration_delay" {
  description = "How long the ALB will wait for the container to drain connections"
}

variable "go_rage_online_desired_count" {
  description = "How many go_rage_online containers we want to have running at any given time"
  default = 2
}
