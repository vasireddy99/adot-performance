extensions:
  sigv4auth:
    region: "us-west-2"
receivers:
  prometheus:
    config:
      global:
        scrape_interval: 1s
      scrape_configs:
      - job_name: "ec2-collector-performance"
        ec2_sd_configs:
          - region: ${region}
            port: ${port}
      - job_name: "self-collector-performance"
        scrape_interval: 5s
        static_configs:
          - targets: [localhost:${port}]
processors:
  batch:
exporters:
  prometheusremotewrite:
    endpoint: "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-4c399252-f488-42dd-a500-3f0b6c09b2ab/api/v1/remote_write"
    auth:
      authenticator: sigv4auth
service:
  pipelines:
    metrics:
     receivers: [prometheus]
     processors: [batch]
     exporters: [prometheusremotewrite]
  extensions: [sigv4auth]
  telemetry:
    logs:
      level: debug
    metrics:
      level: detailed
      address: localhost:${port}