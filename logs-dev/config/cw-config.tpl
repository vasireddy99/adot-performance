{
  "agent": {
    "metrics_collection_interval": 10,
    "region": "${region}",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
    "debug": true
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [["testcase"]],
    "metrics_collected": {
      "procstat": [
        {
          "measurement": [
            "cpu_usage",
            "memory_rss",
            "pid",
            "pid_count"
          ],
          "exe": "${process_name}",
          "append_dimensions": {
            "launch_date": "${launch_date}",
            "instance_type": "${instance_type}"
          }
        }
      ]
    },
    "namespace": "${metric_namespace}"
  },
  "logs":
     {
         "logs_collected": {
             "files": {
                 "collect_list": [
                     {
                         "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
                         "log_group_name": "amazon-cloudwatch-agent.log",
                         "log_stream_name": "cw_agent_stream",
                         "timestamp_format": "%H: %M: %S%y%b%-d"
                     }
                 ]
             }
         },
         "log_stream_name": "${metric_namespace}"
  }
}