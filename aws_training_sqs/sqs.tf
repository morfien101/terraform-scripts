variable "vpc_region" {}

provider "aws" {
    region = "${var.vpc_region}"
}

resource "aws_sqs_queue" "autoscale_watcher" {
	name = "autoscale_watcher"
	visibility_timeout_seconds = 120
}

output "autoscale_watcher_queue_arn" {
	value = "${aws_sqs_queue.autoscale_watcher.arn}"
}