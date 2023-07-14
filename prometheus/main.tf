provider "aws" {
  region = var.region
}

# this ami is used to launch the emitter instance
data "aws_ami" "amazonlinux2" {
  most_recent = true

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami.html#finding-quick-start-ami
  filter {
    name = "name"
    values = [
    "amzn2-ami-kernel*"]
  }

  filter {
    name = "state"
    values = [
    "available"]
  }

  owners = [
  "amazon"]
}

resource "aws_instance" "adot-sample" {
  count                       = var.instance_count
  ami                         = data.aws_ami.amazonlinux2.id
  instance_type               = "m5.2xlarge"
  associate_public_ip_address = true
  key_name                    = local.ssh_key_name
  subnet_id                   = "${aws_subnet.adot-subnet-public-1.id}"
  vpc_security_group_ids      = ["${aws_security_group.adot-sg-sampleapp.id}"]
  iam_instance_profile        = aws_iam_instance_profile.aoc_test_profile.name
  tags = {
    Name      = "Sample-App"
    ephemeral = "true"
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"

    # Use 2 hops because some of the test services run inside docker in the instance.
    # That counts as an extra hop to access the IMDS. The default value is 1.
    http_put_response_hop_limit = 2
  }
}

data "template_file" "sample_app_docker_compose" {
  template = file(var.sample_app_docker_compose_path)
  vars = {
    metric-count = var.metric-load
    label-count  = var.label-count
    series-count = var.series-count
    port         =  var.port
  }
}


resource "null_resource" "setup_sample_app" {
  count           = var.instance_count
  depends_on      = [ aws_instance.adot-sample ]
  provisioner "file" {
    content       = data.template_file.sample_app_docker_compose.rendered
    destination   = "/tmp/docker-compose.yml"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.adot-sample[count.index].public_ip
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo amazon-linux-extras install docker -y",
      "sudo service docker start",
      "sudo usermod -a -G docker ec2-user",
      "sudo curl -L 'https://github.com/docker/compose/releases/download/v2.17.1/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo `aws ecr get-login --no-include-email --region us-west-2`",
      "sleep 30", // sleep 30s to wait until dockerd is totally set up
      "sudo /usr/local/bin/docker-compose -f /tmp/docker-compose.yml up -d"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.adot-sample[count.index].public_ip
    }
  }
}


data "template_file" "mock_docker_compose" {
  template = file(var.mock_docker_compose_path)
}

data "template_file" "set-py" {
  template = file(var.set_py_path)
}

data "template_file" "mock-json" {
  template = file(var.mock_json_path)
}


/*
resource "aws_instance" "mock-server" {
  ami                         = data.aws_ami.amazonlinux2.id
  instance_type               = "m5.2xlarge"
  associate_public_ip_address = true
  key_name                    = local.ssh_key_name
  subnet_id                   = "${aws_subnet.adot-subnet-public-1.id}"
  vpc_security_group_ids      = ["${aws_security_group.adot-sg-mock.id}"]
  iam_instance_profile        = aws_iam_instance_profile.aoc_test_profile.name
  tags = {
    Name      = "mock-server"
    ephemeral = "true"
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"

    # Use 2 hops because some of the test services run inside docker in the instance.
    # That counts as an extra hop to access the IMDS. The default value is 1.
    http_put_response_hop_limit = 2
  }
}

//mock server
resource "null_resource" "setup_mock_server" {
  count           = var.instance_count
  depends_on    = [ aws_instance.adot-sample ]
  provisioner "file" {
    content     = data.template_file.mock_docker_compose.rendered
    destination = "/tmp/mock-docker-compose.yml"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.mock-server.public_ip
    }
  }
  provisioner "file" {
    content     = data.template_file.set-py.rendered
    destination = "/tmp/set_python.py"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.mock-server.public_ip
    }
  }
  provisioner "file" {
    content     = data.template_file.mock-json.rendered
    destination = "/tmp/mock.json"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.mock-server.public_ip
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo amazon-linux-extras install docker -y",
      "sudo service docker start",
      "sudo usermod -a -G docker ec2-user",
      "sudo curl -L 'https://github.com/docker/compose/releases/download/v2.17.1/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo `aws ecr get-login --no-include-email --region us-west-2`",
      "sleep 30", // sleep 30s to wait until dockerd is totally set up
      "sudo /usr/local/bin/docker-compose -f /tmp/mock-docker-compose.yml up -d"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.mock-server.public_ip
    }
  }
}
*/

