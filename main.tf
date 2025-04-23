provider "aws" {
  region = "us-west-1"
}

locals {
  # Load CSV data or use default
  raw_csv       = fileexists("${path.module}/students.csv") ? file("${path.module}/students.csv") : "name\nDefaultStudent"
  raw_students  = csvdecode(local.raw_csv)

  # Build students list with normalized names
  students      = [for student in local.raw_students : {
    name = replace(student.name, " ", "_")
  }]

  student_count = length(local.students)
}

output "raw_students" {
  value = local.raw_students
}

variable "base_ami" {
  description = "AMI to start from"
  default     = "ami-0e40cbc388241f8ce" # RHEL 9 in us-west-1
}

variable "centos_base_ami" {
  description = "AMI for CentOS target nodes"
  default     = "ami-0f45175b9bb67cf08" # CentOS 9 in us-west-1
}

resource "aws_vpc" "custom_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "CustomVPC"
  }
}

resource "aws_internet_gateway" "custom_igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "CustomIGW"
  }
}

resource "aws_subnet" "custom_subnet" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "CustomSubnet"
  }
}

resource "aws_route_table" "custom_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom_igw.id
  }

  tags = {
    Name = "CustomRouteTable"
  }
}

resource "aws_route_table_association" "custom_subnet_association" {
  subnet_id      = aws_subnet.custom_subnet.id
  route_table_id = aws_route_table.custom_route_table.id
}

resource "aws_security_group" "ssh_and_web_access" {
  vpc_id      = aws_vpc.custom_vpc.id
  name        = "all traffic allowed"
 description = "Allow all inbound traffic necessary for ansible"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  tags = {
    Name = "Ansible Cluster Allow All Security Group"
  }
}

# Generate the key pair locally
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "default" {
  key_name   = "dynamic_key_pair"
  public_key = tls_private_key.example.public_key_openssh
}

resource "local_file" "private_key" {
  filename        = "dynamic_key.pem"
  content         = tls_private_key.example.private_key_pem
  file_permission = "0400"
}

# First control node
resource "aws_instance" "first_control_node" {
  count                  = 1
  ami                    = var.base_ami
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.default.key_name
  vpc_security_group_ids = [aws_security_group.ssh_and_web_access.id]
  subnet_id              = aws_subnet.custom_subnet.id
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 80
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              # Create ansible user and set up SSH access
              useradd -m -s /bin/bash ansible
              usermod -aG wheel ansible
              echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
              chmod 440 /etc/sudoers.d/ansible
              mkdir -p /home/ansible/.ssh
              echo '${tls_private_key.example.public_key_openssh}' > /home/ansible/.ssh/authorized_keys
              chown -R ansible:ansible /home/ansible/.ssh
              chmod 700 /home/ansible/.ssh
              chmod 600 /home/ansible/.ssh/authorized_keys
              # Ensure SSH service is running
              systemctl enable sshd
              systemctl start sshd
              # Signal user_data completion
              touch /tmp/user_data_done
              EOF

  tags = {
    Name = "${local.students[0].name}-ControlNode"
  }
}

# Other control nodes (if any)
resource "aws_instance" "other_control_nodes" {
  count                  = local.student_count > 1 ? local.student_count - 1 : 0
  ami                    = var.base_ami
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.default.key_name
  vpc_security_group_ids = [aws_security_group.ssh_and_web_access.id]
  subnet_id              = aws_subnet.custom_subnet.id
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 80
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              # Create ansible user and set up SSH access
              useradd -m -s /bin/bash ansible
              usermod -aG wheel ansible
              echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
              chmod 440 /etc/sudoers.d/ansible
              mkdir -p /home/ansible/.ssh
              echo '${tls_private_key.example.public_key_openssh}' > /home/ansible/.ssh/authorized_keys
              chown -R ansible:ansible /home/ansible/.ssh
              chmod 700 /home/ansible/.ssh
              chmod 600 /home/ansible/.ssh/authorized_keys
              # Ensure SSH service is running
              systemctl enable sshd
              systemctl start sshd
              # Signal user_data completion
              touch /tmp/user_data_done
              EOF

  tags = {
    Name = "${local.students[count.index + 1].name}-ControlNode"
  }
}

resource "aws_instance" "target_node" {
  count                  = local.student_count * 2
  ami                    = var.centos_base_ami
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.default.key_name
  vpc_security_group_ids = [aws_security_group.ssh_and_web_access.id]
  subnet_id              = aws_subnet.custom_subnet.id

  user_data = <<-EOF
              #!/bin/bash
              # Create ansible user and set up SSH access
              useradd -m -s /bin/bash ansible
              usermod -aG wheel ansible
              echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
              chmod 440 /etc/sudoers.d/ansible
              mkdir -p /home/ansible/.ssh
              echo '${tls_private_key.example.public_key_openssh}' > /home/ansible/.ssh/authorized_keys
              chown -R ansible:ansible /home/ansible/.ssh
              chmod 700 /home/ansible/.ssh
              chmod 600 /home/ansible/.ssh/authorized_keys
              # Ensure SSH service is running
              systemctl enable sshd
              systemctl start sshd
              # Signal user_data completion
              touch /tmp/user_data_done
              EOF

  tags = {
    Name = "${local.students[floor(count.index / 2)].name}-TargetNode-${count.index % 2 + 1}"
  }
}

output "control_node_ips" {
  value = concat(aws_instance.first_control_node[*].public_ip, aws_instance.other_control_nodes[*].public_ip)
}

output "target_node_ips" {
  value = aws_instance.target_node[*].public_ip
}

