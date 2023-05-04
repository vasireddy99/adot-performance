global:
  scrape_interval: 1s

# Remote write exporter link
remote_write:
    - url: https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-f7c42266-8868-447b-bb23-f966919f1ce4/api/v1/remote_write
      sigv4:
        region: us-west-2

scrape_configs:

  - job_name: "ec2-prometheus-agent-mode"
    ec2_sd_configs:
      - region: ${region}
        port: ${port}

  - job_name: 'self-telemetry-prometheus'
    static_configs:
      - targets: ["localhost:9090"]