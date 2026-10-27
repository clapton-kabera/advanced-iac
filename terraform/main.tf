#----------------------------------------------------------------------------------------------------
# main.tf
# author: Kabera Clapton
#
# description: Provisions the following: a VPC, Public Subnet, Internet Gateway with Routes to the 
#              to the subnet, Subnet to allow SSH and HTTP traffic to and from and EC2 t2.micro
#              instance, an S3 bucket and DynamoDB instance for Remote state handling.
#----------------------------------------------------------------------------------------------------

/*
  Setup the providers and their versions
*/
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70.0"
    }
    
    http = {
      source = "hashicorp/http"
      version = "~> 3.6.3"
    }

    tls = {
      source = "hashicorp/tls"
      version = "~> 4.4.2"
    }

    local = {
      source = "hashicorp/local"
      version = "~> 2.9.1"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "iac-terraform-lab1"
    }
  }
}

/*
  fetch my current public ip so that it used in the security group rule
*/
data "http" "my_public_ip" {
  url = "http://checkip.amazonaws.com"
}

/*
  Store the ip address in a local variable
*/
locals {
  current_ip = chomp(data.http.my_public_ip.response_body)
}


/*
  provision the VPC
*/
resource "aws_vpc" "sandbox_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "sandbox-vpc"
  }
}

/*
  Create a public subnet in the vpc created.
*/
resource "aws_subnet" "sandbox_pub_subnet" {
  vpc_id                  = aws_vpc.sandbox_vpc.id
  cidr_block              = var.pub_cidr
  map_public_ip_on_launch = true
}

/*
  Create an internet gateway at attach it to the vpc
*/
resource "aws_internet_gateway" "sandbox_gw" {
  vpc_id = aws_vpc.sandbox_vpc.id
  tags = {
    Name = "Sandbox IGW"
  }
}

/*
  Create a route table and route for the vpc
*/
resource "aws_route_table" "sandbox_route_table" {
  vpc_id = aws_vpc.sandbox_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sandbox_gw.id
  }
}

/*
  Associate the route table with the subnet
*/
resource "aws_route_table_association" "rtb_subnet" {
  subnet_id      = aws_subnet.sandbox_pub_subnet.id
  route_table_id = aws_route_table.sandbox_route_table.id
}

/*
  Create the security group that allows SSH and HTTP traffic
*/
resource "aws_security_group" "sandbox_sec_grp" {
  name        = "allow_ssh_http"
  description = "Allow inbound SSH and HTTP traffic"
  vpc_id      = aws_vpc.sandbox_vpc.id

  tags = {
    Name = "allow_ssh_http"
  }
}

/*
  Create an ingress rule for HTTP
*/
resource "aws_vpc_security_group_ingress_rule" "http_rule" {
  security_group_id = aws_security_group.sandbox_sec_grp.id

  cidr_ipv4   = var.source_cidr
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

/*
  Create an ingress rule for SSH
*/
resource "aws_vpc_security_group_ingress_rule" "ssh_rule" {
  security_group_id = aws_security_group.sandbox_sec_grp.id

  cidr_ipv4   = "${local.current_ip}/32"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

/*
  Create an egress rule to allow all outbound traffic since
  when terraform creates sec-groups this is disabled by AWS
*/
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.sandbox_sec_grp.id

  cidr_ipv4 = var.egress_cidr
  ip_protocol = -1
}

/*
  Create a data source to hold the latest ami from the AWS parameter store
*/
data "aws_ami" "al2_latest" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["amazon"]
}

/*
  Create the EC2 Instance in this VPC
*/
resource "aws_instance" "sandbox_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  tags = {
    Name  = "sandbox-server"
    Owner = "sandbox-admin"
  }

  key_name = aws_key_pair.admin_key.key_name

  vpc_security_group_ids = [aws_security_group.sandbox_sec_grp.id]
  subnet_id              = aws_subnet.sandbox_pub_subnet.id
}

/*
  set the encryption algorithm for the key to be generated
*/
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

/*
  Create the key pair to help us ssh into the ec2 instance
*/
resource "aws_key_pair" "admin_key" {
  key_name   = "${var.key_name}"
  public_key = tls_private_key.ssh.public_key_openssh
}

/*
  Store the private key in a .pem file locally
*/
resource "local_sensitive_file" "key_file" {
  content = tls_private_key.ssh.private_key_openssh
  filename = "${path.root}/${var.key_name}.pem"
  file_permissions = "0400"
}

