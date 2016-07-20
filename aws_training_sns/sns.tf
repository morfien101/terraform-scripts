variable "vpc_region" {}
variable "sqs_queue_name" {}
variable "tfstate_bucket" {}

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

resource "aws_sns_topic" "autoscale_notifications" {
	name = "autoscale_notifications"
	display_name = "autoscale_notifications"
}

resource "aws_sqs_queue" "autoscale_watcher" {
	name = "autoscale_watcher"
	visibility_timeout_seconds = 120
	policy = <<EOF
{
    "Version": "2012-10-17",
    "Id": "arn:aws:sqs:${var.vpc_region}:${terraform_remote_state.vpc.output.aws_account_number}:autoscale_watcher/SQSPolicy",
    "Statement": [
        {
            "Sid": "123456789",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "SQS:SendMessage",
            "Resource": "arn:aws:sqs:${var.vpc_region}:${terraform_remote_state.vpc.output.aws_account_number}:autoscale_watcher",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "${aws_sns_topic.autoscale_notifications.arn}"
                }
            }
        }
    ]
}
EOF
}

output "autoscale_watcher_queue_arn" {
	value = "${aws_sqs_queue.autoscale_watcher.arn}"
}

resource "aws_sns_topic_subscription" "autoscale_notifications_sqs" {
	topic_arn = "${aws_sns_topic.autoscale_notifications.arn}"
	protocol = "sqs"
	endpoint = "${aws_sqs_queue.autoscale_watcher.arn}"
	
}

output "aws_sns_topic_autoscale_notifications_arn" {
	value = "${aws_sns_topic.autoscale_notifications.arn}"
}

output "aws_sqs_queue_autoscale_watcher_arn" {
	value = "${aws_sqs_queue.autoscale_watcher.arn}"
}