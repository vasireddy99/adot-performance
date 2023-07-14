output "sampleAppPublicIP" {
  value = aws_instance.adot-sample[0].public_ip
}

output "sample_app_docker_compose" {
  value = data.template_file.sample_app_docker_compose.rendered
}

output "collection_config" {
  value = data.template_file.collector-config.rendered
}

output "prom_config" {
  value = data.template_file.prometheus-config.rendered
}

output "collector_id" {
  value = aws_instance.collection_agent.ami
}

output "CollectionAgentPublicIP" {
 value= aws_instance.collection_agent.public_ip
}