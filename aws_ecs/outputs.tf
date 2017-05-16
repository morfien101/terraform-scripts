output "instance_security_group" {
  value = "${aws_security_group.ecs_asg_sg.id}"
}

output "launch_configuration" {
  value = "${aws_launch_configuration.app.id}"
}

output "asg_name" {
  value = "${aws_autoscaling_group.app.id}"
}

output "elb_hostname" {
  value = "${aws_alb.ecs_alb.dns_name}"
}
