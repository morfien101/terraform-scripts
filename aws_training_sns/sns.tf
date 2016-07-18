variable "vpc_region" {}

provider "aws" {
    region = "${var.vpc_region}"
}

resource "terraform_remote_state" "sqs" {
	backend = "s3"
	config {
		region = "${var.vpc_region}"
		bucket = "randy-terraform-bucket"
		key = "aws_training/sqs/terraform.tfstate"
	}
}

resource "aws_sns_topic" "autoscale_notifications" {
	name = "autoscale_notifications"
	display_name = "autoscale_notifications"
}

resource "aws_sns_topic_subscription" "autoscale_notifications_sqs" {
	topic_arn = "${aws_sns_topic.autoscale_notifications.arn}"
	protocol = "sqs"
	endpoint = "${terraform_remote_state.sqs.output.autoscale_watcher_queue_arn}"
	
}

output "aws_sns_topic_autoscale_notifications_arn" {
	value = "${aws_sns_topic.autoscale_notifications.arn}"
}