# Generate inventory files in YAML format with simplified node names
resource "local_file" "generate_inventory" {
  count = local.student_count

  filename = "inventory_${local.students[count.index].name}.yaml"
  content  = <<-EOT
---
all:
  children:
    control:
      hosts:
        ControlNode:
          ansible_host: ${element(concat(aws_instance.first_control_node[*].public_ip, aws_instance.other_control_nodes[*].public_ip), count.index)}
          ansible_user: ansible
    webservers:
      hosts:
        TargetNode1:
          ansible_host: ${aws_instance.target_node[count.index * 2].public_ip}
          ansible_user: ansible
        TargetNode2:
          ansible_host: ${aws_instance.target_node[count.index * 2 + 1].public_ip}
          ansible_user: ansible
EOT

  depends_on = [aws_instance.first_control_node, aws_instance.other_control_nodes, aws_instance.target_node]
}

# Install ansible, git, copy private key, and run ansible ping on control nodes
resource "null_resource" "setup_control_node" {
  count = local.student_count

  provisioner "remote-exec" {
    inline = [
      # Wait for user_data to complete
      "while [ ! -f /tmp/user_data_done ]; do sleep 5; done",
      # Wait for dnf lock to be released
      "while [ -f /var/run/dnf.pid ]; do sleep 5; done",
      # Install base packages, continue even if some fail due to no subscription
      "sudo dnf install -y python3 python3-pip git openssh-clients || true",
      # Configure alternatives for python if not already set
      "sudo alternatives --install /usr/bin/python python /usr/bin/python3 10 || true",
      "sudo alternatives --set python /usr/bin/python3 || true",
      # Install Ansible via pip, fallback if dnf failed to install pip3
      "sudo pip3 install ansible || sudo curl -o get-pip.py https://bootstrap.pypa.io/get-pip.py && sudo python3 get-pip.py && sudo pip3 install ansible",
      "mkdir -p /home/ansible/inventory",
      "echo '${tls_private_key.example.private_key_pem}' > /home/ansible/.ssh/id_rsa",
      "chmod 600 /home/ansible/.ssh/id_rsa",
      "sudo chown ansible:ansible /home/ansible/.ssh/id_rsa",
      "git clone https://github.com/jruels/automation-dev.git /home/ansible/automation-dev || true",
      "sudo chown -R ansible:ansible /home/ansible/ansible-repo /home/ansible/inventory /home/ansible/.ssh",
      # Add all target nodes and this control node to known_hosts
      "ssh-keyscan -H ${element(concat(aws_instance.first_control_node[*].public_ip, aws_instance.other_control_nodes[*].public_ip), count.index)} >> /home/ansible/.ssh/known_hosts",
      "ssh-keyscan -H ${aws_instance.target_node[count.index * 2].public_ip} >> /home/ansible/.ssh/known_hosts",
      "ssh-keyscan -H ${aws_instance.target_node[count.index * 2 + 1].public_ip} >> /home/ansible/.ssh/known_hosts",
      "sudo chown ansible:ansible /home/ansible/.ssh/known_hosts",
      "chmod 644 /home/ansible/.ssh/known_hosts",
      # Run ansible ping to verify connectivity
      "ansible all -i /home/ansible/inventory/inventory.yaml -m ping"
    ]

    connection {
      type        = "ssh"
      user        = "ansible"
      private_key = file(local_file.private_key.filename)
      host        = element(concat(aws_instance.first_control_node[*].public_ip, aws_instance.other_control_nodes[*].public_ip), count.index)
      timeout     = "15m"
    }
  }

  # Copy the inventory file to the control node
  provisioner "file" {
    source      = "inventory_${local.students[count.index].name}.yaml"
    destination = "/home/ansible/inventory/inventory.yaml"

    connection {
      type        = "ssh"
      user        = "ansible"
      private_key = file(local_file.private_key.filename)
      host        = element(concat(aws_instance.first_control_node[*].public_ip, aws_instance.other_control_nodes[*].public_ip), count.index)
      timeout     = "15m"
    }
  }

  depends_on = [aws_instance.first_control_node, aws_instance.other_control_nodes, aws_instance.target_node, local_file.private_key, local_file.generate_inventory]
}

# # Generate .ppk on the first control node (runs last)
# resource "null_resource" "generate_ppk_on_control" {
#   provisioner "remote-exec" {
#     inline = [
#       # Wait for dnf lock to be released
#       "while [ -f /var/run/dnf.pid ]; do sleep 5; done",
#       "sudo dnf install -y putty || true",
#       "echo '${tls_private_key.example.private_key_pem}' > /home/ansible/dynamic_key.pem",
#       "sudo chown ansible:ansible /home/ansible/dynamic_key.pem",
#       "chmod 400 /home/ansible/dynamic_key.pem",
#       "puttygen /home/ansible/dynamic_key.pem -o /home/ansible/dynamic_key.ppk",
#       "sudo chown ansible:ansible /home/ansible/dynamic_key.ppk",
#       "chmod 400 /home/ansible/dynamic_key.ppk"
#     ]

#     connection {
#       type        = "ssh"
#       user        = "ansible"
#       private_key = file(local_file.private_key.filename)
#       host        = aws_instance.first_control_node[0].public_ip
#       timeout     = "15m"
#     }
#   }

#   depends_on = [
#     aws_instance.first_control_node,
#     aws_instance.other_control_nodes,
#     aws_instance.target_node,
#     null_resource.setup_control_node,
#     local_file.generate_inventory
#   ]
# }

# # Download the .ppk file from the first control node (runs last)
# resource "null_resource" "download_ppk" {
#   provisioner "local-exec" {
#     command = "scp -q -o StrictHostKeyChecking=no -i dynamic_key.pem ansible@${aws_instance.first_control_node[0].public_ip}:/home/ansible/dynamic_key.ppk dynamic_key.ppk"
#   }

#   depends_on = [null_resource.generate_ppk_on_control]
# }
