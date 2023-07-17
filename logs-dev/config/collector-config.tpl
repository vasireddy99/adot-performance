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
     exporters: [awscloudwatchlogs]
    metrics:
     receivers: [prometheus]
     exporters: [awsemf]
  telemetry:
    logs:
      level: debug
    metrics:
      level: detailed
