This Script is used to run the performance analysis of the ADOT Collector with the File Log Receiver and CloudWatch Logs Exporter.

Using the variables referred in [variables.tf](https://gitlab.aws.dev/adot/adot-performance/-/blob/main/variables.tf) file, arguments can be passed based on the use case. Variables such as `log_rate`, `log_size_in_bytes`, `logging_duration_in_seconds` etc.,

* Prerequisites:
    * AWS credentials configured in terminal
    * Terraform
    * Building validator.go (located in logs-dev-scripts) binary using the following command: `GOOS=linux GOARCH=amd64 go build -o validator`
    * Build the Collector RPM (put in the root directory) that has the File Log Receiver and CWL Exporter
      * Option 1: Download from this [link](https://aws-otel-collector-test.s3.amazonaws.com/amazon_linux/amd64/v0.30.0-b98398c/aws-otel-collector.rpm)
      * Option 2: Build it from the dev branch of the [aws-otel-collector repo](https://github.com/aws-observability/aws-otel-collector) by following these [instructions](https://aws-otel-collector-test.s3.amazonaws.com/amazon_linux/amd64/v0.30.0-b98398c/aws-otel-collector.rpm) 
    * Install [RAW](https://code.amazon.com/packages/RustyAmazonWiki/trees/mainline) to allow for publishing load test results to a wiki page 

IMPORTANT NOTE ABOUT HIGHER INTENSITY LOAD TESTS: For more higher intensity load tests (i.e. load tests that have a high log rate such as 1000 or high log size such as 200KB), you will need to make use of the concurrency in the benchmark application. Otherwise it may give you this error: `Detected overruns. Failed to keep up with the expected QPS.`
To utilize concurrency in the benchmark application you simply specify how many concurrent processes you want through the `concurrent_processes_benchmark_app` variable (since `c5.9x large` instance is used you can specify up to 36 processes). 

Example: `terraform apply --var=concurrent_processes_benchmark_app=36 --var=log_rate=10000 --var=log_size_in_bytes=1000 --var=logging_duration_in_seconds=300`

Note about the wiki pages: The page will be named in this format: `testcase-{log rate}-{log size in bytes}` -> Example: testcase-100-100. Additionally they will be published to `[AWS/AWS_Distro_for_OpenTelemetry/internal/logs/loadtests/](https://w.amazon.com/bin/view/AWS/AWS_Distro_for_OpenTelemetry/internal/logs/loadtests)`

Example to run the ADOT collector 
- `terraform apply --var=log_rate=100 --var=log_size_in_bytes=1000 --var=logging_duration_in_seconds=30 -auto-approve`
