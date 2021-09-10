# #############################################################################
# Deploy an instance, then trigger a provisioner
# #############################################################################

terraform {
    required_providers {
        aws = {
        source  = "hashicorp/aws"
        version = "~> 3.27"
        }
    }

    required_version = ">= 0.14.9"
}

provider "aws" {
    region = "${var.aws_region}"
    profile = "default"
}

# #############################################################################
# Deploy the EC2 instance with a public ip
# #############################################################################

resource "aws_instance" "example_public" {
    ami                    = "${data.aws_ami.ubuntu.id}"
    instance_type          = "t3.medium"
    vpc_security_group_ids = ["${aws_security_group.example.id}"]
    key_name               = "${var.key_pair_name}"

    # This EC2 Instance has a public IP and will be accessible directly from the public Internet
    associate_public_ip_address = true

    tags = {
        Name = "${var.instance_name}-public"
    }
}

# #############################################################################
# Create a Security Group to control what requests can go in and out of the
# EC2 instnaces
# #############################################################################

resource "aws_security_group" "example" {
    name = "${var.instance_name}"

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = "${var.ssh_port}"
        to_port   = "${var.ssh_port}"
        protocol  = "tcp"

        # To keep this example simple, we allow incoming SSH requests from any
        # IP. In real-world usage, you should only allow SSH requests from
        # trusted servers, such as a bastion host or VPN server.
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# #############################################################################
# Provision the server using remote-exec
# #############################################################################

resource "null_resource" "example_provisioner" {
    triggers = {
        public_ip = "${aws_instance.example_public.public_ip}"
    }

    connection {
        type = "ssh"
        host = "${aws_instance.example_public.public_ip}"
        user = "${var.ssh_user}"
        port = "${var.ssh_port}"
        agent = false
        private_key = "${file("${var.private_key_path}")}"
    }

    // copy our example script to the server
    provisioner "file" {
        source      = "files/get-public-ip.sh"
        destination = "/tmp/get-public-ip.sh"
    }

    // change permissions to executable and pipe its output into a new file
    provisioner "remote-exec" {
        inline = [
        "chmod +x /tmp/get-public-ip.sh",
        "/tmp/get-public-ip.sh > /tmp/public-ip",
        ]
    }

    provisioner "local-exec" {
        # copy the public-ip file back to CWD, which will be tested
        command = "scp -i ${var.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.ssh_user}@${aws_instance.example_public.public_ip}:/tmp/public-ip public-ip"
    }

    provisioner "file" {
        source      = "files/deploy_dsa.sh"
        destination = "/tmp/deploy_dsa.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/deploy_dsa.sh",
            "sudo /tmp/deploy_dsa.sh"
        ]
    }
}

# #############################################################################
# Look up the latest Ubuntu AMI
# #############################################################################

data "aws_ami" "ubuntu" {
    most_recent = true
    owners      = ["099720109477"] # Canonical

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    filter {
        name   = "architecture"
        values = ["x86_64"]
    }

    filter {
        name   = "image-type"
        values = ["machine"]
    }

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
    }
}
