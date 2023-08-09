receivers:
  filelog:
    include: [/*.log]
    encoding: "ascii"
  prometheus:
    config:
      scrape_configs:
        - job_name: 'collector-monitoring'
          scrape_interval: 5s
          static_configs:
            - targets: ['localhost:8888']
processors:
  batch:
    send_batch_size: ${send_batch_size}
    timeout: ${batch_timeout}s
    send_batch_max_size: ${max_batch_size}
exporters:
  awscloudwatchlogs:
    log_group_name: "${log_group}"
    log_stream_name: "${log_stream}"
  awsemf:
    log_group_name: "emf-metrics-log-group"
    log_stream_name: "emf-metrics-log-stream"
service:
  pipelines:
    logs:
     receivers: [filelog]
     processors: [batch]
     exporters: [awscloudwatchlogs]
    metrics:
     receivers: [prometheus]
     exporters: [awsemf]
  telemetry:
    logs:
      level: debug
    metrics:
      level: detailed
