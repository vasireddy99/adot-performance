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
    log_group = var.log_group
    log_stream = var.log_stream
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

locals {
  wait_cloud_init                    = "for i in {1..300}; do [ ! -f /var/lib/cloud/instance/boot-finished ] && echo 'Waiting for cloud-init...'$i && sleep 1 || break; done"
  install_command                    = "sudo rpm -Uvh aws-otel-collector.rpm"
  start_command                      = "sudo /opt/aws/aws-otel-collector/bin/aws-otel-collector-ctl -c /tmp/ot-default.yml -a start"
  restart_command = "sudo systemctl restart aws-otel-collector"
  cwagent_download_command           = "sudo rpm -Uvh --force https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
  cwagent_install_command            = "sudo yum install amazon-cloudwatch-agent"
  cwagent_start_command              = "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -s -m ec2 -c file:/tmp/cwagent-config.json"
  launch_date                        = formatdate("YYYY-MM-DD", timestamp())
}

resource "null_resource" "start_collector" {
  count    = var.collector ? 1 : 0
  # either getting the install package from s3 or from local
  depends_on = [null_resource.download_collector_from_local]
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
      "sudo chmod +rwx /opt/aws/aws-otel-collector/etc/"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}

// Temporary resource to enable the feature gates
resource "null_resource" "enable_featuregates" {
  depends_on = [null_resource.start_collector]
  provisioner "file" {
    source = "logs-dev-scripts/.env"
    destination = "/tmp/.env"

    connection {
      type = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/.env /opt/aws/aws-otel-collector/etc/.env",
      local.restart_command
    ]
    connection {
      type = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
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
  count            = null_resource.start_collector !=null ? 1 : 0
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

# Installs and runs the benchmark application in the same EC2 instance as the Collector
resource "null_resource" "install_benchmark_application" {
  depends_on = [null_resource.enable_featuregates]
  provisioner "file" {
    source = "logs-dev-scripts/logger.py"
    destination = "/tmp/logger.py"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo python3 /tmp/logger.py --log-rate=${var.log_rate} --log-size-in-bytes=${var.log_size_in_bytes} --count=${var.logging_duration_in_seconds} --tail-file-path=${var.log_file_path}"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}

# Installs and runs the validator in the same EC2 instance as the Collector
resource "null_resource" "install_validator" {
  depends_on = [null_resource.install_benchmark_application]
  provisioner "file" {
    source = "logs-dev-scripts/validator"
    destination = "/tmp/validator"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/validator",
      "export AWS_REGION=${var.region}",
      "export CW_LOG_GROUP_NAME=${var.log_group}",
      "export CW_LOG_STREAM_NAME=${var.log_stream}",
      format("/tmp/validator %d", var.log_rate * var.logging_duration_in_seconds)
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
