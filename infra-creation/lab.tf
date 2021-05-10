provider "aws" {
  region = "us-east-1"
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.0.0"

  name = "dev-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "VPC"
  }
}


resource "aws_db_subnet_group" "private_subnet_group" {
  name       = "main"
  subnet_ids = [module.vpc.private_subnets[0], module.vpc.private_subnets[1], module.vpc.private_subnets[2]]

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "private-subnet-group"
  }
}



resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Security Group for Bastion Host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from everywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "bastion-sg"
  }
}


resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Security Group for EC2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "SSH from Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description     = "Authorise only from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "ec2-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security Group for RDS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Authorise only from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  ingress {
    description     = "Authorise only from Bastion Host"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "rds-sg"
  }
}


resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security Group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Authorise only from everywhere to 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Authorise only from everywhere to 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "alb-sg"
  }
}

resource "aws_db_instance" "mysql_rds" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "Bookstore"
  username               = "admin"
  password               = "admin123"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.private_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  apply_immediately      = true
  provisioner "file" {
    connection {
      user        = "ec2-user"
      host        = "${aws_instance.bastion-ec2-instance.public_ip}"
      private_key = file("./bastion.pem")
    }

    source      = "./schema.sql"
    destination = "/tmp/schema.sql"
  }

  provisioner "remote-exec" {
    connection {
      user        = "ec2-user"
      host        = "${aws_instance.bastion-ec2-instance.public_ip}"
      private_key = file("./bastion.pem")
    }
    inline = [
      "mysql --host=${self.address} --port=${self.port} --user=${self.username} --password=${self.password} < /tmp/schema.sql"
    ]

  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "mysql-rds"
  }
}

resource "aws_ssm_parameter" "dbendpoint" {
  name  = "/database/endpoint"
  type  = "String"
  value = aws_db_instance.mysql_rds.address

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "dbendpoint"
  }
}

resource "aws_ssm_parameter" "dbusername" {
  name  = "/database/username"
  type  = "String"
  value = aws_db_instance.mysql_rds.username

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "dbusername"
  }
}

resource "aws_ssm_parameter" "dbpassword" {
  name  = "/database/password"
  type  = "String"
  value = aws_db_instance.mysql_rds.password

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "dbpassword"
  }
}


resource "aws_ssm_parameter" "dbname" {
  name  = "/database/dbname"
  type  = "String"
  value = aws_db_instance.mysql_rds.name

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "dbname"
  }
}

resource "aws_key_pair" "private_kp" {
  key_name   = "private-kp"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEArpvRund4rryxbenREaftLLp+i5dXTsqJdfWkSzafNe7H2xwKPenzKgxwur3wkV4RzgrLfUmYgIqfMTzVPkLRvqcipTehLu+naqW4WLTWU+u4P3AfwxJi+2Weivgcfe5fvYAiAvDzf1TMTS7YQ9ml7VKqEPtW1EVLlWZTjpJ0eMPaVuWvMuXMVIWqMdWbtrWDxAa203VTxCtfBSmW/Y8MlJqqUVFxHXyrdel8wH8gUIuJOwd9rXZTYh8QXLKsazuCvaGkVieYh7Mqzr8nYJI2f9VxZn45Dg4X3cyNlcPVj8EkoSmgF8VLxzunm45s2z0xKAgj74nf8YAFP7pMU6tyTw== rsa-key-20210506"

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "private-kp"
  }

}


resource "aws_key_pair" "bastion_kp" {
  key_name   = "bastion-kp"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAu/gf1EaMKq44XrnWSLQFj5Hmn+NMRfZonDLkePx94WUu9LBK1LX0Ze+qcfL79Ol1FsXsBPnyWmDNRSWCHkdhHZpLuo6D8/YWu6DKZHdkQNZ+vhS7zZtpWy/Pk1+BE2dTPlWYKIqJHW3o3oHUeKKr8NFhuTm8uqaylksApAZ0PsSyJmNofISZecYCI15Qzz+zLzDbitDOsdb+IJngeWM/twcBuzzm03e5u5qQtY3wYB1UHN4piyAFAN5+Lb7gMVmi75wYa28seLkW3CfulkynSE7FK/HaBGCHhhHDIBAiVaUTfPhLoWJUTZjpAxDKsvf0h7Noq8si3hrrjJbz20V4yQ== rsa-key-20210506"

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "bastion-kp"
  }

}

data "aws_ami" "golden_ami" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = ["golden-ami-*"]
  }
}

data "aws_ami" "amaz-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2"]
  }
}

resource "aws_instance" "bastion-ec2-instance" {
  ami                         = data.aws_ami.amaz-linux-2.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  subnet_id                   = module.vpc.public_subnets[0]
  key_name                    = aws_key_pair.bastion_kp.key_name
  associate_public_ip_address = true
  user_data                   = <<EOF
  #! /bin/bash
  sudo yum install mysql -y
  EOF
  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "ec2-bastion-host"
  }
}

resource "aws_launch_configuration" "launch_config" {
  name                 = "launch-config"
  image_id             = data.aws_ami.golden_ami.id
  instance_type        = "t2.micro"
  iam_instance_profile = "AWSAdminRole"
  security_groups      = [aws_security_group.ec2_sg.id]
  key_name             = aws_key_pair.private_kp.key_name

}

resource "aws_autoscaling_group" "app_asg" {
  name                      = "app-asg"
  launch_configuration      = aws_launch_configuration.launch_config.name
  vpc_zone_identifier       = module.vpc.private_subnets[*]
  health_check_grace_period = 300
  health_check_type         = "EC2"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  target_group_arns         = [aws_lb_target_group.asg_tg.arn]
  depends_on                = [aws_db_instance.mysql_rds]
}

resource "aws_lb" "alb" {
  name               = "load-balancer"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets[*]
  security_groups    = [aws_security_group.alb_sg.id]
  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "load-balancer"
  }
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.asg_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "asg_tg" {
  name        = "asg-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"
  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "asg-tg"
  }
}

resource "aws_autoscaling_policy" "asg_policy" {
  name                      = "asg-policy"
  policy_type               = "TargetTrackingScaling"
  autoscaling_group_name    = aws_autoscaling_group.app_asg.name
  estimated_instance_warmup = 200

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = "60"

  }
}

output "alb_dns" {
	value = aws_lb.alb.dns_name
}