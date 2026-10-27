#----------------------------------------------------------------------------------------------------
# variables.tf
# author: Kabera Clapton
#
# description: Sets up all the variables that are to be used in this terraform project.
#---------------------------------------------------------------------------------------------------- 

variable "key_name" {
  type        = string
  description = "The name of the ssh key used for the EC2 instance"
  default     = "admin-key"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block to be used by the VPC"
  default     = "10.0.0.0/16"
}

variable "egress_cidr" {
  type        = string
  description = "CIDR block for outbound addresses allowed"
  default     = "0.0.0.0/0"
}

variable "pub_cidr" {
  type        = string
  description = "CIDR block to be used by the public subnet"
  default     = "10.0.1.0/24"
}

variable "source_cidr" {
  type        = string
  description = "Source IP address for HTTP traffic"
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "region" {
  type        = string
  description = "Region where the AWS account belongs"
  default     = "eu-west-1"
}
