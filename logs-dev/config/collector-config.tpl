extensions:
  pprof:

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
  attributes/modify:
    actions:
      - key: "service_instance_id"
        action: delete
      - key: "instance_id"
        value: "${instance_id}"
        action: insert
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
    metric_declarations:
      - dimensions: [[service_version, instance_id],[]]
        metric_name_selectors:
          - "^otelcol_process.*"
      - dimensions: [[receiver, service_version, instance_id],[]]
        metric_name_selectors:
          - "^otelcol_receiver.*"
      - dimensions: [[exporter, service_version, instance_id],[]]
        metric_name_selectors:
          - "^otelcol_exporter.*"
service:
  pipelines:
    logs:
     receivers: [filelog]
     processors: [batch]
     exporters: [awscloudwatchlogs]
    metrics:
     receivers: [prometheus]
     processors: [attributes/modify]
     exporters: [awsemf]
  extensions: [pprof]
  telemetry:
    logs:
      level: debug
    metrics:
      level: detailed
