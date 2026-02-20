provider "aws" {
  region = "eu-west-2"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "ssh_my_ip" {
  name        = "tf-lab-ssh-my-ip"
  description = "Allow SSH from my public IP only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["90.249.83.220/32"]
  }

  ingress {
    description = "HTTP from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["90.249.83.220/32"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-lab-ssh-my-ip"
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "tf-lab-key"
 public_key = file("${path.module}/id_ed25519.pub")
}

resource "aws_instance" "test" {
  ami                    = "ami-0c76bd4bd302b30ec"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ssh_my_ip.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    yum update -y
    yum install -y httpd
    systemctl enable --now httpd
    echo "Terraform lab: Apache is up" > /var/www/html/index.html
  EOF
}
