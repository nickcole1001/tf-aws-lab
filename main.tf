provider "aws" {
  region = "eu-west-2"
}

data "aws_vpc" "default" {
  default = true
}

# Pick a subnet in the default VPC so we know the AZ ahead of time
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}

resource "aws_security_group" "ssh_my_ip" {
  name        = "tf-lab-ssh-my-ip"
  description = "Allow SSH/HTTP/Mongo-Express from my public IP only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP (Apache) from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Mongo Express from my IP"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
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
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.ssh_my_ip.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    # --- Apache (your existing bit) ---
    yum update -y
    yum install -y httpd
    systemctl enable --now httpd
    echo "Terraform lab: Apache is up" > /var/www/html/index.html

    # --- Docker ---
    amazon-linux-extras install docker -y || yum install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user || true

    # --- EBS mount for Mongo data ---
    DEVICE=/dev/xvdf

    # Wait for EBS device to appear (volume attachment happens after instance)
    for i in {1..60}; do
      [ -b "$DEVICE" ] && break
      sleep 2
    done

    # Format only if blank (prevents wiping on rebuilds where volume persists)
    if ! file -s $DEVICE | grep -q filesystem; then
      mkfs -t xfs $DEVICE
    fi

    mkdir -p /data
    grep -q "$DEVICE" /etc/fstab || echo "$DEVICE /data xfs defaults,nofail 0 2" >> /etc/fstab
    mount -a

    mkdir -p /data/mongo

    # --- Mongo + Mongo Express (simple "frontend" to populate Mongo) ---
    docker network create labnet || true

    docker rm -f mongo || true
    docker run -d --name mongo --network labnet \
      --restart unless-stopped \
      -v /data/mongo:/data/db \
      mongo:7

    docker rm -f mongo-express || true
    docker run -d --name mongo-express --network labnet \
      --restart unless-stopped \
      -p 8081:8081 \
      -e ME_CONFIG_MONGODB_SERVER=mongo \
      mongo-express:1.0.2
  EOF

  tags = {
    Name = "tf-lab-ec2-mongo"
  }
}

# Create EBS in the same AZ as the chosen subnet
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "tf-lab-mongo-data"
  }
}

resource "aws_volume_attachment" "mongo_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.test.id
}
