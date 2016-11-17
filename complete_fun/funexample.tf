# VPC
variable "vpc_cidr" {}
variable "vpc_region" {}
variable "vpc_az" {}

# RDS
variable "rds_username" {}
variable "rds_password" {}
variable "rds_size" {}

#Basion Host
variable "ami_id" {}
variable "aws_ssh_key_name" {}

# Create the VPC START
provider "aws" {
    region = "${var.vpc_region}"
}

resource "aws_vpc" "vpc1" {
    cidr_block = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    tags {
        Owner = "Demo"
        Name = "Demo VPC"
    }
}

resource "aws_subnet" "private" {
    count = 3
    vpc_id = "${aws_vpc.vpc1.id}"
    availability_zone = "${var.vpc_region}${element(split(",",var.vpc_az),count.index)}"
    cidr_block = "${cidrsubnet(var.vpc_cidr,8,count.index + 1)}"
    tags {
        Name = "Private Subnet ${count.index}"
    }
}

resource "aws_subnet" "public" {
    count = 3
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
        Owner = "Demo"
    }
}

resource "aws_eip" "nat_servers" {
    count = 3
    vpc = true
}

resource "aws_nat_gateway" "nat" {
    count = 3
    allocation_id = "${element(aws_eip.nat_servers.*.id, count.index)}"
    subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
    depends_on = ["aws_internet_gateway.gw"]
}

resource "aws_route_table" "private_routes" {
    count = 3
    vpc_id = "${aws_vpc.vpc1.id}"
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = "${element(aws_nat_gateway.nat.*.id, count.index)}"
    }
    tags {
        Name = "Private subnet ${count.index + 1}"
    }
}

resource "aws_route_table" "public_routes" {
    vpc_id = "${aws_vpc.vpc1.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }
    tags {
        Name = "Private subnets"
    }
}

resource "aws_route_table_association" "public" {
    count = 3
    subnet_id = "${element(aws_subnet.public.*.id,count.index)}"
    route_table_id ="${element(aws_route_table.public_routes.*.id,count.index)}"
}

resource "aws_route_table_association" "private" {
    count = 3
    subnet_id = "${element(aws_subnet.private.*.id,count.index)}"
    route_table_id ="${element(aws_route_table.private_routes.*.id,count.index)}"
}
# Create the VPC END

# Create the RDS START
resource "aws_db_subnet_group" "rds_subnets" {
    name = "main"
    subnet_ids = ["${aws_subnet.private.*.id}"]
    tags {
        Name = "RDS Subnets"
    }
}

resource "aws_security_group" "rds" {
    name="rds_access"
    description="Allow access to MySQL RDS"
    vpc_id="${aws_vpc.vpc1.id}"
    egress {
        from_port=0
        to_port=0
        protocol="-1"
        cidr_blocks=["0.0.0.0/0"]
    }
    ingress {
        from_port=3306
        to_port=3306
        protocol="tcp"
        cidr_blocks=["0.0.0.0/0"]
    }
}

resource "aws_db_instance" "db1" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.6.27"
  instance_class       = "${var.rds_size}"
  name                 = "mydb"
  username             = "${var.rds_username}"
  password             = "${var.rds_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds_subnets.name}"
  parameter_group_name = "default.mysql5.6"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
}
# Create the RDS END

# Create the BASTION START
resource "aws_security_group" "bastion" {
    name="bastion_hosts"
    description="Allows ssh to bastion hosts"
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
        cidr_blocks=["0.0.0.0/0"]
    }
}


resource "aws_instance" "bastion_host" {
    ami = "${var.ami_id}"
    instance_type = "t2.large"
    subnet_id="${element(aws_subnet.public.*.id, 1)}"
    vpc_security_group_ids=["${aws_security_group.bastion.id}"]
    key_name = "${var.aws_ssh_key_name}"
    tags = {
        Name="Demo-Bastion"
    }
    associate_public_ip_address=true
}
# Create the BASTION END

# Create the SNS/SQS START
resource "aws_sns_topic" "autoscale_notifications" {
    name = "autoscale_notifications_fun"
    display_name = "autoscale_notifications_fun"
}

resource "aws_sqs_queue" "autoscale_watcher" {
    name = "autoscale_watcher_fun"
    visibility_timeout_seconds = 120
}

