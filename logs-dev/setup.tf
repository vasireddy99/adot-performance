# ------------------------------------------------------------------------
# Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.
# -------------------------------------------------------------------------

# in this module, we create the necessary common resources for the integ-tests, this setup module will only need to be executed once.
# vpc, iam role, security group, the number of those resources could be limited, creating them concurrently for every pr would trigger throttling issue.


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.8.0"
    }
  }
}

data "aws_caller_identity" "current" {
}

## create one iam role for all the tests
resource "aws_iam_instance_profile" "aoc_test_profile" {
  role = aws_iam_role.aoc_role.name
}

resource "aws_iam_role" "aoc_role" {
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        },
        {
          "Sid": "",
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

data "aws_iam_policy_document" "policy" {
  statement {
    effect    = "Allow"
    actions   = [
      "xray:GetSamplingStatisticSummaries",
      "xray:PutTelemetryRecords",
      "cloudwatch:PutMetricData",
      "ec2:DescribeInstances",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "ec2:DescribeTags",
      "ssm:GetParameters",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
      "xray:GetSamplingTargets",
      "xray:PutTraceSegments",
      "logs:CreateLogStream",
      "ec2:DescribeVolumes",
      "xray:GetSamplingRules",
      "ecr:*",
      "aps:*",
      "*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "policy" {
  name        = "test-policy-logs-dev"
  description = "A test policy"
  policy      = data.aws_iam_policy_document.policy.json
}


resource "aws_iam_role_policy_attachment" "ec2-read-only-policy-attachment" {
  role       = aws_iam_role.aoc_role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_vpc" "adot-vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = "true" #gives you an internal domain name
  enable_dns_hostnames = "true" #gives you an internal host name
  enable_classiclink = "false"
  instance_tenancy = "default"

  tags = { Name = "adot-vpc"}
}

resource "aws_subnet" "adot-subnet-public-1" {
  vpc_id = "${aws_vpc.adot-vpc.id}"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true" //it makes this a public subnet
  availability_zone = "us-west-2a"

  tags = {
    Name = "adot-subnet-public-1"
  }
}


resource "aws_internet_gateway" "adot-igw" {
  vpc_id = "${aws_vpc.adot-vpc.id}"
  tags ={
    Name = "adot-igw"
  }
}

resource "aws_route_table" "adot-public-crt" {
  vpc_id = "${aws_vpc.adot-vpc.id}"

  route {
    //associated subnet can reach everywhere
    cidr_block = "0.0.0.0/0"         //CRT uses this IGW to reach internet
    gateway_id = "${aws_internet_gateway.adot-igw.id}"
  }

  tags = {
    Name = "adot-public-crt"
  }
}

resource "aws_route_table_association" "adot-crta-public-subnet-1"{
  subnet_id = "${aws_subnet.adot-subnet-public-1.id}"
  route_table_id = "${aws_route_table.adot-public-crt.id}"
}

resource "aws_security_group" "adot-sg" {
  vpc_id = "${aws_vpc.adot-vpc.id}"

  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"        // This means, all ip address are allowed to ssh !
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 9090
    to_port = 9999
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 9999
    to_port = 9999
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "adot-sg"
  }
}
