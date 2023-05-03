This Script is used to run the performance analysis of the ADOT COllector and the Prometheus (agent mode).

The Configuration files under /config directory are hardcoded to a specific AMP endpoint, Please change the remote write endpoint as appropriate. 

Using the variables referred in variables.tf file, arguments can be passed based on the use case. Variables such as `metric-load`, `label-count`, `series-interval` etc.,


Example to run the collector
- `terraform apply --var=metric-load=5000 --var=collector=true -auto-approve`

Example to run the prometheus
- `terraform apply --var=metric-load=5000 --var=collector=false -auto-approve`


CwResponse and mocked_servers are invalid for now at the moment, steps will be added later in time to use these modules.