resource "aws_sqs_queue_policy" "autoscale_watcher_policy" {
    queue_url = "${aws_sqs_queue.autoscale_watcher.id}"
    policy = <<POLICY
    {
    "Version": "2012-10-17",
    "Id": "${aws_sqs_queue.autoscale_watcher.arn}/SQSPolicy",
    "Statement": [
        {
            "Sid": "123456789",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "SQS:SendMessage",
            "Resource": "${aws_sqs_queue.autoscale_watcher.arn}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "${aws_sns_topic.autoscale_notifications.arn}"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_sns_topic_subscription" "autoscale_notifications_sqs" {
    topic_arn = "${aws_sns_topic.autoscale_notifications.arn}"
    protocol = "sqs"
    endpoint = "${aws_sqs_queue.autoscale_watcher.arn}"

}
# Create the SNS/SQS END

# Create the ASG and Web Servers START

resource "aws_security_group" "webserver-elb" {
    name="webserver_elb"
    description="traffic from the internet to the webservers"
    vpc_id="${aws_vpc.vpc1.id}"
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
    subnets=["${aws_subnet.public.*.id}"]
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
        target="HTTP:80/index.php"
        interval=10
    }
    tags {
        Name="webserver_elb"
        Owner="Demo"
    }

}

resource "aws_security_group" "webservers-sg" {
    name="webserver_allow_from_internal"
    description="Allow traffic from the ELBs to the web servers"
    vpc_id="${aws_vpc.vpc1.id}"
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
    ingress {
        from_port=22
        to_port=22
        protocol="tcp"
        security_groups=["${aws_security_group.bastion.id}"]
    }
    ingress {
        from_port=80
        to_port=80
        protocol="tcp"
        security_groups=["${aws_security_group.bastion.id}"]
    }
}

resource "aws_launch_configuration" "web-servers" {
    name_prefix="webserver_launch_config-"
    image_id="${var.ami_id}"
    instance_type="t2.large"
    key_name="${var.aws_ssh_key_name}"
    security_groups=["${aws_security_group.webservers-sg.id}","${aws_security_group.rds.id}"]
    user_data=<<EOF
#!/bin/bash
yum clean all && yum makecache
yum install -y httpd php php-mysql
sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf
cat << 'END' > /var/www/html/index.php
<html>
<head>
<title>Fanta Feel the Fun!</title>
</head>
<body>
<?php
$servername = "${aws_db_instance.db1.address}";
$username = "${var.rds_username}";
$password = "${var.rds_password}";
$dbname = "${aws_db_instance.db1.name}";

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);

// Check connection
if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}
//echo "<br />";
//echo "Connected successfully";

// Select 1 from table_name will return false if the table does not exist.
$val = 'SELECT 1 from FeelTheFun LIMIT 1';

if($conn->query($val) === FALSE)
{
    $sql_table = 'CREATE TABLE FeelTheFun (
    id INT NOT NULL AUTO_INCREMENT,
    colour VARCHAR(10) NOT NULL,
    image VARCHAR(125) NOT NULL,
    PRIMARY KEY( id ))';

if ($conn->query($sql_table) === TRUE) {
  $insert = "INSERT INTO FeelTheFun (colour, image) VALUES (
  \"purple\", \"https://dl.dropboxusercontent.com/u/43087169/fanta-grape.jpg\"),
  (\"orange\", \"https://dl.dropboxusercontent.com/u/43087169/fanta-orange.jpg\"),
  (\"yellow\", \"https://dl.dropboxusercontent.com/u/43087169/fanta-pineapple.jpg\")";

  if ($conn->query($insert) === FALSE) {
    echo "Failed to seed DB.";
  }

} else {
    echo "Error creating table: " . $conn->error;
}
}
$sql = 'SELECT * FROM FeelTheFun WHERE `id`='.rand(1,3).' LIMIT 1';
$result = $conn->query($sql);
//if ($result === TRUE) {
  if ($result->num_rows > 0 ) {
    while($row = $result->fetch_assoc()){
      echo "<h1 style=\"color:". $row["colour"] . "\";> Fanta Feel the Fun!!</h1>";
      echo "<br/>";
      echo "<img src=\"" . $row["image"] . "\" atl=\"can\">";
      echo "<br />";
    }
  } else {
    echo "0 results.";
  }
//} else {
//  echo "Failed to get data";
//}

$conn->close();
?>
</body>
</html>
END
service httpd restart
chkconfig httpd on
EOF
    lifecycle {
        create_before_destroy = true
    }

}

resource "aws_autoscaling_group" "webservers" {
    min_size=3
    max_size=9
    desired_capacity=3
    health_check_grace_period=300
    launch_configuration="${aws_launch_configuration.web-servers.name}"
    vpc_zone_identifier=["${aws_subnet.private.*.id}"]
    load_balancers=["${aws_elb.webserver-elb.id}"]
}

resource "aws_autoscaling_notification" "webservers" {
    group_names = ["${aws_autoscaling_group.webservers.name}"]
    notifications  = [
        "autoscaling:EC2_INSTANCE_LAUNCH",
        "autoscaling:EC2_INSTANCE_TERMINATE",
        "autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
    ]
    topic_arn = "${aws_sns_topic.autoscale_notifications.arn}"
}

output "aws_elb_webserver_elb_dns_name" {
    value = "${aws_elb.webserver-elb.dns_name}"
}
# Create the ASG and Web Servers END
