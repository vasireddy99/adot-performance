extensions:
  sigv4auth:
    region: "us-west-2"
receivers:
  prometheus:
    config:
      global:
        scrape_interval: 5s
      scrape_configs:
      - job_name: "ec2-collector-performance"
        ec2_sd_configs:
          - region: ${region}
            port: ${port}
exporters:
  prometheusremotewrite:
    endpoint: "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-4c399252-f488-42dd-a500-3f0b6c09b2ab/api/v1/remote_write"
#    endpoint:  "http://${mockServerPublicIP}:8080/put-data"
    auth:
      authenticator: sigv4auth
    wal:
       directory: ./prom_rw
       buffer_size: 5000
       truncate_frequency: 120s
service:
  pipelines:
    metrics:
     receivers: [prometheus]
     exporters: [prometheusremotewrite]
  extensions: [sigv4auth]
  telemetry:
    logs:
      level: debug
    metrics:
      level: detailed
      address: localhost:8888