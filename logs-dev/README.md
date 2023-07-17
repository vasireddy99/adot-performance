This Script is used to run the performance analysis of the ADOT Collector with the File Log Receiver and CloudWatch Logs Exporter.

Using the variables referred in [variables.tf](https://gitlab.aws.dev/adot/adot-performance/-/blob/main/variables.tf) file, arguments can be passed based on the use case. Variables such as `log_rate`, `log_size_in_bytes`, `logging_duration_in_seconds` etc.,

* Prerequisites:
    * AWS credentials configured in terminal
    * Terraform
    * Building validator.go (located in logs-dev-scripts) binary using the following command: `GOOS=linux GOARCH=amd64 go build -o validator`

Example to run the ADOT collector 
- `terraform apply --var=log_rate=100 --var=log_size_in_bytes=1000 --var=logging_duration_in_seconds=30 -auto-approve`
