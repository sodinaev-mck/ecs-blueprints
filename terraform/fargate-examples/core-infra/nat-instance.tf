data "aws_ami" "amazon_linux_arm64" {
    owners = ["amazon"]
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
    most_recent = true
}


resource "aws_security_group" "nat" {
  name        = "nat-sg"
  vpc_id      = module.vpc.vpc_id
  description = "NAT Instance"

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "0"
    to_port = "0"
    protocol = "-1"
    cidr_blocks = [local.vpc_cidr]
  }
}

resource "aws_instance" "nat" {
  ami = data.aws_ami.amazon_linux_arm64.image_id
  instance_type = "t4g.nano"
  source_dest_check = false
  subnet_id = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.nat.id]
  iam_instance_profile = aws_iam_role.ssm.name
  tags = {
    Name = "${module.vpc.name}-nat-instance"
  }

  user_data = <<EOL
#!/bin/bash
# Turning on IP Forwarding
echo "net.ipv4.ip_forward = 1" | tee /etc/sysctl.d/98-ip-forward.conf
sysctl -p

# iptables
yum install -y iptables iptables-services
systemctl enable iptables
systemctl start iptables

# FW changes.

iptables -I INPUT -j ACCEPT
## Making a catchall rule for routing and masking the private IP
iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
iptables -F FORWARD
service iptables save
systemctl restart iptables


## Ref:
# https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html#nat-routing-table
EOL
}

resource "aws_route" "nat" {
  route_table_id            = module.vpc.private_route_table_ids[0]
  destination_cidr_block    = "0.0.0.0/0"
  network_interface_id = aws_instance.nat.primary_network_interface_id
}
