output "collection_config" {
  value = data.template_file.collector-config.rendered
}

output "collector_id" {
  value = aws_instance.collection_agent.ami
}

output "CollectionAgentPublicIP" {
 value= aws_instance.collection_agent.public_ip
}