//Collector
resource "aws_instance" "collection_agent" {
  ami                         = data.aws_ami.amazonlinux2.id
  instance_type               = "m5.2xlarge"
  associate_public_ip_address = true
  subnet_id                   = "${aws_subnet.adot-subnet-public-1.id}"
  vpc_security_group_ids      = ["${aws_security_group.adot-sg.id}"]
  iam_instance_profile        = aws_iam_instance_profile.aoc_test_profile.name
  key_name                    = local.ssh_key_name

  tags = {
    Name      = "Collection-Agent"
    ephemeral = "true"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}


data "template_file" "collector-config" {
  template = file(var.collector_config_path)
  vars = {
//    mockServerPublicIP = aws_instance.mock-server.public_ip
    region            =  var.region
    port              = var.port
  }
}

data "template_file" "prometheus-config" {
  template = file(var.prometheus_config_path)
  vars = {
//    mockServerPublicIP = aws_instance.mock-server.public_ip
    region            =  var.region
    port              = var.port
  }
}


resource "null_resource" "download_collector_from_local" {
  depends_on = [aws_instance.collection_agent]
  provisioner "file" {
    source      = var.install_package_local_path
    destination = "aws-otel-collector.rpm"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}


resource "null_resource" "start_prometheus" {
  count    = var.collector ? 0 : 1
  # either getting the install package from s3 or from local
  depends_on = [ null_resource.setup_sample_app]
  provisioner "file" {
    content     = data.template_file.prometheus-config.rendered
    destination = "/tmp/prometheus.yml"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "cd /",
      "sudo wget https://github.com/prometheus/prometheus/releases/download/v2.43.0/prometheus-2.43.0.linux-amd64.tar.gz",
      "sudo tar xvfz prometheus-2.43.0.linux-amd64.tar.gz ",
      "cd prometheus-2.43.0.linux-amd64",
      "sudo touch query.log",
      "sudo chmod 777 query.log",
      "sudo ./prometheus --config.file=../tmp/prometheus.yml --enable-feature=agent --log.level=debug &",
      "sleep 30"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}

locals {
    wait_cloud_init                    = "for i in {1..300}; do [ ! -f /var/lib/cloud/instance/boot-finished ] && echo 'Waiting for cloud-init...'$i && sleep 1 || break; done"
    install_command                    = "sudo rpm -Uvh aws-otel-collector.rpm"
    start_command                      = "sudo /opt/aws/aws-otel-collector/bin/aws-otel-collector-ctl -c /tmp/ot-default.yml -a start"
    cwagent_download_command           = "sudo rpm -Uvh --force https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
    cwagent_install_command            = "sudo yum install amazon-cloudwatch-agent"
//    cwagent_install_command            =  "echo 'donothing'"
    cwagent_start_command              = "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -s -m ec2 -c file:/tmp/cwagent-config.json"
    launch_date                        = formatdate("YYYY-MM-DD", timestamp())
}

resource "null_resource" "start_collector" {
  count    = var.collector ? 1 : 0
  # either getting the install package from s3 or from local
  depends_on = [null_resource.download_collector_from_local, null_resource.setup_sample_app]
  provisioner "file" {
    content     = data.template_file.collector-config.rendered
    destination = "/tmp/ot-default.yml"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      local.wait_cloud_init,
      local.install_command,
      local.start_command,
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}


resource "time_sleep" "wait_time_metrics_collected" {
  depends_on      = [null_resource.install_cwagent]
  count           = null_resource.start_collector !=null || null_resource.start_prometheus !=null ? 1 : 0
  create_duration = "${var.collection_period}m"
}


## install cwagent on the instance to collect metric from otel-collector
data "template_file" "cwagent_config" {
  template = file(var.cw-config-path)
  vars = {
    metric_namespace         = "ADOT-Perf"
    testcase                 = var.collector ? "ADOT" : "Prometheus"
    launch_date              = local.launch_date
    data_rate                = var.metric-load
    region                   = var.region
    instance_type            = aws_instance.collection_agent.instance_type
    testing_ami              = aws_instance.collection_agent.ami
    process_name             = var.collector ? "aws-otel-collector" : "prometheus"
  }
}

# install cwagent
resource "null_resource" "install_cwagent" {
  count            = null_resource.start_collector !=null || null_resource.start_prometheus !=null ? 1 : 0
  //  depends_on = [ time_sleep.wait_time_metrics_collected ]
  provisioner "file" {
    content     = data.template_file.cwagent_config.rendered
    destination = "/tmp/cwagent-config.json"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      local.cwagent_download_command,
      local.cwagent_install_command,
      local.cwagent_start_command,
      "sleep 30"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}

resource "aws_cloudwatch_dashboard" "cloudwatch_metrics" {
  depends_on = [null_resource.install_cwagent]
  dashboard_name = "ec2-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 10
        height = 5

        properties = {
          metrics = [
            [
              "${data.template_file.cwagent_config.vars.metric_namespace}",
              "procstat_memory_rss",
              "data_rate",
              "${data.template_file.cwagent_config.vars.data_rate}",
              "testcase",
              "${data.template_file.cwagent_config.vars.testcase}",
              "testing_ami",
              "${aws_instance.collection_agent.ami}"
            ]
          ]
          period = 300
          stat   = "Average"
          region = "us-west-2"
          title  = "Avg EC2 Instance Memory"
        }
      },      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 10
        height = 5

        properties = {
          metrics = [
            [
              "${data.template_file.cwagent_config.vars.metric_namespace}",
              "procstat_memory_rss",
              "data_rate",
              "${data.template_file.cwagent_config.vars.data_rate}",
              "testcase",
              "${data.template_file.cwagent_config.vars.testcase}",
              "testing_ami",
              "${aws_instance.collection_agent.ami}"
            ]
          ]
          period = 300
          stat   = "Maximum"
          region = "us-west-2"
          title  = "Max EC2 Instance Memory"
        }
      },      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 10
        height = 5

        properties = {
          metrics = [
            [
              "${data.template_file.cwagent_config.vars.metric_namespace}",
              "procstat_cpu_usage",
              "data_rate",
              "${data.template_file.cwagent_config.vars.data_rate}",
              "testcase",
              "${data.template_file.cwagent_config.vars.testcase}",
              "testing_ami",
              "${aws_instance.collection_agent.ami}"
            ]
          ]
          period = 300
          stat   = "Average"
          region = "us-west-2"
          title  = "Avg EC2 Instance CPU"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 10
        height = 5

        properties = {
          metrics = [
            [
              "${data.template_file.cwagent_config.vars.metric_namespace}",
              "procstat_cpu_usage",
              "data_rate",
              "${data.template_file.cwagent_config.vars.data_rate}",
              "testcase",
              "${data.template_file.cwagent_config.vars.testcase}",
              "testing_ami",
              "${aws_instance.collection_agent.ami}"
            ]
          ]
          period = 300
          stat   = "Maximum"
          region = "us-west-2"
          title  = "Max EC2 Instance CPU"
        }
      }
    ]
  })
}
