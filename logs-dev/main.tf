provider "aws" {
  region = var.region
}

provider "remote" {
  max_sessions = 2
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
  instance_type               = "c5.9xlarge"
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

# Create Log Group beforehand (so they can be deleted once "terraform destroy" is called
# Log Groups are in this format: testcase-<log rate>-<log size>-log-group (ex: testcase-100-1000-log-group)
resource "aws_cloudwatch_log_group" "testcase-log-group" {
  name = "testcase-${var.log_rate}-${var.log_size_in_bytes}-log-group"
}

# Create Log Stream that's part of the Log Group above
# Log Streams are in this format: testcase-<log rate>-<log size>-log-stream (ex: testcase-100-1000-log-stream)
resource "aws_cloudwatch_log_stream" "testcase-log-stream" {
  name           = "testcase-${var.log_rate}-${var.log_size_in_bytes}-log-stream"
  log_group_name = aws_cloudwatch_log_group.testcase-log-group.name
}

data "template_file" "collector-config" {
  template = file(var.collector_config_path)
  vars = {
    log_group = aws_cloudwatch_log_group.testcase-log-group.name
    log_stream = aws_cloudwatch_log_stream.testcase-log-stream.name
    instance_id = aws_instance.collection_agent.id
    send_batch_size = var.send_batch_size
    batch_timeout = var.batch_timeout
    max_batch_size = var.max_batch_size
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
  cwagent_install_command            = "sudo yum -y install amazon-cloudwatch-agent"
  cwagent_start_command              = "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -s -m ec2 -c file:/tmp/cwagent-config.json"
  launch_date                        = formatdate("YYYY-MM-DD", timestamp())
}

resource "null_resource" "start_collector" {
  count    = var.collector ? 1 : 0
  # either getting the install package from s3 or from local
  depends_on = [null_resource.download_collector_from_local, aws_cloudwatch_log_group.testcase-log-group, aws_cloudwatch_log_stream.testcase-log-stream]
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

resource "time_static" "start_test_with_pre_test_delay" {
  depends_on = [null_resource.install_cwagent]
}

resource "time_sleep" "pre_test_delay" {
  depends_on = [null_resource.enable_featuregates, null_resource.install_cwagent]
  count = 1
  create_duration = "${var.pre_test_delay_in_seconds}s"
}

resource "time_static" "start_test" {
  depends_on = [time_sleep.pre_test_delay]
}

# Installs and runs the benchmark application in the same EC2 instance as the Collector
resource "null_resource" "install_benchmark_application" {
  depends_on = [null_resource.enable_featuregates, time_sleep.pre_test_delay]
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

resource "time_static" "end_test" {
  depends_on = [null_resource.install_benchmark_application]
}

# Will capture metrics during the post-test delay
resource "time_sleep" "post_test_delay" {
  depends_on = [null_resource.install_benchmark_application]
  count = 1
  create_duration = "${var.post_test_delay_in_seconds}s"
}

resource "time_static" "end_test_with_post_test_delay" {
  depends_on = [time_sleep.post_test_delay]
}

resource "time_sleep" "delay_for_capturing_metrics_and_getting_logs" {
  depends_on = [time_sleep.post_test_delay]
  count = 1
  create_duration = "1m"
}

# Installs and runs the validator in the same EC2 instance as the Collector
# Validator's execution should be delayed in order to accurately get log loss and log duplication
resource "null_resource" "install_validator" {
  depends_on = [time_sleep.delay_for_capturing_metrics_and_getting_logs]
  provisioner "file" {
    source      = "logs-dev-scripts/validator"
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
      "export CW_LOG_GROUP_NAME=${aws_cloudwatch_log_group.testcase-log-group.name}",
      "export CW_LOG_STREAM_NAME=${aws_cloudwatch_log_stream.testcase-log-stream.name}",
      format("/tmp/validator %d > /tmp/validator_results.json", var.log_rate * var.logging_duration_in_seconds)
    ]

    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = local.private_key_content
      host        = aws_instance.collection_agent.public_ip
    }
  }
}

data "remote_file" "validator_results" {
  depends_on = [null_resource.install_validator]
  conn {
    user        = "ec2-user"
    private_key = local.private_key_content
    host        = aws_instance.collection_agent.public_ip
  }

  path = "/tmp/validator_results.json"
}

locals {
  cpu_utilization_per_process_json = jsonencode({
    "metrics": [
      [ "ADOT-Perf", "procstat_cpu_usage",
        "exe", "aws-otel-collector",
        "InstanceId", aws_instance.collection_agent.id,
        "process_name", "aws-otel-collector",
        "launch_date", local.launch_date,
        "instance_type", aws_instance.collection_agent.instance_type,
        "testcase", "ADOT"
      ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "title": "Average CPU Utilization per Process of ADOT Collector",
    "period": 5,
  })

  cpu_utilization_per_process_max_json = jsonencode({
    "metrics": [
      [ "ADOT-Perf", "procstat_cpu_usage",
        "exe", "aws-otel-collector",
        "InstanceId", aws_instance.collection_agent.id,
        "process_name", "aws-otel-collector",
        "launch_date", local.launch_date,
        "instance_type", aws_instance.collection_agent.instance_type,
        "testcase", "ADOT"
      ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "stat": "Maximum",
    "title": "Maximum CPU Utilization per Process of ADOT Collector",
    "period": 5,
  })

  //EC2 Instance Data
  ec2_cpu_utilization_json = jsonencode({
    "metrics": [
      [ "AWS/EC2", "CPUUtilization",
        "InstanceId", aws_instance.collection_agent.id ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "title": "EC2 Instance Average CPU Utilization",
    "period": 5,
  })

  ec2_cpu_utilization_max_json = jsonencode({
    "metrics": [
      [ "AWS/EC2", "CPUUtilization",
        "InstanceId", aws_instance.collection_agent.id ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "stat": "Maximum",
    "title": "EC2 Instance Maximum CPU Utilization",
    "period": 5,
  })

  //Self-Telemetry Data
  memory_usage_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_process_memory_rss",
        "instance_id", aws_instance.collection_agent.id,
        "OTelLib", "otelcol/prometheusreceiver" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "title": "Memory Usage of ADOT Collector",
    "period": 5,
  })

  heap_size_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_process_runtime_heap_alloc_bytes",
        "instance_id", aws_instance.collection_agent.id,
        "OTelLib", "otelcol/prometheusreceiver" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "title": "Heap Allocation of ADOT Collector",
    "period": 5,
  })

  queue_size_cwl_exporter_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_exporter_queue_size",
        "instance_id", aws_instance.collection_agent.id,
        "exporter", "awscloudwatchlogs",
        "service_version", "v0.30.0" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "title": "Queue Size of CWL Exporter",
    "period": 5,
  })

  accepted_log_records_filelog_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_receiver_accepted_log_records",
        "instance_id", aws_instance.collection_agent.id,
        "receiver", "filelog",
        "service_version", "v0.30.0" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "stat": "Sum",
    "title": "Accepted Log Records of File Log Receiver",
    "period": 5,
  })

  rejected_log_records_filelog_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_receiver_rejected_log_records",
        "instance_id", aws_instance.collection_agent.id,
        "receiver", "filelog",
        "service_version", "v0.30.0" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "stat": "Sum",
    "title": "Rejected Log Records of File Log Receiver",
    "period": 5,
  })

  log_records_sent_cwl_exporter_json = jsonencode({
    "metrics": [
      [ "collector-monitoring", "otelcol_exporter_sent_log_records",
        "instance_id", aws_instance.collection_agent.id,
        "exporter", "awscloudwatchlogs",
        "service_version", "v0.30.0" ]
    ],
    "annotations": {
      "vertical": [
        {
          "visible": true,
          "color": "#00F00A",
          "label": "Test start",
          "value": time_static.start_test.rfc3339
        },
        {
          "value": time_static.end_test.rfc3339,
          "label": "Test end"
        }
      ]
    },
    "start": time_static.start_test_with_pre_test_delay.rfc3339,
    "end": time_static.end_test_with_post_test_delay.rfc3339,
    "stat": "Sum",
    "title": "Log Records Sent by CWL Exporter",
    "period": 5,
  })
}

