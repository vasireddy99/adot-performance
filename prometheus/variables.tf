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

variable "set_py_path" {
  default = "mocks/setup-python.tpl"
}

variable "mock_json_path" {
  default = "mocks/user-mocks.tpl"
}

variable "mock_docker_compose_path" {
  default = "docker-compose/mock-server-docker-compose.tpl"
}

variable "sample_app_docker_compose_path" {
  default = "docker-compose/sample-app-docker-compose.tpl"
}

variable "collector_config_path" {
  default = "config/collector-config.tpl"
}

variable "prometheus_config_path" {
  default = "config/prometheus-config.tpl"
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