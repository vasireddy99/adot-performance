= Test Case Parameters =
Log Rate: ${log_rate} logs/second
Log Size: ${log_size} bytes
Logging Duration: ${duration} seconds
Log Files Read From: 1
Date test was run: ${date}

== Batch Processor Configuration ==
Maximum Batch Size - ${max_batch_size} logs
Timeout - ${batch_timeout} seconds
Sending Batch Size - ${send_batch_size} logs

= Validator Results =
Total Input Records: ${validator_results.TotalInputRecord}

Total Records Found: ${validator_results.TotalRecordFound}

Unique Logs: ${validator_results.UniqueRecordFound}

Duplicate Logs: ${validator_results.DuplicateRecordFound}

Percent Loss: ${validator_results.PercentLoss}

Missing Logs: ${validator_results.MissingRecordFound}

= Snapshots of Metrics =
image:accepted_logs_filelog-${testcase_extension} image:avg_cpu_utilization-${testcase_extension}
image:avg_ec2_cpu_utilization-${testcase_extension} image:heap_size-${testcase_extension}
image:max_cpu_utilization-${testcase_extension} image:max_ec2_cpu_utilization-${testcase_extension}
image:memory_usage-${testcase_extension} image:queue_size-${testcase_extension}
image:rejected_logs_filelog-${testcase_extension} image:sent_logs_cwl_exporter-${testcase_extension}