locals {
  snapshots_directory = "snapshots/"
  extension = "-testcase-${var.log_rate}-${var.log_size_in_bytes}.png"

  avg_cpu_image_name = "avg_cpu_utilization${local.extension}"
  max_cpu_image_name = "max_cpu_utilization${local.extension}"
  avg_ec2_cpu_image_name = "avg_ec2_cpu_utilization${local.extension}"
  max_ec2_cpu_image_name = "max_ec2_cpu_utilization${local.extension}"
  memory_usage_image_name = "memory_usage${local.extension}"
  heap_size_image_name = "heap_size${local.extension}"
  queue_size_image_name = "queue_size${local.extension}"
  accepted_logs_image_name = "accepted_logs_filelog${local.extension}"
  rejected_logs_image_name = "rejected_logs_filelog${local.extension}"
  sent_logs_cwl_exporter_image_name = "sent_logs_cwl_exporter${local.extension}"
}

resource "null_resource" "add_metric_snapshots" {
  depends_on = [time_sleep.delay_for_capturing_metrics_and_getting_logs]
  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.cpu_utilization_per_process_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.avg_cpu_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.cpu_utilization_per_process_max_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.max_cpu_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.ec2_cpu_utilization_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.avg_ec2_cpu_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.ec2_cpu_utilization_max_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.max_ec2_cpu_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.memory_usage_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.memory_usage_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.heap_size_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.heap_size_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.queue_size_cwl_exporter_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.queue_size_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.accepted_log_records_filelog_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.accepted_logs_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.rejected_log_records_filelog_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.rejected_logs_image_name}"
  }

  provisioner "local-exec" {
    command = "aws cloudwatch get-metric-widget-image --metric-widget '${local.log_records_sent_cwl_exporter_json}' --region ${var.region} | grep MetricWidgetImage | awk '{split($0,a,\"\\\"\"); print a[4]}' | base64 --decode > ${local.snapshots_directory}${local.sent_logs_cwl_exporter_image_name}"
  }
}

