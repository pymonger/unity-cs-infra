variable "ami_name" { default = "unity-ubuntu" }
variable "ami_key_pair_name" { default = "unity-cs-mcp-smolensk" }
variable "ami_id" { default = "" }
variable "vpc_id" { default = "" }
variable "subnet_one_id" { default = "" }
variable "subnet_two_id" { default = "" }
variable "igw_id" { default = "" }

variable "default_tags" {
  default = {
    Owner   = "Unity CS"
    Project = "Unity CS"
  }
  description = "Default Tags"
  type        = map(string)
}

data "aws_vpc" "unity-test-env" {
  id         = var.vpc_id
  cidr_block = "10.52.8.0/22"
}

// Use existing subnets from MCP
data "aws_subnet" "subnet-uno" {
  #  id = "subnet-059bc4f467275b59d"
  id = var.subnet_one_id
}

data "aws_subnet" "subnet-two" {
  #  id = "subnet-0ebdd997cc3ebe58d"
  id = var.subnet_two_id
}

data "aws_internet_gateway" "infra-env-gw" {
  #  internet_gateway_id = "igw-0622379cb99c03649"
  internet_gateway_id = var.igw_id
}

