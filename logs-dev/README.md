This Script is used to run the performance analysis of the ADOT Collector with the File Log Receiver and CloudWatch Logs Exporter.

Using the variables referred in [variables.tf](https://gitlab.aws.dev/adot/adot-performance/-/blob/main/variables.tf) file, arguments can be passed based on the use case. Variables such as `log_rate`, `log_size_in_bytes`, `logging_duration_in_seconds` etc.,

* Prerequisites:
    * AWS credentials configured in terminal
    * Terraform
    * Building validator.go (located in logs-dev-scripts) binary using the following command: `GOOS=linux GOARCH=amd64 go build -o validator`
    * Build the Collector RPM (put in the root directory) that has the File Log Receiver and CWL Exporter
      * Option 1: Download from this [link](https://aws-otel-collector-test.s3.amazonaws.com/amazon_linux/amd64/v0.30.0-b98398c/aws-otel-collector.rpm)
      * Option 2: Build it from the dev branch of the [aws-otel-collector repo](https://github.com/aws-observability/aws-otel-collector) by following these [instructions](https://aws-otel-collector-test.s3.amazonaws.com/amazon_linux/amd64/v0.30.0-b98398c/aws-otel-collector.rpm) 
    * Install [RAW](https://code.amazon.com/packages/RustyAmazonWiki/trees/mainline) to publish 

IMPORTANT INFORMATION FOR PUBLISHING TO WIKI PAGE: To publish to the wiki page you need to make sure it already exists. Also make sure the wiki pages are in the following directory: `AWS/AWS_Distro_for_OpenTelemetry/internal/logs/loadtests/`
In the aforementioned directory, make sure to create a wiki page before the null_resource.publish_to_wiki step starts running. 
The page needs to named in this format: `testcase-{log rate}-{log size in bytes}` -> Example: testcase-100-100

Example to run the ADOT collector 
- `terraform apply --var=log_rate=100 --var=log_size_in_bytes=1000 --var=logging_duration_in_seconds=30 -auto-approve`
