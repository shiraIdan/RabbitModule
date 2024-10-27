# Define rabbit_asg_policy
resource "aws_iam_policy" "rabbit_asg_policy" {
  name = "rabbit_asg_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "autoscaling:DescribeAutoScalingInstances",
          "ec2:DescribeInstances",
        ],
        Resource = "*",
      },
    ],
  })
}

# Define rabbit_asg_logging_policy
resource "aws_iam_policy" "rabbit_asg_logging_policy" {
  name = "rabbit_asg_logging_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ],
        Resource = "*",
      },
    ],
  })
}

# Create rabbit_role IAM role
resource "aws_iam_role" "rabbit_role" {
  name = "rabbit_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com" # Update this if the service is different
        },
      },
    ],
  })
}

# Attach policies to rabbit_role
resource "aws_iam_role_policy_attachment" "rabbit_asg_policy_attach" {
  role       = aws_iam_role.rabbit_role.name
  policy_arn = aws_iam_policy.rabbit_asg_policy.arn
}

resource "aws_iam_role_policy_attachment" "rabbit_asg_logging_policy_attach" {
  role       = aws_iam_role.rabbit_role.name
  policy_arn = aws_iam_policy.rabbit_asg_logging_policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.rabbit_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_full_access" {
  role       = aws_iam_role.rabbit_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}



resource "aws_lb" "name" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-0b1cad40369f5a5dd", "subnet-0caad619a10a3d000"]
  security_groups    = [aws_security_group.example_sg.id]
}

resource "aws_lb_target_group" "rabbitmq_tg" {
  name     = "rabbitmq-tg"
  port     = 15672
  vpc_id   = "vpc-0ce7ca8cbeba6b3d4"
  protocol = "HTTP"

  health_check {
    enabled             = true
    interval            = 30
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.name.arn
  port              = 15672
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq_tg.arn
  }
}

resource "aws_lb" "rabbitmq_internal_nlb" {
  name                             = "rabbitmq-internal-nlb"
  internal                         = true # Set to true if you want the NLB to be internal
  load_balancer_type               = "network"
  subnets                          = ["subnet-0b1cad40369f5a5dd", "subnet-0caad619a10a3d000"]
  enable_cross_zone_load_balancing = false
  security_groups                  = [aws_security_group.example_sg.id]
}



resource "aws_lb_target_group" "rabbitmq_nlb_tg" {
  name     = "rabbitmq-nlb-tg"
  port     = 5672 # Ensure this is the correct port for your application
  vpc_id   = "vpc-0ce7ca8cbeba6b3d4"
  protocol = "TCP"

  health_check {
    enabled             = true
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP" # Make sure this matches the protocol of your service
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.rabbitmq_internal_nlb.arn
  port              = 5672 # The listening port for your NLB
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq_nlb_tg.arn
  }
}





resource "aws_launch_template" "example" {
  name          = "example-template"
  image_id      = var.ami
  instance_type = var.instance_type
  key_name      = "ShiraDevOps_key"
  user_data     = base64encode(data.template_file.init.rendered)


  vpc_security_group_ids = [aws_security_group.example_sg.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "Rabbitmq-Cluster"
      service = "rabbitmq"
      // Additional tags can be added here
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.rabbit_instance_profile.name
  }

}

resource "aws_iam_instance_profile" "rabbit_instance_profile" {
  name = "rabbit_instance_profile"
  role = aws_iam_role.rabbit_role.name
}



data "template_file" "init" {
  template = <<-EOF
#!/bin/bash
# Docker Installation
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install docker
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
# Set up perms
sudo usermod -aG docker $USER


# Create EBS volume mount for RabbitMQ to persist the data
sudo sed -i '$a/dev/xvda /var/lib/rabbitmq/ auto defaults,nofail 0 2' /etc/fstab && sudo mount -a



# Create the configuration file
cat << ZOF > /rabbitconf/config.conf
loopback_users.guest = false
listeners.tcp.default = 5672
cluster_formation.peer_discovery_backend = aws
cluster_formation.aws.region = eu-central-1
cluster_formation.aws.use_autoscaling_group = true
cluster_formation.aws.access_key_id = var.aws_access_key_id
cluster_formation.aws.secret_key    = var.aws_secret_access_key
ZOF

# Create a volume and create a temp container and move the configuration file to volume
docker run -d --name temp-container --rm -v rabbit_config_volume:/rabbit_config_volume alpine
docker cp /rabbitmq/config.conf temp-container:/rabbit_config_volume/
docker stop temp-container



# Create a volume and run the rabbitmq container 
docker volume create rabbit_config_volume
docker run -d --name rabbit \
  --network host \
  -v rabbit_config_volume:/rabbit_config_volume/ \
  -e RABBITMQ_CONFIG_FILE=/rabbit_config_volume/config.conf \
  -e RABBITMQ_ERLANG_COOKIE=WSPp6YtVS41KJQBYZRPlSR+qAT6lRPQhd7BfhRfe \
  rabbitmq:3.13.0 \
  rabbitmq-plugins --offline enable rabbitmq_peer_discovery_aws


# addtional setup
docker exec -d rabbit rabbitmq-server
# Enabling plugins
rabbitmq-plugins enable rabbitmq_management
rabbitmq-plugins --offline enable rabbitmq_peer_discovery_aws





docker run -d --name rabbit \
  --network host \
    -v rabbit_config_volume:/rabbitconf/ \

    rabbitmq:3.13.0 
    
EOF 

}



resource "aws_security_group" "example_sg" {
  name        = "example-sg"
  description = "Example Security Group"
  vpc_id      = var.my_vpc_id
}

resource "aws_security_group_rule" "rule1" {
  type              = "ingress"
  from_port         = 35197
  to_port           = 35197
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}

resource "aws_security_group_rule" "rule15" {
  type              = "ingress"
  from_port         = 15672
  to_port           = 15672
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}
resource "aws_security_group_rule" "rule18" {
  type              = "ingress"
  from_port         = 4369
  to_port           = 4369
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}



resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 signifies all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}


resource "aws_security_group_rule" "rule2" {
  type              = "ingress"
  from_port         = 5672
  to_port           = 5672
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}

resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example_sg.id
}

resource "aws_autoscaling_group" "example" {
  name                = "example-asg"
  max_size            = 3
  min_size            = 1
  desired_capacity    = 2
  vpc_zone_identifier = ["subnet-0b1cad40369f5a5dd", "subnet-0caad619a10a3d000"]


  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "example" {
  name                   = "example_policy"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example.name
}

resource "aws_cloudwatch_metric_alarm" "example_high_cpu" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu usage"
  alarm_actions       = [aws_autoscaling_policy.example.arn]
}

resource "aws_cloudwatch_metric_alarm" "example_low_cpu" {
  alarm_name          = "low-cpu-usage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu usage"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
  alarm_actions = [aws_autoscaling_policy.example.arn]
}

resource "aws_subnet" "example" {
  vpc_id            = "vpc-0ce7ca8cbeba6b3d4"
  cidr_block        = "10.0.32.0/20"
  availability_zone = "us-east-1a"
}

