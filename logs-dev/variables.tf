variable "region" {
  default = "us-west-2"
}

variable "instance_count" {
  default = "2"
}

variable "ssh_key_name" {
  default = ""
}

variable "sshkey_s3_bucket" {
  default = ""
}

variable "sshkey_s3_private_key" {
  default = ""
}

variable "debug" {
  default = true
}

variable "collector_config_path" {
  default = "config/collector-config.tpl"
}

variable "install_package_local_path" {
  default = "aws-otel-collector.rpm"
}

variable "test" {
  default = "ADOTCollector"
}

variable "metric-load" {
  default = 5000
}

variable "label-count" {
  default = 10
}

variable "series-count" {
  default = 10
}

variable "cw-config-path" {
  default = "config/cw-config.tpl"
}

variable "collector" {
  default = true
}

variable "collection_period" {
  default = 10
}

variable "process_name" {
  default = ""
}

variable "port" {
  default = 9090
}

// Benchmark Application (logger.py) configurations
variable "log_rate" {
  default = 10
}

variable "log_size_in_bytes" {
  default = 10
}

variable "logging_duration_in_seconds" {
  default = 10
}

variable "log_file_path" {
  default = "/test.log"
}

variable "pre_test_delay_in_seconds" {
  default = 120
}

variable "post_test_delay_in_seconds" {
  default = 300
}

variable "concurrent_processes_benchmark_app" {
  default = 3
}

variable "send_batch_size" {
  default = 10000
}

variable "max_batch_size" {
  default = 10000
}

variable "batch_timeout" {
  default = 10
}
