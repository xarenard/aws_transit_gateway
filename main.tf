terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  vpcs = {
    "vpc_a"              = { name = "vpc_a", cidr = "10.1.0.0/16" },
    "vpc_b"              = { name = "vpc_b", cidr = "10.2.0.0/16" },
    "vpc_shared_service" = { name = "vpc_shared_service", cidr = "10.4.0.0/16" }
  }

  vpc_clients = { for key, value in local.vpcs : key => value
  if key != "vpc_shared_service" }

  vpc_shared_service = { for key, value in local.vpcs : key => value
  if key == "vpc_shared_service" }
}

//Create all VPCs
resource "aws_vpc" "map" {
  for_each = local.vpcs

  cidr_block = each.value.cidr
  tags = merge(
    { Name = each.key },
  var.common_tag)
}

// Testing purpose for acessing vpc
resource "aws_internet_gateway" "ig" {
  for_each = local.vpc_clients

  vpc_id = aws_vpc.map[each.key].id

  tags = merge(
    { Name = join("-", ["ig", each.key]) },
  var.common_tag)

}

// Create subnet
resource "aws_subnet" "map" {
  for_each = local.vpcs

  cidr_block = cidrsubnet(aws_vpc.map[each.key].cidr_block, 8, 1) //"10.1.1.0/24"
  vpc_id     = aws_vpc.map[each.key].id

  tags = merge(
    { Name = join("-", ["subnet", each.value.name]) },
  var.common_tag)

}

// Create route table for vpc clients
resource "aws_route_table" "rt_vpc_client" {
  for_each = local.vpc_clients

  vpc_id = aws_vpc.map[each.key].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig[each.key].id
  }

  route {
    cidr_block         = "10.4.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id

  }

  tags = merge(
    { Name = join("-", ["rt", each.key]) },
  var.common_tag)

}

// create route table for each clients
resource "aws_route_table_association" "rt_association_vpc_client" {
  for_each = local.vpc_clients

  route_table_id = aws_route_table.rt_vpc_client[each.key].id
  subnet_id      = aws_subnet.map[each.key].id
}

// Create route table for shared service
resource "aws_route_table" "rt_vpc_shared_service" {

  vpc_id = aws_vpc.map["vpc_shared_service"].id

  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id
  }

  tags = merge(
    { Name = join("-", ["rt", "vpc_shared_service"])
    },
  var.common_tag)

}

resource "aws_route_table_association" "rt_association_vpc_shared_service" {
  for_each = local.vpc_clients

  route_table_id = aws_route_table.rt_vpc_shared_service.id
  subnet_id      = aws_subnet.map["vpc_shared_service"].id
}

/* Transit Gateway */
resource "aws_ec2_transit_gateway" "dev_transit_gateway" {
  description                     = "dev-transit-gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = merge(
    { Name = "tg"
    },
  var.common_tag)
}


resource "aws_ec2_transit_gateway_route_table" "rt_vpc_to_shared_service" {
  transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id

  tags = merge(
    { Name = join("-", ["tg", "rt", "vpc", "share-service"])
    },
  var.common_tag)

}


resource "aws_ec2_transit_gateway_route_table" "rt_shared_service_to_vpc" {
  transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id

  tags = merge(
    { Name = join("-", ["tg", "rt", "ss_to_vpc"])
    },
  var.common_tag)
}

resource "aws_ec2_transit_gateway_route_table_association" "rt_ss_to_vpc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpc_ss_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_shared_service_to_vpc.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "rt_ss_to_vpc_propagation" {

  for_each = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpcs_attachment

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpcs_attachment[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_shared_service_to_vpc.id
}

resource "aws_ec2_transit_gateway_route_table_association" "rt_vpc_to_shared_service_association" {

  for_each = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpcs_attachment

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpcs_attachment[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_vpc_to_shared_service.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "rt_vpc_to_shared_service_propagation" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev-transit_gateway_vpc_ss_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_vpc_to_shared_service.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev-transit_gateway_vpc_ss_attachment" {
  subnet_ids         = [aws_subnet.map["vpc_shared_service"].id]
  transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id
  vpc_id             = aws_vpc.map["vpc_shared_service"].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(
    { Name = join("-", ["tg", "attachment-shared-service"])
    },
  var.common_tag)
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev-transit_gateway_vpcs_attachment" {
  for_each = {
    for key, value in local.vpcs : key => value
    if key != "vpc_shared_service"
  }

  subnet_ids         = [aws_subnet.map[each.key].id]
  transit_gateway_id = aws_ec2_transit_gateway.dev_transit_gateway.id
  vpc_id             = aws_vpc.map[each.key].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(
    { Name = join("-", ["tg", "attachment", each.key])
    },
  var.common_tag)
}


resource "aws_security_group" "sg_vpc_client" {
  for_each = local.vpc_clients
  name     = join("_", ["sg", each.key])
  ingress {
    from_port   = 22
    protocol    = "TCP"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]

  }
  vpc_id = aws_vpc.map[each.key].id
}


resource "aws_security_group" "sg_vpc_shared_service" {
  name = "sg_vpc_share_servvice"

  //just testing imcp really
  ingress {
    from_port   = 8
    protocol    = "icmp"
    to_port     = -1
    cidr_blocks = [for key, value in local.vpc_clients : value.cidr]
  }

  ingress {
    from_port   = 22
    protocol    = "TCP"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
    //cidr_blocks = [for key,value in local.vpc_clients: value.cidr]
  }

  vpc_id = aws_vpc.map["vpc_shared_service"].id
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true


  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }


  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
  owners = ["amazon"]
}


resource "aws_instance" "ec2_instance_client" {

  depends_on = [
  aws_internet_gateway.ig]

  for_each = local.vpc_clients

  ami                         = data.aws_ami.amazon-linux-2.id
  associate_public_ip_address = true
  //iam_instance_profile        = "${aws_iam_instance_profile.test.id}"
  instance_type = var.instance_type
  key_name      = var.ssh_key_name
  vpc_security_group_ids = [
  aws_security_group.sg_vpc_client[each.key].id]
  subnet_id = aws_subnet.map[each.key].id
}

resource "aws_instance" "ec2_instance_shared_service" {

  ami                         = data.aws_ami.amazon-linux-2.id
  associate_public_ip_address = false
  instance_type               = var.instance_type
  key_name                    = var.ssh_key_name
  vpc_security_group_ids = [
  aws_security_group.sg_vpc_shared_service.id]
  subnet_id = aws_subnet.map["vpc_shared_service"].id

}

