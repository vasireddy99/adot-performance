This Script is used to run the performance analysis of the ADOT COllector and the Prometheus (agent mode).

The Config file is hardcoded with amp endpoint

To Run the collector

Example to run the collector
- `terraform apply --var=metric-load=5000 --var=collector=true -auto-approve`

Example to run the prometheus
- `terraform apply --var=metric-load=5000 --var=collector=true -auto-approve`