locals {
  page_to_publish_to = "AWS/AWS_Distro_for_OpenTelemetry/internal/logs/loadtests/testcase-${var.log_rate}-${var.log_size_in_bytes}"
  validator_results = jsondecode(data.remote_file.validator_results.content)
  wiki_page = templatefile("wiki_page.tpl", {
    log_rate = var.log_rate
    log_size = var.log_size_in_bytes
    duration = var.logging_duration_in_seconds
    date = formatdate("MMM DD, YYYY", timestamp())
    testcase_extension = "testcase-${var.log_rate}-${var.log_size_in_bytes}.png"
    send_batch_size = var.send_batch_size
    batch_timeout = var.batch_timeout
    max_batch_size = var.max_batch_size
    validator_results = local.validator_results
  })
  wiki_page_string = tostring(local.wiki_page)
}

// Note: Specify in readme that they need to install RustyAmazonWiki (toolbox install raw)
resource "null_resource" "publish_to_wiki" {
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.avg_cpu_image_name} < ${local.snapshots_directory}${local.avg_cpu_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.max_cpu_image_name} < ${local.snapshots_directory}${local.max_cpu_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.avg_ec2_cpu_image_name} < ${local.snapshots_directory}${local.avg_ec2_cpu_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.max_ec2_cpu_image_name} < ${local.snapshots_directory}${local.max_ec2_cpu_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.memory_usage_image_name} < ${local.snapshots_directory}${local.memory_usage_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.heap_size_image_name} < ${local.snapshots_directory}${local.heap_size_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.queue_size_image_name} < ${local.snapshots_directory}${local.queue_size_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.accepted_logs_image_name} < ${local.snapshots_directory}${local.accepted_logs_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.rejected_logs_image_name} < ${local.snapshots_directory}${local.rejected_logs_image_name}"
  }
  provisioner "local-exec" {
    command = "raw attachment ${local.page_to_publish_to} upload ${local.sent_logs_cwl_exporter_image_name} < ${local.snapshots_directory}${local.sent_logs_cwl_exporter_image_name}"
  }
  provisioner "local-exec" {
    command = "echo \"${local.wiki_page_string}\" > wiki_page.xwiki"
  }

  provisioner "local-exec" {
    command = "raw write ${local.page_to_publish_to} --title \"Log Rate ${var.log_rate}, Log Size ${var.log_size_in_bytes} bytes\" --syntax xwiki < wiki_page.xwiki"
  }
}
